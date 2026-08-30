import XCTest
@testable import AudioIntelligenceCore

/// `PiptrackEngine` had zero test coverage anywhere in `Tests/`.
final class PiptrackEngineTests: XCTestCase {

    /// A pure 440Hz tone should have its per-frame peak land close to 440Hz.
    func testPureSineTone_A440_peaksNear440Hz() async {
        let sr = 22050.0
        let n = Int(sr * 1.0)
        let samples = (0..<n).map { Float(0.6 * sin(2.0 * Double.pi * 440.0 * Double($0) / sr)) }
        let stft = await STFTEngine(nFFT: 2048, hopLength: 512, sampleRate: sr).analyze(samples)
        let result = PiptrackEngine().track(stft: stft)

        let nonZero = result.pitches.filter { $0 > 0 }
        XCTAssertFalse(nonZero.isEmpty, "a clean 440Hz tone should produce non-zero pitch estimates")
        let mean = nonZero.reduce(0, +) / Float(nonZero.count)
        XCTAssertEqual(mean, 440.0, accuracy: 15.0, "mean of the non-zero per-frame peaks should land close to 440Hz")
    }

    /// A very small STFT (few frequency bins, from a tiny nFFT) combined with the default (high)
    /// fMax makes `binMax` clamp to 0 while `binStart` (from fMin) is already ≥1 — an inverted
    /// range. The old code built `max(1, binMin)...binMax` as a `ClosedRange` there, which traps
    /// ("Fatal error: Range requires lowerBound <= upperBound"). Verified as a real, reproducible
    /// crash (not a hypothetical): confirmed this exact call trapped the process before the fix
    /// (via a temporary `git stash` of the fix, re-run, observed the trap, then restored the fix).
    func testVeryFewFrequencyBins_doesNotCrash_onInvertedBinRange() async {
        let nFFT = 2 // -> nFreqs = 2, binMax clamps to 0 while binStart is >= 1
        let sr = 22050.0
        let samples = (0..<200).map { Float(sin(Double($0) * 0.3)) }
        let stft = await STFTEngine(nFFT: nFFT, hopLength: 4, sampleRate: sr).analyze(samples)
        let result = PiptrackEngine(fMin: 65.4, fMax: 2093.0).track(stft: stft)
        XCTAssertEqual(result.pitches.count, stft.nFrames) // reaching this line is the assertion
    }
}
