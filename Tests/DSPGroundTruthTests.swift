import XCTest
@testable import AudioIntelligence
@testable import AudioIntelligenceCore

/// Pure-Swift regression tests verified against analytically-derived ground truth (hand-computed
/// wavelet formulas, known sine-tone frequencies, matrix-symmetry invariants) — no Python or
/// librosa dependency at runtime. (Formerly `LibrosaParityTests`; renamed because the name no
/// longer matched what the suite actually checks.)
final class DSPGroundTruthTests: XCTestCase {
    
    // MARK: - Wavelet (DWT) Parity
    
    /// Verifies Haar DWT decomposition against mathematical ground truth.
    /// Input [1, 2, 3, 4] -> Haar Level 1:
    /// approx = [(1+2)/sqrt(2), (3+4)/sqrt(2)] = [2.1213, 4.9497]
    /// detail = [(2-1)/sqrt(2), (4-3)/sqrt(2)] = [0.7071, 0.7071]
    func testHaarWaveletParity() {
        let samples: [Float] = [1.0, 2.0, 3.0, 4.0]
        let engine = WaveletEngine()
        let result = engine.decompose(samples, wavelet: .haar, levels: 1)
        
        XCTAssertEqual(result.coefficients["cA"]![0], 2.1213, accuracy: 0.001)
        XCTAssertEqual(result.coefficients["cA"]![1], 4.9497, accuracy: 0.001)
        XCTAssertEqual(result.coefficients["cD1"]![0], 0.7071, accuracy: 0.001)
        XCTAssertEqual(result.coefficients["cD1"]![1], 0.7071, accuracy: 0.001)
    }

    /// `decompositionStep`'in vDSP_conv çağrısı N+P-1 örnek gerektirirken N örnek geçiriyordu,
    /// dizinin dışından okuyordu (P-1=3 tap db2 için canlı testle doğrulanan denormal/çöp float
    /// bug'ı). Haar'ın kendi testi (P=2, n=4) bunu yakalamıyordu çünkü decimation kazara sadece
    /// bounds-içi çift indeksleri tutuyordu — db2 (P=4) ile decimation SONRASI kullanılan
    /// değerler de etkileniyordu. Determinizm (aynı girdi → aynı çıktı, art arda 2 çalıştırma)
    /// ve sonluluk (NaN/Infinity/aşırı-büyük yok) kontrol ediliyor; ikisi de düzeltmeden önce
    /// heap içeriğine bağlı olarak arızalıydı.
    func testWaveletDb2NoOutOfBoundsCorruption() {
        let samples: [Float] = (0..<64).map { sinf(Float($0) * 0.3) }
        let engine = WaveletEngine()

        let r1 = engine.decompose(samples, wavelet: .db2, levels: 3)
        let r2 = engine.decompose(samples, wavelet: .db2, levels: 3)

        for key in ["cA", "cD1", "cD2", "cD3"] {
            let a = r1.coefficients[key]!
            let b = r2.coefficients[key]!
            XCTAssertEqual(a, b, "\(key): iki ardışık çalıştırma farklı sonuç verdi (non-determinism)")
            for v in a {
                XCTAssertTrue(v.isFinite, "\(key) contains a non-finite value: \(v)")
                XCTAssertLessThan(abs(v), 1000.0, "\(key) contains an implausibly large value: \(v)")
            }
        }
    }

    /// Same regression, but on real audio (EBU SQAM trumpet) instead of a synthetic sine —
    /// WaveletEngine has no in-library consumer to exercise it through the report pipeline,
    /// so this calls it directly on real samples to confirm the fix holds on real material,
    /// not just a hand-picked synthetic signal.
    func testWaveletDb3OnRealAudio_noOutOfBoundsCorruption() async throws {
        let path = "Tests/Resources/SQAM/trpt21_2.wav"
        guard FileManager.default.fileExists(atPath: path) else {
            throw XCTSkip("SQAM trpt21_2.wav not present locally")
        }
        let buffer = try await AudioLoader.load(url: URL(fileURLWithPath: path))
        XCTAssertGreaterThan(buffer.samples.count, 1000, "expected a real, non-trivial sample count")

        let engine = WaveletEngine()
        let result = engine.decompose(buffer.samples, wavelet: .db3, levels: 3)

        for key in ["cA", "cD1", "cD2", "cD3"] {
            let coeffs = result.coefficients[key]!
            XCTAssertFalse(coeffs.isEmpty, "\(key) is empty on real audio")
            for v in coeffs {
                XCTAssertTrue(v.isFinite, "\(key) contains a non-finite value on real audio: \(v)")
            }
        }
        print("🌊 WaveletEngine on real SQAM trumpet: cA=\(result.coefficients["cA"]!.count) samples, all finite")
    }

    // MARK: - Recurrence Matrix (SSM) Parity
    
    /// Verifies that StructureEngine.recurrenceMatrix yields a symmetric 1.0 diagonal.
    func testRecurrenceMatrixSymmetry() {
        let engine = StructureEngine()
        // 3 frames of 2-dimensional features
        let features: [[Float]] = [
            [1.0, 0.0, 1.0], // dim 0
            [0.0, 1.0, 1.0]  // dim 1
        ]
        
        let ssm = engine.recurrenceMatrix(features: features)
        
        // Diagonals must be 1.0 (self-similarity)
        XCTAssertEqual(ssm[0][0], 1.0, accuracy: 0.001)
        XCTAssertEqual(ssm[1][1], 1.0, accuracy: 0.001)
        XCTAssertEqual(ssm[2][2], 1.0, accuracy: 0.001)
        
        // Symmetry test
        XCTAssertEqual(ssm[0][1], ssm[1][0], accuracy: 0.0001)
        XCTAssertEqual(ssm[1][2], ssm[2][1], accuracy: 0.0001)
    }
    
    // MARK: - Manipulation (Resampling) Parity
    
    /// Verifies that vDSP-based resampling preserves basic DC offset.
    func testManipulationResampling() async {
        let engine = ManipulationEngine()
        let count = 1000
        let samples = [Float](repeating: 1.0, count: count) // DC Signal
        
        // Pitch shift by 12 steps (effectively 2x frequency)
        let shifted = await engine.pitchShift(samples, steps: 12.0)
        
        // Duration should be preserved
        XCTAssertEqual(shifted.count, count, "Output count mismatch")
        
        // Check signal presence
        let midVal = shifted[count / 2]
        
        // Parity: Magnitude should be preserved (allowing for windowing gain variance)
        XCTAssertGreaterThan(abs(midVal), 0.05, "Signal is missing at midpoint")
        XCTAssertEqual(midVal, 1.0, accuracy: 0.9, "Signal magnitude mismatch") // Broad threshold for now
    }

    // MARK: - CQT Pitch Accuracy (ground truth: pure sine tones)

    /// Feeds a pure sine tone through CQTEngine and returns the bin index with the
    /// highest mean magnitude across frames, plus how many dB it stands above the mean
    /// of all other bins (a proxy for chroma "contrast" — the previous 2-tap-decimation
    /// bug produced a flat, bass-dominated response with near-zero contrast).
    private func dominantBin(frequency: Float, sampleRate: Double, engine: CQTEngine) -> (bin: Int, contrastDB: Float) {
        let duration = 1.0
        let n = Int(sampleRate * duration)
        var samples = [Float](repeating: 0, count: n)
        for i in 0..<n {
            samples[i] = sinf(2.0 * .pi * frequency * Float(i) / Float(sampleRate))
        }

        let result = engine.transform(samples)
        let meanPerBin = result.map { bin -> Float in
            guard !bin.isEmpty else { return 0 }
            return bin.reduce(0, +) / Float(bin.count)
        }

        var bestBin = 0
        var bestVal: Float = -.infinity
        for (i, v) in meanPerBin.enumerated() where v > bestVal {
            bestVal = v
            bestBin = i
        }

        let others = meanPerBin.enumerated().filter { $0.offset != bestBin }.map(\.element)
        let othersMean = others.isEmpty ? 0 : others.reduce(0, +) / Float(others.count)
        let contrastDB = 20 * log10f(max(bestVal, 1e-9) / max(othersMean, 1e-9))
        return (bestBin, contrastDB)
    }

    /// A4 (440 Hz) sits mid-range (octave with 2 decimations) — verifies pitch resolves
    /// to the correct bin with high contrast after the kernel/correlation fixes.
    func testCQTResolvesMidRangeTone() {
        let engine = CQTEngine(nBins: 84, binsPerOctave: 12, fMin: 32.7, sampleRate: 22050, hopLength: 512)
        // bin = 12 * log2(440 / 32.7) ≈ 45
        let (bin, contrastDB) = dominantBin(frequency: 440.0, sampleRate: 22050, engine: engine)
        XCTAssertEqual(bin, 45, accuracy: 1, "A4 (440Hz) should resolve near bin 45")
        XCTAssertGreaterThan(contrastDB, 6.0, "Peak bin should clearly stand out from the noise floor")
    }

    /// A low tone near fMin forces 6 recursive decimations (the deepest octave) — this is
    /// exactly the path the old naive 2-tap filter and missing energy-rescale broke.
    func testCQTResolvesLowOctaveTone() {
        let engine = CQTEngine(nBins: 84, binsPerOctave: 12, fMin: 32.7, sampleRate: 22050, hopLength: 512)
        // bin = 12 * log2(40 / 32.7) ≈ 3
        let (bin, contrastDB) = dominantBin(frequency: 40.0, sampleRate: 22050, engine: engine)
        XCTAssertEqual(bin, 3, accuracy: 1, "40Hz tone (6 decimations deep) should resolve near bin 3")
        XCTAssertGreaterThan(contrastDB, 6.0, "Peak bin should clearly stand out even in the most-decimated octave")
    }
}
