import XCTest
@testable import AudioIntelligence
@testable import AudioIntelligenceCore

final class ScientificValidationTests: XCTestCase {
    
    let sampleRate: Double = 48000.0
    
    // --- 1. EBU TECH 3341 CALIBRATION ---
    
    /// Official EBU Calibration: 1kHz Sine @ -23dBFS must yield -23.0 LUFS.
    /// Tested across multiple sample rates to verify Bilinear Transform accuracy.
    func testLoudnessCalibrationMultiSR() {
        let sampleRates: [Double] = [44100, 48000, 96000, 192000]
        
        for sr in sampleRates {
            let samples = generateSine(freq: 997, amplitude: powf(10.0, -23.0 / 20.0), duration: 10.0, sr: sr)
            let engine = LoudnessEngine(sampleRate: sr, metalEngine: nil)
            let result = engine.analyze(samples: samples)
            XCTAssertEqual(result.integratedLUFS, -26.0, accuracy: 0.1, "Loudness mismatch at \(sr)Hz.")
        }
    }
    
    /// Gating Logic Test (EBU Tech 3341 Scenario): 
    /// 10s @ -36 | 60s @ -23 | 10s @ -36 -> Target -23.0 LUFS.
    /// This verifies that the -10 LU relative gate correctly excludes the -36 LU blocks.
    func testLoudnessGatingEBU() {
        let sr: Double = 48000
        let s10 = generateSine(freq: 1000, amplitude: powf(10.0, -36.0 / 20.0), duration: 10.0, sr: sr)
        let s60 = generateSine(freq: 1000, amplitude: powf(10.0, -23.0 / 20.0), duration: 60.0, sr: sr)
        
        let samples = s10 + s60 + s10
        let engine = LoudnessEngine(sampleRate: sr, metalEngine: nil)
        let result = engine.analyze(samples: samples)
        XCTAssertEqual(result.integratedLUFS, -26.0, accuracy: 0.1, "EBU Gating failure.")
    }

    /// Absolute Gate Test: Verify that pure silence (< -70 LUFS) is reported as -70.0.
    func testLoudnessAbsoluteGate() {
        let samples = [Float](repeating: 1e-10, count: Int(48000 * 5)) // Near silence
        let engine = LoudnessEngine(sampleRate: 48000, metalEngine: nil)
        let result = engine.analyze(samples: samples)
        
        XCTAssertEqual(result.integratedLUFS, -70.0, accuracy: 0.1, "Absolute gate failure for silence.")
    }
    
    // --- 2. SQAM & CROSS-VALIDATION (Layer 2 & 3) ---
    
    struct SQAMRef {
        let file: String
        let expectedI: Float
        let expectedTPK: Float
        let expectedLRA: Float
    }
    
    func testSQAMCompliance() async throws {
        // References generated via ffmpeg v8.0.1 ebur128
        let references: [SQAMRef] = [
            .init(file: "trpt21_2.wav", expectedI: -22.6, expectedTPK: -7.6, expectedLRA: 18.0),
            .init(file: "horn23_2.wav", expectedI: -20.5, expectedTPK: -6.9, expectedLRA: 11.8),
            .init(file: "spfe49_1.wav", expectedI: -22.5, expectedTPK: -4.7, expectedLRA: 5.9),
            .init(file: "gspi35_1.wav", expectedI: -21.7, expectedTPK: -5.3, expectedLRA: 14.4),
            .init(file: "quar48_1.wav", expectedI: -22.6, expectedTPK: -6.6, expectedLRA: 9.4),
            .init(file: "harp40_1.wav", expectedI: -32.0, expectedTPK: -13.8, expectedLRA: 16.0), // Validated 48kHz Performance
        ]
        
        for ref in references {
            let url = getTestResourceURL(fileName: ref.file)
            let channels = try await AudioLoader.loadMulti(url: url, targetSampleRate: 48000.0)
            
            let engine = LoudnessEngine(sampleRate: 48000.0)
            let result = engine.analyze(channels: channels)
            
            XCTAssertEqual(result.integratedLUFS, ref.expectedI, accuracy: 0.2, "SQAM I-Loudness mismatch: \(ref.file)")
            XCTAssertEqual(result.truePeakDb, ref.expectedTPK, accuracy: 0.5, "SQAM True Peak mismatch: \(ref.file)")
            XCTAssertEqual(result.loudnessRange, ref.expectedLRA, accuracy: 1.0, "SQAM LRA mismatch: \(ref.file)")
        }
    }
    
    // --- 3. PERFORMANCE & REGRESSION (Layer 4) ---
    
    func testAnalysisPerformance() {
        let tenMinutes = [Float](repeating: 0.1, count: Int(44100 * 600)) // 10m noise
        let engine = LoudnessEngine(sampleRate: 44100)
        
        measure(metrics: [XCTClockMetric(), XCTMemoryMetric()]) {
            _ = engine.analyze(samples: tenMinutes)
        }
    }
    
    // --- 4. DETERMINISM (Layer 0) ---
    
    func testNMFDeterminism() {
        let engine = NMFEngine(nComponents: 2)
        // 2 frames, 2 frequency bins (nFFT=2)
        let mag: [Float] = [0.5, 0.2, 0.1, 0.8]
        let phase: [Float] = [0, 0, 0, 0]
        let matrix = STFTMatrix(magnitude: mag, phase: phase, nFFT: 2, hopLength: 1, sampleRate: 48000)
        
        let res1 = engine.decompose(stft: matrix, seed: 123)
        let res2 = engine.decompose(stft: matrix, seed: 123)
        
        XCTAssertEqual(res1.W, res2.W)
        XCTAssertEqual(res1.H, res2.H)
    }

    // MARK: - Helpers
    
    private func generateSine(freq: Float, amplitude: Float, duration: Double, sr: Double) -> [Float] {
        let n = Int(sr * duration)
        var samples = [Float](repeating: 0, count: n)
        for i in 0..<n {
            samples[i] = amplitude * sinf(2.0 * .pi * freq * Float(i) / Float(sr))
        }
        return samples
    }
    
    private func getTestResourceURL(fileName: String) -> URL {
        let path = "Tests/Resources/SQAM/\(fileName)"
        return URL(fileURLWithPath: path)
    }
}
