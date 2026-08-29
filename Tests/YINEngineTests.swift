import XCTest
@testable import AudioIntelligenceCore

/// `YINEngine` had zero test coverage anywhere in `Tests/` despite being the library's core
/// time-domain pitch (f0) estimator, feeding `PitchMetrics`, `ViterbiEngine.smoothPitchPath`,
/// and (via `DSPHelpers.hzToMIDI`) `CounterpointEngine`/`MotifEngine`. Ground-truth ported from
/// the same technique already used for `CQTEngine` (`DSPGroundTruthTests`): pure synthetic sine
/// tones at known frequencies, since a correct pitch detector must resolve those exactly.
final class YINEngineTests: XCTestCase {

    private let sr = 22050.0

    private func sineTone(frequency: Float, seconds: Double, amplitude: Float = 0.6) -> [Float] {
        let n = Int(sr * seconds)
        return (0..<n).map { i in amplitude * sinf(2.0 * .pi * frequency * Float(i) / Float(sr)) }
    }

    /// A4 (440Hz), comfortably mid-range — the textbook tuning reference. Tolerance reflects
    /// this implementation's actual measured precision (a consistent small low bias, ~1% /
    /// under a quarter-tone at the default frameLength/hop) rather than an idealized
    /// theoretical accuracy — measured, not assumed.
    func testPureSineTone_A440_detectsCorrectF0() {
        let samples = sineTone(frequency: 440.0, seconds: 1.0)
        let result = YINEngine(sampleRate: sr).analyze(samples: samples)

        XCTAssertFalse(result.voicedFrames.isEmpty, "a clean sustained tone should have voiced frames")
        XCTAssertEqual(result.meanF0, 440.0, accuracy: 5.0, "mean F0 should resolve close to the true 440Hz tone")
        XCTAssertEqual(result.medianF0, 440.0, accuracy: 5.0)

        // Every voiced frame individually should be close, not just the aggregate mean.
        for f0 in result.f0Series where !f0.isNaN {
            XCTAssertEqual(f0, 440.0, accuracy: 5.0, "every voiced frame should track close to the true tone, not just the average")
        }
    }

    /// C1 (32.7Hz) — the engine's own documented `fMin` default. At the DEFAULT `frameLength`
    /// (2048 samples), a 32.7Hz tone completes only ~3 periods per analysis frame — empirically
    /// confirmed too few for this implementation's trough detection (every frame comes back
    /// unvoiced, 0/N). This is a real, measured limitation of the default configuration at the
    /// very bottom of its documented range, not something this test should silently paper over;
    /// a caller analyzing low-pitched material needs a longer `frameLength` (more periods per
    /// frame) — verified here with 4096, which comfortably resolves it.
    func testLowFrequencyTone_C1_detectsCorrectF0_withLongerFrame() {
        let samples = sineTone(frequency: 32.7, seconds: 1.5)
        let result = YINEngine(sampleRate: sr, frameLength: 4096).analyze(samples: samples)

        XCTAssertFalse(result.voicedFrames.isEmpty, "a clean low tone near fMin should have voiced frames with a frame long enough to capture several periods")
        XCTAssertEqual(result.meanF0, 32.7, accuracy: 1.0)
    }

    /// C6 (1046.5Hz) — comfortably below the engine's `fMax` (2093Hz) but high enough to
    /// exercise the short-period end of the lag range (`tauMin`).
    func testHighFrequencyTone_C6_detectsCorrectF0() {
        let samples = sineTone(frequency: 1046.5, seconds: 1.0)
        let result = YINEngine(sampleRate: sr).analyze(samples: samples)

        XCTAssertFalse(result.voicedFrames.isEmpty)
        XCTAssertEqual(result.meanF0, 1046.5, accuracy: 5.0)
    }

    /// Digital silence must be entirely unvoiced (NaN) — the RMS energy gate, not a spurious
    /// near-zero-frequency "pitch."
    func testSilence_isEntirelyUnvoiced() {
        let samples = [Float](repeating: 0, count: Int(sr * 1.0))
        let result = YINEngine(sampleRate: sr).analyze(samples: samples)

        XCTAssertTrue(result.voicedFrames.isEmpty, "digital silence must not report any voiced frames")
        XCTAssertTrue(result.meanF0.isNaN)
        XCTAssertTrue(result.medianF0.isNaN)
        for f0 in result.f0Series {
            XCTAssertTrue(f0.isNaN)
        }
    }

    /// A genuine pitch glide (continuously rising frequency, not a discrete jump) should be
    /// tracked as a smooth, monotonically increasing sequence — not aliased into random octaves.
    func testRisingGlide_isTrackedMonotonically() {
        let seconds = 1.0
        let n = Int(sr * seconds)
        var phase: Float = 0
        var samples = [Float](repeating: 0, count: n)
        for i in 0..<n {
            let freq = 200.0 + 400.0 * Float(i) / Float(n) // 200Hz -> 600Hz linear glide
            phase += 2.0 * .pi * freq / Float(sr)
            samples[i] = 0.6 * sinf(phase)
        }
        let result = YINEngine(sampleRate: sr).analyze(samples: samples)
        let voicedF0 = result.voicedFrames.map { result.f0Series[$0] }
        XCTAssertGreaterThan(voicedF0.count, 5, "a clean glide should produce several voiced frames")

        // Not strictly monotonic frame-to-frame (interpolation noise), but the overall trend
        // must clearly rise: the back half's mean must exceed the front half's.
        let mid = voicedF0.count / 2
        let frontMean = voicedF0[0..<mid].reduce(0, +) / Float(mid)
        let backMean = voicedF0[mid...].reduce(0, +) / Float(voicedF0.count - mid)
        XCTAssertGreaterThan(backMean, frontMean, "a rising glide's second half must read a higher mean F0 than its first half")
    }

    /// Real SQAM trumpet recording: sanity-checks the engine on real, non-synthetic material —
    /// finite output, a plausible fraction of voiced frames, and a mean F0 in a musically
    /// plausible range for a solo brass recording (not NaN throughout, not wildly out of range).
    func testRealAudio_trumpet_producesPlausibleF0() async throws {
        let path = "Tests/Resources/SQAM/trpt21_2.wav"
        guard FileManager.default.fileExists(atPath: path) else {
            throw XCTSkip("SQAM trpt21_2.wav not present locally")
        }
        let buffer = try await AudioLoader.load(url: URL(fileURLWithPath: path), targetSampleRate: sr)
        let result = YINEngine(sampleRate: sr).analyze(samples: buffer.samples)

        XCTAssertFalse(result.voicedFrames.isEmpty, "a real trumpet recording should have some voiced frames")
        XCTAssertTrue(result.meanF0.isFinite)
        // A trumpet's fundamental range is roughly E3 (~165Hz) to a few octaves up; allow a wide
        // but still musically meaningful band rather than the engine's full 32.7-2093Hz range.
        XCTAssertGreaterThan(result.meanF0, 100.0)
        XCTAssertLessThan(result.meanF0, 1500.0)
        print("🔬 YIN on real trumpet: meanF0=\(result.meanF0)Hz, \(result.voicedFrames.count)/\(result.f0Series.count) frames voiced")
    }
}
