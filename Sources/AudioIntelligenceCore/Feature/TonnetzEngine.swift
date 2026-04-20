// TonnetzEngine.swift
// Elite Music DNA Engine — Phase 4
//
// Tonal Centroid features (Tonnetz).
// Mirroring industry standard.feature.tonnetz.
// Projects chroma features into a 6D space representing harmonic relationships.

import Foundation
import Accelerate

public struct TonnetzResult: Codable, Sendable {
    public let tonnetz: [[Float]] // [6 × nFrames]
}

/// Tonal Centroid (Tonnetz) Mapping Engine.
/// Projects chroma features into a 6-dimensional space to represent harmonic relationships.
public final class TonnetzEngine: Sendable {
    
    public init() {}
    
    /// Computes the Tonal Centroids (Tonnetz) from a chromagram.
    /// Industry Standard: feature.tonnetz()
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
        
        let scales: [Float] = [7.0/6.0, 7.0/6.0, 3.0/2.0, 3.0/2.0, 2.0/3.0, 2.0/3.0]
        let radii: [Float]  = [1.0, 1.0, 1.0, 1.0, 0.5, 0.5] // Fifths, Minor, Major
        
        for i in 0..<6 {
            let scale = scales[i]
            let r = radii[i]
            let shift: Float = (i % 2 == 0) ? 0.5 : 0.0
            
            for k in 0..<12 {
                // phi = R * cos(pi * (scale * k - shift))
                // Note: cos(pi * (x - 0.5)) = sin(pi * x)
                let val = scale * Float(k) - shift
                matrix[i][k] = r * cosf(.pi * val)
            }
        }
        
        return matrix
    }
}
