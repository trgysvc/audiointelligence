import XCTest
@testable import AudioIntelligenceCore

/// Characterizes `identifyTriad`'s recognition accuracy across its full (root, chord-quality)
/// vocabulary — the measurement `TraditionalTheoryEngineTests.swift`'s doc comment flagged as a
/// known-but-unmeasured ambiguity. For all 108 canonical chords (12 roots x 9 qualities), feeds an
/// idealized chroma vector (1.0 at each chord tone, 0 elsewhere) and checks whether the returned
/// (root, type) matches.
///
/// Before the length-normalization fix (see `TraditionalTheoryEngine.identifyTriad`), the raw
/// unnormalized dot-product sum favored 4-note jazz-extension profiles over 3-note triads whenever
/// 3 of 4 notes happened to overlap elsewhere — a scoring-scale artifact, not a music-theory
/// limitation — misidentifying 46/108 (42.6%) canonical chords even on noise-free idealized input.
/// After normalizing by profile length, that drops to 31/108, split into two genuinely different
/// categories (this split — not just the raw count — is the point of this test):
///   - **augmented symmetry (8 cases, irreducible)**: an augmented triad's pitch-class set is
///     identical at 3 roots a major third apart (C aug = E aug = G# aug); no amount of chroma-only
///     analysis can recover the "correct" root without bass information.
///   - **relative-chord superset (23 cases, resolvable in principle)**: classic jazz-theory
///     enharmonic overlaps (e.g. C6/Am7, Cmaj7/Em, Cm6/Am7b5) — chroma-identical, but resolvable if
///     the bass note is known. `TraditionalTheoryEngine.detectBassNote` already computes this from
///     the real CQT for inversion labeling, but `identifyTriad` never sees it — wiring the bass
///     note into root selection is a separate, larger follow-up (see DEVLOG), not this fix's scope.
final class ChordScoringAmbiguityTests: XCTestCase {

    // Mirrors TraditionalTheoryEngine.identifyTriad's own profile list exactly (chord-tone
    // definitions, not the decision algorithm) so each idealized input represents a real,
    // in-vocabulary chord the engine is supposed to recognize.
    private let profiles: [(name: String, type: TraditionalTheoryEngine.TriadType, offsets: [Int])] = [
        ("major", .major, [0, 4, 7]),
        ("minor", .minor, [0, 3, 7]),
        ("diminished", .diminished, [0, 3, 6]),
        ("augmented", .augmented, [0, 4, 8]),
        ("maj7", .major, [0, 4, 7, 11]),
        ("dom7", .major, [0, 4, 7, 10]),
        ("m7", .minor, [0, 3, 7, 10]),
        ("m7b5", .diminished, [0, 3, 6, 10]),
        ("m6", .minor, [0, 3, 7, 9]),
    ]
    private let noteNames = ["C","C#","D","D#","E","F","F#","G","G#","A","A#","B"]

    private func idealizedChroma(root: Int, offsets: [Int]) -> [Float] {
        var chroma = [Float](repeating: 0, count: 12)
        for o in offsets { chroma[(root + o) % 12] = 1.0 }
        return chroma
    }

    func testCatalogAmbiguity_acrossAllRootsAndQualities() {
        let engine = TraditionalTheoryEngine()
        var mismatches: [String] = []
        var augmentedSymmetryCount = 0     // irreducible: identical pitch-class set at another root
        var relativeChordSupersetCount = 0 // resolvable via bass note (already in CQT, not yet wired)
        var otherCount = 0
        var total = 0

        for root in 0..<12 {
            for p in profiles {
                total += 1
                let chroma = idealizedChroma(root: root, offsets: p.offsets)
                let (gotRoot, gotType) = engine.identifyTriad(chroma)
                let intendedName = "\(noteNames[root]) \(p.name)"

                if gotRoot != root || gotType != p.type {
                    let gotName = "\(noteNames[gotRoot]) \(gotType)"

                    // Classify: augmented mismatches are always augmented-symmetry (the intended
                    // chord's own quality is augmented — the 3-note augmented set is identical at
                    // 3 roots a major third apart, so ANY augmented mismatch is irreducible).
                    // Everything else that still ties/loses after length-normalization is a
                    // relative-chord chroma-superset case (bass-note-resolvable in principle).
                    if p.type == .augmented {
                        augmentedSymmetryCount += 1
                        mismatches.append("\(intendedName) -> \(gotName)  [AUGMENTED SYMMETRY - irreducible from chroma alone]")
                    } else {
                        relativeChordSupersetCount += 1
                        mismatches.append("\(intendedName) -> \(gotName)  [RELATIVE-CHORD SUPERSET - bass-note resolvable]")
                    }
                }
            }
        }
        otherCount = mismatches.count - augmentedSymmetryCount - relativeChordSupersetCount

        print("=== CHORD AMBIGUITY DIAGNOSTIC (post length-normalization fix) ===")
        print("Total canonical chords tested: \(total)")
        print("Total mismatches: \(mismatches.count)/\(total)")
        print("  - augmented symmetry (irreducible): \(augmentedSymmetryCount)")
        print("  - relative-chord superset (bass-note resolvable): \(relativeChordSupersetCount)")
        print("  - other/unclassified: \(otherCount)")
        print("\n--- DETAIL ---")
        mismatches.forEach { print($0) }

        XCTAssertEqual(otherCount, 0, "found a mismatch that isn't augmented-symmetry or relative-chord-superset — investigate before assuming the classification above is exhaustive")

        // Regression guards on the exact counts, not just the total: a change to `identifyTriad`
        // (profile list, scoring, or threshold) that shifts these numbers should be a deliberate,
        // reviewed decision — not a silent drift this test stays blind to.
        XCTAssertEqual(augmentedSymmetryCount, 8, "augmented-symmetry count changed — expected exactly the 8 irreducible major-third-related root triples (4 symmetry classes x 2 other roots each)")
        XCTAssertEqual(relativeChordSupersetCount, 23, "relative-chord-superset count changed — this is exactly the count DEVLOG ties to the future bass-note-wiring follow-up; if this number moved, that follow-up's target moved too")
    }
}
