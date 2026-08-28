import XCTest
@testable import AudioIntelligenceCore

final class MeterEngineTests: XCTestCase {

    /// `bestG == 2` fell into the `default:` branch and was mislabeled "Complex" — 2/4 is a
    /// simple meter, not a complex/irregular one.
    func test2_4Meter_classifiedAsSimple() async {
        // Every stride-4 sample is trivially a SUBSET of every stride-2 sample (beat 4k is
        // always also beat 2·2k), so a naive "strong on all even beats" pattern ties g=2 and
        // g=4 exactly, and the tie-break is undefined. Alternate the two even-beat phases
        // (≡0 mod 4 weaker, ≡2 mod 4 stronger) so g=2's average genuinely exceeds g=4's,
        // unambiguously exercising the "which grouping wins" logic instead of a coin flip.
        let sr = 22050.0
        let beatInterval = 0.5 // seconds
        let beatTimes = (0..<40).map { Double($0) * beatInterval }
        var onset = [Float](repeating: 0.05, count: 2000)
        for (i, t) in beatTimes.enumerated() {
            let frame = Int(t * sr / 512.0)
            guard frame < onset.count else { continue }
            switch i % 4 {
            case 0: onset[frame] = 0.6
            case 2: onset[frame] = 1.0
            default: onset[frame] = 0.1
            }
        }

        let result = await MeterEngine().detectMeter(beatTimes: beatTimes, onsetStrength: onset, sr: sr)
        XCTAssertEqual(result.timeSignature, "2/4")
        XCTAssertEqual(result.meterType, "Simple", "2/4 must classify as Simple, not fall through to Complex")
    }

    /// Ground truth: an onset envelope built from two combined periodic pulse trains at a 3:2
    /// ratio (primary period 40 frames, secondary ~26.7 frames) — the classic "3 against 2"
    /// cross-rhythm. Must be detected, not silently return nil (the old hardcoded placeholder).
    func testGenuine3Against2Polyrhythm_isDetected() {
        let primaryPeriod = 40
        let secondaryPeriod = 27 // ≈ 40 * 2/3
        var onsets = [Float](repeating: 0, count: 2000)
        var p = 0
        while p < onsets.count { onsets[p] = 1.0; p += primaryPeriod }
        var s = 0
        while s < onsets.count { onsets[s] = max(onsets[s], 0.8); s += secondaryPeriod }

        let ratio = MeterEngine().detectPolyrhythm(onsets, primaryPeriodFrames: Double(primaryPeriod))
        print("🔬 detected polyrhythm ratio: \(ratio ?? "nil")")
        XCTAssertEqual(ratio, "3:2")
    }

    /// A clean single-pulse signal (no secondary periodicity) must NOT report a spurious
    /// polyrhythm.
    func testSinglePulse_noFalsePolyrhythm() {
        let primaryPeriod = 40
        var onsets = [Float](repeating: 0.02, count: 2000) // low noise floor, no secondary pulse
        var p = 0
        while p < onsets.count { onsets[p] = 1.0; p += primaryPeriod }

        let ratio = MeterEngine().detectPolyrhythm(onsets, primaryPeriodFrames: Double(primaryPeriod))
        XCTAssertNil(ratio, "a single clean pulse train must not report a spurious polyrhythm")
    }
}
