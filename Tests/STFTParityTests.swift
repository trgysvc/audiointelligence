import XCTest
@testable import AudioIntelligence
@testable import AudioIntelligenceCore
@testable import AudioIntelligenceMetal

final class STFTParityTests: XCTestCase {
    
    let sampleRate: Double = 44100.0
    let duration: Double = 2.0
    
    /// Verifies that the CPU (vDSP) and GPU (Metal) paths yield mathematically identical results.
    /// Tolerance: 1e-4 (Forensic-grade parity between Accelerate and Metal)
    func testM4SiliconMathematicalParity() async throws {
        let nFFT = 2048
        let hopLength = 512
        let samples = generateFrequencySweep(startFreq: 20, endFreq: 20000, duration: duration, sr: sampleRate)
        
        // 1. Reference: CPU Path (MetalEngine = nil)
        let cpuEngine = STFTEngine(nFFT: nFFT, hopLength: hopLength, sampleRate: sampleRate, metalEngine: nil)
        let cpuMatrix = await cpuEngine.analyze(samples)
        
        // 2. Target: GPU Path (MetalEngine active)
        // SEALED: Clear cache to ensure fresh GPU execution (not returning CPU cached results)
        await IntelligenceCache.shared.clear()
        
        let metal = MetalEngine()
        guard metal.getHardwareStatus() != "None (Metal No Supported)" else {
            XCTFail("❌ Metal Hardware not found. Cannot verify M4 Silicon Hook parity.")
            return
        }
        
        let gpuEngine = STFTEngine(nFFT: nFFT, hopLength: hopLength, sampleRate: sampleRate, metalEngine: metal)
        let gpuMatrix = await gpuEngine.analyze(samples)
        
        // 3. Telemetry Verification (Seal Lock)
        XCTAssertGreaterThan(metal.kernelExecutionCount["window_and_magnitude", default: 0], 0, "❌ GPU Windowing Hook failed to engage.")
        XCTAssertGreaterThan(metal.kernelExecutionCount["complex_magnitude_phase", default: 0], 0, "❌ GPU Magnitude/Phase Hook failed to engage.")
        
        // 4. Parity Verification
        XCTAssertEqual(cpuMatrix.magnitude.count, gpuMatrix.magnitude.count)
        
        let epsilon: Float = 1e-4
        for i in 0..<cpuMatrix.magnitude.count {
            XCTAssertEqual(cpuMatrix.magnitude[i], gpuMatrix.magnitude[i], accuracy: epsilon, "Magnitude mismatch at index \(i)")
            XCTAssertEqual(cpuMatrix.phase[i], gpuMatrix.phase[i], accuracy: epsilon, "Phase mismatch at index \(i)")
        }
        
        print("✅ [M4 SEALED] Mathematical Parity Confirmed (Epsilon: \(epsilon))")
    }
    
    /// Verifies that the hardware acceleration status is correctly reported.
    func testM4SiliconExecutionLock() {
        let metal = MetalEngine()
        let engine = STFTEngine(metalEngine: metal)
        
        if metal.getHardwareStatus() != "None (Metal No Supported)" {
            XCTAssertTrue(engine.isHardwareAccelerated, "❌ STFTEngine failed to report hardware acceleration status correctly.")
        }
    }
    
    // MARK: - Helpers
    
    private func generateFrequencySweep(startFreq: Float, endFreq: Float, duration: Double, sr: Double) -> [Float] {
        let n = Int(sr * duration)
        var samples = [Float](repeating: 0, count: n)
        for i in 0..<n {
            let t = Float(i) / Float(sr)
            let freq = startFreq + (endFreq - startFreq) * (t / Float(duration))
            samples[i] = 0.5 * sinf(2.0 * .pi * freq * t)
        }
        return samples
    }
}
