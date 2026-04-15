import Foundation
import Accelerate

/// v25.0: Professional Stereo Image Engine (AudioIntelligence)
/// Analyzes channel correlation and mono compatibility.
public final class StereoEngine: Sendable {
    
    public init() {}
    
    public struct StereoResult: Sendable {
        public let correlation: Float        // -1.0 (Out of phase) to 1.0 (Mono/In phase)
        public let width: Float             // Estimated stereo width [0..1]
        public let monoCompatibility: String // Human summary
    }
    
    /// Analyzes correlation between Left and Right channels.
    /// Expects interleaved or separate canal arrays.
    public func analyze(left: [Float], right: [Float]) -> StereoResult {
        let count = min(left.count, right.count)
        guard count > 0 else { return StereoResult(correlation: 0, width: 0, monoCompatibility: "Veri Yok") }
        
        // v25.0: DOT Product Correlation using Accelerate
        // Formula: dot(L, R) / (sqrt(sum(L^2)) * sqrt(sum(R^2)))
        
        var dotProduct: Float = 0
        vDSP_dotpr(left, 1, right, 1, &dotProduct, vDSP_Length(count))
        
        var sumSqL: Float = 0
        vDSP_svemg(left, 1, &sumSqL, vDSP_Length(count)) // Approximation of magnitude
        
        var sumSqR: Float = 0
        vDSP_svemg(right, 1, &sumSqR, vDSP_Length(count))
        
        let correlation = (sumSqL > 1e-8 && sumSqR > 1e-8) ? dotProduct / (sqrtf(sumSqL) * sqrtf(sumSqR)) : 1.0
        
        let width = 1.0 - abs(correlation)
        
        let compat: String
        if correlation > 0.8 { compat = "Mono Uyumlu" }
        else if correlation > 0.3 { compat = "Geniş Stereo" }
        else if correlation > -0.2 { compat = "Faz Sorunu Riski" }
        else { compat = "Kritör Faz Çakışması" }
        
        return StereoResult(
            correlation: correlation,
            width: width,
            monoCompatibility: compat
        )
    }
}
