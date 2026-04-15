// RhythmEngine.swift
// Elite Music DNA Engine — Phase 3
//
// Onset Detection and Tempo Tracking.
// Mirroring librosa.onset.onset_detect and librosa.beat.beat_track.

import Foundation
import Accelerate

public struct RhythmResult: Sendable {
    public let bpm: Double
    public let beatFrames: [Int]
    public let beatTimes: [Double]
    public let gridStdSec: Double
    public let onsetMean: Float
    public let onsetPeak: Float
}

public final class RhythmEngine: Sendable {
    
    private let sampleRate: Double
    
    public init(sampleRate: Double = 44100) {
        self.sampleRate = sampleRate
    }
    
    public func analyze(onsetResult: OnsetResult) async -> RhythmResult {
        let bpm = RhythmEngine.estimateTempo(
            onsetStrength: onsetResult.envelope, 
            sr: sampleRate, 
            hopLength: 512
        )
        
        return RhythmResult(
            bpm: Double(bpm),
            beatFrames: onsetResult.onsetFrames,
            beatTimes: onsetResult.onsetTimes,
            gridStdSec: Double(onsetResult.mean), // Placeholder for std
            onsetMean: onsetResult.mean,
            onsetPeak: onsetResult.peak
        )
    }
    
    /// Librosa: beat.plp() - Predominant Local Pulse.
    /// Multi-band implementation for robust pulse tracking.
    public func computePLP(from stft: STFTMatrix) -> [Float] {
        let bands = splitIntoFrequencyBands(from: stft)
        let nFrames = stft.nFrames
        
        // Recommended weights [0.15, 0.35, 0.35, 0.15] for Sub, Low, Mid, High
        let weights: [Float] = [0.15, 0.35, 0.35, 0.15]
        var combinedPulse = [Float](repeating: 0, count: nFrames)
        
        for (i, bandOnset) in bands.enumerated() {
            let weight = weights[i]
            var pulse = [Float](repeating: 0, count: nFrames)
            
            // Per-band pulse estimation using local autocorrelation
            // Simplified: weighted contribution of band-wise onset flux
            vDSP_vsmul(bandOnset, 1, [weight], &pulse, 1, vDSP_Length(nFrames))
            vDSP_vadd(combinedPulse, 1, pulse, 1, &combinedPulse, 1, vDSP_Length(nFrames))
        }
        
        // Final normalization
        return DSPHelpers.normalizeMax(combinedPulse)
    }

    private func splitIntoFrequencyBands(from stft: STFTMatrix) -> [[Float]] {
        let nFreqs = stft.nFreqs
        let nFrames = stft.nFrames
        let sr = Float(sampleRate)
        let nFFT = Float((nFreqs - 1) * 2)
        
        // Frequency boundaries: [Sub, Low, Mid, High]
        let boundaries: [Float] = [100.0, 400.0, 2500.0]
        var binBoundaries = boundaries.map { Int(roundf(($0 * nFFT) / sr)) }
        binBoundaries = binBoundaries.map { min(max(0, $0), nFreqs) }
        
        let startBins = [0] + binBoundaries
        let endBins = binBoundaries + [nFreqs]
        
        var bandOnsets = [[Float]]()
        
        for (start, end) in zip(startBins, endBins) {
            var flux = [Float](repeating: 0, count: nFrames)
            for t in 1..<nFrames {
                var sum: Float = 0
                for f in start..<end {
                    let diff = stft.magnitude[f * nFrames + t] - stft.magnitude[f * nFrames + (t - 1)]
                    sum += max(0, diff)
                }
                flux[t] = sum
            }
            bandOnsets.append(DSPHelpers.normalizeMax(flux))
        }
        
        return bandOnsets
    }
    
    // MARK: - Onset Strength (Novelty Function)
    
    /// Librosa: onset.onset_strength()
    /// Computes the spectral flux (rectified difference) 
    /// which spikes at note onsets.
    public static func onsetStrength(from stft: STFTMatrix) -> [Float] {
        let nFreqs = stft.nFreqs
        let nFrames = stft.nFrames
        
        var strength = [Float](repeating: 0, count: nFrames)
        
        for t in 1..<nFrames {
            var flux: Float = 0
            for f in 0..<nFreqs {
                let current = stft.magnitude[f * nFrames + t]
                let previous = stft.magnitude[f * nFrames + (t - 1)]
                
                // Rectified difference: max(0, curr - prev)
                flux += max(0, current - previous)
            }
            strength[t] = flux
        }
        
        // Normalize
        return DSPHelpers.normalizeMax(strength)
    }
    
    // MARK: - Tempo Tracking
    
    /// Librosa: beat.tempo()
    /// Estimates BPM using autocorrelation of the onset strength.
    public static func estimateTempo(onsetStrength: [Float], sr: Double, hopLength: Int) -> Float {
        let n = onsetStrength.count
        guard n > 0 else { return 120.0 }
        
        // 1. Autocorrelation
        var acorr = [Float](repeating: 0, count: n)
        // vDSP_conv requires reversed window for cross-correlation logic
        let reversed = Array(onsetStrength.reversed())
        vDSP_conv(onsetStrength, 1, reversed, 1, &acorr, 1, vDSP_Length(n), vDSP_Length(n))
        
        // 2. Identify peak in the tempo range (40...240 BPM)
        // Convert lag to BPM: bpm = 60 * sr / (hop_length * lag)
        
        let minLag = Int(60.0 * Float(sr) / (Float(hopLength) * 240.0))
        let maxLag = Int(60.0 * Float(sr) / (Float(hopLength) * 40.0))
        
        var bestBPM = Float(120.0)
        var maxVal: Float = -1.0
        
        for lag in max(1, minLag)...min(n-1, maxLag) {
            let val = acorr[lag]
            if val > maxVal {
                maxVal = val
                bestBPM = 60.0 * Float(sr) / (Float(hopLength) * Float(lag))
            }
        }
        
        return bestBPM
    }
}
