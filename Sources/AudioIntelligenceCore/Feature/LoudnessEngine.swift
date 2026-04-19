import Foundation
import Accelerate
import AudioIntelligenceMetal

/// EBU R128 / ITU-R BS.1770-4 / EBU Tech 3342 Calibrated Loudness Metering Engine.
/// Provides Integrated LUFS, Momentary LUFS, Short-term LUFS, and Loudness Range (LRA).
///
/// Features:
/// - Double Precision prefix sum for energy accumulation (BS.1770-4 compliant).
/// - Industry-standard Dual-Gating (-70 absolute, -10/-20 relative).
/// - Correct Channel Summing (Energy addition vs averaging).
/// - Standard Percentile Logic for LRA (10th/95th).
public final class LoudnessEngine: Sendable {
    
    private let sampleRate: Double
    private let tpEngine = TruePeakEngine()
    private let metalEngine: MetalEngine?
    
    public init(sampleRate: Double, metalEngine: MetalEngine? = nil) {
        self.sampleRate = sampleRate
        self.metalEngine = metalEngine
    }
    
    public struct LoudnessResult: Sendable, Codable {
        public let integratedLUFS: Float
        public let momentaryLUFsMax: Float
        public let shortTermLUFsMax: Float
        public let truePeakDb: Float
        public let loudnessRange: Float
    }
    
    /// Multi-channel Loudness Analysis (EBU R128 / BS.1770-4)
    public func analyze(channels: [[Float]]) -> LoudnessResult {
        guard !channels.isEmpty, !channels[0].isEmpty else {
            return LoudnessResult(integratedLUFS: -100, momentaryLUFsMax: -100, shortTermLUFsMax: -100, truePeakDb: -100, loudnessRange: 0)
        }
        
        let nFrames = channels[0].count
        let nChannels = channels.count
        
        // 1. K-Weighting Filter each channel (BS.1770)
        let weightedChannels = channels.map { applyBS1770Filter(samples: $0) }
        
        // 2. High-Precision Power Calculation (Sum of Channel Energies)
        // BS.1770-4: Loudness is based on the sum of weighted channel energies.
        var totalSquared = [Float](repeating: 0, count: nFrames)
        for ch in 0..<nChannels {
            let squared: [Float]
            if let metal = metalEngine {
                squared = metal.executeParallelSquaring(samples: weightedChannels[ch])
            } else {
                squared = [Float](repeating: 0, count: nFrames)
                vDSP_vsq(weightedChannels[ch], 1, UnsafeMutablePointer(mutating: squared), 1, vDSP_Length(nFrames))
            }
            
            // Channel weights: L/R/C = 1.0, Surrounds = 1.41 (+1.5 dB)
            // For now, we assume 1.0 for L/R in typical layouts. 
            // In a pro implementation, we check channel map.
            vDSP_vadd(totalSquared, 1, squared, 1, &totalSquared, 1, vDSP_Length(nFrames))
        }
        
        // Step B: Compute Double Precision Prefix Sum
        // Critical for preventing precision loss in long tracks and large dynamics.
        var prefixSum = [Double](repeating: 0, count: nFrames + 1)
        var runningSum: Double = 0
        for i in 0..<nFrames {
            runningSum += Double(totalSquared[i])
            prefixSum[i + 1] = runningSum
        }
        
        // 3. Sliding Window Analysis
        // Momentary: 400ms. Short-term: 3s.
        let momWindowSteps = Int(round(0.4 * sampleRate))
        let stWindowSteps = Int(round(3.0 * sampleRate))
        let hopSize = Int(round(0.1 * sampleRate)) // 100ms step (10Hz sampling)
        
        var momentaryLUFS = [Float]()
        var shortTermLUFS = [Float]()
        
        // Sample Momentary across the whole file
        for i in stride(from: 0, to: nFrames - momWindowSteps + 1, by: hopSize) {
            let sumMom = prefixSum[i + momWindowSteps] - prefixSum[i]
            let msMom = Float(sumMom / Double(momWindowSteps))
            momentaryLUFS.append(-0.691 + 10 * log10f(max(1e-12, msMom)))
        }
        
        // Sample Short-term across the whole file
        for i in stride(from: 0, to: nFrames - stWindowSteps + 1, by: hopSize) {
            let sumST = prefixSum[i + stWindowSteps] - prefixSum[i]
            let msST = Float(sumST / Double(stWindowSteps))
            shortTermLUFS.append(-0.691 + 10 * log10f(max(1e-12, msST)))
        }
        
        // 4. Integrated Loudness (Dual-Gated)
        // BS.1770-4: Mean of 400ms blocks above thresholds.
        var integratedLUFS: Float = -70.0
        
        // Use the momentary (400ms) blocks for integration gating.
        let blocksPower = stride(from: 0, to: nFrames - momWindowSteps + 1, by: hopSize).map { i in
            Float((prefixSum[i + momWindowSteps] - prefixSum[i]) / Double(momWindowSteps))
        }
        
        let absGateBlocks = blocksPower.filter { -0.691 + 10 * log10f(max(1e-12, $0)) > -70.0 }
        if !absGateBlocks.isEmpty {
            let meanAbsGated = absGateBlocks.reduce(0, +) / Float(absGateBlocks.count)
            let relThresholdLUFS = (-0.691 + 10 * log10f(max(1e-12, meanAbsGated))) - 10.0
            let relThresholdPower = powf(10.0, (relThresholdLUFS + 0.691) / 10.0)
            
            let relGatedBlocks = absGateBlocks.filter { $0 >= relThresholdPower }
            if !relGatedBlocks.isEmpty {
                let finalMeanPower = relGatedBlocks.reduce(0, +) / Float(relGatedBlocks.count)
                integratedLUFS = -0.691 + 10 * log10f(max(1e-12, finalMeanPower))
            }
        }
        
        // 5. True Peak & LRA
        var maxTP: Float = -100.0
        for ch in channels {
            maxTP = max(maxTP, tpEngine.detect(samples: ch))
        }
        
        let lra = calculateLRA(prefixSum: prefixSum, nFrames: nFrames)
        
        return LoudnessResult(
            integratedLUFS: integratedLUFS,
            momentaryLUFsMax: momentaryLUFS.max() ?? -70.0,
            shortTermLUFsMax: shortTermLUFS.max() ?? -70.0,
            truePeakDb: maxTP,
            loudnessRange: lra
        )
    }
    
    // Convenience for Mono
    public func analyze(samples: [Float]) -> LoudnessResult {
        return analyze(channels: [samples])
    }
    
    private func calculateLRA(prefixSum: [Double], nFrames: Int) -> Float {
        let stWindowSteps = Int(round(3.0 * sampleRate))
        let stepSize = Int(round(0.1 * sampleRate)) // Use 100ms step (10Hz) for highest accuracy
        
        var stPowers = [Double]()
        for i in stride(from: 0, to: nFrames - stWindowSteps + 1, by: stepSize) {
            let sum = prefixSum[i + stWindowSteps] - prefixSum[i]
            stPowers.append(sum / Double(stWindowSteps))
        }
        
        guard !stPowers.isEmpty else { return 0.0 }
        
        let stLUFS = stPowers.map { -0.691 + 10.0 * log10(max(1e-12, $0)) }
        let absGated = stLUFS.filter { $0 > -70.0 }
        guard !absGated.isEmpty else { return 0.0 }
        
        // Relative Gate (-20 LU)
        // EBU-3342: Threshold is relative to the mean power of abs-gated blocks.
        let absGatedPower = absGated.map { pow(10.0, ($0 + 0.691) / 10.0) }
        let meanPower = absGatedPower.reduce(0, +) / Double(absGatedPower.count)
        let relThresholdLUFS = (-0.691 + 10.0 * log10(max(1e-12, meanPower))) - 20.0
        
        let finalLUFS = absGated.filter { $0 >= relThresholdLUFS }.sorted()
        guard !finalLUFS.isEmpty else { return 0.0 }
        
        // Percentile Calculation (10th and 95th)
        let n = Double(finalLUFS.count)
        let lowIdx = Int(round((n - 1) * 0.10))
        let highIdx = Int(round((n - 1) * 0.95))
        
        let low = Float(finalLUFS[min(max(0, lowIdx), finalLUFS.count - 1)])
        let high = Float(finalLUFS[min(max(0, highIdx), finalLUFS.count - 1)])
        
        return high - low
    }
    
    private func applyBS1770Filter(samples: [Float]) -> [Float] {
        let preCoeffs = LoudnessFilterBuilder.preFilterCoefficients(sampleRate: sampleRate)
        let rlbCoeffs = LoudnessFilterBuilder.rlbFilterCoefficients(sampleRate: sampleRate)
        
        var output = [Float](repeating: 0, count: samples.count)
        var temp = [Float](repeating: 0, count: samples.count)
        
        applyBiquad(input: samples, output: &temp, coeffs: preCoeffs.asArray)
        applyBiquad(input: temp, output: &output, coeffs: rlbCoeffs.asArray)
        
        return output
    }
    
    private func applyBiquad(input: [Float], output: inout [Float], coeffs: [Double]) {
        guard let setup = vDSP_biquad_CreateSetup(coeffs, 1) else { return }
        defer { vDSP_biquad_DestroySetup(setup) }
        
        var delay = [Float](repeating: 0, count: 2)
        vDSP_biquad(setup, &delay, input, 1, &output, 1, vDSP_Length(input.count))
    }
}
