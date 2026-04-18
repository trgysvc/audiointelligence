// TonnetzEngine.swift
// Elite Music DNA Engine — Phase 4
//
// Tonal Centroid features (Tonnetz).
// Mirroring librosa.feature.tonnetz.
// Projects chroma features into a 6D space representing harmonic relationships.

import Foundation
import Accelerate

public struct TonnetzResult: Sendable {
    public let tonnetz: [[Float]] // [6 × nFrames]
}

public final class TonnetzEngine: Sendable {
    
    public init() {}
    
    /// Computes the Tonal Centroids (Tonnetz) from a chromagram.
    /// Librosa: feature.tonnetz()
    public func compute(chromagram: [[Float]]) -> TonnetzResult {
        guard !chromagram.isEmpty else { return TonnetzResult(tonnetz: []) }
        let nFrames = chromagram[0].count
        
        // 1. Ensure L1 normalization of the chromagram
        var l1Chroma = [[Float]](repeating: [Float](repeating: 0, count: 12), count: nFrames)
        for t in 0..<nFrames {
            let frame = (0..<12).map { chromagram[$0][t] }
            l1Chroma[t] = DSPHelpers.normalizeL1(frame)
        }
        
        // 2. Tonnetz projection matrix (6 x 12)
        // Rows: [Fifth_sin, Fifth_cos, M3_sin, M3_cos, m3_sin, m3_cos]
        let matrix = createTonnetzMatrix()
        
        // 3. Project
        var tonnetz = [[Float]](repeating: [Float](repeating: 0, count: nFrames), count: 6)
        
        for i in 0..<6 {
            let weights = matrix[i]
            for t in 0..<nFrames {
                var sum: Float = 0
                for k in 0..<12 {
                    sum += weights[k] * l1Chroma[t][k]
                }
                tonnetz[i][t] = sum
            }
        }
        
        return TonnetzResult(tonnetz: tonnetz)
    }
    
    private func createTonnetzMatrix() -> [[Float]] {
        var matrix = [[Float]](repeating: [Float](repeating: 0, count: 12), count: 6)
        
        let r1: Float = 1.0 // Radius for Perfect Fifth
        let r2: Float = 1.0 // Radius for Major Third
        let r3: Float = 0.5 // Radius for Minor Third
        
        for k in 0..<12 {
            let angleFifth = Float(k) * 7.0 * .pi / 6.0
            matrix[0][k] = r1 * sinf(angleFifth)
            matrix[1][k] = r1 * cosf(angleFifth)
            
            let angleM3 = Float(k) * 3.0 * .pi / 2.0 // Actually it's 2*pi*(k*3)/12? No, Librosa uses specific constants.
            // Librosa defaults:
            // d1 = 7 (fifth), d2 = 3 (m3), d3 = 4 (M3)
            // Librosa uses: 
            // Phi(k, d) = [sin(2*pi*k*d/12), cos(2*pi*k*d/12)]
            
            // Fifth (d=7)
            matrix[0][k] = r1 * sinf(2.0 * .pi * Float(k) * 7.0 / 12.0)
            matrix[1][k] = r1 * cosf(2.0 * .pi * Float(k) * 7.0 / 12.0)
            
            // Minor Third (d=3)
            matrix[2][k] = r2 * sinf(2.0 * .pi * Float(k) * 3.0 / 12.0)
            matrix[3][k] = r2 * cosf(2.0 * .pi * Float(k) * 3.0 / 12.0)
            
            // Major Third (d=4)
            matrix[4][k] = r3 * sinf(2.0 * .pi * Float(k) * 4.0 / 12.0)
            matrix[5][k] = r3 * cosf(2.0 * .pi * Float(k) * 4.0 / 12.0)
        }
        
        return matrix
    }
}
