// RhythmEngine.swift
// Elite Music DNA Engine — Phase 3
//
// Onset Detection and Tempo Tracking.
// Mirroring industry standard.onset.onset_detect and industry standard.beat.beat_track.

import Foundation
import Accelerate

public struct RhythmResult: Sendable {
    public let bpm: Double
    public let bpmConfidence: Float // v50.0 Addition
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
    
    public func analyze(onsetResult: OnsetResult, hopLength: Int = 512) async -> RhythmResult {
        // 1. Estimate global tempo
        let tempoResult = RhythmEngine.estimateTempo(
            onsetStrength: onsetResult.envelope, 
            sr: sampleRate, 
            hopLength: hopLength
        )
        
        let bpm = tempoResult.bpm
        
        // 2. Dynamic Programming Beat Tracking (Ellis, 2007)
        let (beatFrames, _) = RhythmEngine.beatTrack(
            onsetStrength: onsetResult.envelope,
            bpm: bpm,
            sr: sampleRate,
            hopLength: hopLength
        )
        
        let beatTimes = beatFrames.map { Double($0 * hopLength) / sampleRate }
        
        return RhythmResult(
            bpm: Double(bpm),
            bpmConfidence: tempoResult.confidence,
            beatFrames: beatFrames,
            beatTimes: beatTimes,
            gridStdSec: Double(onsetResult.mean),
            onsetMean: onsetResult.mean,
            onsetPeak: onsetResult.peak
        )
    }
    
    // MARK: - Dynamic Programming Beat Tracking
    
    /// Industry Standard: beat.beat_track() using Ellis (2007) DP approach.
    /// Finds the best sequence of beat events that align with onsets and maintain tempo.
    public static func beatTrack(
        onsetStrength: [Float],
        bpm: Float,
        sr: Double,
        hopLength: Int,
        alpha: Float = 100.0 // Tightness parameter
    ) -> (beats: [Int], score: Float) {
        let n = onsetStrength.count
        guard n > 0 else { return ([], 0) }
        
        // Preferred period in frames
        let period = Float(60.0 * sr) / (Float(hopLength) * bpm)
        
        var cumScore = [Float](repeating: 0, count: n)
        var backPointer = [Int](repeating: -1, count: n)
        
        // DP: Forward pass
        for i in 0..<n {
            var bestScore = onsetStrength[i]
            var bestJ = -1
            
            // Search range: [0.5*period, 2.0*period]
            let minLag = Int(round(0.5 * period))
            let maxLag = Int(round(2.0 * period))
            
            let startJ = max(0, i - maxLag)
            let endJ = max(-1, i - minLag)
            
            if endJ >= 0 {
                for j in startJ...endJ {
                    let lag = Float(i - j)
                    // Transition cost: -alpha * (log(lag / period))^2
                    let cost = -alpha * powf(logf(lag / period), 2.0)
                    let score = cumScore[j] + cost
                    
                    if score > bestScore {
                        bestScore = score
                        bestJ = j
                    }
                }
            }
            
            cumScore[i] = bestScore + onsetStrength[i]
            backPointer[i] = bestJ
        }
        
        // Backtrack from the maximum cumulative score
        var maxScore: Float = -Float.infinity
        var lastIdx = n - 1
        
        for i in 0..<n {
            if cumScore[i] > maxScore {
                maxScore = cumScore[i]
                lastIdx = i
            }
        }
        
        var beats: [Int] = []
        var curr = lastIdx
        while curr != -1 {
            beats.append(curr)
            curr = backPointer[curr]
        }
        
        return (beats.reversed(), maxScore)
    }
    
    /// Industry Standard: beat.plp() - Predominant Local Pulse.
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
                    let current = stft.magnitude[t * nFreqs + f]
                    let previous = stft.magnitude[(t - 1) * nFreqs + f]
                    let diff = current - previous
                    sum += max(0, diff)
                }
                flux[t] = sum
            }
            bandOnsets.append(DSPHelpers.normalizeMax(flux))
        }
        
        return bandOnsets
    }
    
    // MARK: - Onset Strength (Novelty Function)
    
    /// Industry Standard: onset.onset_strength()
    /// Computes the spectral flux (rectified difference) 
    /// which spikes at note onsets.
    public static func onsetStrength(from stft: STFTMatrix) -> [Float] {
        let nFreqs = stft.nFreqs
        let nFrames = stft.nFrames
        
        var strength = [Float](repeating: 0, count: nFrames)
        
        for t in 1..<nFrames {
            var flux: Float = 0
            for f in 0..<nFreqs {
                let current = stft.magnitude[t * nFreqs + f]
                let previous = stft.magnitude[(t - 1) * nFreqs + f]
                
                // Rectified difference: max(0, curr - prev)
                flux += max(0, current - previous)
            }
            strength[t] = flux
        }
        
        // Normalize
        return DSPHelpers.normalizeMax(strength)
    }
    
    // MARK: - Tempo Tracking
    
    /// Industry Standard: beat.tempo()
    /// Estimates BPM using autocorrelation of the onset strength.
    public static func estimateTempo(onsetStrength: [Float], sr: Double, hopLength: Int) -> (bpm: Float, confidence: Float) {
        let n = onsetStrength.count
        guard n > 0 else { return (120.0, 0.0) }
        
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
        
        // 3. Confidence: Peak-to-Mean ratio of autocorrelation in range
        var meanVal: Float = 0
        acorr.withUnsafeBufferPointer { ptr in
            if let base = ptr.baseAddress {
                vDSP_meanv(base + minLag, 1, &meanVal, vDSP_Length(maxLag - minLag + 1))
            }
        }
        let confidence = maxVal > 0 ? min(1.0, (maxVal - meanVal) / maxVal) : 0.0
        
        return (bestBPM, confidence)
    }
}
