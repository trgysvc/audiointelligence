import XCTest
@testable import AudioIntelligenceCore

/// `LoudnessEngine.analyze`'s 6-channel (5.1) energy sum treated every channel with weight 1.0
/// — ITU-R BS.1770-4's own channel-weighting table (§2.4) requires LFE to be excluded entirely
/// (weight 0) and surround channels (Ls/Rs) to be weighted 1.41 (+1.5dB), matching the reference
/// `ffmpeg ebur128` implementation (`libavfilter/f_ebur128.c`) this engine is validated against.
/// Stereo/mono (the only channel counts exercised by the SQAM reference suite) are unaffected —
/// these tests use synthetic 6-channel material since no real 5.1 reference audio is available.
final class LoudnessEngineSurroundTests: XCTestCase {

    private let sr = 48000.0

    private func sine(frequency: Double, amplitude: Float, seconds: Double) -> [Float] {
        let n = Int(sr * seconds)
        return (0..<n).map { i in amplitude * sinf(2.0 * .pi * Float(frequency) * Float(i) / Float(sr)) }
    }

    private func silence(seconds: Double) -> [Float] {
        [Float](repeating: 0, count: Int(sr * seconds))
    }

    /// LFE must be excluded entirely: a 6-channel buffer with a very loud LFE tone must produce
    /// the exact same integrated loudness as the identical buffer with LFE silenced.
    func testLFEChannel_isExcludedFromLoudness() {
        let seconds = 2.0
        let front = sine(frequency: 1000, amplitude: 0.5, seconds: seconds)
        let quietLFE = silence(seconds: seconds)
        let loudLFE = sine(frequency: 60, amplitude: 0.9, seconds: seconds) // very loud sub-bass

        let engine = LoudnessEngine(sampleRate: sr)
        let withoutLFE = engine.analyze(channels: [front, front, front, quietLFE, front, front])
        let withLoudLFE = engine.analyze(channels: [front, front, front, loudLFE, front, front])

        XCTAssertEqual(withoutLFE.integratedLUFS, withLoudLFE.integratedLUFS, accuracy: 0.01,
                        "a loud LFE-channel signal must not change integrated loudness — LFE is excluded from the BS.1770 sum")
    }

    /// Surround channels (Ls/Rs, indices 4/5 in standard 5.1 order) must be weighted 1.41
    /// (+1.5dB per ITU-R BS.1770-4) relative to front channels at weight 1.0.
    func testSurroundChannels_getPlusOneHalfDBWeight() {
        let seconds = 2.0
        let tone = sine(frequency: 1000, amplitude: 0.5, seconds: seconds)
        let silent = silence(seconds: seconds)

        let engine = LoudnessEngine(sampleRate: sr)
        // Identical tone, once placed on a front channel (weight 1.0), once on a surround
        // channel (weight 1.41) — every other channel silent.
        let frontOnly    = engine.analyze(channels: [tone, silent, silent, silent, silent, silent])
        let surroundOnly = engine.analyze(channels: [silent, silent, silent, silent, tone, silent])

        let expectedDeltaDB: Float = 10 * log10f(1.41)
        let measuredDeltaDB = surroundOnly.integratedLUFS - frontOnly.integratedLUFS
        XCTAssertEqual(measuredDeltaDB, expectedDeltaDB, accuracy: 0.05,
                        "an identical tone on a surround channel should read ~+1.5dB louder than on a front channel")
    }

    /// Regression guard: stereo (the common case, and what every existing SQAM/EBU test uses)
    /// must be completely unaffected by the 6-channel-only weighting logic.
    func testStereo_unaffectedByChannelWeighting() {
        let seconds = 2.0
        let tone = sine(frequency: 1000, amplitude: 0.5, seconds: seconds)
        let engine = LoudnessEngine(sampleRate: sr)
        let result = engine.analyze(channels: [tone, tone])
        XCTAssertTrue(result.integratedLUFS.isFinite)
        XCTAssertGreaterThan(result.integratedLUFS, -70.0, "a real tone should not hit the absolute silence floor")
    }
}
