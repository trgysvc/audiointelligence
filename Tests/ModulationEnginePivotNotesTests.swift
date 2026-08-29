import XCTest
@testable import AudioIntelligenceCore

/// `ModulationEngine.identifyPivotNotes` returned a hardcoded `["Common Tones"]` string for
/// EVERY modulation event, ignoring both parameters entirely. Fixed to actually compute the
/// diatonic pitch classes shared between the two keys.
final class ModulationEnginePivotNotesTests: XCTestCase {

    func testCMajorToGMajor_sharesSixOfSevenNotes() {
        // C Major: C D E F G A B. G Major: G A B C D E F#. Shared: C D E G A B (6 notes,
        // only F/F# differ) — the textbook "closely related key" pivot-chord case.
        let pivots = ModulationEngine().identifyPivotNotes(from: "C Major", to: "G Major")
        XCTAssertEqual(Set(pivots), Set(["C", "D", "E", "G", "A", "B"]))
    }

    func testCMajorToAMinor_relativeKeys_shareAllSevenNotes() {
        // A Minor is C Major's relative minor — identical key signature, all 7 notes shared.
        let pivots = ModulationEngine().identifyPivotNotes(from: "C Major", to: "A Minor")
        XCTAssertEqual(Set(pivots), Set(["C", "D", "E", "F", "G", "A", "B"]))
    }

    func testDistantKeys_shareFewerNotes() {
        // C Major vs F# Major (the tritone-distant key) shares far fewer diatonic notes than
        // a closely related key pair — a real, meaningful computation should show that.
        let pivots = ModulationEngine().identifyPivotNotes(from: "C Major", to: "F# Major")
        XCTAssertLessThan(pivots.count, 6, "a distant key change should share noticeably fewer pivot notes than a closely related one")
    }

    func testUnclassifiedKey_returnsEmpty() {
        XCTAssertEqual(ModulationEngine().identifyPivotNotes(from: "Unclassified", to: "C Major"), [])
    }
}

/// `TonalMetrics.keySignature` was hardcoded to a wrong-shaped `[0.1]` single-element
/// placeholder on every analysis, despite its own doc comment describing a "12 semitone key
/// weights" profile. `ModulationEngine.keyCorrelationProfile` reuses the engine's own,
/// already-tested Krumhansl-Kessler correlation matching (the same math `identifyKey` performs
/// internally) and exposes the full 12-root profile instead of collapsing it to one winner.
final class ModulationEngineKeyCorrelationProfileTests: XCTestCase {

    private static let asMajor: [Float] = [6.35, 2.23, 3.48, 2.33, 4.38, 4.09, 2.52, 5.19, 2.39, 3.66, 2.29, 2.88]

    /// A chroma vector that IS the (unrotated) major-key profile should correlate most
    /// strongly with root 0 (C) — the profile's own maximum should land there.
    func testPureCMajorChroma_peaksAtRootZero() {
        let profile = ModulationEngine().keyCorrelationProfile(Self.asMajor)
        XCTAssertEqual(profile.count, 12)
        let peakRoot = profile.enumerated().max(by: { $0.element < $1.element })?.offset
        XCTAssertEqual(peakRoot, 0, "a pure C-major-shaped chroma should correlate strongest with root 0")
    }

    /// Malformed input (not a 12-element chroma vector) must not crash — returns a neutral,
    /// correctly-shaped all-zero profile instead.
    func testMalformedInput_returnsZeroProfile() {
        let profile = ModulationEngine().keyCorrelationProfile([1, 2, 3])
        XCTAssertEqual(profile, [Float](repeating: 0, count: 12))
    }
}
