// YINEngine.swift
// Elite Music DNA Engine — Phase 2
//
// Librosa eşdeğeri: core/pitch.py → yin()
//
// Tam algoritma (kaynak koddan):
//   1. Frame'e böl
//   2. CMND (Cumulative Mean Normalized Difference) hesapla
//   3. Threshold trough: tau < 0.1
//   4. Parabolic interpolation (sub-bin refinement)
//   5. f0 = sr / period
//
// KRİTİK EK: V/UV (Voiced/Unvoiced) karar mekanizması
//   - Unvoiced: trough_value >= threshold (0.1), yani belirsiz F0
//   - Energy gate: RMS < energy_threshold → sessiz bölge → NaN
//   - Bu olmadan davul ve sessiz bölgeler sahte frekans üretir

import Accelerate
import Foundation

public struct PitchResult: Sendable {
    public let f0Series: [Float]      // F0 per frame (NaN = unvoiced/silent)
    public let voicedFrames: [Int]    // Voiced frame indices
    public let meanF0: Float          // Mean of voiced frames only
    public let medianF0: Float        // Median of voiced frames (more robust)
}

public final class YINEngine: @unchecked Sendable {

    public let sampleRate: Double
    public let frameLength: Int       // Librosa default: 2048
    public let hopLength: Int
    public let fMin: Float            // Minimum detectable F0 (Hz), default: 32.7 (C1)
    public let fMax: Float            // Maximum detectable F0 (Hz), default: 2093 (C7)
    public let threshold: Float       // YIN threshold, default: 0.1

    // V/UV energy gate
    public let energyThreshold: Float // RMS below this → unvoiced, default: 0.01

    public init(sampleRate: Double = 22050, frameLength: Int = 2048, hopLength: Int = 512,
                fMin: Float = 32.7, fMax: Float = 2093.0, threshold: Float = 0.1,
                energyThreshold: Float = 0.01) {
        self.sampleRate = sampleRate
        self.frameLength = frameLength
        self.hopLength = hopLength
        self.fMin = fMin
        self.fMax = fMax
        self.threshold = threshold
        self.energyThreshold = energyThreshold
    }

    // MARK: Analyze

    public func analyze(samples: [Float]) -> PitchResult {
        let n = samples.count
        let nFrames = max(1, 1 + (n - frameLength) / hopLength)
        var f0Series = [Float](repeating: Float.nan, count: nFrames)

        // Lag range from fMin/fMax
        let tauMax = Int(Float(sampleRate) / fMin)
        let tauMin = Int(Float(sampleRate) / fMax)

        for t in 0..<nFrames {
            let start = t * hopLength
            let end = min(start + frameLength, n)
            let frameLen = end - start
            guard frameLen == frameLength else { continue }

            let frame = Array(samples[start..<end])

            // V/UV Energy gate (kullanıcı feedbackinden: energy threshold ekle)
            var rms: Float = 0
            vDSP_measqv(frame, 1, &rms, vDSP_Length(frameLen))
            rms = sqrtf(rms)
            guard rms >= energyThreshold else {
                f0Series[t] = Float.nan  // Sessiz bölge
                continue
            }

            // CMND hesabı
            let cmnd = computeCMND(frame: frame, tauMin: tauMin, tauMax: tauMax)

            // Threshold trough: ilk tau < threshold
            guard let period = findPeriod(cmnd: cmnd, tauMin: tauMin, tauMax: tauMax) else {
                // Unvoiced: güvenilir pitch yok
                f0Series[t] = Float.nan
                continue
            }

            // F0 from period
            f0Series[t] = Float(sampleRate) / period
        }

        // Voiced frames (finite F0)
        let voicedFrames = (0..<nFrames).filter { !f0Series[$0].isNaN }
        let voicedF0 = voicedFrames.map { f0Series[$0] }

        // Mean and median of voiced frames
        let meanF0: Float
        let medianF0: Float

        if voicedF0.isEmpty {
            meanF0 = Float.nan
            medianF0 = Float.nan
        } else {
            var sum: Float = 0
            for v in voicedF0 { sum += v }
            meanF0 = sum / Float(voicedF0.count)

            let sorted = voicedF0.sorted()
            medianF0 = sorted[sorted.count / 2]
        }

        return PitchResult(
            f0Series: f0Series,
            voicedFrames: voicedFrames,
            meanF0: meanF0,
            medianF0: medianF0
        )
    }

    // MARK: CMND (Cumulative Mean Normalized Difference)

    /// YIN algoritması step 2-4:
    /// 1. Difference function: d[tau] = sum(x[n] - x[n+tau])^2
    ///    = 2 * acf[0] - 2 * acf[tau]  (autocorrelation formulation)
    /// 2. CMND: cmnd[tau] = d[tau] / (sum(d[1..tau]) / tau)
    private func computeCMND(frame: [Float], tauMin: Int, tauMax: Int) -> [Float] {
        let n = frame.count
        let maxTau = min(tauMax, n / 2)

        // Difference function via autocorrelation
        let acf = DSPHelpers.autocorrelate(frame, maxSize: maxTau + 1)

        var diff = [Float](repeating: 0, count: maxTau + 1)
        diff[0] = 0
        for tau in 1...maxTau {
            // d[tau] = 2 * (acf[0] - acf[tau])
            diff[tau] = 2.0 * (acf[0] - acf[tau])
        }

        // Cumulative mean normalization
        var cmnd = [Float](repeating: 1.0, count: maxTau + 1)
        cmnd[0] = 1.0
        var running: Float = 0
        for tau in 1...maxTau {
            running += diff[tau]
            if running > 0 {
                cmnd[tau] = diff[tau] * Float(tau) / running
            } else {
                cmnd[tau] = 1.0
            }
        }

        return cmnd
    }

    // MARK: Period Finder (Trough + Parabolic Interpolation)

    /// YIN step 5-6:
    /// 1. Find first tau in [tauMin, tauMax] where cmnd < threshold
    /// 2. Global minimum fallback
    /// 3. Parabolic interpolation for sub-bin precision
    private func findPeriod(cmnd: [Float], tauMin: Int, tauMax: Int) -> Float? {
        let validEnd = min(tauMax, cmnd.count - 1)

        // Find first trough below threshold (local minimum + below threshold)
        var candidateTau: Int? = nil
        for tau in tauMin...validEnd {
            if cmnd[tau] < threshold {
                // Local minimum check
                if tau > 0 && tau < cmnd.count - 1 &&
                   cmnd[tau] < cmnd[tau - 1] {
                    candidateTau = tau
                    break
                }
            }
        }

        // Global minimum fallback (pYIN approach)
        if candidateTau == nil {
            var minVal = Float.infinity
            var minTau = tauMin
            for tau in tauMin...validEnd {
                if cmnd[tau] < minVal {
                    minVal = cmnd[tau]
                    minTau = tau
                }
            }
            // Only use if reasonably confident (< 0.3)
            if minVal < 0.3 {
                candidateTau = minTau
            }
        }

        guard let tau = candidateTau else { return nil }

        // Parabolic interpolation for sub-integer period
        if tau > 0 && tau < cmnd.count - 1 {
            let s0 = cmnd[tau - 1]
            let s1 = cmnd[tau]
            let s2 = cmnd[tau + 1]
            let adjustment = (s2 - s0) / (2.0 * (2.0 * s1 - s2 - s0))
            return Float(tau) + adjustment
        }

        return Float(tau)
    }
}
