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
    public func decompose(stft: STFTMatrix) -> NMFResult {
        let V = stft.magnitude // [nFreqs × nFrames]
        let nFreqs = stft.nFreqs
        let nFrames = stft.nFrames
        
        // 1. Initialize W and H with random positive values
        var W = (0..<nFreqs).map { _ in (0..<nComponents).map { _ in Float.random(in: 0.1...1.0) } }
        var H = (0..<nComponents).map { _ in (0..<nFrames).map { _ in Float.random(in: 0.1...1.0) } }
        
        // 2. Iterative updates (KL divergence MU rules)
        for _ in 0..<maxIter {
            // Update H: H ← H * (W^T * (V / (WH))) / (W^T * 1)
            let WH = computeWH(W: W, H: H, rows: nFreqs, cols: nFrames, comps: nComponents)
            
            var V_over_WH = [Float](repeating: 0, count: V.count)
            for i in 0..<V.count {
                V_over_WH[i] = V[i] / (WH[i] + 1e-10)
            }
            
            // H update factor: WT * (V/WH)
            let hFactor = computeWT_V(W: W, V: V_over_WH, rows: nFreqs, cols: nFrames, comps: nComponents)
            
            // W column sums for normalization
            var wSums = [Float](repeating: 0, count: nComponents)
            for c in 0..<nComponents {
                var sum: Float = 0
                for f in 0..<nFreqs { sum += W[f][c] }
                wSums[c] = max(1e-10, sum)
            }
            
            for c in 0..<nComponents {
                for t in 0..<nFrames {
                    H[c][t] *= hFactor[c][t] / wSums[c]
                }
            }
            
            // Update W: W ← W * ((V / (WH)) * H^T) / (1 * H^T)
            let NewWH = computeWH(W: W, H: H, rows: nFreqs, cols: nFrames, comps: nComponents)
            var V_over_NewWH = [Float](repeating: 0, count: V.count)
            for i in 0..<V.count {
                V_over_NewWH[i] = V[i] / (NewWH[i] + 1e-10)
            }
            
            let wFactor = computeV_HT(V: V_over_NewWH, H: H, rows: nFreqs, cols: nFrames, comps: nComponents)
            
            // H row sums for normalization
            var hSums = [Float](repeating: 0, count: nComponents)
            for c in 0..<nComponents {
                var sum: Float = 0
                vDSP_sve(H[c], 1, &sum, vDSP_Length(nFrames))
                hSums[c] = max(1e-10, sum)
            }
            
            for f in 0..<nFreqs {
                for c in 0..<nComponents {
                    W[f][c] *= wFactor[f][c] / hSums[c]
                }
            }
        }
        
        return NMFResult(W: W, H: H)
    }
    
    // MARK: - Optimized Matrix Ops
    
    private func computeWH(W: [[Float]], H: [[Float]], rows: Int, cols: Int, comps: Int) -> [Float] {
        var result = [Float](repeating: 0, count: rows * cols)
        for i in 0..<rows {
            for j in 0..<cols {
                var sum: Float = 0
                for k in 0..<comps {
                    sum += W[i][k] * H[k][j]
                }
                result[i * cols + j] = sum
            }
        }
        return result
    }
    
    private func computeWT_V(W: [[Float]], V: [Float], rows: Int, cols: Int, comps: Int) -> [[Float]] {
        var result = [[Float]](repeating: [Float](repeating: 0, count: cols), count: comps)
        for c in 0..<comps {
            for t in 0..<cols {
                var sum: Float = 0
                for f in 0..<rows {
                    sum += W[f][c] * V[f * cols + t]
                }
                result[c][t] = sum
            }
        }
        return result
    }
    
    private func computeV_HT(V: [Float], H: [[Float]], rows: Int, cols: Int, comps: Int) -> [[Float]] {
        var result = [[Float]](repeating: [Float](repeating: 0, count: comps), count: rows)
        for f in 0..<rows {
            for c in 0..<comps {
                var sum: Float = 0
                for t in 0..<cols {
                    sum += V[f * cols + t] * H[c][t]
                }
                result[f][c] = sum
            }
        }
        return result
    }
}
