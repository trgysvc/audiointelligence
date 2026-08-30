import XCTest
@testable import AudioIntelligenceCore

/// `ManipulationEngine` (time-stretch/pitch-shift) had zero test coverage, and its only output
/// path (`STFTEngine.synthesize`) had a real, severe bug (see `STFTRoundTripTests` / DEVLOG) —
/// meaning this engine's real-world output was silently garbage (~101% relative RMS error, not
/// a recognizable stretched/shifted version of the input) until that fix. This is a direct,
/// real-audio confirmation that the fix actually restores this consumer's output quality.
final class ManipulationEngineTests: XCTestCase {
    private let sr = 44100.0

    private func sineTone(frequency: Float, seconds: Double) -> [Float] {
        let n = Int(sr * seconds)
        return (0..<n).map { i in 0.5 * sinf(2.0 * .pi * frequency * Float(i) / Float(sr)) }
    }

    /// Time-stretch at rate=1.0 (no actual speed change) should still faithfully round-trip a
    /// stationary tone through the phase vocoder + ISTFT — same recognizable pitch, comparable
    /// energy, not silence or noise.
    func testTimeStretch_rateOne_preservesRecognizableTone() async {
        let samples = sineTone(frequency: 440.0, seconds: 1.0)
        let engine = ManipulationEngine(sampleRate: sr)
        let output = await engine.timeStretch(samples, rate: 1.0)

        XCTAssertGreaterThan(output.count, 0)
        let outRMS = sqrtf(output.reduce(0) { $0 + $1 * $1 } / Float(output.count))
        XCTAssertGreaterThan(outRMS, 0.1, "output should have comparable energy to the input, not be near-silent/garbage")

        let pitch = YINEngine(sampleRate: sr).analyze(samples: output)
        XCTAssertFalse(pitch.voicedFrames.isEmpty, "the stretched tone should still be a recognizable pitched signal")
        XCTAssertEqual(pitch.meanF0, 440.0, accuracy: 15.0, "rate=1.0 time-stretch should preserve the original 440Hz pitch")
    }

    /// Time-stretch at rate=2.0 (double speed) should produce roughly half the sample count.
    func testTimeStretch_rateTwo_producesRoughlyHalfLength() async {
        let samples = sineTone(frequency: 440.0, seconds: 1.0)
        let engine = ManipulationEngine(sampleRate: sr)
        let output = await engine.timeStretch(samples, rate: 2.0)

        let expected = samples.count / 2
        let tolerance = Int(sr * 0.05)
        XCTAssertLessThan(abs(output.count - expected), tolerance, "rate=2.0 should roughly halve the sample count")
    }
}
