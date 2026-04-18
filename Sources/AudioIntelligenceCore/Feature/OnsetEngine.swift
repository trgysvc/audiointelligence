// OnsetEngine.swift
// Elite Music DNA Engine — Phase 2
//
// Industry Standard equivalent: onset.onset_strength_multi() + onset_detect()
//
// Full algorithm (kaynak koddan):
//   1. Mel spectrogram → power_to_db (log scale)
//   2. max_size=1 → ref = S (no max-filter in default mode)
//   3. onset_env = maximum(0, S[t+1] - S[t])  (spectral flux, half-wave rectified)
//   4. aggregate = np.mean across mel bins
//   5. center pad: n_fft//(2*hop_length) frames left-pad
//   6. Peak pick: pre_max=30ms, post_max=0ms, pre_avg=100ms, wait=30ms, delta=0.07

import Accelerate
import Foundation

public enum OnsetMode: String, Sendable {
    case spectralFlux      // Standard spectral flux (rectified difference)
    case superflux         // Max-filtered spectral flux (better for vibrato suppression)
    case energy            // Mean energy of frames
    case spectralCentroid  // Centroid-based onset detection
    case complexDomain     // Complex domain novelty (phase + magnitude)
}

public struct OnsetResult: Sendable {
    public let envelope: [Float]      // Onset strength per frame
    public let onsetFrames: [Int]     // Detected onset locations (in frames)
    public let onsetTimes: [Double]   // Onset times in seconds
    public let mean: Float
    public let peak: Float
    public let mode: OnsetMode        // Used mode
}

public final class OnsetEngine: @unchecked Sendable {

    private let stft: STFTEngine
    private let mel: MelFilterBank
    private let sampleRate: Double
    private let hopLength: Int

    public init(sampleRate: Double = 22050, nFFT: Int = 2048, hopLength: Int = 512) {
        self.sampleRate = sampleRate
        self.hopLength = hopLength
        self.stft = STFTEngine(nFFT: nFFT, hopLength: hopLength, sampleRate: sampleRate)
        self.mel = MelFilterBank(nMels: 128, nFFT: nFFT, sampleRate: sampleRate,
                                 fMin: 0.0, fMax: Float(sampleRate / 2.0))
    }

    // MARK: Onset Strength

    /// Industry Standard-style onset strength detection with multiple modes.
    /// - Parameters:
    ///   - samples: Raw audio samples
    ///   - mode: Detection algorithm (default: .superflux)
    ///   - useMel: Whether to use Mel spectrogram (default: true)
    public func onsetStrength(_ samples: [Float], mode: OnsetMode = .superflux, useMel: Bool = true) async -> OnsetResult {
        let stftResult = await stft.analyze(samples)
        let nFrames = stftResult.nFrames
        let nFreqs = stftResult.nFreqs
        
        var envelope = [Float](repeating: 0, count: nFrames)
        
        switch mode {
        case .spectralFlux, .superflux:
            let magnitude: [[Float]]
            if useMel {
                magnitude = mel.apply(magnitude: stftResult.magnitude, nFrames: nFrames)
            } else {
                // Return Frequency-major structure for flux calculation logic
                magnitude = (0..<nFreqs).map { f in
                    stftResult.magnitudeRow(forBin: f)
                }
            }
            
            // Log scale (power_to_db equivalent)
            let logSpec = magnitude.map { stft.powerToDb($0) }
            
            if mode == .superflux {
                envelope = computeSuperflux(logSpec)
            } else {
                envelope = computeSpectralFlux(logSpec)
            }
            
        case .energy:
            // RMS energy per frame (Contiguous in Frame-major)
            for t in 0..<nFrames {
                var sum: Float = 0
                let frame = stftResult.magnitudeFrame(forTimeline: t)
                vDSP_svesq(Array(frame), 1, &sum, vDSP_Length(nFreqs))
                envelope[t] = sqrtf(sum / Float(nFreqs))
            }
            
        case .spectralCentroid:
            // Spectral centroid as novelty function (Optimized cache access)
            for t in 0..<nFrames {
                var weightedSum: Float = 0
                var totalMag: Float = 0
                for f in 0..<nFreqs {
                    let mag = stftResult.magnitude[t * nFreqs + f]
                    weightedSum += mag * Float(f)
                    totalMag += mag
                }
                envelope[t] = totalMag > 1e-8 ? weightedSum / totalMag : 0
            }
            
        case .complexDomain:
            // Simplified complex domain novelty
            // env[t] = sum |X[t] - X_pred[t]| where X_pred is predicted from previous phase
            envelope = computeComplexDomainNovelty(stft: stftResult)
        }

        // Center compensation: pad_width = n_fft // (2 * hop_length)
        let padWidth = stft.nFFT / (2 * hopLength)
        if padWidth > 0 && padWidth < envelope.count {
            envelope = [Float](repeating: 0, count: padWidth) + Array(envelope.dropLast(padWidth))
        }

        // Normalize to [0, 1]
        envelope = DSPHelpers.normalizeMax(envelope)

        // Statistics
        var mean: Float = 0
        var peak: Float = 0
        vDSP_meanv(envelope, 1, &mean, vDSP_Length(envelope.count))
        vDSP_maxv(envelope, 1, &peak, vDSP_Length(envelope.count))

        // Peak pick
        let frameRate = sampleRate / Double(hopLength)
        let onsetFrames = DSPHelpers.peakPick(
            envelope,
            preMax: max(1, Int(0.03 * frameRate)),
            postMax: max(1, Int(0.00 * frameRate) + 1),
            preAvg: max(1, Int(0.10 * frameRate)),
            postAvg: max(1, Int(0.10 * frameRate) + 1),
            wait: max(1, Int(0.03 * frameRate)),
            delta: 0.07
        )

        let onsetTimes = onsetFrames.map { Double($0 * hopLength) / sampleRate }

        return OnsetResult(
            envelope: envelope,
            onsetFrames: onsetFrames,
            onsetTimes: onsetTimes,
            mean: mean,
            peak: peak,
            mode: mode
        )
    }
    
    // MARK: - Private Algorithms
    
    private func computeSpectralFlux(_ logSpec: [[Float]]) -> [Float] {
        let nMels = logSpec.count
        let nFrames = logSpec[0].count
        var envelope = [Float](repeating: 0, count: nFrames)
        
        for t in 1..<nFrames {
            var flux: Float = 0
            for m in 0..<nMels {
                let diff = logSpec[m][t] - logSpec[m][t-1]
                if diff > 0 { flux += diff }
            }
            envelope[t] = flux / Float(nMels)
        }
        return envelope
    }
    
    /// Superflux: max-filtered spectral flux.
    /// Industry Standard: onset.onset_strength(..., max_size=3)
    private func computeSuperflux(_ logSpec: [[Float]]) -> [Float] {
        let nMels = logSpec.count
        let nFrames = logSpec[0].count
        var envelope = [Float](repeating: 0, count: nFrames)
        
        // Max-filter each frequency bin independently
        let maxSpec = logSpec.map { DSPHelpers.maxFilter1D($0, windowSize: 3) }
        
        for t in 1..<nFrames {
            var flux: Float = 0
            for m in 0..<nMels {
                // S[t] - max_filter(S[t-1])
                let diff = logSpec[m][t] - maxSpec[m][t-1]
                if diff > 0 { flux += diff }
            }
            envelope[t] = flux / Float(nMels)
        }
        return envelope
    }
    
    private func computeComplexDomainNovelty(stft: STFTMatrix) -> [Float] {
        let nFrames = stft.nFrames
        let nFreqs = stft.nFreqs
        var envelope = [Float](repeating: 0, count: nFrames)
        
        // Real complex domain novelty usually looks at target complex value 
        // derived from previous magnitude and phase prediction.
        // This is a simplified version using magnitude change + phase deviation.
        for t in 2..<nFrames {
            var score: Float = 0
            for f in 0..<nFreqs {
                let m1 = stft.magnitude[t * nFreqs + f]
                let m0 = stft.magnitude[(t - 1) * nFreqs + f]
                let p1 = stft.phase[t * nFreqs + f]
                let p0 = stft.phase[(t - 1) * nFreqs + f]
                let p_1 = stft.phase[(t - 2) * nFreqs + f]
                
                // Phase prediction error
                let phase_pred = 2 * p0 - p_1
                var phase_err = p1 - phase_pred
                // Wrap phase error to [-pi, pi]
                phase_err = phase_err - 2 * .pi * round(phase_err / (2 * .pi))
                
                // Novelty = sqrt( m0^2 + m1^2 - 2*m0*m1*cos(phase_err) )
                score += sqrtf(max(0, m0*m0 + m1*m1 - 2*m0*m1*cosf(phase_err)))
            }
            envelope[t] = score / Float(nFreqs)
        }
        return envelope
    }
}
