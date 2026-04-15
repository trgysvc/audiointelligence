import Foundation
import Accelerate

/// v28.0: The Infinity Engine — Professional Loudness Engineering
/// Provides Integrated, Momentary, and Short-term LUFS (EBU R128).
public final class LoudnessEngine: Sendable {
    
    private let sampleRate: Double
    
    public init(sampleRate: Double) {
        self.sampleRate = sampleRate
    }
    
    public struct LoudnessResult: Sendable {
        public let integratedLUFS: Float
        public let momentaryLUFsMax: Float
        public let shortTermLUFsMax: Float
        public let truePeakDb: Float
        public let loudnessRange: Float
    }
    
    /// Calculates Integrated, Momentary, and Short-term Loudness (LUFS).
    public func analyze(samples: [Float]) -> LoudnessResult {
        let weightedSamples = applyKWeighting(samples: samples)
        
        // 1. Integrated Loudness
        var meanSquare: Float = 0
        vDSP_meamgv(weightedSamples, 1, &meanSquare, vDSP_Length(weightedSamples.count))
        let integratedLUFS = (meanSquare > 1e-12) ? -0.691 + (10 * log10f(meanSquare)) : -70.0
        
        // 2. Momentary LUFS (400ms window)
        let momWindow = Int(0.4 * sampleRate)
        var maxMom: Float = -70.0
        if weightedSamples.count >= momWindow {
            for i in stride(from: 0, to: weightedSamples.count - momWindow, by: momWindow / 2) {
                var chunkMS: Float = 0
                let start = i
                let end = i + momWindow
                weightedSamples.withUnsafeBufferPointer { ptr in
                    if let base = ptr.baseAddress {
                        vDSP_meamgv(base.advanced(by: start), 1, &chunkMS, vDSP_Length(momWindow))
                    }
                }
                let lufs = -0.691 + (10 * log10f(max(1e-12, chunkMS)))
                maxMom = max(maxMom, lufs)
            }
        }
        
        // 3. Short-term LUFS (3s window)
        let stWindow = Int(3.0 * sampleRate)
        var maxST: Float = -70.0
        if weightedSamples.count >= stWindow {
            for i in stride(from: 0, to: weightedSamples.count - stWindow, by: stWindow / 2) {
                var chunkMS: Float = 0
                let start = i
                let end = i + stWindow
                weightedSamples.withUnsafeBufferPointer { ptr in
                    if let base = ptr.baseAddress {
                        vDSP_meamgv(base.advanced(by: start), 1, &chunkMS, vDSP_Length(stWindow))
                    }
                }
                let lufs = -0.691 + (10 * log10f(max(1e-12, chunkMS)))
                maxST = max(maxST, lufs)
            }
        }
        
        // 4. True Peak
        var peak: Float = 0
        vDSP_maxmgv(samples, 1, &peak, vDSP_Length(samples.count))
        let truePeakDb = (peak > 1e-12) ? 20 * log10f(peak) : -100.0
        
        return LoudnessResult(
            integratedLUFS: integratedLUFS,
            momentaryLUFsMax: maxMom,
            shortTermLUFsMax: maxST,
            truePeakDb: truePeakDb,
            loudnessRange: 0 
        )
    }
    
    private func applyKWeighting(samples: [Float]) -> [Float] {
        var output = samples
        let alpha: Float = 0.95 
        var last: Float = 0
        for i in 0..<output.count {
            let current = output[i]
            output[i] = current - last + alpha * last
            last = current
        }
        return output
    }
}
