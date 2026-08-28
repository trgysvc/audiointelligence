import XCTest
@testable import AudioIntelligenceCore

/// `HistoricalEngine.inferPeriod`'s first branch was `lufs < -18 && instruments.contains
/// ("Piano") || instruments.contains("Strings")` — Swift binds `&&` tighter than `||`, so this
/// parsed as `(lufs < -18 && Piano) || Strings`, meaning ANY track whose primaryLabel merely
/// contained "Strings" was classified "Romantic/Classical Era" regardless of loudness.
final class HistoricalEngineTests: XCTestCase {

    /// The exact failure case: a loud (modern) track whose instrument label contains "Strings"
    /// (e.g. a synth-strings patch) must NOT be classified as Romantic/Classical — only a
    /// genuinely quiet track with acoustic Piano/Strings should.
    func testLoudStringsTrack_isNotMisclassifiedAsClassical() {
        let result = HistoricalEngine.inferPeriod(
            lufs: -8.0, // loud, modern mastering — nowhere near the -18 LUFS threshold
            bpm: 120,
            instruments: "Strings/Synth",
            entropy: 0.3, // below the 0.8 threshold, so the Digital-Era branch shouldn't fire either
            harmonicStability: 0.5
        )
        XCTAssertNotEqual(result.period, "Romantic / Classical Era",
                           "a loud track must not be misclassified as Classical just for containing \"Strings\"")
    }

    /// The genuine positive case must still work: quiet + Piano/Strings -> Classical.
    func testQuietAcousticTrack_isClassifiedAsClassical() {
        let result = HistoricalEngine.inferPeriod(
            lufs: -22.0, // below -18
            bpm: 90,
            instruments: "Piano/Keyboard",
            entropy: 0.4,
            harmonicStability: 0.5
        )
        XCTAssertEqual(result.period, "Romantic / Classical Era")

        let resultStrings = HistoricalEngine.inferPeriod(
            lufs: -22.0,
            bpm: 90,
            instruments: "Strings/Synth",
            entropy: 0.4,
            harmonicStability: 0.5
        )
        XCTAssertEqual(resultStrings.period, "Romantic / Classical Era", "quiet + Strings should still match, same as quiet + Piano")
    }

    /// A loud track with neither Piano nor Strings, and no other branch matching, should fall
    /// through to the default classification rather than false-triggering the Classical branch.
    func testLoudNonMatchingTrack_fallsThroughToDefault() {
        let result = HistoricalEngine.inferPeriod(
            lufs: -8.0,
            bpm: 100,
            instruments: "Vocals/Chorus",
            entropy: 0.3,
            harmonicStability: 0.5
        )
        XCTAssertEqual(result.period, "Modern/Unclassified")
    }
}
