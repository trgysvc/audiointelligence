// YINEngine.swift
// Elite Music DNA Engine — Phase 2
//
// Industry Standard equivalent: core/pitch.py → yin()
//
// Full algorithm (from source code):
//   1. Frame decomposition
//   2. CMND (Cumulative Mean Normalized Difference) calculation
//   3. Threshold trough detection: tau < 0.1
//   4. Parabolic interpolation (sub-bin refinement)
//   5. f0 = sr / period
//
// CRITICAL ADDITION: V/UV (Voiced/Unvoiced) Decision Logic
//   - Unvoiced: trough_value >= threshold (0.1), i.e., ambiguous F0
//   - Energy gate: RMS < energy_threshold → silent region → NaN
//   - Without this, percussion and silent regions generate false pitch data.

import Accelerate
import Foundation

public struct PitchResult: Codable, Sendable {
    public let f0Series: [Float]      // F0 per frame (NaN = unvoiced/silent)
    public let voicedFrames: [Int]    // Voiced frame indices
    public let meanF0: Float          // Mean of voiced frames only
    public let medianF0: Float        // Median of voiced frames (more robust)

    /// Builds a `PitchResult` from a raw f0-per-frame series (NaN = unvoiced), deriving
    /// `voicedFrames`/`meanF0`/`medianF0` the same way `YINEngine.analyze` does. Used to wrap
    /// `PYINDecoder.decode(candidatesPerFrame:)`'s output (also a NaN-for-unvoiced `[Float]`)
    /// into the same shape `YINEngine.analyze`'s callers already consume, so pYIN is a drop-in
    /// replacement for YIN wherever a `PitchResult` is expected.
    public static func from(f0Series: [Float]) -> PitchResult {
        let voicedFrames = f0Series.indices.filter { !f0Series[$0].isNaN }
        let voicedF0 = voicedFrames.map { f0Series[$0] }
        let meanF0: Float
        let medianF0: Float
        if voicedF0.isEmpty {
            meanF0 = Float.nan
            medianF0 = Float.nan
        } else {
            meanF0 = voicedF0.reduce(0, +) / Float(voicedF0.count)
            medianF0 = voicedF0.sorted()[voicedF0.count / 2]
        }
        return PitchResult(f0Series: f0Series, voicedFrames: voicedFrames, meanF0: meanF0, medianF0: medianF0)
    }
}

/// One frame's pYIN candidate: a period estimate with the probability mass the Beta-weighted
/// threshold sweep assigned to it (Mauch & Dixon 2014, eq. 4). Candidate probabilities across a
/// frame sum to <= 1; the remainder is the frame's unvoiced probability mass.
public struct PYINCandidate: Sendable {
    public let tau: Float       // sub-sample-interpolated period, in samples
    public let probability: Float
}

/// A `PYINCandidate` converted to frequency domain — what `analyzePYINCandidates` and the
/// pYIN-HMM stage actually consume (the HMM works in Hz/pitch-bin space, not period samples).
public struct PYINFrequencyCandidate: Sendable {
    public let frequencyHz: Float
    public let probability: Float
}

/// Time-Domain Fundamental Frequency Estimation Engine (YIN).
/// Provides robust pitch tracking by minimizing the squared difference function.
public final class YINEngine: @unchecked Sendable {

    public let sampleRate: Double
    public let frameLength: Int       // Industry Standard default: 2048
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

            // V/UV Energy gate (from user feedback: add energy threshold)
            var rms: Float = 0
            vDSP_measqv(frame, 1, &rms, vDSP_Length(frameLen))
            rms = sqrtf(rms)
            guard rms >= energyThreshold else {
                f0Series[t] = Float.nan  // Silent region
                continue
            }

            // CMND calculation
            let cmnd = computeCMND(frame: frame, tauMin: tauMin, tauMax: tauMax)

            // Threshold trough: ilk tau < threshold
            guard let period = findPeriod(cmnd: cmnd, tauMin: tauMin, tauMax: tauMax) else {
                // Unvoiced: no reliable pitch found
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

    /// YIN algorithm step 2-4:
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
        // `stride` (not `1...maxTau`) — a very short frameLength can make maxTau 0, and a
        // ClosedRange with lowerBound > upperBound (1...0) traps; stride is empty-safe.
        for tau in stride(from: 1, through: maxTau, by: 1) {
            // d[tau] = 2 * (acf[0] - acf[tau])
            diff[tau] = 2.0 * (acf[0] - acf[tau])
        }

        // Cumulative mean normalization
        var cmnd = [Float](repeating: 1.0, count: maxTau + 1)
        cmnd[0] = 1.0
        var running: Float = 0
        for tau in stride(from: 1, through: maxTau, by: 1) {
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
    func findPeriod(cmnd: [Float], tauMin: Int, tauMax: Int) -> Float? {
        let validEnd = min(tauMax, cmnd.count - 1)

        // Find first trough below threshold, then descend to its TRUE local minimum (canonical
        // YIN step 4: don't stop at the first point below threshold if cmnd keeps decreasing —
        // that point isn't the trough bottom yet, and feeding it into the parabolic
        // interpolation below as if it were gives a biased, non-principled estimate).
        var candidateTau: Int? = nil
        var tau = tauMin
        while tau <= validEnd {
            if cmnd[tau] < threshold {
                while tau + 1 <= validEnd && cmnd[tau + 1] < cmnd[tau] {
                    tau += 1
                }
                candidateTau = tau
                break
            }
            tau += 1
        }

        // Global minimum fallback (pYIN approach). `stride` (not `tauMin...validEnd`) — a very
        // short frameLength combined with a high fMax can make tauMin > validEnd (fMax pushes
        // tauMin up while a short frame caps validEnd down), and a ClosedRange traps in that
        // case; stride is empty-safe and just skips to "no candidate" instead.
        if candidateTau == nil {
            var minVal = Float.infinity
            var minTau = tauMin
            for tau in stride(from: tauMin, through: validEnd, by: 1) {
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

    // MARK: - pYIN (Mauch & Dixon 2014): multi-candidate, probabilistic-threshold extension

    /// Sub-sample-refines a candidate tau via the same parabolic interpolation `findPeriod` uses.
    private func refine(tau: Int, cmnd: [Float]) -> Float {
        guard tau > 0, tau < cmnd.count - 1 else { return Float(tau) }
        let s0 = cmnd[tau - 1], s1 = cmnd[tau], s2 = cmnd[tau + 1]
        let denom = 2.0 * (2.0 * s1 - s2 - s0)
        guard abs(denom) > 1e-12 else { return Float(tau) }
        return Float(tau) + (s2 - s0) / denom
    }

    /// All interior local minima (troughs) of the CMND curve in `[tauMin, tauMax]` — the full
    /// candidate pool pYIN's threshold sweep draws from (not just the first below-threshold one
    /// `findPeriod` stops at).
    private func findLocalMinima(cmnd: [Float], tauMin: Int, tauMax: Int) -> [(tau: Int, value: Float)] {
        let validEnd = min(tauMax, cmnd.count - 2) // need tau+1 in range
        let validStart = max(tauMin, 1)            // need tau-1 in range
        guard validStart <= validEnd else { return [] }
        var dips: [(tau: Int, value: Float)] = []
        for tau in validStart...validEnd {
            if cmnd[tau] < cmnd[tau - 1] && cmnd[tau] <= cmnd[tau + 1] {
                dips.append((tau, cmnd[tau]))
            }
        }
        return dips
    }

    /// Closed-form Beta(2,18) CDF — the pYIN threshold prior (Mauch & Dixon's mean=0.10 variant,
    /// the one most commonly cited as pYIN's default; alpha=2 fixed across their three tested
    /// priors, beta=18/11.33/8 for means 0.10/0.15/0.20).
    ///
    /// For integer alpha=2, the regularized incomplete beta function has a closed polynomial
    /// form — derived directly rather than looked up: f(x) = 342*x*(1-x)^17 (342 = 1/B(2,18) =
    /// 18*19), and integrating f from 0 to x gives, with y = 1-x:
    ///   CDF(x) = 1 - 19*y^18 + 18*y^19
    /// (CDF(0)=0, CDF(1)=1, verified algebraically). Exact and threshold-grid-independent — no
    /// discretization artifact from approximating the continuous prior with N sample points.
    private static func betaCDF18(_ x: Float) -> Float {
        let xc = min(max(x, 0), 1)
        let y = 1 - xc
        let y18 = powf(y, 18)
        return 1 - 19 * y18 + 18 * y18 * y
    }

    /// pYIN Stage 1 (Mauch & Dixon 2014, eq. 4-5): instead of one hard threshold, integrates a
    /// Beta-distributed threshold PRIOR (continuous, not a discretized grid) to find, for every
    /// period any threshold in [0,1] could have selected, the exact probability mass of
    /// thresholds that select it.
    ///
    /// Efficient equivalent of sweeping every threshold in [0,1] and re-running YIN at each one
    /// (see DEVLOG): sort all CMND troughs by their OWN value ascending (= the threshold at which
    /// each first becomes eligible); as thresholds rise, the selected candidate is always the
    /// smallest-tau trough among those eligible so far, so scanning troughs in value order and
    /// tracking a running minimum tau yields the exact sequence of "winners" and the threshold
    /// breakpoints between them in one pass. Each winner's probability is then the EXACT definite
    /// integral of the Beta(2,18) density over its breakpoint range (`betaCDF18` difference) —
    /// analytic, not a 100-point discrete sum, so it doesn't depend on any threshold-grid
    /// resolution.
    func pyinCandidates(cmnd: [Float], tauMin: Int, tauMax: Int) -> [PYINCandidate] {
        let validEnd = min(tauMax, cmnd.count - 1)
        guard tauMin <= validEnd else { return [] }

        // Global-minimum fallback (used only for thresholds below the first real trough's value).
        var fallbackTau = tauMin
        var fallbackVal = Float.infinity
        for tau in stride(from: tauMin, through: validEnd, by: 1) where cmnd[tau] < fallbackVal {
            fallbackVal = cmnd[tau]
            fallbackTau = tau
        }

        let dips = findLocalMinima(cmnd: cmnd, tauMin: tauMin, tauMax: tauMax)
        let sortedByValue = dips.sorted { $0.value < $1.value }

        // "Winners": the prefix-minima-by-tau sequence as thresholds rise, each tagged with the
        // threshold (= its own CMND value) at which it starts being selected.
        var winners: [(threshold: Float, tau: Int)] = []
        var runningMinTau = Int.max
        for dip in sortedByValue where dip.tau < runningMinTau {
            runningMinTau = dip.tau
            winners.append((dip.value, dip.tau))
        }

        let pA: Float = 0.01 // Mauch & Dixon's fallback-strategy weight
        var massByTau: [Int: Float] = [:]

        // Fallback region: thresholds in [0, winners[0].threshold) where no trough is eligible
        // yet, weighted by pA (eq. 5's "otherwise" branch).
        let firstBreak = winners.first?.threshold ?? 1.0
        let fallbackMass = Self.betaCDF18(firstBreak) - Self.betaCDF18(0)
        if fallbackMass > 0 {
            massByTau[fallbackTau, default: 0] += fallbackMass * pA
        }

        // Each winner owns [its own threshold, next winner's threshold) (or 1.0 for the last).
        for (idx, winner) in winners.enumerated() {
            let upper = idx + 1 < winners.count ? winners[idx + 1].threshold : 1.0
            let mass = Self.betaCDF18(upper) - Self.betaCDF18(winner.threshold)
            guard mass > 0 else { continue }
            massByTau[winner.tau, default: 0] += mass
        }

        return massByTau.map { PYINCandidate(tau: refine(tau: $0.key, cmnd: cmnd), probability: $0.value) }
            .sorted { $0.probability > $1.probability }
    }

    /// pYIN Stage 1 over a full signal: per-frame candidate lists (frequency + probability),
    /// mirroring `analyze`'s frame decomposition and energy gate but without collapsing to a
    /// single f0 — `ViterbiEngine`'s pYIN-HMM extension consumes this directly.
    public func analyzePYINCandidates(samples: [Float]) -> [[PYINFrequencyCandidate]] {
        let n = samples.count
        let nFrames = max(1, 1 + (n - frameLength) / hopLength)
        var result = [[PYINFrequencyCandidate]](repeating: [], count: nFrames)

        let tauMax = Int(Float(sampleRate) / fMin)
        let tauMin = Int(Float(sampleRate) / fMax)

        for t in 0..<nFrames {
            let start = t * hopLength
            let end = min(start + frameLength, n)
            guard end - start == frameLength else { continue }
            let frame = Array(samples[start..<end])

            var rms: Float = 0
            vDSP_measqv(frame, 1, &rms, vDSP_Length(frameLength))
            rms = sqrtf(rms)
            guard rms >= energyThreshold else { continue } // stays [] -> fully unvoiced

            let cmnd = computeCMND(frame: frame, tauMin: tauMin, tauMax: tauMax)
            let candidates = pyinCandidates(cmnd: cmnd, tauMin: tauMin, tauMax: tauMax)
            result[t] = candidates
                .map { PYINFrequencyCandidate(frequencyHz: Float(sampleRate) / $0.tau, probability: $0.probability) }
                .filter { $0.frequencyHz.isFinite }
        }
        return result
    }
}
