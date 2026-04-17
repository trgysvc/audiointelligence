// HPSSEngine.swift
// Elite Music DNA Engine — Phase 3
//
// Harmonic-Percussive Source Separation (HPSS) using 2D Median Filtering.
// Mirroring librosa.decompose.hpss.

import Foundation
import Accelerate

public struct HPSSResult: Sendable {
    public let harmonic: STFTMatrix
    public let percussive: STFTMatrix
    public let harmonicEnergyRatio: Float
    public let percussiveEnergyRatio: Float
    public let characterization: String
}

public final class HPSSEngine: Sendable {
    
    private let winHarm: Int
    private let winPerc: Int
    
    public init(winHarm: Int = 31, winPerc: Int = 31) {
        self.winHarm = winHarm
        self.winPerc = winPerc
    }
    
    public func analyze(stft: STFTMatrix) -> HPSSResult {
        let (h, p) = HPSSEngine.separate(from: stft, kernelSize: max(winHarm, winPerc))
        
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
    
    /// Librosa: decompose.hpss()
    /// - Parameters:
    ///   - stft: Full STFT result (magnitude + phase)
    ///   - kernelSize: Default 31 (Librosa default)
    ///   - power: Weiner filter power (Default 2.0)
    /// - Returns: (Harmonic STFT, Percussive STFT)
    public static func separate(
        from stft: STFTMatrix, 
        kernelSize: Int = 31, 
        power: Float = 2.0
    ) -> (harmonic: STFTMatrix, percussive: STFTMatrix) {
        
        let nFreqs = stft.nFreqs
        let nFrames = stft.nFrames
        let magnitude = stft.magnitude
        
        // 1. Median Filtering
        // Harmonic: Horizontal (time axis)
        let harmonicMedian = medianFilter(magnitude, nFreqs: nFreqs, nFrames: nFrames, size: kernelSize, axis: .horizontal)
        
        // Percussive: Vertical (frequency axis)
        let percussiveMedian = medianFilter(magnitude, nFreqs: nFreqs, nFrames: nFrames, size: kernelSize, axis: .vertical)
        
        // 2. Softmasking (Wiener Filter)
        var maskHarmonic   = [Float](repeating: 0, count: magnitude.count)
        var maskPercussive = [Float](repeating: 0, count: magnitude.count)
        
        for i in 0..<magnitude.count {
            let h = powf(harmonicMedian[i], power)
            let p = powf(percussiveMedian[i], power)
            let total = h + p + 1e-10
            
            maskHarmonic[i]   = h / total
            maskPercussive[i] = p / total
        }
        
        // 3. Apply masks to retrieve complex components
        var magH = [Float](repeating: 0, count: magnitude.count)
        var magP = [Float](repeating: 0, count: magnitude.count)
        
        // Vector multiply for performance
        vDSP_vmul(magnitude, 1, maskHarmonic, 1, &magH, 1, vDSP_Length(magnitude.count))
        vDSP_vmul(magnitude, 1, maskPercussive, 1, &magP, 1, vDSP_Length(magnitude.count))
        
        let outH = STFTMatrix(
            magnitude: magH, 
            phase: stft.phase, // Reuse phase
            nFFT: stft.nFFT, 
            hopLength: stft.hopLength, 
            sampleRate: stft.sampleRate
        )
        
        let outP = STFTMatrix(
            magnitude: magP, 
            phase: stft.phase, 
            nFFT: stft.nFFT, 
            hopLength: stft.hopLength, 
            sampleRate: stft.sampleRate
        )
        
        return (outH, outP)
    }
    
    // MARK: - Median Filter Logic
    
    private enum Axis {
        case horizontal // Time
        case vertical   // Frequency
    }
    
    private static func medianFilter(_ data: [Float], nFreqs: Int, nFrames: Int, size: Int, axis: Axis) -> [Float] {
        var result = [Float](repeating: 0, count: data.count)
        let half = size / 2
        
        if axis == .horizontal {
            for f in 0..<nFreqs {
                let rowStart = f * nFrames
                var window = [Float](repeating: 0, count: size)
                for t in 0..<nFrames {
                    let rStart = max(0, t - half)
                    let rEnd = min(nFrames - 1, t + half)
                    let count = rEnd - rStart + 1
                    
                    // Direct copy to window buffer
                    data.withUnsafeBufferPointer { ptr in
                        window.withUnsafeMutableBufferPointer { wPtr in
                            memcpy(wPtr.baseAddress!, ptr.baseAddress! + (rowStart + rStart), count * MemoryLayout<Float>.size)
                        }
                    }
                    
                    // Sort only the active portion (Quickselect would be even faster, but sort is O(K log K))
                    var subWindow = Array(window[0..<count])
                    subWindow.sort()
                    result[rowStart + t] = subWindow[count / 2]
                }
            }
        } else {
            for t in 0..<nFrames {
                var window = [Float](repeating: 0, count: size)
                for f in 0..<nFreqs {
                    let rStart = max(0, f - half)
                    let rEnd = min(nFreqs - 1, f + half)
                    let count = rEnd - rStart + 1
                    
                    // Vertical is strided, copy one by one
                    for i in 0..<count {
                        window[i] = data[(rStart + i) * nFrames + t]
                    }
                    
                    var subWindow = Array(window[0..<count])
                    subWindow.sort()
                    result[f * nFrames + t] = subWindow[count / 2]
                }
            }
        }
        
        return result
    }
}
