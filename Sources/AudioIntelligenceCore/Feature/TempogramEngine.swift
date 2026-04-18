// TempogramEngine.swift
// Elite Music DNA Engine — Phase 4
//
// Tempogram implementation for mapping tempo variations over time.
// Mirroring industry standard.feature.tempogram using Autocorrelation (ACT).

import Foundation
import Accelerate

public struct TempogramResult: Sendable {
    public let tempogram: [[Float]] // [winLength × nFrames]
    public let winLength: Int
    public let hopLength: Int
}

public final class TempogramEngine: Sendable {
    
    private let winLength: Int
    
    public init(winLength: Int = 384) {
        self.winLength = winLength
    }
    
    /// Computes an Autocorrelation Tempogram from onset strength.
    /// - Parameters:
    ///   - onsetStrength: Envelope from OnsetEngine
    ///   - hopLength: Temporal resolution (default: 1 frame)
    public func computeACT(onsetStrength: [Float], hopLength: Int = 1) -> TempogramResult {
        let n = onsetStrength.count
        let nFrames = (n - winLength) / hopLength + 1
        guard nFrames > 0 else {
            return TempogramResult(tempogram: [], winLength: winLength, hopLength: hopLength)
        }
        
        var tempogram = [[Float]](repeating: [Float](repeating: 0, count: nFrames), count: winLength)
        
        for t in 0..<nFrames {
            let start = t * hopLength
            let end = start + winLength
            let frame = Array(onsetStrength[start..<end])
            
            // Autocorrelation of the windowed onset strength
            let acf = DSPHelpers.autocorrelate(frame, maxSize: winLength)
            
            // Fill tempogram column
            for lag in 0..<winLength {
                tempogram[lag][t] = acf[lag]
            }
        }
        
        return TempogramResult(
            tempogram: tempogram,
            winLength: winLength,
            hopLength: hopLength
        )
    }
}
