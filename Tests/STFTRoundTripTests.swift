import XCTest
@testable import AudioIntelligenceCore

/// `STFTEngine.synthesize()` (ISTFT) had never been round-trip tested — only read for bugs by
/// static inspection. At hop=512 with an nFFT=2048 Hann window (75% overlap), the window
/// satisfies the COLA (constant overlap-add) condition, so analyze() -> synthesize() should
/// reconstruct the original signal to near machine precision, not just "plausibly."
final class STFTRoundTripTests: XCTestCase {
    private let sr = 22050.0

    private func multiTone(n: Int) -> [Float] {
        let freqs = [440.0, 1320.0, 3010.0]
        var s = [Float](repeating: 0, count: n)
        for i in 0..<n {
            let t = Double(i) / sr
            var v = 0.0
            for f in freqs { v += 0.2 * sin(2.0 * Double.pi * f * t) }
            s[i] = Float(v)
        }
        return s
    }

    func testAnalyzeSynthesize_roundTrip_realTone_reconstructsCloseToOriginal() async {
        let n = Int(2.0 * sr)
        let original = multiTone(n: n)

        let engine = STFTEngine(nFFT: 2048, hopLength: 512, sampleRate: sr)
        let stft = await engine.analyze(original, center: true)
        let reconstructed = engine.synthesize(stft, length: n)

        XCTAssertEqual(reconstructed.count, original.count, "cropped-to-length reconstruction should match the original sample count exactly")

        // Edge frames (within one nFFT of the start/end) carry more windowing-edge error even
        // under COLA, since analyze()'s own hop-frame coverage doesn't fully overlap there.
        // Measure error only in the well-covered interior.
        let edge = 2048
        guard reconstructed.count > 2 * edge else {
            XCTFail("signal too short for this test's edge margin")
            return
        }
        var errSumSq: Double = 0
        var origSumSq: Double = 0
        for i in edge..<(reconstructed.count - edge) {
            let d = Double(reconstructed[i] - original[i])
            errSumSq += d * d
            origSumSq += Double(original[i]) * Double(original[i])
        }
        let relError = (origSumSq > 0) ? (errSumSq / origSumSq).squareRoot() : Double.nan
        print("🔬 ISTFT round-trip interior relative RMS error: \(relError * 100)%")
        XCTAssertLessThan(relError, 0.01, "interior reconstruction should match the original to well under 1% relative RMS error under COLA (Hann, 75% overlap)")
    }

    func testAnalyzeSynthesize_roundTrip_silence_staysNearZero() async {
        let n = Int(1.0 * sr)
        let original = [Float](repeating: 0, count: n)

        let engine = STFTEngine(nFFT: 2048, hopLength: 512, sampleRate: sr)
        let stft = await engine.analyze(original, center: true)
        let reconstructed = engine.synthesize(stft, length: n)

        XCTAssertEqual(reconstructed.count, n)
        let maxAbs = reconstructed.map { abs($0) }.max() ?? 0
        XCTAssertLessThan(maxAbs, 1e-4, "digital silence should round-trip to (near) silence, not accumulated noise")
    }
}
