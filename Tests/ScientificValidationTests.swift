import XCTest
@testable import AudioIntelligence
@testable import AudioIntelligenceCore

final class ScientificValidationTests: XCTestCase {
    
    let sampleRate: Double = 48000.0
    
    // --- 1. EBU TECH 3341 CALIBRATION ---
    
    /// Official EBU Calibration: 1kHz Sine @ -23dBFS must yield -23.0 LUFS.
    func testLoudnessCalibration() {
        let duration = 5.0
        let n = Int(sampleRate * duration)
        let frequency: Float = 1000.0
        let amplitude = powf(10.0, -23.0 / 20.0)
        
        var samples = [Float](repeating: 0, count: n)
        for i in 0..<n {
            samples[i] = amplitude * sinf(2.0 * Float.pi * frequency * Float(i) / Float(sampleRate))
        }
        
        let engine = LoudnessEngine(sampleRate: sampleRate)
        let result = engine.analyze(samples: samples)
        
        XCTAssertEqual(result.integratedLUFS, -23.0, accuracy: 0.1, "Loudness should be exactly -23.0 LUFS for a -23dBFS 1kHz sine.")
    }
    
    /// Gating Logic Test: Verify that silence is ignored in integrated loudness.
    func testLoudnessGating() {
        let duration = 5.0
        let nHalf = Int(sampleRate * duration)
        let frequency: Float = 1000.0
        let ampHigh = powf(10.0, -20.0 / 20.0) // -20dBFS
        let ampLow = powf(10.0, -100.0 / 20.0) // -100dBFS (Silence)
        
        var samples = [Float](repeating: 0, count: nHalf * 2)
        
        // 5s Loud Sine
        for i in 0..<nHalf {
            samples[i] = ampHigh * sinf(2.0 * Float.pi * frequency * Float(i) / Float(sampleRate))
        }
        
        // 5s Silence (ampLow)
        for i in nHalf..<(nHalf * 2) {
            samples[i] = ampLow
        }
        
        let engine = LoudnessEngine(sampleRate: sampleRate)
        let result = engine.analyze(samples: samples)
        
        XCTAssertEqual(result.integratedLUFS, -20.0, accuracy: 0.5, "Integrated loudness should match the loud section, gating out the silence.")
    }
    
    // --- 2. TRUE PEAK INTER-SAMPLE AUDIT ---
    
    /// Verify that our 4x oversampler detects inter-sample peaks.
    func testTruePeakOversampling() {
        // A sine wave at 1/4 Nyquist, shifted by 45 degrees.
        // Sampled values: sin(pi/4), sin(3pi/4)... all 0.707 (-3.01 dBFS).
        // Real peak is 1.0 (0.0 dBFS).
        let n = 1000
        var samples = [Float](repeating: 0, count: n)
        for i in 0..<n {
            samples[i] = sinf(Float(i) * Float.pi / 2.0 + Float.pi / 4.0)
        }
        
        let engine = TruePeakEngine()
        let tp = engine.detect(samples: samples)
        
        XCTAssertGreaterThan(tp, -0.5, "True peak should be close to 0.0 dBTP, detected from -3.0 dBFS samples.")
        XCTAssertLessThanOrEqual(tp, 0.1, "True Peak should not exceed 0.1 dBTP for a 1.0 peak sine.")
    }
    
    // --- 3. FORENSIC ENTROPY (NATIVE VS UPSAMPLED) ---
    
    /// Prove that our Shannon Entropy analysis identifies bit-depth forgery.
    func testForensicEntropySensitivity() async {
        let n = 48000
        let engine = ForensicDNAEngine()
        
        // CASE A: High Entropy (White Noise) - Simulated 24-bit
        var nativeSamples = [Float](repeating: 0, count: n)
        for i in 0..<n {
            nativeSamples[i] = Float.random(in: -1.0...1.0)
        }
        let nativeRes = engine.analyzeBitDepthIntegrity(samples: nativeSamples)
        
        // CASE B: Low Entropy (16-bit Quantized) - Shifted to 24-bit
        var fakeSamples = [Float](repeating: 0, count: n)
        for i in 0..<n {
            // Precise 16-bit quantization simulation
            let s16 = Int16(clamp(nativeSamples[i], min: -1.0, max: 1.0) * 32768.0)
            fakeSamples[i] = Float(s16) / 32768.0
        }
        let fakeRes = engine.analyzeBitDepthIntegrity(samples: fakeSamples)
        
        XCTAssertLessThanOrEqual(fakeRes.effectiveBits, 16, "Upsampled 16-bit should show <= 16 effective bits.")
        XCTAssertGreaterThan(nativeRes.effectiveBits, 20, "Native noise should show high bit-depth entropy.")
        XCTAssertTrue(fakeRes.isLikelyUpsampled, "Engine should flag quantized noise as upsampled.")
    }
    
    // --- 4. EBU TECH 3342 (LRA) VALIDATION ---
    
    /// Verify LRA calculation using a dynamic 20s profile.
    func testLoudnessRange() {
        let duration = 10.0
        let nHalf = Int(sampleRate * duration)
        
        // 10s @ -20 LUFS, 10s @ -30 LUFS
        let amp1 = powf(10.0, -20.0 / 20.0)
        let amp2 = powf(10.0, -30.0 / 20.0)
        
        var samples = [Float](repeating: 0, count: nHalf * 2)
        for i in 0..<nHalf {
            samples[i] = amp1 * sinf(2.0 * Float.pi * 1000.0 * Float(i) / Float(sampleRate))
            samples[i + nHalf] = amp2 * sinf(2.0 * Float.pi * 1000.0 * Float(i) / Float(sampleRate))
        }
        
        let engine = LoudnessEngine(sampleRate: sampleRate)
        let result = engine.analyze(samples: samples)
        
        XCTAssertGreaterThan(result.loudnessRange, 9.0, "LRA should detect the 10 LU dynamic shift.")
        XCTAssertLessThan(result.loudnessRange, 11.0, "LRA should be within 1 LU of the target shift.")
    }
    
    // --- 5. AES17 & SCIENCE VALIDATION ---
    
    func testAudioScienceAES17() {
        let n = 48000
        let ampStim = powf(10.0, -60.0 / 20.0)
        let ampNoise = powf(10.0, -110.0 / 20.0)
        
        var samples = [Float](repeating: 0, count: n)
        for i in 0..<n {
            let sine = ampStim * sinf(2.0 * Float.pi * 997.0 * Float(i) / Float(sampleRate))
            let noise = Float.random(in: -ampNoise...ampNoise)
            samples[i] = sine + noise
        }
        
        let engine = AudioScienceEngine(sampleRate: sampleRate)
        let result = engine.analyze(samples: samples)
        
        XCTAssertGreaterThan(result.dynamicRangeAES17, 40.0, "AES17 Dynamic Range should identify the noise floor.")
    }

    /// --- 6. THE MASTER DIAGNOSTIC AUDIT (v52.1) ---
    /// This test outputs the formal "Truth Table" for the ScientificValidation.md manifest.
    func testDiagnosticAuditReport() {
        let auditor = ScientificAuditor()
        let results = [
            auditor.runScenarioA(),
            auditor.runScenarioB(),
            auditor.runScenarioC(),
            auditor.runScenarioD()
        ]
        
        print("\n--- 🧪 AUDIOINTELLIGENCE SCIENTIFIC AUDIT REPORT ---")
        print("| Scenario | Expected | Measured | Error | Status |")
        print("| :--- | :--- | :--- | :--- | :--- |")
        
        for res in results {
            let status = res.passed ? "✅ PASS" : "❌ FAIL"
            print("| \(res.scenarioName) | \(res.expectedValue) | \(res.measuredValue) | \(String(format: "%.3f", res.errorDb)) | \(status) |")
        }
        print("----------------------------------------------------\n")
    }
    
    private func clamp<T: Comparable>(_ value: T, min: T, max: T) -> T {
        return Swift.max(min, Swift.min(max, value))
    }
}
