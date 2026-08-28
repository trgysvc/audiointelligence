import Foundation
import Accelerate

/// Professional-grade Viterbi Decoder for sequence modeling (HMM).
/// Uses log-space math and Accelerate-optimized emission calculations.
/// Hidden Markov Model (HMM) Viterbi Decoder.
/// Optimized for sequence modeling and pitch path stabilization using dynamic programming.
public final class ViterbiEngine: Sendable {
    
    public init() {}
    
    /// Finds the most likely sequence of states.
    /// - Parameters:
    ///   - observations: Matrix of emission probabilities [nFrames][nStates].
    ///   - transitionMatrix: Square matrix of state transition probabilities [nStates][nStates].
    ///   - startProbs: Initial state probabilities [nStates].
    /// - Returns: Sequence of state indices.
    public func decode(
        observations: [[Float]],
        transitionMatrix: [[Float]],
        startProbs: [Float]
    ) -> [Int] {
        let nFrames = observations.count
        guard nFrames > 0 else { return [] }
        let nStates = startProbs.count
        
        // Log-space transformation to prevent underflow
        let logTransitions = transitionMatrix.map { row in row.map { logf($0 + 1e-20) } }
        let logStart = startProbs.map { logf($0 + 1e-20) }
        let logEmissions = observations.map { row in row.map { logf($0 + 1e-20) } }
        
        // viterbi[frame][state] = max log-probability
        var viterbi = [[Float]](repeating: [Float](repeating: -Float.infinity, count: nStates), count: nFrames)
        // backpointer[frame][state] = index of previous state
        var backpointer = [[Int]](repeating: [Int](repeating: 0, count: nStates), count: nFrames)
        
        // Initialization
        for s in 0..<nStates {
            viterbi[0][s] = logStart[s] + logEmissions[0][s]
        }
        
        // Recursion
        for t in 1..<nFrames {
            for s in 0..<nStates {
                var maxVal: Float = -Float.infinity
                var bestPrev = 0
                
                // Vectorizable inner loop? 
                // Since it's a small state space usually, we use a loop for now.
                for sPrev in 0..<nStates {
                    let prob = viterbi[t-1][sPrev] + logTransitions[sPrev][s]
                    if prob > maxVal {
                        maxVal = prob
                        bestPrev = sPrev
                    }
                }
                
                viterbi[t][s] = maxVal + logEmissions[t][s]
                backpointer[t][s] = bestPrev
            }
        }
        
        // Termination
        var result = [Int](repeating: 0, count: nFrames)
        var maxVal: Float = -Float.infinity
        var lastState = 0
        
        for s in 0..<nStates {
            if viterbi[nFrames - 1][s] > maxVal {
                maxVal = viterbi[nFrames - 1][s]
                lastState = s
            }
        }
        
        // Path Backtracking
        result[nFrames - 1] = lastState
        for t in stride(from: nFrames - 1, to: 0, by: -1) {
            result[t - 1] = backpointer[t][result[t]]
        }
        
        return result
    }
}

// MARK: - Pitch-path smoothing (pYIN-style, simplified)

extension ViterbiEngine {
    /// Smooths a noisy frame-by-frame f0 estimate (e.g. from `YINEngine`) into a stable,
    /// jump-resistant MIDI note path using this decoder — the exact application this engine's
    /// own doc comment describes ("pitch path stabilization"), which was written but never
    /// actually wired into the pipeline (`DNAReportBuilder` always passed `allViterbi: []`).
    ///
    /// A simplified relative of the pYIN algorithm (Mauch & Dixon 2014): pYIN's full HMM uses
    /// MULTIPLE per-frame pitch candidates (from YIN's raw CMND troughs) with probabilities
    /// derived from the CMND curve itself. `YINEngine.analyze` only exposes a single resolved
    /// f0 per frame (no candidate list), so here each frame's emission is a Gaussian centered
    /// on that single estimate instead of a true multi-candidate distribution — still a
    /// genuine HMM-smoothed pitch contour (it removes isolated octave-jump/glitch frames a raw
    /// per-frame estimate is prone to), just built from less information than full pYIN has.
    ///
    /// - Parameters:
    ///   - f0Series: per-frame f0 in Hz, NaN or <=0 for unvoiced/silent (as `YINEngine` emits).
    ///   - minMIDI/maxMIDI: the pitch-state range — defaults to 24...96 (C1-C7), matching
    ///     `YINEngine`'s own default `fMin`/`fMax` (32.7Hz/2093Hz map to exactly this range).
    /// - Returns: one MIDI note number per frame (0 = silence, the same "no pitch" sentinel
    ///   `DSPHelpers.hzToMIDI` already uses elsewhere in this codebase).
    public func smoothPitchPath(f0Series: [Float], minMIDI: Int = 24, maxMIDI: Int = 96) -> [Int] {
        let nFrames = f0Series.count
        guard nFrames > 0 else { return [] }

        let nPitchStates = maxMIDI - minMIDI + 1
        let silenceState = nPitchStates // one extra state past the pitch range
        let nStates = nPitchStates + 1

        let pitchSigma: Float = 1.5      // semitones — emission spread around the raw estimate
        let transitionSigma: Float = 1.0 // semitones — how much pitch may drift frame-to-frame
        let silenceTransitionProb: Float = 0.05

        func gaussian(_ x: Float, sigma: Float) -> Float {
            expf(-0.5 * (x / sigma) * (x / sigma))
        }

        // Emission probabilities per frame per state.
        var observations = [[Float]](repeating: [Float](repeating: 0, count: nStates), count: nFrames)
        for t in 0..<nFrames {
            let hz = f0Series[t]
            if hz.isNaN || hz <= 0 {
                observations[t][silenceState] = 0.9
                for s in 0..<nPitchStates { observations[t][s] = 0.1 / Float(nPitchStates) }
            } else {
                let rawMIDI = 69.0 + 12.0 * log2(Double(hz) / 440.0)
                var rowSum: Float = 0
                for s in 0..<nPitchStates {
                    let dist = Float(rawMIDI) - Float(minMIDI + s)
                    let p = gaussian(dist, sigma: pitchSigma)
                    observations[t][s] = p
                    rowSum += p
                }
                observations[t][silenceState] = 0.01
                // A raw estimate far outside [minMIDI, maxMIDI] would collapse every pitch
                // state's emission to ~0 — fall back to uniform so Viterbi still has a
                // meaningful (if low-confidence) choice instead of an all-zero row.
                if rowSum < 1e-6 {
                    for s in 0..<nPitchStates { observations[t][s] = 1.0 / Float(nPitchStates) }
                }
            }
        }

        // Transition matrix: smooth drift between nearby pitch states, small fixed probability
        // of switching to/from silence.
        var transitions = [[Float]](repeating: [Float](repeating: 0, count: nStates), count: nStates)
        for i in 0..<nPitchStates {
            var rowSum: Float = 0
            for j in 0..<nPitchStates {
                let p = gaussian(Float(i - j), sigma: transitionSigma)
                transitions[i][j] = p
                rowSum += p
            }
            if rowSum > 0 {
                let scale = (1.0 - silenceTransitionProb) / rowSum
                for j in 0..<nPitchStates { transitions[i][j] *= scale }
            }
            transitions[i][silenceState] = silenceTransitionProb
        }
        for j in 0..<nPitchStates { transitions[silenceState][j] = silenceTransitionProb / Float(nPitchStates) }
        transitions[silenceState][silenceState] = 1.0 - silenceTransitionProb

        let startProbs = [Float](repeating: 1.0 / Float(nStates), count: nStates)
        let path = decode(observations: observations, transitionMatrix: transitions, startProbs: startProbs)

        return path.map { $0 == silenceState ? 0 : minMIDI + $0 }
    }
}
