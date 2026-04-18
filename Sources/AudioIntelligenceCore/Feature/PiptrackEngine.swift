// PiptrackEngine.swift
// Elite Music DNA Engine — Phase 4
//
// Pitch tracking using parabolic interpolation of STFT peaks.
// Mirroring industry standard.feature.piptrack for melody extraction.

import Foundation
import Accelerate

public struct PiptrackResult: Codable, Sendable {
    public let pitches: [Float]    // Refined frequency per frame
    public let magnitudes: [Float] // Magnitude of the primary pitch per frame
}

/// Sub-bin Pitch Tracking Engine.
/// Uses parabolic interpolation on STFT magnitude peaks to achieve refined frequency estimation.
public final class PiptrackEngine: Sendable {
    
    private let fMin: Float
    private let fMax: Float
    private let threshold: Float
    
    public init(fMin: Float = 65.4, fMax: Float = 2093.0, threshold: Float = 0.1) {
        self.fMin = fMin
        self.fMax = fMax
        self.threshold = threshold
    }
    
    /// Industry Standard: feature.piptrack()
    /// Extracts pitch and magnitude series from an STFT spectrogram.
    public func track(stft: STFTMatrix) -> PiptrackResult {
        let nFrames = stft.nFrames
        let nFreqs = stft.nFreqs
        let sr = Float(stft.sampleRate)
        let nFFT = Float((nFreqs - 1) * 2)
        
        var pitches = [Float](repeating: 0, count: nFrames)
        var magnitudes = [Float](repeating: 0, count: nFrames)
        
        // Min/Max bin indices
        let binMin = Int(floorf(fMin * nFFT / sr))
        let binMax = Int(min(Float(nFreqs - 2), ceilf(fMax * nFFT / sr)))
        
        for t in 0..<nFrames {
            var framePitches: [Float] = []
            var frameMags: [Float] = []
            
            // 1. Find local maxima in the frequency range (Contiguous in Frame-major)
            for f in max(1, binMin)...binMax {
                let current = stft.magnitude[t * nFreqs + f]
                let prev = stft.magnitude[t * nFreqs + (f - 1)]
                let next = stft.magnitude[t * nFreqs + (f + 1)]
                
                if current > prev && current > next && current > threshold {
                    // 2. Parabolic Interpolation
                    // p = 0.5 * (prev - next) / (prev - 2*current + next)
                    let p = 0.5 * (prev - next) / (prev - 2.0 * current + next)
                    let refinedBin = Float(f) + p
                    let refinedFreq = refinedBin * sr / nFFT
                    
                    framePitches.append(refinedFreq)
                    frameMags.append(current)
                }
            }
            
            // 3. Selection (usually pick the strongest peak)
            if !frameMags.isEmpty {
                var maxIdx = 0
                var maxM: Float = -1.0
                for (i, m) in frameMags.enumerated() {
                    if m > maxM {
                        maxM = m
                        maxIdx = i
                    }
                }
                pitches[t] = framePitches[maxIdx]
                magnitudes[t] = frameMags[maxIdx]
            }
        }
        
        return PiptrackResult(pitches: pitches, magnitudes: magnitudes)
    }
}
