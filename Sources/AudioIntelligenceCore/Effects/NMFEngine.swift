// NMFEngine.swift
// Elite Music DNA Engine — Phase 4
//
// Non-negative Matrix Factorization (NMF).
// Mirroring industry standard.decompose.nmf.
// High-Performance vDSP accelerated implementation.
//
// Industry Standard Notation: V ≈ W * H
// Here, we use Frame-Major layout for V [Frames x Freqs]
// V ≈ H * W where H is [Frames x Components] and W is [Components x Freqs]

import Foundation
import Accelerate

public struct NMFResult: Codable, Sendable {
    public let W: [[Float]] // [nComponents × nFreqs] — Spectral basis
    public let H: [[Float]] // [nFrames × nComponents] — Temporal activations
}

/// Non-negative Matrix Factorization (NMF) Engine.
/// Decomposes spectral data into basis components and activations for blind source identification.
public final class NMFEngine: Sendable {
    
    private let nComponents: Int
    private let maxIter: Int
    
    public init(nComponents: Int = 2, maxIter: Int = 50) {
        self.nComponents = nComponents
        self.maxIter = maxIter
    }
    
    /// Computes NMF using Multiplicative Update (MU) rules with KL divergence.
    /// Mathematically Optimized using Apple Accelerate (vDSP).
    public func decompose(stft: STFTMatrix, seed: UInt64 = 42) -> NMFResult {
        let nFreqs = stft.nFreqs
        let nFrames = stft.nFrames
        let totalElements = nFrames * nFreqs
        
        // 1. Initialize H and W with deterministic positive values (Flat Buffers)
        var rng = LCG(seed: seed)
        var H_flat = [Float](repeating: 0, count: nFrames * nComponents)
        var W_flat = [Float](repeating: 0, count: nComponents * nFreqs)
        
        for i in 0..<H_flat.count { H_flat[i] = rng.next() }
        for i in 0..<W_flat.count { W_flat[i] = rng.next() }
        
        let V = stft.magnitude // [nFrames × nFreqs]
        
        var HW = [Float](repeating: 0, count: totalElements)
        var V_over_HW = [Float](repeating: 0, count: totalElements)
        
        // 2. Iterative updates (KL divergence MU rules)
        for _ in 0..<maxIter {
            // A. Update W: W ← W * (H^T * (V / (HW))) / (H^T * 1)
            DSPHelpers.safeMatrixMultiply(H_flat, rowsA: nFrames, colsA: nComponents, W_flat, rowsB: nComponents, colsB: nFreqs, C: &HW)
            
            // V_over_HW = V / (HW + epsilon)
            vDSP_vadd(HW, 1, [1e-10], 0, &HW, 1, vDSP_Length(totalElements))
            vDSP_vdiv(HW, 1, V, 1, &V_over_HW, 1, vDSP_Length(totalElements))
            
            H_flat.withUnsafeBufferPointer { hBuff in
                W_flat.withUnsafeMutableBufferPointer { wBuff in
                    guard let hBase = hBuff.baseAddress, let wBase = wBuff.baseAddress else { return }
                    
                    for c in 0..<nComponents {
                        var numerator_W = [Float](repeating: 0, count: nFreqs)
                        
                        // Vectorized cross-correlation for W update
                        for f in 0..<nFreqs {
                            var dot: Float = 0
                            // Manual stride check for M4 safety
                            vDSP_dotpr(hBase.advanced(by: c), nComponents, 
                                       V_over_HW.withUnsafeBufferPointer { $0.baseAddress!.advanced(by: f) }, nFreqs, 
                                       &dot, vDSP_Length(nFrames))
                            numerator_W[f] = dot
                        }
                        
                        var h_sum: Float = 0
                        vDSP_sve(hBase.advanced(by: c), nComponents, &h_sum, vDSP_Length(nFrames))
                        h_sum = max(1e-10, h_sum)
                        
                        var invSum = 1.0 / h_sum
                        vDSP_vsmul(numerator_W, 1, &invSum, &numerator_W, 1, vDSP_Length(nFreqs))
                        
                        let offsetW = c * nFreqs
                        vDSP_vmul(wBase.advanced(by: offsetW), 1, numerator_W, 1, wBase.advanced(by: offsetW), 1, vDSP_Length(nFreqs))
                    }
                }
            }
            
            // B. Update H: H ← H * ((V / (HW)) * W^T) / (1 * W^T)
            DSPHelpers.safeMatrixMultiply(H_flat, rowsA: nFrames, colsA: nComponents, W_flat, rowsB: nComponents, colsB: nFreqs, C: &HW)
            vDSP_vadd(HW, 1, [1e-10], 0, &HW, 1, vDSP_Length(totalElements))
            vDSP_vdiv(HW, 1, V, 1, &V_over_HW, 1, vDSP_Length(totalElements))
            
            W_flat.withUnsafeBufferPointer { wBuff in
                H_flat.withUnsafeMutableBufferPointer { hBuff in
                    guard let wBase = wBuff.baseAddress, let hBase = hBuff.baseAddress else { return }
                    
                    for t in 0..<nFrames {
                        let offsetV = t * nFreqs
                        let offsetH = t * nComponents
                        
                        for c in 0..<nComponents {
                            let offsetW = c * nFreqs
                            var dot: Float = 0
                            vDSP_dotpr(V_over_HW.withUnsafeBufferPointer { $0.baseAddress!.advanced(by: offsetV) }, 1, 
                                       wBase.advanced(by: offsetW), 1, 
                                       &dot, vDSP_Length(nFreqs))
                            
                            var w_sum: Float = 0
                            vDSP_sve(wBase.advanced(by: offsetW), 1, &w_sum, vDSP_Length(nFreqs))
                            w_sum = max(1e-10, w_sum)
                            
                            let idx = offsetH + c
                            hBase[idx] *= dot / w_sum
                            if hBase[idx].isNaN || hBase[idx].isInfinite {
                                hBase[idx] = 1e-10
                            }
                        }
                    }
                }
            }
        }
        
        // 3. Return results in stratified nested format for compatibility
        var outW = [[Float]](repeating: [], count: nComponents)
        for c in 0..<nComponents {
            outW[c] = Array(W_flat[(c * nFreqs)..<((c + 1) * nFreqs)])
        }
        
        var outH = [[Float]](repeating: [], count: nFrames)
        for t in 0..<nFrames {
            outH[t] = Array(H_flat[(t * nComponents)..<((t + 1) * nComponents)])
        }
        
        return NMFResult(W: outW, H: outH)
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
