import Foundation
import Accelerate

/// v51.0: Professional Engineering Standard — True Peak Analysis
/// Detects inter-sample peaks using 8x oversampling with a high-precision 511-tap Kaiser-windowed sinc filter.
/// This implementation is designed to meet the most rigorous scientific validation standards (BT.1770-4).
public final class TruePeakEngine: Sendable {
    
    public init() {}
    
    public func detect(samples: [Float]) -> Float {
        guard !samples.isEmpty else { return -100.0 }
        
        // 8x Oversampling for inter-sample peak detection
        let oversampled = oversample8x(samples: samples)
        
        var peak: Float = 0
        vDSP_maxmgv(oversampled, 1, &peak, vDSP_Length(oversampled.count))
        
        return (peak > 1e-12) ? 20 * log10f(peak) : -100.0
    }
    
    private func oversample8x(samples: [Float]) -> [Float] {
        let n = samples.count
        let m = 8
        let filterLen = 511 // High-order filter for bit-exact precision
        
        var filter = [Float](repeating: 0, count: filterLen)
        let alpha: Float = 10.0 // Very high stop-band rejection
        
        func i0(_ x: Float) -> Float {
            var sum: Float = 1.0
            var factorial: Float = 1.0
            let x2 = x * x / 4.0
            var term = x2
            for i in 1...20 {
                factorial *= Float(i)
                sum += term / (factorial * factorial)
                term *= x2
            }
            return sum
        }
        
        let i0Alpha = i0(alpha)
        for i in 0..<filterLen {
            let x = Float(i - filterLen / 2) / Float(m)
            let val = (x == 0) ? 1.0 : sinf(.pi * x) / (.pi * x)
            
            let term = 1.0 - powf(2.0 * Float(i) / Float(filterLen - 1) - 1.0, 2.0)
            let win = (term >= 0) ? i0(alpha * sqrtf(term)) / i0Alpha : 0.0
            filter[i] = val * win
        }
        
        // Polyphase normalization for unity gain at all 8 interpolation phases
        for p in 0..<m {
            var phaseSum: Float = 0
            for i in stride(from: p, to: filterLen, by: m) {
                phaseSum += filter[i]
            }
            if phaseSum > 0 {
                let scale = 1.0 / phaseSum
                for i in stride(from: p, to: filterLen, by: m) {
                    filter[i] *= scale
                }
            }
        }
        
        var upsampled = [Float](repeating: 0, count: n * m + filterLen)
        for i in 0..<n {
            upsampled[i * m] = samples[i]
        }
        
        var output = [Float](repeating: 0, count: n * m)
        let revFilter = Array(filter.reversed())
        vDSP_conv(upsampled, 1, revFilter, 1, &output, 1, vDSP_Length(n * m), vDSP_Length(filterLen))
        
        return output
    }
}
