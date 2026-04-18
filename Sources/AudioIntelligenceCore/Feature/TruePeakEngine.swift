import Foundation
import Accelerate

/// v51.0: Professional Engineering Standard — True Peak Analysis
/// Detects inter-sample peaks using 4x oversampling as per BS.1770.
public final class TruePeakEngine: Sendable {
    
    public init() {}
    
    /// Detects the True Peak level in dBTP.
    public func detect(samples: [Float]) -> Float {
        guard !samples.isEmpty else { return -100.0 }
        
        // 4x Oversampling
        let oversampled = oversample4x(samples: samples)
        
        // Find max magnitude in oversampled signal
        var peak: Float = 0
        vDSP_maxmgv(oversampled, 1, &peak, vDSP_Length(oversampled.count))
        
        // Convert to dBTP
        return (peak > 1e-12) ? 20 * log10f(peak) : -100.0
    }
    
    private func oversample4x(samples: [Float]) -> [Float] {
        let n = samples.count
        let m = 4 // Oversampling factor
        let filterLen = 24 // Reasonable length for inter-sample accuracy
        
        // 1. Create a Sinc-based interpolation filter
        var filter = [Float](repeating: 0, count: filterLen)
        for i in 0..<filterLen {
            let x = Float(i - filterLen / 2) / Float(m)
            if x == 0 {
                filter[i] = 1.0
            } else {
                let piX = Float.pi * x
                filter[i] = sinf(piX) / piX
            }
            // Hamming window
            let window = 0.54 - 0.46 * cosf(2.0 * Float.pi * Float(i) / Float(filterLen - 1))
            filter[i] *= window
        }
        
        // 2. Perform upsampling and filtering
        // Manually zero-stuff and convolve (4x)
        var upsampled = [Float](repeating: 0, count: n * m)
        for i in 0..<n {
            upsampled[i * m] = samples[i]
        }
        
        var output = [Float](repeating: 0, count: n * m)
        vDSP_conv(upsampled, 1, filter, 1, &output, 1, vDSP_Length(n * m), vDSP_Length(filterLen))
        
        return output
    }
}
