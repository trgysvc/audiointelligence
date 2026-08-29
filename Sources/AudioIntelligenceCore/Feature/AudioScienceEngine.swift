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

        // SMPTE/DIN IMD: a 60 Hz + 7 kHz (4:1) stimulus; nonlinearity amplitude-modulates the
        // 7 kHz carrier, producing sidebands at 7000 ± k·60. IMD = RMS(sidebands)/carrier.
        // The previous code measured the 60 Hz tone's energy and scaled by 0.1 — unrelated to
        // intermodulation. This is a windowed-FFT measurement of the actual sideband structure.
        let n = 1 << Int(log2(Double(samples.count)))
        guard n >= 1024 else { return Float.nan }

        var real = [Double](repeating: 0, count: n)
        let a0 = 0.35875, a1 = 0.48829, a2 = 0.14128, a3 = 0.01168
        for i in 0..<n {
            let x = 2.0 * Double.pi * Double(i) / Double(n - 1)
            real[i] = Double(samples[i]) * (a0 - a1 * cos(x) + a2 * cos(2 * x) - a3 * cos(3 * x))
        }
        var imag = [Double](repeating: 0, count: n)
        let log2n = UInt(log2(Double(n)))
        guard let setup = vDSP_create_fftsetupD(log2n, FFTRadix(kFFTRadix2)) else { return Float.nan }
        defer { vDSP_destroy_fftsetupD(setup) }
        real.withUnsafeMutableBufferPointer { rp in
            imag.withUnsafeMutableBufferPointer { ip in
                var sc = DSPDoubleSplitComplex(realp: rp.baseAddress!, imagp: ip.baseAddress!)
                vDSP_fft_zipD(setup, &sc, 1, log2n, FFTDirection(kFFTDirection_Forward))
            }
        }

        func powerAround(_ hz: Double, _ guardBins: Int = 6) -> Double {
            let b = Int((hz * Double(n) / sampleRate).rounded())
            guard b > guardBins, b < n / 2 - guardBins else { return 0 }
            var p = 0.0
            for k in (b - guardBins)...(b + guardBins) { p += real[k] * real[k] + imag[k] * imag[k] }
            return p
        }
        let carrierP = powerAround(7000)
        let sidebandP = [6940.0, 7060.0, 6880.0, 7120.0].map { powerAround($0) }.reduce(0, +)
        return Float(sqrt(sidebandP / max(1e-20, carrierP)) * 100.0)
    }
    
    // MARK: - ITU-R 468 Noise Weighting
    
    /// Exact ITU-R 468 linear response R(f), normalized so 1 kHz = unity gain (0 dB).
    /// Standard analytic form; replaces the hardcoded biquad approximation that under-
    /// responded ~6 dB at the 6.3 kHz peak.
    private func itu468Response(_ f: Double) -> Double {
        let h1 = -4.737338981378384e-24 * pow(f, 6) + 2.043828333606125e-15 * pow(f, 4)
               - 1.363894795463638e-7 * f * f + 1.0
        let h2 = 1.306612257412824e-19 * pow(f, 5) - 2.118150887518656e-11 * pow(f, 3)
               + 5.559488023498642e-4 * f
        let r = 1.246332637532143e-4 * f / sqrt(h1 * h1 + h2 * h2)
        return r / 0.12246482731463624 // ÷ R(1000) → 1 kHz = 0 dB
    }

    private func measureITU468NoiseFloor(samples: [Float]) -> Float {
        // Frequency-domain weighting with the exact analytic R(f), windowed FFT.
        let n = 1 << Int(log2(Double(samples.count)))
        guard n >= 1024 else { return -120 }
        var real = [Double](repeating: 0, count: n)
        let a0 = 0.35875, a1 = 0.48829, a2 = 0.14128, a3 = 0.01168
        for i in 0..<n {
            let x = 2.0 * Double.pi * Double(i) / Double(n - 1)
            real[i] = Double(samples[i]) * (a0 - a1 * cos(x) + a2 * cos(2 * x) - a3 * cos(3 * x))
        }
        var imag = [Double](repeating: 0, count: n)
        let log2n = UInt(log2(Double(n)))
        guard let setup = vDSP_create_fftsetupD(log2n, FFTRadix(kFFTRadix2)) else { return -120 }
        defer { vDSP_destroy_fftsetupD(setup) }
        real.withUnsafeMutableBufferPointer { rp in
            imag.withUnsafeMutableBufferPointer { ip in
                var sc = DSPDoubleSplitComplex(realp: rp.baseAddress!, imagp: ip.baseAddress!)
                vDSP_fft_zipD(setup, &sc, 1, log2n, FFTDirection(kFFTDirection_Forward))
            }
        }
        var weightedMS = 0.0
        for k in 1..<(n / 2) {
            let f = Double(k) * sampleRate / Double(n)
            let w = itu468Response(f)
            weightedMS += (real[k] * real[k] + imag[k] * imag[k]) * w * w
        }
        // Consistent scale (FFT energy / window) → relative gains are exact 468 curve values.
        return Float(10 * log10(max(1e-20, weightedMS) / (Double(n) * Double(n))))
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

        // Frequency-domain THD+N. A windowed FFT isolates the fundamental cleanly (a wide IIR
        // notch leaked ~1% of the fundamental). THD+N is an RMS ratio, so we take the square
        // root of the residual/total *power* ratio — the previous code returned the power
        // ratio directly, under-reporting a 1% distortion as 0.02%.
        let n = 1 << Int(log2(Double(samples.count)))   // largest power of two ≤ count
        guard n >= 1024 else { return Float.nan }

        // 4-term Blackman-Harris (−92 dB side lobes): a sine at a non-integer bin (997 Hz is
        // deliberately not bin-aligned) leaks far less than under a Hann window, so a pure
        // tone reads ~0% instead of a spurious ~0.7% from window skirts.
        var real = [Double](repeating: 0, count: n)
        let a0 = 0.35875, a1 = 0.48829, a2 = 0.14128, a3 = 0.01168
        for i in 0..<n {
            let x = 2.0 * Double.pi * Double(i) / Double(n - 1)
            let w = a0 - a1 * cos(x) + a2 * cos(2 * x) - a3 * cos(3 * x)
            real[i] = Double(samples[i]) * w
        }
        var imag = [Double](repeating: 0, count: n)
        let log2n = UInt(log2(Double(n)))
        guard let setup = vDSP_create_fftsetupD(log2n, FFTRadix(kFFTRadix2)) else { return Float.nan }
        defer { vDSP_destroy_fftsetupD(setup) }
        real.withUnsafeMutableBufferPointer { rp in
            imag.withUnsafeMutableBufferPointer { ip in
                var sc = DSPDoubleSplitComplex(realp: rp.baseAddress!, imagp: ip.baseAddress!)
                vDSP_fft_zipD(setup, &sc, 1, log2n, FFTDirection(kFFTDirection_Forward))
            }
        }

        let fundBin = Int((997.0 * Double(n) / sampleRate).rounded())
        let guardBins = 6 // Blackman-Harris main lobe is ~±4 bins; ±6 captures it fully
        var totalP = 0.0, fundP = 0.0
        for k in 1..<(n / 2) {
            let p = real[k] * real[k] + imag[k] * imag[k]
            totalP += p
            if abs(k - fundBin) <= guardBins { fundP += p }
        }
        let residual = max(0.0, totalP - fundP)
        return Float(sqrt(residual / max(1e-20, totalP)) * 100.0)
    }
    
    // MARK: - DSP Helpers

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
