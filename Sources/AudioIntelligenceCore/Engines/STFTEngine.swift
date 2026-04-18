// STFTEngine.swift
// Elite Music DNA Engine — Phase 1
//
// Librosa functional parity: librosa.stft() — core/spectrum.py
//

import Accelerate
import Foundation

// MARK: - Window Type

public enum WindowType: String, Sendable {
    case hann
    case hamming
}

// MARK: - STFT Result Matrix

/// Flat memory layout for high-performance audio analysis.
/// Matches Librosa's (n_freqs, n_frames) structure.
public struct STFTMatrix: Sendable, Codable {
    /// Contiguous data: magnitude[f * nFrames + t]
    public let magnitude: [Float]
    /// Contiguous data: phase[f * nFrames + t]
    public let phase: [Float]
    
    public let nFFT: Int
    public let hopLength: Int
    public let sampleRate: Double
    
    public var nFreqs: Int { nFFT / 2 + 1 }
    public var nFrames: Int { magnitude.count / nFreqs }

    public init(magnitude: [Float], phase: [Float], nFFT: Int, hopLength: Int, sampleRate: Double) {
        self.magnitude = magnitude
        self.phase = phase
        self.nFFT = nFFT
        self.hopLength = hopLength
        self.sampleRate = sampleRate
    }

    /// Accessor for a specific frequency bin across all frames
    public func magnitudeRow(forBin f: Int) -> ArraySlice<Float> {
        let start = f * nFrames
        return magnitude[start..<(start + nFrames)]
    }
    
    /// Accessor for a specific frame across all frequencies
    public func magnitudeFrame(forTimeline t: Int) -> [Float] {
        var frame = [Float](repeating: 0, count: nFreqs)
        for f in 0..<nFreqs {
            frame[f] = magnitude[f * nFrames + t]
        }
        return frame
    }

    public func frequencies() -> [Float] {
        (0..<nFreqs).map { Float($0) * Float(sampleRate) / Float(nFFT) }
    }

    public func frameToTime(_ frame: Int) -> Double {
        Double(frame * hopLength) / sampleRate
    }
}

// MARK: - STFTEngine

public final class STFTEngine: @unchecked Sendable {
    public static let defaultNFFT = 2048
    public static let defaultHopLength = 512

    public let nFFT: Int
    public let hopLength: Int
    public let sampleRate: Double
    public let windowType: WindowType

    private let nFreqs: Int
    private let window: [Float]
    private let dftSetup: vDSP_DFT_Setup
    private let idftSetup: vDSP_DFT_Setup

    public init(nFFT: Int = defaultNFFT, 
                hopLength: Int = defaultHopLength, 
                sampleRate: Double = 22050,
                windowType: WindowType = .hann) {
        self.nFFT = nFFT
        self.hopLength = hopLength
        self.sampleRate = sampleRate
        self.windowType = windowType
        self.nFreqs = nFFT / 2 + 1

        // Use periodic window (Librosa default: sym=False)
        self.window = STFTEngine.createPeriodicWindow(type: windowType, length: nFFT)

        // vDSP_DFT real-to-complex setup
        self.dftSetup = vDSP_DFT_zop_CreateSetup(nil, vDSP_Length(nFFT), .FORWARD)!
        self.idftSetup = vDSP_DFT_zop_CreateSetup(nil, vDSP_Length(nFFT), .INVERSE)!
    }

    deinit {
        vDSP_DFT_DestroySetup(dftSetup)
        vDSP_DFT_DestroySetup(idftSetup)
    }

    // MARK: Periodic Window Creation

    private static func createPeriodicWindow(type: WindowType, length: Int) -> [Float] {
        var w = [Float](repeating: 0, count: length)
        let alpha: Float
        let beta: Float
        
        switch type {
        case .hann:
            alpha = 0.5
            beta = 0.5
        case .hamming:
            alpha = 0.54
            beta = 0.46
        }
        
        for n in 0..<length {
            w[n] = alpha - beta * cosf(2.0 * .pi * Float(n) / Float(length))
        }
        return w
    }

    // MARK: Analyze

    /// Computes STFT with Librosa-exact behavior.
    /// - Parameter padMode: 'constant' (zeros) or 'reflect' (Librosa default: 'constant')
    public func analyze(_ samples: [Float], center: Bool = true, padMode: String = "constant") async -> STFTMatrix {
        // Cache Check (Unique hash of samples for reliability)
        let sampleHash = samples.prefix(1000).map { String($0) }.joined() + "\(samples.count)"
        let cacheKey = await IntelligenceCache.shared.generateKey(for: URL(string: "stft://local")!, parameters: [
            "hash": sampleHash, "nFFT": nFFT, "hop": hopLength, "window": windowType.rawValue, "center": center, "pad": padMode
        ])
        
        if let cached: STFTMatrix = await IntelligenceCache.shared.get(forKey: cacheKey) {
            return cached
        }

        let input: [Float]
        if center {
            input = padSignal(samples, pad: nFFT / 2, mode: padMode)
        } else {
            input = samples
        }

        let nSamples = input.count
        let nFrames = 1 + (nSamples - nFFT) / hopLength
        
        // Output buffers: Flattened for performance
        var magnitudes = [Float](repeating: 0, count: nFreqs * nFrames)
        var phases     = [Float](repeating: 0, count: nFreqs * nFrames)

        // DFT working buffers
        var realIn  = [Float](repeating: 0, count: nFFT)
        var imagIn  = [Float](repeating: 0, count: nFFT)
        var realOut = [Float](repeating: 0, count: nFFT)
        var imagOut = [Float](repeating: 0, count: nFFT)

        for t in 0..<nFrames {
            let start = t * hopLength
            
            // Apply window
            vDSP_vmul(Array(input[start..<(start + nFFT)]), 1,
                      window, 1,
                      &realIn, 1,
                      vDSP_Length(nFFT))
            
            imagIn.replaceSubrange(0..<nFFT, with: repeatElement(0, count: nFFT))

            // FFT
            vDSP_DFT_Execute(dftSetup, realIn, imagIn, &realOut, &imagOut)

            // Extract magnitude and phase for only the positive frequencies [0...n_fft/2]
            for f in 0..<nFreqs {
                let re = realOut[f]
                let im = imagOut[f]
                
                // Librosa scaling: By default, FFT returns raw sums. 
                // However, we remain consistent with the magnitude/phase structure.
                let mag = sqrtf(re * re + im * im)
                let phi = atan2f(im, re)
                
                magnitudes[f * nFrames + t] = mag
                phases[f * nFrames + t]     = phi
            }
        }
        
        let matrix = STFTMatrix(magnitude: magnitudes, phase: phases, nFFT: nFFT, hopLength: hopLength, sampleRate: sampleRate)
        await IntelligenceCache.shared.set(matrix, forKey: cacheKey)
        return matrix
    }

    // MARK: - Synthesize (ISTFT)

    /// Librosa: istft() — core/spectrum.py
    /// Reconstructs time-domain signal from STFT matrix.
    public func synthesize(_ stft: STFTMatrix) -> [Float] {
        let nFrames = stft.nFrames
        let nFreqs = stft.nFreqs
        let nFFT = stft.nFFT
        let hopLength = stft.hopLength
        
        let expectedLength = (nFrames - 1) * hopLength + nFFT
        var signal = [Float](repeating: 0, count: expectedLength)
        var windowSum = [Float](repeating: 0, count: expectedLength)
        
        var realIn  = [Float](repeating: 0, count: nFFT)
        var imagIn  = [Float](repeating: 0, count: nFFT)
        var realOut = [Float](repeating: 0, count: nFFT)
        var imagOut = [Float](repeating: 0, count: nFFT)
        
        for t in 0..<nFrames {
            // 1. Reconstruct full complex spectrum (Hermitian symmetry)
            for f in 0..<nFreqs {
                let mag = stft.magnitude[f * nFrames + t]
                let phi = stft.phase[f * nFrames + t]
                
                let re = mag * cosf(phi)
                let im = mag * sinf(phi)
                
                realIn[f] = re
                imagIn[f] = im
                
                if f > 0 && f < nFreqs - 1 {
                    // Conjugate symmetry for negative frequencies
                    realIn[nFFT - f] = re
                    imagIn[nFFT - f] = -im
                }
            }
            
            // 2. Inverse FFT
            vDSP_DFT_Execute(idftSetup, realIn, imagIn, &realOut, &imagOut)
            
            // vDSP Scale for Inverse FFT: 1/N
            var scale = 1.0 / Float(nFFT)
            vDSP_vsmul(realOut, 1, &scale, &realOut, 1, vDSP_Length(nFFT))
            
            // 3. Apply window and Overlap-Add
            let start = t * hopLength
            for i in 0..<nFFT {
                let sIdx = start + i
                if sIdx < expectedLength {
                    let win = window[i]
                    signal[sIdx] += realOut[i] * win
                    windowSum[sIdx] += win * win
                }
            }
        }
        
        // 4. Normalize by window square sum (WOLA)
        for i in 0..<expectedLength {
            if windowSum[i] > 1e-10 {
                signal[i] /= windowSum[i]
            }
        }
        
        return signal
    }

    // MARK: Padding Logic

    private func padSignal(_ samples: [Float], pad: Int, mode: String) -> [Float] {
        if mode == "reflect" {
            // librosa.util.pad_center(samples, size=n, mode='reflect')
            // Equivalent to np.pad(y, pad, mode='reflect')
            var padded = [Float](repeating: 0, count: samples.count + 2 * pad)
            
            // Center
            padded.replaceSubrange(pad..<(pad + samples.count), with: samples)
            
            // Left Reflection
            for i in 0..<pad {
                padded[pad - 1 - i] = samples[i + 1]
            }
            
            // Right Reflection
            let lastIdx = samples.count - 1
            for i in 0..<pad {
                padded[pad + samples.count + i] = samples[lastIdx - 1 - i]
            }
            
            return padded
        } else {
            // Constant (Zero) padding
            let zeros = [Float](repeating: 0, count: pad)
            return zeros + samples + zeros
        }
    }

    // MARK: Post-Processing

    public func powerSpectrogram(from stft: STFTMatrix) -> [Float] {
        var power = [Float](repeating: 0, count: stft.magnitude.count)
        vDSP_vsq(stft.magnitude, 1, &power, 1, vDSP_Length(stft.magnitude.count))
        return power
    }

    public func amplitudeToDb(_ magnitudes: [Float], ref: Float? = nil) -> [Float] {
        let maxVal = ref ?? (magnitudes.max() ?? 1.0)
        let safeRef = max(maxVal, 1e-10)
        
        return magnitudes.map { 20.0 * log10f(max($0, 1e-10) / safeRef) }
    }
    
    public func powerToDb(_ power: [Float], ref: Float? = nil) -> [Float] {
        let maxVal = ref ?? (power.max() ?? 1.0)
        let safeRef = max(maxVal, 1e-10)
        
        return power.map { 10.0 * log10f(max($0, 1e-10) / safeRef) }
    }
    
    public func powerToDb(_ power: [[Float]], ref: Float? = nil) -> [[Float]] {
        // Flatten to find global max if ref is nil
        let flat = power.flatMap { $0 }
        let maxVal = ref ?? (flat.max() ?? 1.0)
        let safeRef = max(maxVal, 1e-10)
        
        return power.map { row in
            row.map { 10.0 * log10f(max($0, 1e-10) / safeRef) }
        }
    }
}
