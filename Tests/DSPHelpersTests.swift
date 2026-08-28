import XCTest
@testable import AudioIntelligenceCore

/// `DSPHelpers.hzToMIDI` — added because `DNAReportBuilder` was passing raw Hz frequencies
/// straight into `fullPitchPath: [Int]`, which `CounterpointEngine`/`MotifEngine` both consume
/// as MIDI note numbers ("leadMidi", counting "semitones" between entries). A 440Hz A4 was read
/// as MIDI note 440 — over 30 octaves above the actual note — making their interval/semitone
/// math on real music meaningless.
final class DSPHelpersTests: XCTestCase {

    func testKnownReferencePitches() {
        XCTAssertEqual(DSPHelpers.hzToMIDI(440.0), 69, "A4 = 440Hz = MIDI 69")
        XCTAssertEqual(DSPHelpers.hzToMIDI(261.63), 60, "C4 (middle C) ≈ MIDI 60")
        XCTAssertEqual(DSPHelpers.hzToMIDI(880.0), 81, "A5 = 880Hz = MIDI 81 (one octave above A4)")
        XCTAssertEqual(DSPHelpers.hzToMIDI(220.0), 57, "A3 = 220Hz = MIDI 57 (one octave below A4)")
    }

    func testSilenceSentinel() {
        XCTAssertEqual(DSPHelpers.hzToMIDI(0.0), 0, "0Hz (PiptrackEngine's silent-frame default) must map to the 0 sentinel, not a real MIDI note")
        XCTAssertEqual(DSPHelpers.hzToMIDI(-5.0), 0, "any non-positive input must map to the sentinel")
    }

    /// Real end-to-end check: a genuine 440Hz tone through the actual STFT -> Piptrack pipeline
    /// (the exact path `DNAReportBuilder` uses) must land on MIDI 69, not raw-Hz ~440.
    func testRealPitchTrackingPipeline_producesMIDIRange() async {
        let sr = 22050.0
        let n = Int(sr * 1.0)
        let samples = (0..<n).map { Float(0.5 * sin(2.0 * Double.pi * 440.0 * Double($0) / sr)) }

        let stft = await STFTEngine(nFFT: 2048, hopLength: 512, sampleRate: sr).analyze(samples)
        let piptrack = PiptrackEngine().track(stft: stft)

        var midiPath: [Int] = []
        for p in piptrack.pitches { midiPath.append(DSPHelpers.hzToMIDI(p)) }

        let voiced = midiPath.filter { $0 != 0 }
        XCTAssertFalse(voiced.isEmpty, "should detect pitch in most frames of a clean 440Hz tone")
        for midi in voiced {
            XCTAssertLessThan(midi, 128, "MIDI note numbers must stay in the valid 0-127 range — the old bug produced values like 440 here")
            XCTAssertEqual(midi, 69, accuracy: 1, "a clean 440Hz tone should track to MIDI 69 (A4)")
        }
    }
}
