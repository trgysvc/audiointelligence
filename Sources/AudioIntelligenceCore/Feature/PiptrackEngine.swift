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

            // Librosa piptrack: threshold = 0.1 * max(S[:, t]) in [fMin, fMax] range
            // This makes detection amplitude-invariant (same behaviour on quiet and loud signals)
            var frameMax: Float = 0
            for f in max(1, binMin)...binMax {
                let v = stft.magnitude[t * nFreqs + f]
                if v > frameMax { frameMax = v }
            }
            let dynamicThreshold = threshold * frameMax

            // 1. Find local maxima in [fMin, fMax] — parabolic interpolation
            for f in max(1, binMin)...binMax {
                let current = stft.magnitude[t * nFreqs + f]
                let prev    = stft.magnitude[t * nFreqs + (f - 1)]
                let next    = stft.magnitude[t * nFreqs + (f + 1)]

                // Local-max AND above frame-normalised threshold
                if current > prev && current > next && current > dynamicThreshold {
                    // 2. Parabolic interpolation (sub-bin refinement)
                    let p = 0.5 * (prev - next) / (prev - 2.0 * current + next)
                    let refinedBin = Float(f) + p
                    let refinedFreq = refinedBin * sr / nFFT

                    framePitches.append(refinedFreq)
                    frameMags.append(current)
                }
            }
            
            // 3. Selection (v7.1 Forensic Upgrade: Favor fundamental over overtones)
            if !frameMags.isEmpty {
                let maxM = frameMags.max() ?? 1.0
                var fundamentalIdx = 0
                // Pick the LOWEST peak that is at least 30% of the max peak's strength
                for (i, m) in frameMags.enumerated() {
                    if m > (maxM * 0.3) {
                        fundamentalIdx = i
                        break
                    }
                }
                pitches[t] = framePitches[fundamentalIdx]
                magnitudes[t] = frameMags[fundamentalIdx]
            }
        }
        
        return PiptrackResult(pitches: pitches, magnitudes: magnitudes)
    }
}
