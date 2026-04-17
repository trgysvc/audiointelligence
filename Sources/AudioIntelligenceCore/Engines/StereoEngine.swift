import Foundation
import Accelerate

/// v28.0: The Infinity Engine — Stereo & Phase Analysis
/// Provides Phase Correlation, Mono Compatibility, and L/R Balance.
public final class StereoEngine: Sendable {
    
    public init() {}
    
    public struct StereoResult: Sendable {
        public let correlation: Float
        public let monoCompatibility: String
        public let balance: Float // v28.0: -1.0 (Left) to +1.0 (Right)
        public let msBalance: Float // v51.0: Mid/Side balance (0.0 = Pure Mono, 1.0 = Pure Side)
    }
    
    /// Analyzes stereo image properties.
    public func analyze(left: [Float], right: [Float]) -> StereoResult {
        let count = min(left.count, right.count)
        guard count > 0 else { return StereoResult(correlation: 0, monoCompatibility: "N/A", balance: 0, msBalance: 0) }
        
        // 1. Phase Correlation: Pearson correlation between L and R
        var correlation: Float = 0
        
        var dotProduct: Float = 0
        vDSP_dotpr(left, 1, right, 1, &dotProduct, vDSP_Length(count))
        
        var sumSqL: Float = 0
        vDSP_svemg(left, 1, &sumSqL, vDSP_Length(count)) // Approximate energy
        vDSP_dotpr(left, 1, left, 1, &sumSqL, vDSP_Length(count))
        
        var sumSqR: Float = 0
        vDSP_dotpr(right, 1, right, 1, &sumSqR, vDSP_Length(count))
        
        let denominator = sqrtf(sumSqL * sumSqR)
        correlation = (denominator > 1e-12) ? dotProduct / denominator : 0
        
        // 2. L/R Balance
        var rmsL: Float = 0
        vDSP_rmsqv(left, 1, &rmsL, vDSP_Length(count))
        
        var rmsR: Float = 0
        vDSP_rmsqv(right, 1, &rmsR, vDSP_Length(count))
        
        let balance = (rmsL + rmsR > 1e-12) ? (rmsR - rmsL) / (rmsL + rmsR) : 0
        
        // 3. Mid/Side Balance (v51.0)
        var mid = [Float](repeating: 0, count: count)
        var side = [Float](repeating: 0, count: count)
        
        vDSP_vadd(left, 1, right, 1, &mid, 1, vDSP_Length(count))
        vDSP_vsub(right, 1, left, 1, &side, 1, vDSP_Length(count))
        
        var rmsMid: Float = 0
        var rmsSide: Float = 0
        vDSP_rmsqv(mid, 1, &rmsMid, vDSP_Length(count))
        vDSP_rmsqv(side, 1, &rmsSide, vDSP_Length(count))
        
        let msBalance = (rmsMid + rmsSide > 1e-12) ? rmsSide / (rmsMid + rmsSide) : 0
        
        // 4. Status
        let compatibility: String
        if correlation > 0.8 {
            compatibility = "Mükemmel"
        } else if correlation > 0.5 {
            compatibility = "İyi"
        } else if correlation > 0 {
            compatibility = "Zayıf (Mono sorunları olabilir)"
        } else {
            compatibility = "Faz İptali Riski"
        }
        
        return StereoResult(
            correlation: correlation,
            monoCompatibility: compatibility,
            balance: balance,
            msBalance: msBalance
        )
    }
}
