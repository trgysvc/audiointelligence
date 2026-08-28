import XCTest
@testable import AudioIntelligenceCore

/// `ReductionEngine.reduce` used to hardcode `512.0 / 44100.0` for converting chroma-frame
/// count to a real-world duration, regardless of the file's actual sample rate — any non-44.1kHz
/// file (48kHz is extremely common) computed the wrong `totalDuration`, which fed directly into
/// `sRatio`/`eRatio` and therefore mapped every segment's start/end time to the wrong chroma
/// frames. Fixed by taking `sampleRate` (and `hopLength`) as parameters instead of hardcoding.
final class ReductionEngineTests: XCTestCase {

    /// Builds a chromagram where the first half of frames has all energy on pitch class 0 (C)
    /// and the second half on pitch class 7 (G) — a hard, unambiguous split — then asks for the
    /// tonic of a segment covering only real-world seconds 0-1 out of a longer file. At 48kHz
    /// (not 44.1kHz), the correct frame boundary for "1 second" differs from what the old
    /// hardcoded 44100 constant would have computed, so this only passes if the real sample
    /// rate is actually used.
    func testNonstandardSampleRate_mapsSegmentTimeToCorrectFrames() async {
        let sr = 48000.0
        let hop = 512
        // 4 seconds of chroma frames at 48kHz/512 hop.
        let totalFrames = Int(4.0 * sr / Double(hop))
        let halfway = totalFrames / 2

        var chromagram = [[Float]](repeating: [Float](repeating: 0, count: totalFrames), count: 12)
        for f in 0..<totalFrames {
            let pitchClass = f < halfway ? 0 : 7 // C for first half, G for second half
            chromagram[pitchClass][f] = 1.0
        }

        // Segment covering real-world seconds [0, 1] — well within the first (C) half, since
        // the full file is 4 seconds and the split is at 2 seconds.
        let earlySegment = MusicSegment(id: 0, start: 0.0, end: 1.0, label: "test")

        let result = await ReductionEngine().reduce(chromagram: chromagram, segments: [earlySegment], sampleRate: sr, hopLength: hop)

        XCTAssertEqual(result.structuralPillars.first, "C",
                        "segment [0,1]s at 48kHz must map to the C-dominant early frames, not be thrown off by an incorrect (44.1kHz-assumed) duration")
    }

    /// Same construction at 44100Hz (the value that used to be hardcoded) — must still work,
    /// confirming this isn't a regression for the previously-"working" sample rate.
    func test44100SampleRate_stillMapsCorrectly() async {
        let sr = 44100.0
        let hop = 512
        let totalFrames = Int(4.0 * sr / Double(hop))
        let halfway = totalFrames / 2

        var chromagram = [[Float]](repeating: [Float](repeating: 0, count: totalFrames), count: 12)
        for f in 0..<totalFrames {
            let pitchClass = f < halfway ? 0 : 7
            chromagram[pitchClass][f] = 1.0
        }

        let lateSegment = MusicSegment(id: 0, start: 3.0, end: 4.0, label: "test")
        let result = await ReductionEngine().reduce(chromagram: chromagram, segments: [lateSegment], sampleRate: sr, hopLength: hop)

        XCTAssertEqual(result.structuralPillars.first, "G", "segment [3,4]s must map to the G-dominant late frames at 44.1kHz")
    }
}
