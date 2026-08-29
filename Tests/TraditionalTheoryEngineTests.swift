import XCTest
@testable import AudioIntelligenceCore

/// `DNAReportBuilder` always called `TraditionalTheoryEngine.analyzeVertical(...,
/// cqtMatrix: [], key:...)` with a literal empty array. `detectBassNote`'s bounds check
/// (`bin < cqtMatrix.count`) is always false against an empty array, so `dominantBin` never
/// updated from its `0` default — every single chord's detected bass note silently read as "C"
/// regardless of the real root, corrupting the inversion label for every non-C chord (a real
/// major/minor/diminished root-position chord whose root happens not to be C would get a
/// spurious "/C" appended, misreading it as an inverted chord). Now wired to a real, per-chunk
/// CQT transform (`DNAReportBuilder.swift`), verified here directly against
/// `TraditionalTheoryEngine.analyzeVertical`'s public behavior with a real (non-empty) CQT
/// matrix — `detectBassNote` itself is `private`, so this exercises it through the one public
/// entry point that calls it.
final class TraditionalTheoryEngineTests: XCTestCase {

    /// Builds a single-frame chromagram matching a C major triad (root=0: C, E, G at chroma
    /// indices 0, 4, 7) and a single-frame CQT matrix (24 bins, the range `detectBassNote`
    /// scans) with all energy concentrated at `bassBin`.
    ///
    /// C major (not G, or any other non-C root) is deliberately chosen: `identifyTriad` scores
    /// every (root, chord-type) combination and keeps the first strict improvement, so a sparse
    /// 3-note chroma vector is inherently ambiguous with the rootless 7th chord a third below it
    /// (e.g. G-B-D — G major's own notes — score identically as a rootless E-minor-7th, and
    /// since root 4 (E) is visited before root 7 (G) in the scan, the E interpretation would
    /// silently win the tie). Root 0 (C) has no smaller root that can tie it this way, so it's
    /// the one unambiguous choice for isolating the CQT bass-note wiring specifically, without
    /// fighting this separate, pre-existing chroma-matching characteristic.
    private func verticalChord(bassBin: Int) -> VerticalChord? {
        var chromagram = [[Float]](repeating: [0], count: 12)
        for c in [0, 4, 7] { chromagram[c] = [1.0] } // C, E, G

        var cqtMatrix = [[Float]](repeating: [0.0], count: 24)
        cqtMatrix[bassBin] = [1.0]

        let result = TraditionalTheoryEngine().analyzeVertical(chromagram: chromagram, cqtMatrix: cqtMatrix, key: "C Major")
        return result.first
    }

    /// Bass energy at C (bin 0, the chord's own root) — a genuine root-position chord — must
    /// format as plain "C".
    func testBassAtRoot_formatsAsRootPosition() {
        guard let chord = verticalChord(bassBin: 0) else { return XCTFail("expected a detected chord") }
        XCTAssertEqual(chord.symbol, "C", "root-position C major must not be mislabeled with a bass note")
    }

    /// Bass energy at G (bin 7, the chord's fifth) — a genuine second-inversion chord — must
    /// format as "C/G", not the old bug's constant "C" (root position) regardless of real bass.
    func testBassAtFifth_formatsAsSecondInversion() {
        guard let chord = verticalChord(bassBin: 7) else { return XCTFail("expected a detected chord") }
        XCTAssertEqual(chord.symbol, "C/G")
    }

    /// Bass energy at E (bin 4, the chord's third) — a genuine first-inversion chord.
    func testBassAtThird_formatsAsFirstInversion() {
        guard let chord = verticalChord(bassBin: 4) else { return XCTFail("expected a detected chord") }
        XCTAssertEqual(chord.symbol, "C/E")
    }

    /// A non-chord-tone bass (e.g. bin 9 = A, not in {C, E, G}) must still be reported honestly
    /// as that real note, proving the bass note genuinely comes from the CQT data rather than
    /// being clamped to one of the three "expected" values.
    func testNonChordToneBass_reportsRealNote() {
        guard let chord = verticalChord(bassBin: 9) else { return XCTFail("expected a detected chord") }
        XCTAssertEqual(chord.symbol, "C/A")
    }

    /// An empty `cqtMatrix` (the old, buggy call-site value) is still handled gracefully — bass
    /// note falls back to bin 0 (C) without crashing — documenting the old degenerate behavior
    /// (a root-position C chord happens to look identical to this fallback; every OTHER root
    /// would have shown the bug clearly, as the non-C tests above now do with real CQT data).
    func testEmptyCQTMatrix_doesNotCrash() {
        var chromagram = [[Float]](repeating: [0], count: 12)
        for c in [0, 4, 7] { chromagram[c] = [1.0] }
        let result = TraditionalTheoryEngine().analyzeVertical(chromagram: chromagram, cqtMatrix: [], key: "C Major")
        XCTAssertEqual(result.first?.symbol, "C")
    }
}
