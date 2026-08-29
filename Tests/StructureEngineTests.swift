import XCTest
@testable import AudioIntelligenceCore

/// `StructureEngine.analyze`'s only existing coverage (`DSPGroundTruthTests.
/// testRecurrenceMatrixSymmetry`) checks that the self-similarity matrix is symmetric — it never
/// exercises boundary detection or section labeling at all. A real human-annotated structure
/// dataset (SALAMI) isn't available in this project (its audio isn't a single archive — see
/// `~/Desktop/AudioIntelligence_Yapilacaklar.md`), so true segmentation *accuracy* against
/// ground truth remains an open item. This adds the ground-truth check that IS available without
/// external data: a synthetic track built from two objectively distinct, alternating sections
/// (different chroma AND different timbre/MFCC) with known transition points — a correct
/// segmentation engine must place boundaries near those known transitions, not scattered
/// arbitrarily or missing entirely.
final class StructureEngineTests: XCTestCase {

    private let hopLength = 512
    private let sampleRate = 22050.0

    /// Builds a synthetic chromagram/MFCC pair: pattern A for `[0, transition)`, pattern B for
    /// `[transition, 2*transition)`, pattern A again for `[2*transition, 3*transition)` — two
    /// genuinely different musical "sections" (a maximally distinct chroma root + a very
    /// different timbral MFCC profile) with A repeating verbatim in the third section, plus a
    /// small per-frame jitter so the self-similarity matrix isn't degenerately perfect.
    private func syntheticTrack(sectionFrames: Int) -> (chromagram: [[Float]], mfcc: [[Float]], transitions: [Int]) {
        let total = sectionFrames * 3
        var chroma = [[Float]](repeating: [Float](repeating: 0, count: total), count: 12)
        var mfcc = [[Float]](repeating: [Float](repeating: 0, count: total), count: 13)

        var rng = SystemRandomNumberGenerator()
        func jitter() -> Float { Float.random(in: -0.02...0.02, using: &rng) }

        for t in 0..<total {
            let inSectionB = (t >= sectionFrames && t < sectionFrames * 2)
            if inSectionB {
                // Pattern B: F#-major-ish chroma (tritone from C, maximally distinct), a very
                // different (much larger) MFCC profile simulating a different timbre.
                for c in [6, 10, 1] { chroma[c][t] = 1.0 + jitter() }
                for m in 0..<13 { mfcc[m][t] = 15.0 + Float(m) + jitter() }
            } else {
                // Pattern A: C-major-ish chroma, a low-magnitude MFCC profile.
                for c in [0, 4, 7] { chroma[c][t] = 1.0 + jitter() }
                for m in 0..<13 { mfcc[m][t] = 1.0 + Float(m) * 0.1 + jitter() }
            }
        }
        return (chroma, mfcc, [sectionFrames, sectionFrames * 2])
    }

    /// Real transitions must be detected within a generous tolerance (well under one section's
    /// width) — not missed entirely, and not just noise scattered anywhere in the track.
    func testAlternatingSections_boundariesDetectedNearKnownTransitions() {
        let sectionFrames = 400 // ~9.3s per section at hop=512/sr=22050 — comfortably over the
                                 // engine's built-in 8s minimum segment spacing.
        let (chroma, mfcc, trueTransitions) = syntheticTrack(sectionFrames: sectionFrames)

        let result = StructureEngine(hopLength: hopLength, sampleRate: sampleRate).analyze(chromagram: chroma, mfccs: mfcc)

        XCTAssertFalse(result.segments.isEmpty, "a track with clear structural changes must produce segments, not none")

        let detectedStarts = result.segments.map { Int(($0.startSec * sampleRate / Double(hopLength)).rounded()) }
        print("🔬 true transitions: \(trueTransitions), detected segment starts: \(detectedStarts)")

        // Every true transition should have SOME detected boundary within a generous window
        // (a fraction of the 400-frame section width) — proves the engine finds real structural
        // change, without demanding frame-perfect peak-picking precision from a heuristic.
        let tolerance = 100 // frames (~2.3s)
        for trueT in trueTransitions {
            let nearest = detectedStarts.min(by: { abs($0 - trueT) < abs($1 - trueT) })
            XCTAssertNotNil(nearest)
            if let nearest {
                XCTAssertLessThan(abs(nearest - trueT), tolerance,
                                   "expected a detected boundary within \(tolerance) frames of the true transition at \(trueT), nearest was \(nearest)")
            }
        }
    }

    /// Segments must cover the whole track in order, with no gaps or overlaps — a basic
    /// structural-integrity property independent of label accuracy.
    func testSegments_coverWholeTrackContiguously() {
        let sectionFrames = 400
        let (chroma, mfcc, _) = syntheticTrack(sectionFrames: sectionFrames)
        let result = StructureEngine(hopLength: hopLength, sampleRate: sampleRate).analyze(chromagram: chroma, mfccs: mfcc)

        guard let firstSegment = result.segments.first else { return XCTFail("expected non-empty segments") }
        XCTAssertEqual(firstSegment.startSec, 0.0, accuracy: 0.001, "the first segment must start at time 0")
        for i in 1..<result.segments.count {
            XCTAssertEqual(result.segments[i].startSec, result.segments[i - 1].endSec, accuracy: 0.001,
                            "segment \(i) must start exactly where segment \(i-1) ended — no gap or overlap")
        }
    }

    /// Too few frames (below the engine's own `nFrames > 10` guard) must return an empty,
    /// well-formed result rather than crash.
    func testTooFewFrames_returnsEmptyGracefully() {
        let chroma = [[Float]](repeating: [Float](repeating: 0, count: 5), count: 12)
        let mfcc = [[Float]](repeating: [Float](repeating: 0, count: 5), count: 13)
        let result = StructureEngine(hopLength: hopLength, sampleRate: sampleRate).analyze(chromagram: chroma, mfccs: mfcc)
        XCTAssertEqual(result.segmentCount, 0)
        XCTAssertTrue(result.segments.isEmpty)
    }
}
