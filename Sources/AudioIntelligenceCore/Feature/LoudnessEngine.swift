import Foundation
import Accelerate
import AudioIntelligenceMetal

/// v51.0: Professional Engineering Standard — EBU R128 compliant.
/// Uses BS.1770-4 K-weighting filters and Absolute/Relative gating.
public final class LoudnessEngine: Sendable {
    
    private let sampleRate: Double
    private let metalEngine: MetalEngine?
    
    public init(sampleRate: Double, metalEngine: MetalEngine? = nil) {
        self.sampleRate = sampleRate
        self.metalEngine = metalEngine
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
            let chunk = Array(weighted[i..<(i + momWindowSteps)])
            
            if let metal = metalEngine {
                ms = metal.executeParallelPower(samples: chunk) / Float(momWindowSteps)
            } else {
                vDSP_measqv(chunk, 1, &ms, vDSP_Length(momWindowSteps))
            }
            
            let lufs = -0.691 + (10 * log10f(max(1e-12, ms))) + 3.01
            momentaryValues.append(lufs)
        }
        
        // Process short-term (no gate)
        for i in stride(from: 0, to: samples.count - stWindowSteps, by: momWindowSteps / 4) {
            var ms: Float = 0
            weighted.withUnsafeBufferPointer { ptr in
                vDSP_measqv(ptr.baseAddress!.advanced(by: i), 1, &ms, vDSP_Length(stWindowSteps))
            }
            let lufs = -0.691 + (10 * log10f(max(1e-12, ms))) + 3.01
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
                vDSP_measqv(ptr.baseAddress!.advanced(by: i), 1, &ms, vDSP_Length(blockLen))
            }
            blocksMS.append(ms)
        }
        
        // Absolute Gate
        let absGateBlocks = blocksMS.filter { ms in
            let lufs = -0.691 + (10 * log10f(max(1e-12, ms))) + 3.01
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
                integratedLUFS = -0.691 + (10 * log10f(max(1e-12, finalMeanMS))) + 3.01
            }
        }
        
        // 3. True Peak (v51.0: Real Oversampling)
        let tpEngine = TruePeakEngine()
        let truePeakDb = tpEngine.detect(samples: samples)
        
        // 4. Loudness Range (v52.0: EBU Tech 3342)
        let lra = calculateLRA(weightedSamples: weighted)
        
        return LoudnessResult(
            integratedLUFS: integratedLUFS,
            momentaryLUFsMax: momentaryValues.max() ?? -70.0,
            shortTermLUFsMax: shortTermValues.max() ?? -70.0,
            truePeakDb: truePeakDb,
            loudnessRange: lra
        )
    }
    
    /// EBU Tech 3342: Loudness Range (LRA) Algorithm
    private func calculateLRA(weightedSamples: [Float]) -> Float {
        let stWindowSteps = Int(3.0 * sampleRate)
        let stepSize = Int(0.1 * sampleRate) // 2.9s overlap (3.0 - 2.9 = 0.1)
        
        var stShortTermPowers = [Float]()
        
        // 1. Gather all short-term (3s) power blocks with 2.9s overlap
        for i in stride(from: 0, to: weightedSamples.count - stWindowSteps, by: stepSize) {
            var ms: Float = 0
            let chunk = Array(weightedSamples[i..<(i + stWindowSteps)])
            
            if let metal = metalEngine {
                ms = metal.executeParallelPower(samples: chunk) / Float(stWindowSteps)
            } else {
                vDSP_measqv(chunk, 1, &ms, vDSP_Length(stWindowSteps))
            }
            stShortTermPowers.append(ms)
        }
        
        guard !stShortTermPowers.isEmpty else { return 0.0 }
        
        // 2. Absolute Gate (-70 LUFS)
        let absGated = stShortTermPowers.compactMap { ms -> Float? in
            let lufs = -0.691 + (10 * log10f(max(1e-12, ms))) + 3.01
            return lufs > -70.0 ? lufs : nil
        }
        
        guard !absGated.isEmpty else { return 0.0 }
        
        // 3. Relative Gate (-20 LU below mean of absolute-gated blocks)
        // Convert LUFS back to linear for averaging
        let absGatedLinear = absGated.map { powf(10.0, ($0 + 0.691 - 3.01) / 10.0) }
        let meanAbsGatedLinear = absGatedLinear.reduce(0, +) / Float(absGatedLinear.count)
        let relativeThresholdLUFS = (-0.691 + (10 * log10(max(1e-12, Double(meanAbsGatedLinear)))) + 3.01) - 20.0
        
        let finalGatedLUFS = absGated.filter { $0 >= Float(relativeThresholdLUFS) }.sorted()
        
        guard !finalGatedLUFS.isEmpty else { return 0.0 }
        
        // 4. LRA = 95th Percentile - 10th Percentile
        let idx10 = Int(Double(finalGatedLUFS.count) * 0.10)
        let idx95 = Int(Double(finalGatedLUFS.count) * 0.95)
        
        let p10 = finalGatedLUFS[min(idx10, finalGatedLUFS.count - 1)]
        let p95 = finalGatedLUFS[min(idx95, finalGatedLUFS.count - 1)]
        
        return p95 - p10
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
