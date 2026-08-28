import XCTest
@testable import AudioIntelligenceCore

/// `CadenceEngine.identifyInversion` was hardcoded to only recognize a root of "C" — every one
/// of the other 11 possible chord roots fell through to a generic, untranslated-Turkish
/// "Çevrimli Pozisyon (bass Bassa)" label instead of a real inversion classification. Rewritten
/// to parse the actual root/quality/bass from `TraditionalTheoryEngine.formatSymbol`'s real
/// output convention and compute the true inversion for any root/quality.
///
/// Also covers `TraditionalTheoryEngine.determineFunction`'s fallback-format bug: with no
/// parseable key it returned a bare "Tonic" instead of "Tonic (I)", which `CadenceEngine.
/// classify` never matches (it looks for the "(I)"-suffixed form) — every cadence in a passage
/// with an undetected key silently went unclassified.
final class CadenceEngineTests: XCTestCase {

    private func chord(_ symbol: String) -> VerticalChord {
        VerticalChord(frame: 0, symbol: symbol, function: "Tonic (I)", reasoning: "")
    }

    func testRootPosition_noSlash() {
        XCTAssertEqual(CadenceEngine().identifyInversion(chord: chord("C")), "Root Position (5/3)")
        XCTAssertEqual(CadenceEngine().identifyInversion(chord: chord("g")), "Root Position (5/3)")
    }

    func testMajorTriad_firstInversion_everyRoot() {
        // G major, 1st inversion: bass = B (the major 3rd of G).
        XCTAssertEqual(CadenceEngine().identifyInversion(chord: chord("G/B")), "First Inversion (6/3)")
        // D major, 1st inversion: bass = F# (the major 3rd of D) — a non-C root, the exact
        // case the old hardcoded-to-C logic could never handle.
        XCTAssertEqual(CadenceEngine().identifyInversion(chord: chord("D/F#")), "First Inversion (6/3)")
    }

    func testMajorTriad_secondInversion() {
        // G major, 2nd inversion: bass = D (the perfect 5th of G).
        XCTAssertEqual(CadenceEngine().identifyInversion(chord: chord("G/D")), "Second Inversion (6/4)")
    }

    func testMinorTriad_inversions() {
        // a minor (lowercase = minor per formatSymbol): 3rd = C, 5th = E.
        XCTAssertEqual(CadenceEngine().identifyInversion(chord: chord("a/C")), "First Inversion (6/3)")
        XCTAssertEqual(CadenceEngine().identifyInversion(chord: chord("a/E")), "Second Inversion (6/4)")
    }

    func testDiminishedTriad_inversion() {
        // c° (diminished): 3rd = Eb, 5th = Gb (F# enharmonic — this codebase's noteNames only
        // has sharps, so the diminished 5th of C is spelled F# here).
        XCTAssertEqual(CadenceEngine().identifyInversion(chord: chord("c°/D#")), "First Inversion (6/3)")
    }

    func testNonChordToneBass_english_notTurkish() {
        // F is not a chord tone of C major (root, 3rd=E, 5th=G) — must fall through to the
        // generic label, in English, with the actual bass note named.
        let result = CadenceEngine().identifyInversion(chord: chord("C/F"))
        XCTAssertEqual(result, "Inverted Position (F in the bass)")
        XCTAssertFalse(result.contains("Çevrim"), "must not contain leftover Turkish text in a public-facing English report field")
        XCTAssertFalse(result.contains("Bassa"), "must not contain leftover Turkish text in a public-facing English report field")
    }

    /// Direct test of the actual bug: `determineFunction`'s unparseable-key fallback used to
    /// return a bare "Tonic", which `CadenceEngine.classify`'s `.contains("Tonic (I)")` check
    /// never matches.
    func testDetermineFunction_unparseableKey_usesMatchableFormat() {
        let (function, _) = TraditionalTheoryEngine().determineFunction(root: 0, type: .major, key: "Unclassified")
        XCTAssertEqual(function, "Tonic (I)", "the fallback must use the same \"<Name> (<RomanNumeral>)\" format every other branch uses")
    }

    /// End-to-end: with the fallback format fixed, a genuine V-I motion is classified as a
    /// cadence even when the overall key is "Unclassified" (previously always silently dropped).
    func testCadenceClassification_worksWithFallbackTonicFormat() async {
        let prep = VerticalChord(frame: 0, symbol: "G", function: "Dominant (V)", reasoning: "")
        let conc = VerticalChord(frame: 1, symbol: "C", function: "Tonic (I)", reasoning: "")
        let segments = [MusicSegment(id: 0, start: 0.0, end: Double(1 * 512) / 22050.0, label: "test")]

        let cadences = await CadenceEngine().detect(verticalChords: [prep, conc], segments: segments, key: "Unclassified", sr: 22050)
        XCTAssertFalse(cadences.isEmpty, "a genuine V-I motion must still be classified as a cadence even with an unparseable overall key")
        XCTAssertEqual(cadences.first?.type, "Perfect Authentic Cadence (PAC)")
    }
}
