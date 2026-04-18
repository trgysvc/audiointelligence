// NMFEngine.swift
// Elite Music DNA Engine — Phase 4
//
// Non-negative Matrix Factorization (NMF).
// Mirroring industry standard.decompose.nmf.
// Used for blind source separation and component analysis.

import Foundation
import Accelerate

public struct NMFResult: Sendable {
    public let W: [[Float]] // [nFreqs × nComponents] — Spectral basis
    public let H: [[Float]] // [nComponents × nFrames] — Temporal activations
}

public final class NMFEngine: Sendable {
    
    private let nComponents: Int
    private let maxIter: Int
    
    public init(nComponents: Int = 2, maxIter: Int = 50) {
        self.nComponents = nComponents
        self.maxIter = maxIter
    }
    
    /// Computes NMF using Multiplicative Update (MU) rules with KL divergence.
    /// V ≈ WH
    /// Computes NMF using Multiplicative Update (MU) rules with KL divergence.
    /// V ≈ H * W (V is [nFrames × nFreqs], H is [nFrames × nComponents], W is [nComponents × nFreqs])
    public func decompose(stft: STFTMatrix, seed: UInt64 = 42) -> NMFResult {
        let V = stft.magnitude // [nFrames × nFreqs]
        let nFreqs = stft.nFreqs
        let nFrames = stft.nFrames
        
        // 1. Initialize W and H with deterministic positive values.
        var rng = LCG(seed: seed)
        var W = (0..<nFreqs).map { _ in (0..<nComponents).map { _ in rng.next() } }
        var H = (0..<nComponents).map { _ in (0..<nFrames).map { _ in rng.next() } }
        
        // 2. Iterative updates (KL divergence MU rules adapted for [Frames x Freqs])
        for _ in 0..<maxIter {
            // Update W: W ← W * (H^T * (V / (HW))) / (H^T * 1)
            let HW = computeHW(H: H, W: W, frames: nFrames, freqs: nFreqs, comps: nComponents)
            
            var V_over_HW = [Float](repeating: 0, count: V.count)
            for i in 0..<V.count {
                V_over_HW[i] = V[i] / (HW[i] + 1e-10)
            }
            
            // W update factor: HT * (V/HW)
            let wFactor = computeHT_V(H: H, V: V_over_HW, frames: nFrames, freqs: nFreqs, comps: nComponents)
            
            // H column sums for normalization
            var hSums = [Float](repeating: 0, count: nComponents)
            for c in 0..<nComponents {
                var sum: Float = 0
                for t in 0..<nFrames { sum += H[t][c] }
                hSums[c] = max(1e-10, sum)
            }
            
            for c in 0..<nComponents {
                for f in 0..<nFreqs {
                    W[c][f] *= wFactor[c][f] / hSums[c]
                }
            }
            
            // Update H: H ← H * ((V / (HW)) * W^T) / (1 * W^T)
            let NewHW = computeHW(H: H, W: W, frames: nFrames, freqs: nFreqs, comps: nComponents)
            var V_over_NewHW = [Float](repeating: 0, count: V.count)
            for i in 0..<V.count {
                V_over_NewHW[i] = V[i] / (NewHW[i] + 1e-10)
            }
            
            let hFactor = computeV_WT(V: V_over_NewHW, W: W, frames: nFrames, freqs: nFreqs, comps: nComponents)
            
            // W row sums for normalization
            var wSums = [Float](repeating: 0, count: nComponents)
            for c in 0..<nComponents {
                var sum: Float = 0
                vDSP_sve(W[c], 1, &sum, vDSP_Length(nFreqs))
                wSums[c] = max(1e-10, sum)
            }
            
            for t in 0..<nFrames {
                for c in 0..<nComponents {
                    H[t][c] *= hFactor[t][c] / wSums[c]
                }
            }
        }
        
        // Return results: W as basis [nFreqs x nComponents], H as activations [nComponents x nFrames]
        // This maintains the original Result structure but uses internal Frame-major efficiency.
        var outW = [[Float]](repeating: [Float](repeating: 0, count: nComponents), count: nFreqs)
        var outH = [[Float]](repeating: [Float](repeating: 0, count: nFrames), count: nComponents)
        
        for f in 0..<nFreqs {
            for c in 0..<nComponents { outW[f][c] = W[c][f] }
        }
        for c in 0..<nComponents {
            for t in 0..<nFrames { outH[c][t] = H[t][c] }
        }
        
        return NMFResult(W: outW, H: outH)
    }
    
    // MARK: - Optimized Matrix Ops (Frame-major [Frames x Freqs])
    
    private func computeHW(H: [[Float]], W: [[Float]], frames: Int, freqs: Int, comps: Int) -> [Float] {
        var result = [Float](repeating: 0, count: frames * freqs)
        for t in 0..<frames {
            for f in 0..<freqs {
                var sum: Float = 0
                for c in 0..<comps {
                    sum += H[t][c] * W[c][f]
                }
                result[t * freqs + f] = sum
            }
        }
        return result
    }
    
    private func computeHT_V(H: [[Float]], V: [Float], frames: Int, freqs: Int, comps: Int) -> [[Float]] {
        var result = [[Float]](repeating: [Float](repeating: 0, count: freqs), count: comps)
        for c in 0..<comps {
            for f in 0..<freqs {
                var sum: Float = 0
                for t in 0..<frames {
                    sum += H[t][c] * V[t * freqs + f]
                }
                result[c][f] = sum
            }
        }
        return result
    }
    
    private func computeV_WT(V: [Float], W: [[Float]], frames: Int, freqs: Int, comps: Int) -> [[Float]] {
        var result = [[Float]](repeating: [Float](repeating: 0, count: comps), count: frames)
        for t in 0..<frames {
            for c in 0..<comps {
                var sum: Float = 0
                for f in 0..<freqs {
                    sum += V[t * freqs + f] * W[c][f]
                }
                result[t][c] = sum
            }
        }
        return result
    }
    
    // MARK: - Deterministic RNG (LCG)
    
    private struct LCG {
        var state: UInt64
        init(seed: UInt64) { self.state = seed }
        mutating func next() -> Float {
            state = (state &* 6364136223846793005) &+ 1442695040888963407
            return Float(state >> 40) / Float(1 << 24) * 0.9 + 0.1
        }
    }
}
