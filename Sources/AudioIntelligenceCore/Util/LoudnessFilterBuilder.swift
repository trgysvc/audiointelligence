import Foundation

/// Mathematical builder for ITU-R BS.1770 K-Weighting filter coefficients.
/// Uses Bilinear Transformation to calculate frequency-accurate coefficients for any sample rate.
public struct LoudnessFilterBuilder {
    
    public struct BiquadCoeffs {
        public let b0: Double
        public let b1: Double
        public let b2: Double
        public let a1: Double
        public let a2: Double
        
        public var asArray: [Double] { [b0, b1, b2, a1, a2] }
    }
    
    /// Stage 1: Pre-filter (High Shelving Filter)
    /// Models the acoustic effects of the head.
    public static func preFilterCoefficients(sampleRate: Double) -> BiquadCoeffs {
        let dbGain = 3.999847285444853
        let f0 = 1681.9744509555319
        let Q = 0.7071752369554193
        
        let K = tan(Double.pi * f0 / sampleRate)
        let Vh = pow(10.0, dbGain / 20.0)
        let common = 1.0 + (K / Q) + (K * K)
        
        let b0 = (Vh + sqrt(Vh) / Q * K + K * K) / common
        let b1 = 2.0 * (K * K - Vh) / common
        let b2 = (Vh - sqrt(Vh) / Q * K + K * K) / common
        let a1 = 2.0 * (K * K - 1.0) / common
        let a2 = (1.0 - (K / Q) + (K * K)) / common
        
        return BiquadCoeffs(b0: b0, b1: b1, b2: b2, a1: a1, a2: a2)
    }
    
    /// Stage 2: RLB Filter (High-pass Filter)
    /// Models the human hearing sensitivity at low frequencies.
    public static func rlbFilterCoefficients(sampleRate: Double) -> BiquadCoeffs {
        let f0 = 38.13547087613982
        let Q = 0.5 // Butterworth
        
        let K = tan(Double.pi * f0 / sampleRate)
        let common = 1.0 + (K / Q) + (K * K)
        
        let b0 = 1.0 / common
        let b1 = -2.0 / common
        let b2 = 1.0 / common
        let a1 = 2.0 * (K * K - 1.0) / common
        let a2 = (1.0 - (K / Q) + (K * K)) / common
        
        return BiquadCoeffs(b0: b0, b1: b1, b2: b2, a1: a1, a2: a2)
    }
}
