import XCTest
@testable import AudioIntelligenceCore
@testable import AudioIntelligence

/// Open item 8 (Yapilacaklar madde 8 / DEVLOG Phase 36's closing note): this session caught the
/// SAME class of bug five separate times, by hand, across five different engines — an
/// isolated/validation pipeline silently computing something different from what production's
/// real code path actually does (wrong sample rate, wrong function entirely, wrong mixdown, wrong
/// buffer size). Each was only found because someone happened to compare production's real output
/// against the isolated pipeline's on the same input. This file is the permanent, automatic
/// version of that comparison — cheap enough to run on every `swift test` (short synthetic clips,
/// no real audio files, no GPU-heavy full-track processing), so silent drift doesn't require
/// someone to remember to check.
///
/// Each test below is a MINIATURE of Phase 39's wiring identity check: run the REAL production
/// entry point (`AudioIntelligence().analyze(url:)`, going through `DNAReportBuilder` exactly like
/// a real caller would) and an ISOLATED helper (mirroring what `GoldenDatasetValidationTests` /
/// accuracy-validation code calls) on the literal same synthesized file, and assert they agree.
/// This is output-identity, not accuracy — there is no "correct" BPM/key/f0 being asserted, only
/// that production and the isolated measurement pipeline computed the SAME thing from the SAME
/// input. A disagreement here means the two paths have silently diverged (wrong function, wrong
/// rate, wrong preprocessing) — exactly the failure class Phase 35/36/39 found by hand.
///
/// Tolerances are derived from each metric's own consumer-visible precision, not copied from
/// Phase 39's calibration-confidence bound (0.005) -- that number is specific to a 0..1 value
/// rounded to whole percent and has no meaning for a BPM or a musical key string.
final class ProductionPipelineIdentityTests: XCTestCase {
    private static let sr = 44100 // native-rate synthetic file, matching how real files arrive

    private func writeTempWAV(_ samples: [Float], sampleRate: Int) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("prod-parity-\(UUID().uuidString).wav")
        try SyntheticAudio.writeWAV(to: url, channels: [samples], sampleRate: sampleRate, bitDepth: 16)
        return url
    }

    // MARK: - Tempo

    /// BPM is displayed to whole numbers (`CLIExample`'s `String(format: "%.1f", tempo.value)` is
    /// the most precise consumer -- one decimal place). Half a BPM can never be consumer-visible;
    /// this asserts far tighter than that (2 BPM) because production and isolated should be
    /// running the literal same deterministic algorithm on the literal same samples -- any gap at
    /// all here means a real divergence, not rounding noise.
    func testTempo_productionMatchesIsolatedHelper_onSameSyntheticClip() async throws {
        let bpm = 120.0
        let samples = SyntheticAudio.clickTrack(bpm: bpm, durationSec: 10.0, sampleRate: Self.sr)
        let url = try writeTempWAV(samples, sampleRate: Self.sr)
        defer { try? FileManager.default.removeItem(at: url) }

        let report = try await AudioIntelligence().analyze(url: url)
        let productionBPM = report.estimations.tempo.value

        // Isolated helper: the exact functions `DNAReportBuilder` calls for tempo
        // (`OnsetEngine`'s SuperFlux path, then `RhythmEngine`) -- NOT
        // `RhythmEngine.onsetStrength` (the test-only function Phase 36 found production never
        // calls at all) -- at the file's NATIVE rate, not a hardcoded 22050 (Phase 36's bug).
        let buf = try await AudioLoader.load(url: url, targetSampleRate: Double(Self.sr))
        let onset = await OnsetEngine(sampleRate: Double(Self.sr)).onsetStrength(buf.samples)
        let rhythm = await RhythmEngine(sampleRate: Double(Self.sr)).analyze(onsetResult: onset)
        let isolatedBPM = rhythm.bpm

        XCTAssertEqual(productionBPM, isolatedBPM, accuracy: 2.0,
                        "production tempo (\(productionBPM)) diverged from the isolated OnsetEngine+RhythmEngine pipeline (\(isolatedBPM)) on the same synthetic click track -- one of them is not calling what the other calls")
    }

    // MARK: - Key

    /// `report.estimations.key.value` is mode-qualified (e.g. `"C Major"`) -- no float tolerance,
    /// only exact-string agreement.
    ///
    /// History (DEVLOG Phase 41 & 43 / Yapilacaklar madde 8/9/11): this test's first version
    /// asserted against `ModulationEngine.detectKey`, matching what `GoldenDatasetValidationTests`
    /// itself claimed was production's real key path -- it failed, which is what surfaced that
    /// claim was wrong: production's `key.value` came from a completely different algorithm
    /// (`ReductionEngine.fundamentalNote`, no mode) at the time. That was retracted, both
    /// algorithms were measured side by side on real GiantSteps (Phase 42, tonic-only accuracy
    /// statistically tied but `detectKey`'s free mode signal real and measured), and `key.value`
    /// was rewired to `detectKey` (Phase 43) as the actual fix -- not just a label correction.
    /// This test is that rewiring's closing evidence: it now asserts against `detectKey` again,
    /// and this time passing means the wiring genuinely matches, not that the test is asserting
    /// against the wrong thing a second time.
    func testKey_productionMatchesIsolatedHelper_onSameSyntheticClip() async throws {
        let samples = SyntheticAudio.chord(rootMidi: 60, semitones: [0, 4, 7], durationSec: 10.0, sampleRate: Self.sr)
        let url = try writeTempWAV(samples, sampleRate: Self.sr)
        defer { try? FileManager.default.removeItem(at: url) }

        let report = try await AudioIntelligence().analyze(url: url)
        let productionKey = report.estimations.key.value
        let productionKeyConfidence = report.estimations.key.confidence

        // Isolated helper: the exact functions `DNAReportBuilder` calls for the global key --
        // whole-track STFT(8192)/`ChromaEngine` chroma, mean-pooled, fed to
        // `ModulationEngine.detectKeyWithConfidence` -- at the file's NATIVE rate.
        let buf = try await AudioLoader.load(url: url, targetSampleRate: Double(Self.sr))
        let stftChroma = await STFTEngine(nFFT: 8192, hopLength: 512, sampleRate: Double(Self.sr)).analyze(buf.samples)
        let chroma = ChromaEngine(nFFT: 8192, sampleRate: Double(Self.sr)).chromagram(stft: stftChroma)
        let meanChroma: [Float] = (0..<12).map { c in
            let bin = chroma[c]
            return bin.isEmpty ? 0 : bin.reduce(0, +) / Float(bin.count)
        }
        let (isolatedKey, isolatedConfidence) = ModulationEngine().detectKeyWithConfidence(meanChroma)

        XCTAssertEqual(productionKey, isolatedKey,
                        "production key (\(productionKey)) diverged from the isolated ChromaEngine+ModulationEngine.detectKey pipeline (\(isolatedKey)) on the same synthetic C major clip -- one of them is not calling what the other calls")
        XCTAssertEqual(Double(productionKeyConfidence), Double(isolatedConfidence), accuracy: 0.001,
                        "production key confidence (\(productionKeyConfidence)) diverged from the isolated pipeline's (\(isolatedConfidence)) -- keyConfidence should track detectKey's own correlation strength, not a leftover from a different algorithm")
    }

    // MARK: - Pitch

    /// `PitchMetrics` is displayed to 1 decimal Hz (`MarkdownRenderer`'s `num(..., 1)`). A
    /// sustained pure tone gives pYIN an unambiguous target; 1Hz accuracy is far tighter than
    /// display precision, so any gap here is a real divergence, not rounding.
    ///
    /// History (DEVLOG Phase 44 / Yapilacaklar madde 10): `.medianF0` used to be a second copy of
    /// `.meanF0` (`DNAReportBuilder.swift` passed the same variable into both `PitchMetrics`
    /// parameters) -- this test originally asserted against that actual-but-wrong behavior, doc
    /// comment explaining why. Fixed to compute both statistics from the real raw voiced-frame
    /// pool; this test now asserts BOTH fields independently, each against its own correctly-
    /// computed isolated equivalent -- passing now means the fix is wired end-to-end, not that
    /// the test was loosened to match a bug a second time.
    func testPitch_productionMatchesIsolatedHelper_onSameSyntheticClip() async throws {
        let freq = 440.0
        let samples = SyntheticAudio.sine(freqHz: freq, durationSec: 5.0, sampleRate: Self.sr)
        let url = try writeTempWAV(samples, sampleRate: Self.sr)
        defer { try? FileManager.default.removeItem(at: url) }

        let report = try await AudioIntelligence().analyze(url: url)
        let productionMean = Double(report.estimations.pitch.meanF0)
        let productionMedian = Double(report.estimations.pitch.medianF0)

        // Isolated helper: the exact functions `DNAReportBuilder` calls for pitch
        // (`YINEngine.analyzePYINCandidates` -> `PYINDecoder.decode` -> `PitchResult.from`),
        // at the file's NATIVE rate. This clip is short enough to stay in one production chunk,
        // so `PitchResult.from`'s own per-chunk mean/median already equal the whole-track pool's
        // (no cross-chunk pooling needed to reproduce them here).
        let buf = try await AudioLoader.load(url: url, targetSampleRate: Double(Self.sr))
        let candidates = YINEngine(sampleRate: Double(Self.sr)).analyzePYINCandidates(samples: buf.samples)
        let f0Series = PYINDecoder().decode(candidatesPerFrame: candidates)
        let isolated = PitchResult.from(f0Series: f0Series)
        let isolatedMean = Double(isolated.meanF0)
        let isolatedMedian = Double(isolated.medianF0)

        XCTAssertEqual(productionMean, isolatedMean, accuracy: 1.0,
                        "production mean f0 (\(productionMean)Hz) diverged from the isolated pipeline (\(isolatedMean)Hz)")

        XCTAssertEqual(productionMedian, isolatedMedian, accuracy: 1.0,
                        "production median f0 (\(productionMedian)Hz) diverged from the isolated pipeline (\(isolatedMedian)Hz)")
    }
}
