// OnsetEngine.swift
// Elite Music DNA Engine — Phase 2
//
// Librosa eşdeğeri: onset.onset_strength_multi() + onset_detect()
//
// Tam algoritma (kaynak koddan):
//   1. Mel spectrogram → power_to_db (log scale)
//   2. max_size=1 → ref = S (no max-filter in default mode)
//   3. onset_env = maximum(0, S[t+1] - S[t])  (spectral flux, half-wave rectified)
//   4. aggregate = np.mean across mel bins
//   5. center pad: n_fft//(2*hop_length) frames left-pad
//   6. Peak pick: pre_max=30ms, post_max=0ms, pre_avg=100ms, wait=30ms, delta=0.07

import Accelerate
import Foundation

public struct OnsetResult: Sendable {
    public let envelope: [Float]      // Onset strength per frame
    public let onsetFrames: [Int]     // Detected onset locations (in frames)
    public let onsetTimes: [Double]   // Onset times in seconds
    public let mean: Float
    public let peak: Float
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

    /// Librosa: onset.onset_strength(y, sr, aggregate=np.mean)
    public func onsetStrength(_ samples: [Float]) -> OnsetResult {
        let stftResult = stft.analyze(samples)

        // Mel power spectrogram
        let melSpec = mel.apply(magnitude: stftResult.magnitude, nFrames: stftResult.nFrames)

        // power_to_db (10 * log10, ref = max)
        let dbSpec = stft.powerToDb(melSpec)

        let nMels = dbSpec.count
        let nFrames = dbSpec[0].count

        // Spectral flux onset envelope:
        // onset_env[t] = mean_mel( max(0, S[mel, t] - S[mel, t-1]) )
        // Librosa lag=1 default
        var envelope = [Float](repeating: 0, count: nFrames)

        for t in 1..<nFrames {
            var frameFlux: Float = 0
            for m in 0..<nMels {
                let diff = dbSpec[m][t] - dbSpec[m][t - 1]
                if diff > 0 { frameFlux += diff }
            }
            envelope[t] = frameFlux / Float(nMels)  // aggregate: mean
        }

        // Center compensation: pad_width = n_fft // (2 * hop_length)
        let padWidth = stft.nFFT / (2 * hopLength)
        if padWidth > 0 && padWidth < envelope.count {
            // Shift right by padWidth (prepend zeros)
            envelope = [Float](repeating: 0, count: padWidth) + Array(envelope.dropLast(padWidth))
        }

        // Normalize to [0, 1]
        var maxVal: Float = 0
        var minVal: Float = 0
        vDSP_maxv(envelope, 1, &maxVal, vDSP_Length(envelope.count))
        vDSP_minv(envelope, 1, &minVal, vDSP_Length(envelope.count))
        let range = maxVal - minVal
        if range > 1e-8 {
            var shift = -minVal
            vDSP_vsadd(envelope, 1, &shift, &envelope, 1, vDSP_Length(envelope.count))
            var invRange = 1.0 / range
            vDSP_vsmul(envelope, 1, &invRange, &envelope, 1, vDSP_Length(envelope.count))
        }

        // Statistics
        var mean: Float = 0
        var peak: Float = 0
        vDSP_meanv(envelope, 1, &mean, vDSP_Length(envelope.count))
        vDSP_maxv(envelope, 1, &peak, vDSP_Length(envelope.count))

        // Peak pick (Librosa default params scaled to frame rate)
        let frameRate = sampleRate / Double(hopLength)
        let preMax  = max(1, Int(0.03 * frameRate))   // 30ms
        let postMax = max(1, Int(0.00 * frameRate) + 1)
        let preAvg  = max(1, Int(0.10 * frameRate))   // 100ms
        let postAvg = max(1, Int(0.10 * frameRate) + 1)
        let wait    = max(1, Int(0.03 * frameRate))   // 30ms

        let onsetFrames = DSPHelpers.peakPick(
            envelope,
            preMax: preMax,
            postMax: postMax,
            preAvg: preAvg,
            postAvg: postAvg,
            wait: wait,
            delta: 0.07
        )

        let onsetTimes = onsetFrames.map { Double($0 * hopLength) / sampleRate }

        return OnsetResult(
            envelope: envelope,
            onsetFrames: onsetFrames,
            onsetTimes: onsetTimes,
            mean: mean,
            peak: peak
        )
    }
}
