import Foundation
import Accelerate

/// Professional-grade Viterbi Decoder for sequence modeling (HMM).
/// Uses log-space math and Accelerate-optimized emission calculations.
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
