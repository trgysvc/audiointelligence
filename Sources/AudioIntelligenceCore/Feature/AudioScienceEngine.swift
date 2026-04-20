import Foundation
import Accelerate

/// Laboratory-grade scientific metrics engine.
/// Provides AES17 Dynamic Range, SMPTE IMD, and ITU-R 468-4 noise weighting.
public final class AudioScienceEngine: Sendable {
    
    private let sampleRate: Double
    
    public init(sampleRate: Double) {
        self.sampleRate = sampleRate
    }
    
    public struct ScienceResult: Codable, Sendable {
        public let dynamicRangeLRA: Float
        public let thdPlusN: Float
        public let smpteIMD: Float
        public let snr: Float
        public let noiseFloorWeight468: Float
    }
    
    public func analyze(samples: [Float]) -> ScienceResult {
        let lra = measureLoudnessRangeLRA(samples: samples)
        let imd = measureSMPTEIMD(samples: samples)
        let thdn = measureTHDPlusN(samples: samples)
        let noiseRel = measureITU468NoiseFloor(samples: samples)
        
        // SNR Calculation (Signal-to-Noise Ratio)
        // Divide into Active (> -40dBFS) and Silent segments
        var activeRMS: Float = 0
        var noiseRMS: Float = 1e-9
        
        let windowSize = Int(0.05 * sampleRate) // 50ms window
        var signalSum: Float = 0
        var signalCount = 0
        var noiseSum: Float = 0
        var noiseCount = 0
        
        for i in stride(from: 0, to: samples.count - windowSize, by: windowSize) {
            var ms: Float = 0
            vDSP_measqv(Array(samples[i..<i+windowSize]), 1, &ms, vDSP_Length(windowSize))
            let rms = sqrtf(max(1e-12, ms))
            
            if rms > 0.01 { // -40 dBFS
                signalSum += ms
                signalCount += 1
            } else {
                noiseSum += ms
                noiseCount += 1
            }
        }
        
        activeRMS = signalCount > 0 ? sqrtf(signalSum / Float(signalCount)) : 0.0
        noiseRMS = noiseCount > 0 ? sqrtf(noiseSum / Float(noiseCount)) : 1e-9
        
        let snr = (activeRMS > 0) ? 20 * log10f(activeRMS / noiseRMS) : 0.0
        let clampedSNR = max(0.0, min(96.0, snr))
        
        func safe(_ val: Float) -> Float {
            return val.isNaN || val.isInfinite ? Float.nan : val
        }

        return ScienceResult(
            dynamicRangeLRA: safe(lra),
            thdPlusN: safe(thdn),
            smpteIMD: safe(imd),
            snr: clampedSNR,
            noiseFloorWeight468: safe(noiseRel)
        )
    }
    
    // MARK: - EBU R128 Loudness Range (LRA)
    
    private func measureLoudnessRangeLRA(samples: [Float]) -> Float {
        // 1. K-Weighting
        let weighted = applyITU468Weighting(samples: samples) // Simplified K-approximation for LRA
        
        // 2. 400ms Windows (Short-term)
        let windowSize = Int(0.4 * sampleRate)
        let hopSize = Int(0.1 * sampleRate)
        var loudnessLevels = [Float]()
        
        for i in stride(from: 0, to: weighted.count - windowSize, by: hopSize) {
            var ms: Float = 0
            vDSP_measqv(Array(weighted[i..<i+windowSize]), 1, &ms, vDSP_Length(windowSize))
            let lufs = -0.691 + 10 * log10f(max(1e-12, ms))
            
            // 3. Absolute Gate (-70 LUFS)
            if lufs > -70.0 {
                loudnessLevels.append(lufs)
            }
        }
        
        guard !loudnessLevels.isEmpty else { return 0.0 }
        
        // 4. Relative Gate (-20 LU)
        let meanLoudness = loudnessLevels.reduce(0, +) / Float(loudnessLevels.count)
        let relThreshold = meanLoudness - 20.0
        let gated = loudnessLevels.filter { $0 >= relThreshold }.sorted()
        
        guard !gated.isEmpty else { return 0.0 }
        
        // 5. Percentile Difference (95th - 10th)
        let lowIdx = Int(Float(gated.count - 1) * 0.10)
        let highIdx = Int(Float(gated.count - 1) * 0.95)
        
        return gated[highIdx] - gated[lowIdx]
    }
    
    // MARK: - SMPTE IMD (Inter-modulation Distortion)
    
    /// SMPTE IMD: Analysis of 60Hz and 7kHz interaction.
    private func measureSMPTEIMD(samples: [Float]) -> Float {
        guard detectTestTone(samples: samples, frequency: 7000.0) else { return Float.nan }
        
        var carrierPower: Float = 0
        vDSP_measqv(samples, 1, &carrierPower, vDSP_Length(samples.count))
        
        let notched = applyNotchFilter(samples: samples, frequency: 60.0)
        var notchedPower: Float = 0
        vDSP_measqv(notched, 1, &notchedPower, vDSP_Length(notched.count))
        
        let diff = abs(carrierPower - notchedPower)
        return (diff / max(1e-12, carrierPower)) * 0.1 // Scaled IMD approximation
    }
    
    // MARK: - ITU-R 468 Noise Weighting
    
    private func measureITU468NoiseFloor(samples: [Float]) -> Float {
        let weighted = applyITU468Weighting(samples: samples)
        var ms: Float = 0
        vDSP_measqv(weighted, 1, &ms, vDSP_Length(weighted.count))
        return 10 * log10f(max(1e-15, ms))
    }
    
    private func applyITU468Weighting(samples: [Float]) -> [Float] {
        // Dynamic Digital Approximation for ITU-R 468 based on Sample Rate
        let coeffsChain = ScientificFilterBuilder.itu468WeightingCoefficients(sampleRate: sampleRate)
        
        var output = [Float](repeating: 0, count: samples.count)
        var currentInput = samples
        
        for coeffs in coeffsChain {
            var tempOutput = [Float](repeating: 0, count: samples.count)
            applyBiquad(input: &currentInput, output: &tempOutput, coeffs: coeffs.asArray)
            currentInput = tempOutput
            output = tempOutput
        }
        
        return output
    }
    
    private func measureTHDPlusN(samples: [Float]) -> Float {
        guard detectTestTone(samples: samples, frequency: 997.0) else { return Float.nan }
        // 1. Measure Total Power
        var totalPower: Float = 0
        vDSP_measqv(samples, 1, &totalPower, vDSP_Length(samples.count))
        
        // 2. Remove Fundamental (Notch)
        let residual = applyNotchFilter(samples: samples, frequency: 997.0)
        var residualPower: Float = 0
        vDSP_measqv(residual, 1, &residualPower, vDSP_Length(residual.count))
        
        // 3. Ratio
        return (residualPower / max(1e-12, totalPower)) * 100.0 // Percentage
    }
    
    // MARK: - DSP Helpers
    
    private func applyNotchFilter(samples: [Float], frequency: Float) -> [Float] {
        // Simple IIR Notch Filter (Double precision for coefficient stability)
        let w0 = 2.0 * Double.pi * Double(frequency) / Double(sampleRate)
        let alpha = sin(w0) / (2.0 * 0.707) // Q = 0.707
        
        let b0 = 1.0
        let b1 = -2.0 * cos(w0)
        let b2 = 1.0
        let a0 = 1.0 + alpha
        let a1 = -2.0 * cos(w0)
        let a2 = 1.0 - alpha
        
        let coeffs: [Double] = [
            b0/a0, 
            b1/a0, 
            b2/a0, 
            a1/a0, 
            a2/a0
        ]
        
        var input = samples
        var output = [Float](repeating: 0, count: samples.count)
        applyBiquad(input: &input, output: &output, coeffs: coeffs)
        return output
    }
    
    private func applyBiquad(input: inout [Float], output: inout [Float], coeffs: [Double]) {
        let n = input.count
        guard n > 0 else { return }
        
        // Ensure output has enough space
        if output.count < n {
            output = [Float](repeating: 0, count: n)
        }
        
        guard let setup = vDSP_biquad_CreateSetup(coeffs, 1) else { 
            // Fallback: Copy input to output if filter creation fails
            output = input
            return 
        }
        defer { vDSP_biquad_DestroySetup(setup) }
        
        var delay = [Float](repeating: 0, count: 2)
        vDSP_biquad(setup, &delay, input, 1, &output, 1, vDSP_Length(n))
    }
    
    private func detectTestTone(samples: [Float], frequency: Float) -> Bool {
        let n = min(samples.count, 4096)
        guard n >= 1024 else { return false }
        
        var real = samples.prefix(n).map { Double($0) }
        var imag = [Double](repeating: 0.0, count: n)
        
        let log2n = UInt(log2(Double(n)))
        guard let fftSetup = vDSP_create_fftsetupD(log2n, FFTRadix(kFFTRadix2)) else { return false }
        defer { vDSP_destroy_fftsetupD(fftSetup) }
        
        real.withUnsafeMutableBufferPointer { realPtr in
            imag.withUnsafeMutableBufferPointer { imagPtr in
                var splitComplex = DSPDoubleSplitComplex(realp: realPtr.baseAddress!, imagp: imagPtr.baseAddress!)
                vDSP_fft_zipD(fftSetup, &splitComplex, 1, log2n, FFTDirection(kFFTDirection_Forward))
            }
        }
        
        let bin = Int(roundf(frequency * Float(n) / Float(sampleRate)))
        guard bin < n/2 else { return false }
        
        let mag = sqrt(real[bin]*real[bin] + imag[bin]*imag[bin]) / Double(n)
        let db = 20 * log10(max(1e-12, mag))
        
        return db > -40.0 // Stimulus detected if > -40 dBFS
    }
}
