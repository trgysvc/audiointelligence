import XCTest
import Foundation
@testable import AudioIntelligenceCore

/// `detectCodecCutoff` (private, exercised via `ForensicEngine.analyze`) had a real bug: the
/// floor-detection branch never `break`'d, so it kept overwriting the reported cutoff at every
/// subsequent quiet bin scanning down to `searchStartBin` — reporting whichever bin happened to
/// be quiet last, not the actual highest-frequency boundary where content stops. Fixed with a
/// confirm-run (3 consecutive non-floor bins after at least one floor bin) so an isolated
/// spectral dip doesn't get mistaken for the real cutoff, in either direction.
final class ForensicEngineTests: XCTestCase {

    private let sr = 44100.0
    private let nFFT = 2048
    private let hopLength = 512

    private func stftMagnitude(_ samples: [Float]) async -> (magnitude: [Float], nFrames: Int) {
        let stft = await STFTEngine(nFFT: nFFT, hopLength: hopLength, sampleRate: sr).analyze(samples)
        return (stft.magnitude, stft.nFrames)
    }

    /// Ground truth: a signal built ONLY from harmonics below 8kHz, sustained for a full
    /// second, with genuinely zero energy above — the exact scenario `detectCodecCutoff` is
    /// meant to catch. Cutoff should land near 8kHz, not near Nyquist (the old first-match-only
    /// idea) and not at some arbitrary lower bin (the old no-break bug).
    func testHardBandLimitedSignal_reportsCutoffNearTrueLimit() async throws {
        let n = Int(sr * 1.0)
        var samples = [Float](repeating: 0, count: n)
        let freqs: [Double] = [220, 440, 880, 1760, 3520, 7040] // all comfortably below 8kHz
        for i in 0..<n {
            let t = Double(i) / sr
            var v = 0.0
            for f in freqs { v += 0.15 * sin(2.0 * Double.pi * f * t) }
            samples[i] = Float(v)
        }
        let (magnitude, nFrames) = await stftMagnitude(samples)
        let result = ForensicEngine().analyze(samples: samples, magnitude: magnitude, nFrames: nFrames, nFFT: nFFT, sampleRate: sr)

        // True content stops at 7040Hz; the reported cutoff should be well below Nyquist
        // (22050Hz) and in the plausible neighborhood of the real content ceiling — not
        // pinned to Nyquist (under-detection) and not collapsed to some much lower bin from
        // a coincidental dip (the original bug).
        XCTAssertLessThan(result.codecCutoffHz, 15000, "should detect the real high-frequency silence, not report near-Nyquist")
        XCTAssertGreaterThan(result.codecCutoffHz, 5000, "should not collapse to a spuriously low bin")
    }

    /// Ground truth: full-bandwidth white noise has real (if declining) energy all the way to
    /// Nyquist — there is no real "cutoff" to report. Regression check for the naive
    /// break-on-first-floor-match fix, which would have wrongly fired at the very first
    /// near-Nyquist bin on real content that merely dips quietly for a bin or two.
    func testFullBandwidthNoise_reportsNoSpuriousCutoff() async throws {
        let n = Int(sr * 1.0)
        var rng = SystemRandomNumberGenerator()
        let samples: [Float] = (0..<n).map { _ in Float.random(in: -0.3...0.3, using: &rng) }
        let (magnitude, nFrames) = await stftMagnitude(samples)
        let result = ForensicEngine().analyze(samples: samples, magnitude: magnitude, nFrames: nFrames, nFFT: nFFT, sampleRate: sr)

        XCTAssertGreaterThan(result.codecCutoffHz, 18000, "full-bandwidth noise must not report a false cutoff")
    }

    /// Reproduces the ORIGINAL bug precisely. The single-bin "cliff" branch (unchanged by this
    /// fix — it already had its own `break`) already handles a *sharp* brick-wall transition
    /// correctly on its own, so a hard-edged test signal doesn't exercise the floor-branch bug
    /// at all. This signal instead has a *gradual* rolloff into silence around 12kHz (no single
    /// adjacent-bin jump ever exceeds the 10x cliff threshold, forcing the algorithm to rely
    /// solely on the floor condition), PLUS an unrelated narrow spectral notch around 5kHz
    /// (silence between two real audio events — completely normal in music). The pre-fix code
    /// (no `break` on the floor branch) scans past the true ~12kHz boundary, keeps going, hits
    /// the 5kHz notch, and overwrites the reported cutoff down to ~5kHz — very wrong. The fix's
    /// confirm-run must stop at the real ~12kHz boundary and never reach the notch.
    func testNotchInContent_doesNotOverrideRealCutoff() async throws {
        let n = Int(sr * 1.0)
        var samples = [Float](repeating: 0, count: n)
        for i in 0..<n {
            let t = Double(i) / sr
            var v = 0.0
            var f = 200.0
            while f <= 13500 {
                if f < 4800 || f > 5500 { // leave a silent notch at 4800-5500Hz
                    // Gradual taper from 10500Hz to 13500Hz — no single-bin cliff anywhere,
                    // so only the floor condition can find this boundary.
                    let taper = f <= 10500 ? 1.0 : max(0.0, 1.0 - (f - 10500) / 3000.0)
                    v += 0.05 * taper * sin(2.0 * Double.pi * f * t)
                }
                f += 150.0
            }
            samples[i] = Float(v)
        }
        let (magnitude, nFrames) = await stftMagnitude(samples)
        let result = ForensicEngine().analyze(samples: samples, magnitude: magnitude, nFrames: nFrames, nFFT: nFFT, sampleRate: sr)

        print("🔬 notch test: codecCutoffHz=\(result.codecCutoffHz) (true content ceiling ~10500-13500 taper, notch ~5000 must NOT be reported)")
        XCTAssertGreaterThan(result.codecCutoffHz, 9000, "must not collapse to the unrelated ~5kHz notch")
    }

    /// Real, lossless reference audio (EBU SQAM) — sanity check on real material, not just
    /// synthetic signals.
    func testRealSQAMAudio_reportsHighCutoff() async throws {
        let path = "Tests/Resources/SQAM/trpt21_2.wav"
        guard FileManager.default.fileExists(atPath: path) else {
            throw XCTSkip("SQAM trpt21_2.wav not present locally")
        }
        let buffer = try await AudioLoader.load(url: URL(fileURLWithPath: path), targetSampleRate: sr)
        let (magnitude, nFrames) = await stftMagnitude(buffer.samples)
        let result = ForensicEngine().analyze(samples: buffer.samples, magnitude: magnitude, nFrames: nFrames, nFFT: nFFT, sampleRate: sr)

        print("🔬 ForensicEngine on real SQAM trumpet: codecCutoffHz=\(result.codecCutoffHz)")
        XCTAssertGreaterThan(result.codecCutoffHz, 15000, "lossless reference audio should not report a low false-positive cutoff")
    }
}
