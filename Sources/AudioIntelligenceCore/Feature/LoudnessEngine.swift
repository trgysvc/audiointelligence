import Foundation
import Accelerate
import AudioIntelligenceMetal

/// EBU R128 / ITU-R BS.1770-4 Calibrated Loudness Metering Engine.
/// Provides Integrated LUFS, Momentary LUFS, Short-term LUFS, and Loudness Range (LRA).
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
    
    /// Multi-channel Loudness Analysis (EBU R128)
    public func analyze(channels: [[Float]]) -> LoudnessResult {
        guard !channels.isEmpty, !channels[0].isEmpty else {
            return LoudnessResult(integratedLUFS: -100, momentaryLUFsMax: -100, shortTermLUFsMax: -100, truePeakDb: -100, loudnessRange: 0)
        }
        
        let nFrames = channels[0].count
        let nChannels = channels.count
        
        // 1. K-Weighting Filter each channel (BS.1770)
        let weightedChannels = channels.map { applyBS1770Filter(samples: $0) }
        
        // 2. High-Throughput Power Calculation (Integral Signal Architecture)
        // Step A: Square all channels & sum them (Global Pass)
        var totalSquared = [Float](repeating: 0, count: nFrames)
        for ch in 0..<nChannels {
            let squared: [Float]
            if let metal = metalEngine {
                squared = metal.executeParallelSquaring(samples: weightedChannels[ch])
            } else {
                squared = weightedChannels[ch].map { $0 * $0 }
            }
            vDSP_vadd(totalSquared, 1, squared, 1, &totalSquared, 1, vDSP_Length(nFrames))
        }
        
        // Step B: Compute Prefix Sum for O(1) Windowed Energy (CPU)
        var prefixSum = [Float](repeating: 0, count: nFrames + 1)
        var runningSum: Float = 0
        for i in 0..<nFrames {
            runningSum += totalSquared[i]
            prefixSum[i + 1] = runningSum
        }
        
        // 3. Sliding Window Analysis
        let stWindowSteps = Int(3.0 * sampleRate) // 3 seconds
        let momWindowSteps = Int(0.4 * sampleRate) // 400ms
        let stepSize = Int(0.1 * sampleRate) // 100ms overlap
        
        var momentaryLUFS = [Float]()
        var shortTermLUFS = [Float]()
        
        for i in stride(from: 0, to: nFrames - stWindowSteps, by: stepSize) {
            let sumST = prefixSum[i + stWindowSteps] - prefixSum[i]
            let sumMom = prefixSum[i + stWindowSteps] - prefixSum[i + stWindowSteps - momWindowSteps]
            
            // Channel weights (Assume sum of weights=1.0 for simplicity in this pass, 
            // but BS.1770 uses 1.0 for L/R/C and 1.41 for surrounds)
            let msST = sumST / Float(stWindowSteps)
            let msMom = sumMom / Float(momWindowSteps)
            
            momentaryLUFS.append(-0.691 + 10 * log10f(max(1e-12, msMom)))
            shortTermLUFS.append(-0.691 + 10 * log10f(max(1e-12, msST)))
        }
        
        // 4. Integrated Loudness (Gated blocks)
        var blocksPower = [Float]()
        let blockSize = momWindowSteps
        for i in stride(from: 0, to: nFrames - blockSize, by: blockSize / 4) {
            let sum = prefixSum[i + blockSize] - prefixSum[i]
            blocksPower.append(sum / Float(blockSize))
        }
        
        var integratedLUFS: Float = -70.0
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
    
    private func calculateLRA(prefixSum: [Float], nFrames: Int) -> Float {
        let stWindowSteps = Int(3.0 * sampleRate)
        let stepSize = Int(0.1 * sampleRate)
        
        var stPowers = [Float]()
        for i in stride(from: 0, to: nFrames - stWindowSteps, by: stepSize) {
            let sum = prefixSum[i + stWindowSteps] - prefixSum[i]
            stPowers.append(sum / Float(stWindowSteps))
        }
        
        let stLUFS = stPowers.map { -0.691 + 10 * log10f(max(1e-12, $0)) }
        let absGated = stLUFS.filter { $0 > -70.0 }
        guard !absGated.isEmpty else { return 0.0 }
        
        // Relative Gate (-20 LU)
        let absGatedPower = absGated.map { powf(10.0, ($0 + 0.691) / 10.0) }
        let meanPower = absGatedPower.reduce(0, +) / Float(absGatedPower.count)
        let relThresholdLUFS = (-0.691 + 10 * log10f(max(1e-12, meanPower))) - 20.0
        
        let finalLUFS = absGated.filter { $0 >= relThresholdLUFS }.sorted()
        guard !finalLUFS.isEmpty else { return 0.0 }
        
        let low = finalLUFS[Int(Double(finalLUFS.count) * 0.10)]
        let high = finalLUFS[Int(Double(finalLUFS.count) * 0.95)]
        
        return high - low
    }
    
    private func applyBS1770Filter(samples: [Float]) -> [Float] {
        let preCoeffs = LoudnessFilterBuilder.preFilterCoefficients(sampleRate: sampleRate)
        let rlbCoeffs = LoudnessFilterBuilder.rlbFilterCoefficients(sampleRate: sampleRate)
        
        var output = [Float](repeating: 0, count: samples.count)
        var tempInput = samples
        applyBiquad(input: &tempInput, output: &output, coeffs: preCoeffs.asArray)
        var tempInput2 = output
        applyBiquad(input: &tempInput2, output: &output, coeffs: rlbCoeffs.asArray)
        return output
    }
    
    private func applyBiquad(input: inout [Float], output: inout [Float], coeffs: [Double]) {
        guard let setup = vDSP_biquad_CreateSetup(coeffs, 1) else { return }
        defer { vDSP_biquad_DestroySetup(setup) }
        var delay = [Float](repeating: 0, count: 2)
        vDSP_biquad(setup, &delay, input, 1, &output, 1, vDSP_Length(input.count))
    }
}
