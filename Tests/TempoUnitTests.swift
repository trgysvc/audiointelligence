import XCTest
import Foundation
@testable import AudioIntelligenceCore

/// Direct unit test of the tempo estimator — bypasses the full pipeline and the STFT
/// cache so we isolate whether `estimateTempo` itself maps a clean periodic onset
/// envelope to the correct BPM.
final class TempoUnitTests: XCTestCase {

    /// Runs the REAL OnsetEngine on a click track and inspects the envelope it produces,
    /// to see whether onset detection (not estimateTempo) is what drives 258 BPM.
    func testOnsetEngine_clickTrack_envelope() async {
        let sr = 22050
        let samples = SyntheticAudio.clickTrack(bpm: 120, durationSec: 45, sampleRate: sr)
        let onset = await OnsetEngine(sampleRate: Double(sr)).onsetStrength(samples)
        let env = onset.envelope

        let nonZero = env.filter { $0 > 0.01 }.count
        print("📈 onset env frames=\(env.count) nonzero=\(nonZero) mean=\(env.reduce(0,+)/Float(max(1,env.count)))")
        let peakFrames = env.enumerated().filter { $0.element > 0.5 }.map { $0.offset }.prefix(12)
        print("📈 onset peak frames (>0.5): \(Array(peakFrames))")
        if peakFrames.count > 2 {
            let diffs = zip(peakFrames.dropFirst(), peakFrames).map { $0 - $1 }
            print("📈 peak frame spacings: \(diffs)")
        }

        var mean: Float = 0; for v in env { mean += v }; mean /= Float(max(1, env.count))
        let centered = env.map { $0 - mean }
        let acorr = DSPHelpers.autocorrelate(centered, maxSize: env.count)
        let minLag = Int(60.0 * Double(sr) / (512.0 * 240.0))
        let maxLag = Int(60.0 * Double(sr) / (512.0 * 40.0))
        var peaks: [(Int, Float)] = []
        for lag in max(1, minLag)...min(acorr.count - 1, maxLag) { peaks.append((lag, acorr[lag])) }
        print("📈 onset-acorr top peaks (lag, bpm, val):")
        for p in peaks.sorted(by: { $0.1 > $1.1 }).prefix(6) {
            print(String(format: "   lag %2d  bpm %.1f  val %.3f", p.0, 60.0*Double(sr)/(512.0*Double(p.0)), p.1))
        }
        let bpm = RhythmEngine.estimateTempo(onsetStrength: env, sr: Double(sr), hopLength: 512)
        print("🎯 estimateTempo(real click onset) = \(bpm.bpm) BPM")

        // Regression gate for both the SuperFlux and autocorrelate fixes:
        // a clear click train must yield a non-empty envelope and ≈120 BPM.
        XCTAssertGreaterThan(nonZero, 0, "SuperFlux must produce a non-zero onset envelope")
        XCTAssertEqual(Double(bpm.bpm), 120.0, accuracy: 5.0, "Click-track tempo must be ≈120, got \(bpm.bpm)")
    }

    func testEstimateTempo_cleanPeriodicOnset_120bpm() {
        let sr = 22050.0
        let hop = 512
        let bpm = 120.0
        let periodFrames = 60.0 * sr / (Double(hop) * bpm) // ≈ 21.53
        let nFrames = 2000

        var onset = [Float](repeating: 0, count: nFrames)
        var t = 0.0
        while Int(t.rounded()) < nFrames {
            onset[Int(t.rounded())] = 1.0
            t += periodFrames
        }

        // Inspect the raw autocorrelation peak structure (mean-centered, like the engine).
        var mean: Float = 0
        for v in onset { mean += v }; mean /= Float(onset.count)
        let centered = onset.map { $0 - mean }
        let acorr = DSPHelpers.autocorrelate(centered, maxSize: onset.count)
        let minLag = Int(60.0 * sr / (Double(hop) * 240.0))
        let maxLag = Int(60.0 * sr / (Double(hop) * 40.0))
        var peaks: [(lag: Int, val: Float, bpm: Double)] = []
        for lag in max(1, minLag)...min(acorr.count - 1, maxLag) {
            peaks.append((lag, acorr[lag], 60.0 * sr / (Double(hop) * Double(lag))))
        }
        let top = peaks.sorted { $0.val > $1.val }.prefix(8)
        print("📈 spike positions: \(Array(onset.enumerated().filter{$0.element>0}.map{$0.offset}.prefix(8)))")
        print("📈 top acorr peaks (lag, bpm, val):")
        for p in top { print(String(format: "   lag %2d  bpm %.1f  val %.3f", p.lag, p.bpm, p.val)) }

        let result = RhythmEngine.estimateTempo(onsetStrength: onset, sr: sr, hopLength: hop)
        print("🎯 estimateTempo(clean 120bpm onset) = \(result.bpm) BPM (conf \(result.confidence))")
        XCTAssertEqual(Double(result.bpm), 120.0, accuracy: 3.0,
                       "Clean 120 BPM onset train must estimate ≈120, got \(result.bpm)")
    }

    /// At sr=44100/hop=512, `minLag` (the tempo-range floor, ~240 BPM) is ~21 frames. An
    /// onset envelope shorter than that (< ~0.25s of audio) previously crashed:
    /// `vDSP_meanv(base + minLag, ..., vDSP_Length(acorr.count - minLag))` computed a
    /// negative length and `vDSP_Length` (UInt) traps on a negative Int. Must now return a
    /// safe fallback instead of crashing.
    func testEstimateTempo_veryShortOnsetEnvelope_doesNotCrash() {
        for n in [0, 1, 5, 10, 20] {
            let onset = [Float](repeating: 0.5, count: n)
            let result = RhythmEngine.estimateTempo(onsetStrength: onset, sr: 44100, hopLength: 512)
            XCTAssertTrue(result.bpm.isFinite, "n=\(n): bpm must be finite, got \(result.bpm)")
            XCTAssertTrue(result.confidence.isFinite, "n=\(n): confidence must be finite, got \(result.confidence)")
        }
    }
}
