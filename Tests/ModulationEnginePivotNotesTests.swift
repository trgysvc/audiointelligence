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
