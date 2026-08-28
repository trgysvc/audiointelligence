import XCTest
@testable import AudioIntelligenceCore

/// `ViterbiEngine.smoothPitchPath` — `ViterbiEngine` itself was never wired into the pipeline
/// (`DNAReportBuilder` always passed `allViterbi: []`, so the public `ViterbiMetrics.path` field
/// was always empty) despite its own doc comment describing exactly this use ("pitch path
/// stabilization"). This wires it up: a Gaussian-emission HMM over a MIDI-note state space +
/// silence state, smoothing a raw per-frame f0 estimate into a stable note path.
final class ViterbiPitchSmoothingTests: XCTestCase {

    private func hzForMIDI(_ midi: Int) -> Float {
        440.0 * powf(2.0, Float(midi - 69) / 12.0)
    }

    /// Ground truth: a steady A4 (MIDI 69) held for 40 frames, with 4 isolated frames corrupted
    /// to a wrong octave (MIDI 81, A5) — the classic YIN octave-jump artifact. The smoothed path
    /// must correct these isolated glitches back to MIDI 69 (or something close), since a single
    /// frame jumping and immediately jumping back is exactly what the transition matrix (which
    /// heavily favors staying near the current pitch) is built to suppress.
    func testIsolatedOctaveGlitches_areSmoothedOut() {
        var f0 = [Float](repeating: hzForMIDI(69), count: 40)
        for glitchFrame in [10, 20, 25, 33] { f0[glitchFrame] = hzForMIDI(81) }

        let smoothed = ViterbiEngine().smoothPitchPath(f0Series: f0)

        XCTAssertEqual(smoothed.count, f0.count)
        var wrongOctaveSurvived = 0
        for i in [10, 20, 25, 33] where smoothed[i] == 81 { wrongOctaveSurvived += 1 }
        print("🔬 glitch frames still at MIDI 81 after smoothing: \(wrongOctaveSurvived)/4")
        XCTAssertLessThanOrEqual(wrongOctaveSurvived, 1, "isolated single-frame octave glitches should mostly be corrected by the smoother")

        // The steady frames (well away from any glitch) must stay correct.
        for i in [0, 5, 15, 38] {
            XCTAssertEqual(smoothed[i], 69, "a clean, steady frame should track the true pitch")
        }
    }

    /// A genuine, sustained pitch CHANGE (not a glitch) must still be tracked, not smoothed away
    /// entirely — otherwise the "smoother" would just flatten every real melodic motion too.
    func testSustainedPitchChange_isTracked() {
        var f0 = [Float](repeating: hzForMIDI(60), count: 30) // C4 held
        for i in 30..<60 { f0.append(hzForMIDI(67)) } // then G4 held (a real interval jump)

        let smoothed = ViterbiEngine().smoothPitchPath(f0Series: f0)

        // Well inside each stable region, the smoother should reflect the real note.
        let earlyAvg = smoothed[5...10].reduce(0, +) / (10 - 5 + 1)
        let lateAvg = smoothed[50...55].reduce(0, +) / (55 - 50 + 1)
        XCTAssertEqual(earlyAvg, 60, accuracy: 1, "should track the first sustained note")
        XCTAssertEqual(lateAvg, 67, accuracy: 1, "should track the second sustained note, not get stuck on the first")
    }

    /// Silent/unvoiced frames (NaN, matching YINEngine's convention) must map to the 0 sentinel.
    func testSilentFrames_mapToZeroSentinel() {
        let f0: [Float] = [Float.nan, Float.nan, Float.nan, Float.nan, Float.nan]
        let smoothed = ViterbiEngine().smoothPitchPath(f0Series: f0)
        XCTAssertEqual(smoothed, [0, 0, 0, 0, 0])
    }

    func testEmptyInput_returnsEmpty() {
        XCTAssertEqual(ViterbiEngine().smoothPitchPath(f0Series: []), [])
    }
}
