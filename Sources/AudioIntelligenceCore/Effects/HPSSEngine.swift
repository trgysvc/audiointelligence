import Foundation
import Accelerate
import AudioIntelligenceMetal

public struct HPSSResult: Sendable {
    public let harmonic: STFTMatrix
    public let percussive: STFTMatrix
    public let harmonicEnergyRatio: Float
    public let percussiveEnergyRatio: Float
    public let characterization: String
}

/// Harmonic-Percussive Source Separation (HPSS) Engine.
/// Decomposes audio into harmonic (tonal) and percussive (transient) components.
public final class HPSSEngine: Sendable {
    
    private let winHarm: Int
    private let winPerc: Int
    private let metalEngine: MetalEngine?
    
    public init(winHarm: Int = 31, winPerc: Int = 31, metalEngine: MetalEngine? = nil) {
        self.winHarm = winHarm
        self.winPerc = winPerc
        self.metalEngine = metalEngine
    }
    
    public func analyze(stft: STFTMatrix) -> HPSSResult {
        let (h, p) = separate(from: stft, winHarm: winHarm, winPerc: winPerc)
        
        // Calculate energy ratios
        var hEnergy: Float = 0
        var pEnergy: Float = 0
        vDSP_sve(h.magnitude, 1, &hEnergy, vDSP_Length(h.magnitude.count))
        vDSP_sve(p.magnitude, 1, &pEnergy, vDSP_Length(p.magnitude.count))
        
        let total = hEnergy + pEnergy + 1e-10
        let hRatio = hEnergy / total
        let pRatio = pEnergy / total
        
        let characterization: String
        if hRatio > 0.7 {
            characterization = "Harmonic Dominant (Melodic/Instrumental)"
        } else if pRatio > 0.7 {
            characterization = "Percussive Dominant (Rhythmic/Drums)"
        } else {
            characterization = "Balanced Mix"
        }
        
        return HPSSResult(
            harmonic: h,
            percussive: p,
            harmonicEnergyRatio: hRatio,
            percussiveEnergyRatio: pRatio,
            characterization: characterization
        )
    }
    
    /// Industry Standard: decompose.hpss()
    /// Refactored for Dual-Path Acceleration (v7.2 Aligned)
    public func separate(
        from stft: STFTMatrix, 
        winHarm: Int = 31, 
        winPerc: Int = 31,
        power: Float = 2.0
    ) -> (harmonic: STFTMatrix, percussive: STFTMatrix) {
        
        let nFreqs = stft.nFreqs
        let nFrames = stft.nFrames
        let magnitude = stft.magnitude
        
        var harmonicMedian: [Float]
        var percussiveMedian: [Float]

        // 1. Dual-Path Median Filtering (GPU Priority)
        if let metal = metalEngine, nFrames * nFreqs > 10000 {
            // Offload to M4 GPU for large spectrograms
            harmonicMedian = metal.executeMedianFilter2D(data: magnitude, nRows: nFrames, nCols: nFreqs, windowSize: winHarm, isHorizontal: false)
            percussiveMedian = metal.executeMedianFilter2D(data: magnitude, nRows: nFrames, nCols: nFreqs, windowSize: winPerc, isHorizontal: true)
        } else {
            // Fallback to optimized Accelerate (AMX)
            harmonicMedian = HPSSEngine.vDSPMedianFilter(magnitude, nRows: nFrames, nCols: nFreqs, windowSize: winHarm, axis: .vertical)
            percussiveMedian = HPSSEngine.vDSPMedianFilter(magnitude, nRows: nFrames, nCols: nFreqs, windowSize: winPerc, axis: .horizontal)
        }
        
        // 2. Softmasking (Wiener Filter)
        var maskHarmonic   = [Float](repeating: 0, count: magnitude.count)
        var maskPercussive = [Float](repeating: 0, count: magnitude.count)
        
        // Vectorized power and mask calculation
        for i in 0..<magnitude.count {
            let h = powf(harmonicMedian[i], power)
            let p = powf(percussiveMedian[i], power)
            let total = h + p + 1e-10
            
            maskHarmonic[i]   = h / total
            maskPercussive[i] = p / total
        }
        
        // 3. Apply masks
        var magH = [Float](repeating: 0, count: magnitude.count)
        var magP = [Float](repeating: 0, count: magnitude.count)
        
        vDSP_vmul(magnitude, 1, maskHarmonic, 1, &magH, 1, vDSP_Length(magnitude.count))
        vDSP_vmul(magnitude, 1, maskPercussive, 1, &magP, 1, vDSP_Length(magnitude.count))
        
        let outH = STFTMatrix(magnitude: magH, phase: stft.phase, nFFT: stft.nFFT, hopLength: stft.hopLength, sampleRate: stft.sampleRate)
        let outP = STFTMatrix(magnitude: magP, phase: stft.phase, nFFT: stft.nFFT, hopLength: stft.hopLength, sampleRate: stft.sampleRate)
        
        return (outH, outP)
    }
    
    private enum Axis {
        case horizontal
        case vertical
    }
    
    /// Incremental sliding-window median filter (CPU fallback path, used when no `MetalEngine`
    /// is supplied or the spectrogram is small). The previous implementation re-extracted and
    /// fully re-sorted (`vDSP_vsort`, O(w log w)) a fresh `windowSize`-element window at *every
    /// single output pixel*, even though adjacent windows share all but one element — a real,
    /// measured cost (~5s/file on typical ~10s clips at windowSize=31, confirmed while
    /// diagnosing why an unrelated batch measurement was unexpectedly slow; see DEVLOG Phase
    /// 16). This version sorts each row/column's first window once, then maintains that sorted
    /// window incrementally as it slides — removing the one element that leaves and
    /// binary-search-inserting the one that enters, both O(w) array operations instead of a full
    /// O(w log w) re-sort. Verified to produce bit-for-bit identical output to the original
    /// brute-force version (`HPSSEngineTests.testIncrementalMedianFilter_matchesBruteForce`).
    private static func vDSPMedianFilter(
        _ data: [Float],
        nRows: Int,
        nCols: Int,
        windowSize: Int,
        axis: Axis
    ) -> [Float] {
        var result = [Float](repeating: 0, count: data.count)
        let halfWin = windowSize / 2

        func insertSorted(_ arr: inout [Float], _ value: Float) {
            var lo = 0, hi = arr.count
            while lo < hi {
                let mid = (lo + hi) / 2
                if arr[mid] < value { lo = mid + 1 } else { hi = mid }
            }
            arr.insert(value, at: lo)
        }
        func removeSorted(_ arr: inout [Float], _ value: Float) {
            var lo = 0, hi = arr.count
            while lo < hi {
                let mid = (lo + hi) / 2
                if arr[mid] < value { lo = mid + 1 } else { hi = mid }
            }
            if lo < arr.count { arr.remove(at: lo) }
        }

        if axis == .horizontal {
            // Filter each row (frequency bin) independently
            for r in 0..<nRows {
                let rowStart = r * nCols
                func sample(_ idx: Int) -> Float { (idx >= 0 && idx < nCols) ? data[rowStart + idx] : 0 }

                var window: [Float] = (0..<windowSize).map { sample($0 - halfWin) }
                window.sort()
                result[rowStart] = window[halfWin]

                for c in 1..<nCols {
                    removeSorted(&window, sample(c - 1 - halfWin))
                    insertSorted(&window, sample(c + halfWin))
                    result[rowStart + c] = window[halfWin]
                }
            }
        } else {
            // Filter each column (time frame) independently
            for c in 0..<nCols {
                func sample(_ idx: Int) -> Float { (idx >= 0 && idx < nRows) ? data[idx * nCols + c] : 0 }

                var window: [Float] = (0..<windowSize).map { sample($0 - halfWin) }
                window.sort()
                result[c] = window[halfWin]

                for r in 1..<nRows {
                    removeSorted(&window, sample(r - 1 - halfWin))
                    insertSorted(&window, sample(r + halfWin))
                    result[r * nCols + c] = window[halfWin]
                }
            }
        }
        return result
    }
}
