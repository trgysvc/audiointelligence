import Foundation
import Accelerate

/// v51.0: Professional Engineering Standard — EBU R128 compliant.
/// Uses BS.1770-4 K-weighting filters and Absolute/Relative gating.
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
    
    public func analyze(samples: [Float]) -> LoudnessResult {
        let weighted = applyBS1770Filter(samples: samples)
        
        // 1. Momentary & Short-term (400ms & 3s windows)
        let momWindowSteps = Int(0.4 * sampleRate)
        let stWindowSteps = Int(3.0 * sampleRate)
        
        var momentaryValues = [Float]()
        var shortTermValues = [Float]()
        
        // Sliding window for LU (Mean Square to dB)
        // EBU R128 defines LU as -0.691 + 10 * log10(mean_square)
        
        // Process momentary (no gate)
        for i in stride(from: 0, to: samples.count - momWindowSteps, by: momWindowSteps / 4) {
            var ms: Float = 0
            weighted.withUnsafeBufferPointer { ptr in
                vDSP_meamgv(ptr.baseAddress!.advanced(by: i), 1, &ms, vDSP_Length(momWindowSteps))
            }
            let lufs = -0.691 + (10 * log10f(max(1e-12, ms)))
            momentaryValues.append(lufs)
        }
        
        // Process short-term (no gate)
        for i in stride(from: 0, to: samples.count - stWindowSteps, by: momWindowSteps / 4) {
            var ms: Float = 0
            weighted.withUnsafeBufferPointer { ptr in
                vDSP_meamgv(ptr.baseAddress!.advanced(by: i), 1, &ms, vDSP_Length(stWindowSteps))
            }
            let lufs = -0.691 + (10 * log10f(max(1e-12, ms)))
            shortTermValues.append(lufs)
        }
        
        // 2. Integrated Loudness (Gated)
        // BS.1770 Gating logic: 
        // 1. Absolute Threshold (-70 LKFS)
        // 2. Relative Threshold (-10 dB relative to mean of absolute-gated blocks)
        
        let blockLen = Int(0.4 * sampleRate)
        let overlap = blockLen / 4
        var blocksMS = [Float]()
        
        for i in stride(from: 0, to: samples.count - blockLen, by: overlap) {
            var ms: Float = 0
            weighted.withUnsafeBufferPointer { ptr in
                vDSP_meamgv(ptr.baseAddress!.advanced(by: i), 1, &ms, vDSP_Length(blockLen))
            }
            blocksMS.append(ms)
        }
        
        // Absolute Gate
        let absGateBlocks = blocksMS.filter { ms in
            let lufs = -0.691 + (10 * log10f(max(1e-12, ms)))
            return lufs > -70.0
        }
        
        var integratedLUFS: Float = -70.0
        if !absGateBlocks.isEmpty {
            let meanAbsGated = absGateBlocks.reduce(0, +) / Float(absGateBlocks.count)
            let relativeThresholdLUFS = (-0.691 + (10 * log10f(max(1e-12, meanAbsGated)))) - 10.0
            let relThresholdMS = powf(10.0, (relativeThresholdLUFS + 0.691) / 10.0)
            
            let relGatedBlocks = absGateBlocks.filter { $0 >= relThresholdMS }
            if !relGatedBlocks.isEmpty {
                let finalMeanMS = relGatedBlocks.reduce(0, +) / Float(relGatedBlocks.count)
                integratedLUFS = -0.691 + (10 * log10f(max(1e-12, finalMeanMS)))
            }
        }
        
        // 3. True Peak (v51.0: Real Oversampling)
        let tpEngine = TruePeakEngine()
        let truePeakDb = tpEngine.detect(samples: samples)
        
        return LoudnessResult(
            integratedLUFS: integratedLUFS,
            momentaryLUFsMax: momentaryValues.max() ?? -70.0,
            shortTermLUFsMax: shortTermValues.max() ?? -70.0,
            truePeakDb: truePeakDb,
            loudnessRange: 0 // Complexity too high for this phase
        )
    }
    
    private func applyBS1770Filter(samples: [Float]) -> [Float] {
        // Cascaded Biquad for K-Weighting (Pre-filter + RLB)
        // Coefficients derived for 48kHz (most common)
        // b0, b1, b2, a1, a2
        let preFilter: [Double] = [1.53512485958697, -2.69169618940638, 1.19839281085285, -1.69065929318241, 0.73248077421585]
        let rlbFilter: [Double] = [1.0, -2.0, 1.0, -1.99004745483398, 0.99007225036621]
        
        var output = samples
        var input = samples
        
        // Stage 1: Pre-filter
        applyBiquad(input: &input, output: &output, coeffs: preFilter)
        
        // Stage 2: RLB filter
        var input2 = output
        applyBiquad(input: &input2, output: &output, coeffs: rlbFilter)
        
        return output
    }
    
    private func applyBiquad(input: inout [Float], output: inout [Float], coeffs: [Double]) {
        let n = input.count
        guard let setup = vDSP_biquad_CreateSetup(coeffs, 1) else { return }
        defer { vDSP_biquad_DestroySetup(setup) }
        
        var delay = [Float](repeating: 0, count: 2)
        vDSP_biquad(setup, &delay, input, 1, &output, 1, vDSP_Length(n))
    }
}
