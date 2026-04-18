import Foundation
import Accelerate

/**
 * v55.1: Stereo & Phase Analysis Engine
 * Laboratory-grade verification of mono compatibility and spatial integrity.
 */
/// Stereo and Spatial Analysis Engine.
/// Provides laboratory-grade verification of phase correlation, mono compatibility, and stereo width.
public final class StereoEngine: Sendable {
    
    public struct StereoResult: Codable, Sendable {
        public let correlationIndex: Float   // -1.0 to +1.0
        public let monoCompatibility: String // Excellent, Good, Risky, Phase Issues
        public let sideEnergyPercent: Float  // 0-100%
        public let stereoWidth: Float        // Normalized 0.0 - 1.0 (Side/Mid ratio)
    }
    
    public init() {}
    
    public func analyze(left: [Float], right: [Float]) -> StereoResult {
        guard left.count == right.count, !left.isEmpty else {
            return StereoResult(correlationIndex: 0, monoCompatibility: "Unknown", sideEnergyPercent: 0, stereoWidth: 0)
        }
        
        let n = vDSP_Length(left.count)
        
        // 1. Correlation Index
        // Correlation = sum(L * R) / sqrt(sum(L^2) * sum(R^2))
        var dotProduct: Float = 0
        vDSP_dotpr(left, 1, right, 1, &dotProduct, n)
        
        var sumSqL: Float = 0
        vDSP_svesq(left, 1, &sumSqL, n)
        
        var sumSqR: Float = 0
        vDSP_svesq(right, 1, &sumSqR, n)
        
        let denominator = sqrtf(sumSqL * sumSqR)
        let correlation = denominator > 1e-12 ? dotProduct / denominator : 0.0
        
        // 2. Mid/Side Energies
        // Mid = (L+R)/2, Side = (L-R)/2
        // Mid: (L + R) * 0.5
        var mid = [Float](repeating: 0, count: left.count)
        vDSP_vadd(left, 1, right, 1, &mid, 1, n)
        var half: Float = 0.5
        vDSP_vsmul(mid, 1, &half, &mid, 1, n)
        
        // Side: (L - R) * 0.5 
        var side = [Float](repeating: 0, count: left.count)
        vDSP_vsub(right, 1, left, 1, &side, 1, n) // Side = L - R
        vDSP_vsmul(side, 1, &half, &side, 1, n)
        
        var midEnergy: Float = 0
        vDSP_svesq(mid, 1, &midEnergy, n)
        
        var sideEnergy: Float = 0
        vDSP_svesq(side, 1, &sideEnergy, n)
        
        let totalMSEnergy = midEnergy + sideEnergy
        let sidePercent = totalMSEnergy > 1e-12 ? (sideEnergy / totalMSEnergy) * 100.0 : 0
        let width = midEnergy > 1e-12 ? (sideEnergy / midEnergy) : 0
        
        // 3. Status
        var isMono = false
        if correlation > 0.999 && sidePercent < 0.01 {
            isMono = true
        }

        var status = "Unknown"
        if isMono {
            status = "Mono Downmix (N/A)"
        } else if correlation > 0.8 {
            status = "Excellent (Precise Mono)"
        } else if correlation > 0.5 {
            status = "Good (Natural Stereo)"
        } else if correlation > 0.0 {
            status = "Risky (Wide/Artificial)"
        } else {
            status = "Critical (Phase Cancellation)"
        }
        
        return StereoResult(
            correlationIndex: correlation,
            monoCompatibility: status,
            sideEnergyPercent: sidePercent,
            stereoWidth: min(1.0, width)
        )
    }
}
