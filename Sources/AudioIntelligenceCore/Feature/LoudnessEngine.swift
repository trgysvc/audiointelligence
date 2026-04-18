import Foundation
import Accelerate
import AudioIntelligenceMetal

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
        
        // 1. Filter each channel
        let weightedChannels = channels.map { applyBS1770Filter(samples: $0) }
        
        // 2. Compute Mean Square per channel in windows
        let momWindowSteps = Int(0.4 * sampleRate)
        let stWindowSteps = Int(3.0 * sampleRate)
        let stepSize = Int(0.1 * sampleRate) // 100ms
        
        var momentaryLUFS = [Float]()
        var shortTermLUFS = [Float]()
        
        // Sliding window for LU (Sum of Powers)
        for i in stride(from: 0, to: nFrames - stWindowSteps, by: stepSize) {
            var totalPowerST: Float = 0
            var totalPowerMom: Float = 0
            
            for ch in 0..<weightedChannels.count {
                var msST: Float = 0
                var msMom: Float = 0
                
                weightedChannels[ch].withUnsafeBufferPointer { ptr in
                    // Short Term (3s)
                    vDSP_measqv(ptr.baseAddress!.advanced(by: i), 1, &msST, vDSP_Length(stWindowSteps))
                    // Momentary (400ms)
                    vDSP_measqv(ptr.baseAddress!.advanced(by: i + stWindowSteps - momWindowSteps), 1, &msMom, vDSP_Length(momWindowSteps))
                }
                
                // Weighting (L/R = 1.0, others vary but we assume Stereo for now)
                totalPowerST += msST
                totalPowerMom += msMom
            }
            
            momentaryLUFS.append(-0.691 + 10 * log10f(max(1e-12, totalPowerMom)))
            shortTermLUFS.append(-0.691 + 10 * log10f(max(1e-12, totalPowerST)))
        }
        
        // 3. Integrated Loudness (Gated blocks of 400ms)
        var blocksPower = [Float]()
        for i in stride(from: 0, to: nFrames - momWindowSteps, by: momWindowSteps / 4) { // 75% overlap
            var totalPower: Float = 0
            for ch in 0..<weightedChannels.count {
                var ms: Float = 0
                weightedChannels[ch].withUnsafeBufferPointer { ptr in
                    vDSP_measqv(ptr.baseAddress!.advanced(by: i), 1, &ms, vDSP_Length(momWindowSteps))
                }
                totalPower += ms
            }
            blocksPower.append(totalPower)
        }
        
        var integratedLUFS: Float = -70.0
        // Absolute Gate
        let absGateBlocks = blocksPower.filter { p in
            let lufs = -0.691 + 10 * log10f(max(1e-12, p))
            return lufs > -70.0
        }
        
        if !absGateBlocks.isEmpty {
            let meanAbsGated = absGateBlocks.reduce(0, +) / Float(absGateBlocks.count)
            let relativeThresholdLUFS = (-0.691 + 10 * log10f(max(1e-12, meanAbsGated))) - 10.0
            let relThresholdPower = powf(10.0, (relativeThresholdLUFS + 0.691) / 10.0)
            
            let relGatedBlocks = absGateBlocks.filter { $0 >= relThresholdPower }
            if !relGatedBlocks.isEmpty {
                let finalMeanPower = relGatedBlocks.reduce(0, +) / Float(relGatedBlocks.count)
                integratedLUFS = -0.691 + 10 * log10f(max(1e-12, finalMeanPower))
            }
        }
        
        // 4. True Peak (Max of all channels)
        var maxTP: Float = -100.0
        for ch in channels {
            let tp = tpEngine.detect(samples: ch)
            maxTP = max(maxTP, tp)
        }
        
        // 5. LRA
        let lra = calculateLRA(weightedChannels: weightedChannels)
        
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
    
    private func calculateLRA(weightedChannels: [[Float]]) -> Float {
        let nFrames = weightedChannels[0].count
        let stWindowSteps = Int(3.0 * sampleRate)
        let stepSize = Int(0.1 * sampleRate)
        
        var stPowers = [Float]()
        for i in stride(from: 0, to: nFrames - stWindowSteps, by: stepSize) {
            var totalPower: Float = 0
            for ch in 0..<weightedChannels.count {
                var ms: Float = 0
                weightedChannels[ch].withUnsafeBufferPointer { ptr in
                    vDSP_measqv(ptr.baseAddress!.advanced(by: i), 1, &ms, vDSP_Length(stWindowSteps))
                }
                totalPower += ms
            }
            stPowers.append(totalPower)
        }
        
        let stLUFS = stPowers.map { -0.691 + 10 * log10f(max(1e-12, $0)) }
        let absGated = stLUFS.filter { $0 > -70.0 }
        guard !absGated.isEmpty else { return 0.0 }
        
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
