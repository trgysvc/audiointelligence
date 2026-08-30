import Foundation

/// pYIN Stage 2 (Mauch & Dixon 2014, section 2.2): HMM-based pitch tracking over `YINEngine`'s
/// Stage-1 multi-candidate output. 480 pitch bins spanning 4 octaves (55Hz/A1 to just under
/// 880Hz/A5) at 10-cent (0.1 semitone) resolution, each with a voiced and an unvoiced state
/// (960 states total) — not a single shared "silence" state as a simpler pitch-smoothing HMM
/// would use. Pitch transitions follow a triangular window (max jump 25 bins = 2.5 semitones per
/// frame); voicing transitions are a simple 0.99-stay/0.01-switch model, independent of pitch.
///
/// Deliberately NOT built on `ViterbiEngine.decode()`'s generic O(nStates^2) recursion — at 960
/// states that's ~920K operations per frame, and the paper explicitly notes it "exploits the
/// sparseness of the transition matrix" for efficiency. This decoder exploits the same sparsity
/// directly (only the +-24-bin band around each state has nonzero transition weight), bringing
/// the per-frame cost down to ~188K operations.
///
/// Known range limitation, inherited from the paper: candidates outside 55-880Hz (e.g. a bass
/// guitar's low register, or pitches above a soprano's range) fall outside this HMM's 480 bins
/// and are silently unrepresentable here, even though `YINEngine`'s own `fMin`/`fMax` can be
/// configured wider for Stage 1. This mirrors pYIN's original design target (solo singing) and
/// is a real, documented constraint — not a bug — for material outside that range.
public final class PYINDecoder: Sendable {
    public let nBins = 480
    private let minHz: Float = 55.0
    private let centsPerBin: Float = 10.0
    private let maxJump = 24 // bins; triangular window support is -maxJump...maxJump
    private let voicingSelfProb: Float = 0.99

    public init() {}

    private func binToHz(_ bin: Int) -> Float {
        minHz * powf(2.0, Float(bin) * centsPerBin / 1200.0)
    }

    /// Nearest bin for a frequency, or nil if outside the 4-octave window.
    private func hzToBin(_ hz: Float) -> Int? {
        guard hz.isFinite, hz > 0 else { return nil }
        let bin = Int((1200.0 * log2f(hz / minHz) / centsPerBin).rounded())
        guard bin >= 0, bin < nBins else { return nil }
        return bin
    }

    /// Raw (unnormalized) triangular weight at offset `d`, `-maxJump...maxJump`, peak at 0.
    private func rawTriangularWeight(_ d: Int) -> Float {
        Float(maxJump + 1 - abs(d))
    }

    /// Per-source-bin normalization sum (edge bins have a truncated window, per the paper: "the
    /// window is always normalised to sum to 1").
    private func buildEdgeNormSums() -> [Float] {
        (0..<nBins).map { i in
            var sum: Float = 0
            for d in -maxJump...maxJump where i + d >= 0 && i + d < nBins {
                sum += rawTriangularWeight(d)
            }
            return sum
        }
    }

    /// Per-frame emission: `obsVoiced[m]` for each pitch bin, and a single scalar `unvoiced`
    /// (identical across all bins, per eq. 6 — "unvoiced" doesn't distinguish which pitch).
    private func observation(for candidates: [PYINFrequencyCandidate]) -> (voiced: [Float], unvoiced: Float) {
        var voiced = [Float](repeating: 0, count: nBins)
        var totalMass: Float = 0
        for c in candidates {
            guard let bin = hzToBin(c.frequencyHz) else { continue }
            voiced[bin] += c.probability
            totalMass += c.probability
        }
        for i in 0..<nBins { voiced[i] *= 0.5 }
        let unvoiced = 0.5 * max(0, 1 - totalMass)
        return (voiced, unvoiced)
    }

    /// Decodes the most likely pitch track. Returns one f0 (Hz) per frame; `.nan` where the
    /// decoded state is unvoiced — matching `YINEngine.PitchResult`'s own NaN-for-unvoiced
    /// convention.
    public func decode(candidatesPerFrame: [[PYINFrequencyCandidate]]) -> [Float] {
        let nFrames = candidatesPerFrame.count
        guard nFrames > 0 else { return [] }

        let edgeNormSums = buildEdgeNormSums()
        let nStates = 2 * nBins
        func voicedState(_ b: Int) -> Int { b }
        func unvoicedState(_ b: Int) -> Int { nBins + b }

        let logVoicingSame = logf(voicingSelfProb)
        let logVoicingSwitch = logf(1 - voicingSelfProb)
        let floor: Float = 1e-20

        var viterbi = [[Float]](repeating: [Float](repeating: -Float.infinity, count: nStates), count: nFrames)
        var backptr = [[Int32]](repeating: [Int32](repeating: -1, count: nStates), count: nFrames)

        // Frame 0: uniform over UNVOICED states only (paper: "initial probabilities are set to
        // be uniformly distributed over the unvoiced states").
        let obs0 = observation(for: candidatesPerFrame[0])
        let logInitUnvoiced = logf(1.0 / Float(nBins))
        for b in 0..<nBins {
            viterbi[0][unvoicedState(b)] = logInitUnvoiced + logf(max(obs0.unvoiced, floor))
        }

        for t in 1..<nFrames {
            let obs = observation(for: candidatesPerFrame[t])
            let prevRow = viterbi[t - 1]

            for j in 0..<nBins {
                let lo = max(0, j - maxJump), hi = min(nBins - 1, j + maxJump)
                var bestToVoiced: Float = -Float.infinity, bestToVoicedFrom: Int32 = -1
                var bestToUnvoiced: Float = -Float.infinity, bestToUnvoicedFrom: Int32 = -1

                for i in lo...hi {
                    let d = j - i
                    let pitchW = rawTriangularWeight(d) / edgeNormSums[i]
                    guard pitchW > 0 else { continue }
                    let logPitch = logf(pitchW)

                    let fromV = prevRow[voicedState(i)]
                    let fromU = prevRow[unvoicedState(i)]

                    // -> target voiced: from voiced (same-voicing) or from unvoiced (switch)
                    let candVtoV = fromV + logPitch + logVoicingSame
                    if candVtoV > bestToVoiced { bestToVoiced = candVtoV; bestToVoicedFrom = Int32(voicedState(i)) }
                    let candUtoV = fromU + logPitch + logVoicingSwitch
                    if candUtoV > bestToVoiced { bestToVoiced = candUtoV; bestToVoicedFrom = Int32(unvoicedState(i)) }

                    // -> target unvoiced: from unvoiced (same-voicing) or from voiced (switch)
                    let candUtoU = fromU + logPitch + logVoicingSame
                    if candUtoU > bestToUnvoiced { bestToUnvoiced = candUtoU; bestToUnvoicedFrom = Int32(unvoicedState(i)) }
                    let candVtoU = fromV + logPitch + logVoicingSwitch
                    if candVtoU > bestToUnvoiced { bestToUnvoiced = candVtoU; bestToUnvoicedFrom = Int32(voicedState(i)) }
                }

                viterbi[t][voicedState(j)] = bestToVoiced + logf(max(obs.voiced[j], floor))
                backptr[t][voicedState(j)] = bestToVoicedFrom
                viterbi[t][unvoicedState(j)] = bestToUnvoiced + logf(max(obs.unvoiced, floor))
                backptr[t][unvoicedState(j)] = bestToUnvoicedFrom
            }
        }

        // Termination + backtrack.
        var path = [Int](repeating: 0, count: nFrames)
        var bestFinal: Float = -Float.infinity
        for s in 0..<nStates where viterbi[nFrames - 1][s] > bestFinal {
            bestFinal = viterbi[nFrames - 1][s]
            path[nFrames - 1] = s
        }
        for t in stride(from: nFrames - 1, to: 0, by: -1) {
            let bp = backptr[t][path[t]]
            path[t - 1] = bp >= 0 ? Int(bp) : path[t]
        }

        return path.map { state in
            state < nBins ? binToHz(state) : Float.nan
        }
    }
}
