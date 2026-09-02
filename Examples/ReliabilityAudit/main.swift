// ReliabilityAudit — a single, repeatable pass over every engine that has a real ground-truth
// dataset, producing a dated, versioned "reliability scorecard" instead of scattered ad-hoc
// test runs. Not part of `swift test` — some batteries (GiantSteps tempo, IRMAS, OpenMIC) run
// over hundreds/thousands of real audio files and are genuinely slow; this is a manually-run
// (or CI-release-gated) tool, matching the existing `InfinityAudit`/`SQAMAuditTool` pattern.
//
// Every metric here is either measured against real, independently-sourced ground truth, or
// explicitly reported as `not_available` with the reason — never silently skipped or guessed.
//
// Usage:
//   swift run -c release ReliabilityAudit                # quick pass (small per-task sample)
//   RA_TEMPO_LIMIT=0 RA_IRMAS_PER_CLASS=0 ... swift run -c release ReliabilityAudit
//     (any RA_*_LIMIT=0 means "use the full dataset" for that task)

import Foundation
import Accelerate
import AVFoundation
import AudioIntelligence
import AudioIntelligenceCore
import AudioIntelligenceMetal

// Shared GPU engine — passed to every `HPSSEngine` call below so its 2D median filter (winHarm/
// winPerc=31) offloads to Metal instead of falling back to the CPU path (real spectrograms here
// are always well above the `nFrames*nFreqs > 10000` GPU-dispatch threshold). Reused across
// calls rather than constructed per-file: it holds a persistent device/command queue.
let sharedMetalEngine = MetalEngine()

// MARK: - Report model

struct TaskResult: Codable {
    let name: String
    let status: String // "measured" | "not_available"
    let metric: String?
    let value: Double?
    let sampleCount: Int?
    let dataset: String?
    let note: String?
}

struct ReliabilityReport: Codable {
    let date: String
    var tasks: [TaskResult]
}

// MARK: - Small helpers

func envLimit(_ key: String, default def: Int) -> Int {
    guard let s = ProcessInfo.processInfo.environment[key], let v = Int(s) else { return def }
    return v
}

func isoDate() -> String {
    let f = ISO8601DateFormatter()
    return f.string(from: Date())
}

/// Deterministically thins a collection to at most `limit` elements (0 = no thinning),
/// evenly spaced rather than just the prefix, so a quick run still samples the whole set.
func thinned<T>(_ items: [T], limit: Int) -> [T] {
    guard limit > 0, items.count > limit else { return items }
    let stride = Double(items.count) / Double(limit)
    return (0..<limit).map { items[Int(Double($0) * stride)] }
}

// MARK: - Instrument coarse-class mapping
// InstrumentEngine has 6 coarse classes; source datasets are finer-grained. Mapping follows
// the same "acceptable class list" methodology already used for the SQAM baseline — several
// fine classes have no exact coarse counterpart (no woodwind class exists), so those map to
// the closest plausible coarse neighbor(s), same as an ambiguous SQAM instrument would.

let irmasToCoarse: [String: [String]] = [
    "cel": ["Strings/Synth"],
    "cla": ["Brass/Trumpet", "Strings/Synth"],
    "flu": ["Brass/Trumpet", "Strings/Synth"],
    "gac": ["Strings/Synth"],
    "gel": ["Strings/Synth"],
    "org": ["Piano/Keyboard"],
    "pia": ["Piano/Keyboard"],
    "sax": ["Brass/Trumpet"],
    "tru": ["Brass/Trumpet"],
    "vio": ["Strings/Synth"],
    "voi": ["Vocals/Chorus"],
]

let openmicToCoarse: [String: [String]] = [
    "accordion": ["Piano/Keyboard"],
    "banjo": ["Strings/Synth"],
    "bass": ["Bass (Acoustic/Electric)"],
    "cello": ["Strings/Synth"],
    "clarinet": ["Brass/Trumpet", "Strings/Synth"],
    "cymbals": ["Drums/Percussion"],
    "drums": ["Drums/Percussion"],
    "flute": ["Brass/Trumpet", "Strings/Synth"],
    "guitar": ["Strings/Synth"],
    "mallet_percussion": ["Drums/Percussion", "Piano/Keyboard"],
    "mandolin": ["Strings/Synth"],
    "organ": ["Piano/Keyboard"],
    "piano": ["Piano/Keyboard"],
    "saxophone": ["Brass/Trumpet"],
    "synthesizer": ["Strings/Synth", "Piano/Keyboard"],
    "trombone": ["Brass/Trumpet"],
    "trumpet": ["Brass/Trumpet"],
    "ukulele": ["Strings/Synth"],
    "violin": ["Strings/Synth"],
    "voice": ["Vocals/Chorus"],
]

// MARK: - Shared instrument-prediction helper

/// Isolated-path instrument prediction, full multi-label result (DEVLOG item 2 Stage 2 /
/// Phase 37 needs the whole thresholded `predictions` set, not just the argmax `primaryLabel`
/// `predictInstrument` below returns).
func predictInstrumentFull(samples: [Float], sampleRate: Double) async -> InstrumentMetrics {
    let stftEngine = STFTEngine(nFFT: 2048, hopLength: 512, sampleRate: sampleRate)
    let stft = await stftEngine.analyze(samples)
    let specRaw = SpectralEngine(sampleRate: sampleRate).analyze(stft: stft, samples: samples)
    let spectral = AdvancedSpectralMetrics(
        centroid: specRaw.centroidHz, rolloff: specRaw.rolloffHz, flatness: specRaw.flatness,
        flux: specRaw.flux, skewness: specRaw.skewness, kurtosis: specRaw.kurtosis,
        bandwidth: specRaw.bandwidthHz, zcr: specRaw.zcr, dynamicRange: specRaw.spectralCrestFactor,
        rmsMean: specRaw.rmsMean, rmsMax: specRaw.rmsMax, brightnessDescription: "",
        fullMagnitudes: []
    )
    let mel = MelSpectrogramEngine(stftEngine: stftEngine, nMels: 128)
    let mfccEngine = MFCCEngine(melEngine: mel, nMFCC: 20)
    let mfcc = await mfccEngine.createMFCC(from: samples)
    let lowBand = DSPHelpers.lowBandEnergyRatio(stft: stft, cutoffHz: 250)
    let hpss = HPSSEngine(winHarm: 31, winPerc: 31, metalEngine: sharedMetalEngine).analyze(stft: stft)
    return InstrumentEngine().predict(spectral: spectral, mfcc: Array(mfcc.mfcc.prefix(10)), lowBandEnergyRatio: lowBand, percussiveEnergyRatio: hpss.percussiveEnergyRatio)
}

func predictInstrument(samples: [Float], sampleRate: Double) async -> String {
    await predictInstrumentFull(samples: samples, sampleRate: sampleRate).primaryLabel
}

/// Loads and mono-mixes EXACTLY like `DNAReportBuilder.swift`'s `analyticalChunk` construction
/// (lines ~144-149): stereo loaded with per-channel resample (no downmix inside the converter),
/// THEN an explicit `(L+R)*0.5` average via vDSP. `AudioLoader.load(url:, targetSampleRate:)`
/// (used by `predictInstrumentBreakdown` below) does NOT do this -- it requests a 1-channel
/// output format directly from `AVAudioConverter`, which downmixes stereo->mono INSIDE the
/// conversion using its own (undocumented, not-necessarily-equal-average) algorithm. Found via
/// the wiring identity check failing with small-but-real score differences that crossed isotonic
/// block boundaries -- the earlier CPU-vs-GPU feature-path check was real and correct, but both
/// sides of THAT comparison used `AudioLoader.load`'s converter-mixdown, so it could not have
/// caught this: a genuinely different, previously-unverified divergence source (mono-downmix
/// procedure, not compute backend). This is the loader every calibration fit/validate/identity
/// function below now uses, so the fit matches what production's `analyticalChunk` actually
/// computes, not an approximation of it.
func predictInstrumentBreakdownProductionMix(url: URL, sampleRate: Double) async -> [InstrumentEngine.ScoreBreakdown]? {
    // Uses `loadNextChunkStereoManual` directly (offset 0, frameCount = whole file) -- the EXACT
    // low-level call `DNAReportBuilder` makes per-chunk -- not `AudioLoader.loadStereo`'s
    // whole-file convenience wrapper. The wiring identity check found a residual (max 0.00038,
    // concentrated entirely in the Platt classes -- isotonic's flat blocks absorb tiny
    // differences unless they cross a boundary, Platt's smooth curve can't) even after fixing the
    // mono-mixdown itself; `loadStereo`/`loadMulti` compute the output buffer's frame capacity
    // from `totalFrames` while `loadNextChunkStereoManual` computes it from the just-read chunk
    // buffer's actual `frameLength` -- for a short (~10s) file the two math out to the same
    // number, but the codepaths differ, and this eliminates that difference at the source instead
    // of accepting an unexplained residual.
    guard let file = try? AVAudioFile(forReading: url) else { return nil }
    guard let stereo = try? AudioLoader.loadNextChunkStereoManual(
        file: file, offset: 0, frameCount: AVAudioFrameCount(file.length), targetSampleRate: sampleRate
    ) else { return nil }
    var samples = [Float](repeating: 0, count: stereo.left.count)
    vDSP_vadd(stereo.left, 1, stereo.right, 1, &samples, 1, vDSP_Length(samples.count))
    var halfScale: Float = 0.5
    vDSP_vsmul(samples, 1, &halfScale, &samples, 1, vDSP_Length(samples.count))
    return await predictInstrumentBreakdown(samples: samples, sampleRate: sampleRate)
}

/// GPU-backend mirror of `predictInstrumentBreakdown`, matching `DNAReportBuilder.swift`'s real
/// `analyticalChunk` branch EXACTLY (same `metalEngine:` passed to STFT/Mel/MFCC/HPSS, same
/// nFFT/hopLength/nMels/nMFCC/winHarm/winPerc/lowBand-cutoff) -- needed because the calibration
/// fit used the CPU-only `predictInstrumentBreakdown`, and production computes every one of these
/// features on GPU. Parameters matching is not the same as VALUES matching (this session's onset-
/// function incident: same sample rate, different function, different numbers) -- this exists to
/// measure that gap directly rather than assume "same params" means "same output."
func predictInstrumentBreakdownGPU(samples: [Float], sampleRate: Double) async -> [InstrumentEngine.ScoreBreakdown] {
    let stftEngine = STFTEngine(nFFT: 2048, hopLength: 512, sampleRate: sampleRate, metalEngine: sharedMetalEngine)
    let stft = await stftEngine.analyze(samples)
    let specRaw = SpectralEngine(sampleRate: sampleRate).analyze(stft: stft, samples: samples)
    let spectral = AdvancedSpectralMetrics(
        centroid: specRaw.centroidHz, rolloff: specRaw.rolloffHz, flatness: specRaw.flatness,
        flux: specRaw.flux, skewness: specRaw.skewness, kurtosis: specRaw.kurtosis,
        bandwidth: specRaw.bandwidthHz, zcr: specRaw.zcr, dynamicRange: specRaw.spectralCrestFactor,
        rmsMean: specRaw.rmsMean, rmsMax: specRaw.rmsMax, brightnessDescription: "",
        fullMagnitudes: []
    )
    let mel = MelSpectrogramEngine(stftEngine: stftEngine, nMels: 128, metalEngine: sharedMetalEngine)
    let mfccEngine = MFCCEngine(melEngine: mel, nMFCC: 20, metalEngine: sharedMetalEngine)
    let mfcc = await mfccEngine.createMFCC(from: samples)
    let lowBand = DSPHelpers.lowBandEnergyRatio(stft: stft, cutoffHz: 250)
    let hpss = HPSSEngine(winHarm: 31, winPerc: 31, metalEngine: sharedMetalEngine).analyze(stft: stft)
    return InstrumentEngine().predictWithBreakdown(spectral: spectral, mfcc: Array(mfcc.mfcc.prefix(10)), lowBandEnergyRatio: lowBand, percussiveEnergyRatio: hpss.percussiveEnergyRatio)
}

/// Isolated-path raw score breakdown, UNthresholded (every profile's score regardless of the
/// 0.3 inclusion cutoff) -- needed for the Phase 37 calibration pre-check, which must see scores
/// that never crossed 0.3 too, not just the ones `predictInstrumentFull` would include.
func predictInstrumentBreakdown(samples: [Float], sampleRate: Double) async -> [InstrumentEngine.ScoreBreakdown] {
    let stftEngine = STFTEngine(nFFT: 2048, hopLength: 512, sampleRate: sampleRate)
    let stft = await stftEngine.analyze(samples)
    let specRaw = SpectralEngine(sampleRate: sampleRate).analyze(stft: stft, samples: samples)
    let spectral = AdvancedSpectralMetrics(
        centroid: specRaw.centroidHz, rolloff: specRaw.rolloffHz, flatness: specRaw.flatness,
        flux: specRaw.flux, skewness: specRaw.skewness, kurtosis: specRaw.kurtosis,
        bandwidth: specRaw.bandwidthHz, zcr: specRaw.zcr, dynamicRange: specRaw.spectralCrestFactor,
        rmsMean: specRaw.rmsMean, rmsMax: specRaw.rmsMax, brightnessDescription: "",
        fullMagnitudes: []
    )
    let mel = MelSpectrogramEngine(stftEngine: stftEngine, nMels: 128)
    let mfccEngine = MFCCEngine(melEngine: mel, nMFCC: 20)
    let mfcc = await mfccEngine.createMFCC(from: samples)
    let lowBand = DSPHelpers.lowBandEnergyRatio(stft: stft, cutoffHz: 250)
    let hpss = HPSSEngine(winHarm: 31, winPerc: 31, metalEngine: sharedMetalEngine).analyze(stft: stft)
    return InstrumentEngine().predictWithBreakdown(spectral: spectral, mfcc: Array(mfcc.mfcc.prefix(10)), lowBandEnergyRatio: lowBand, percussiveEnergyRatio: hpss.percussiveEnergyRatio)
}

/// Cheap discriminator for the production-vs-isolated divergence found by
/// `runInstrumentProductionParityCheck` (DEVLOG Phase 35): identical to `predictInstrument` in
/// every respect EXCEPT that `STFTEngine`/`MelSpectrogramEngine`/`MFCCEngine` are given
/// `sharedMetalEngine` (GPU), matching `DNAReportBuilder.swift`'s real construction, instead of
/// defaulting to CPU. If re-running the same parity sample with ONLY this swapped closes most of
/// the ~45% agreement gap, the divergence is a GPU/CPU numerical difference upstream of the
/// already-verified DCT scale fix (Phase 19); if agreement stays low, the real cause is elsewhere
/// in the wiring (chunking, feature order, HPSS params, etc.) and chasing GPU/CPU would be the
/// wrong layer.
func predictInstrumentGPU(samples: [Float], sampleRate: Double) async -> String {
    let stftEngine = STFTEngine(nFFT: 2048, hopLength: 512, sampleRate: sampleRate, metalEngine: sharedMetalEngine)
    let stft = await stftEngine.analyze(samples)
    let specRaw = SpectralEngine(sampleRate: sampleRate).analyze(stft: stft, samples: samples)
    let spectral = AdvancedSpectralMetrics(
        centroid: specRaw.centroidHz, rolloff: specRaw.rolloffHz, flatness: specRaw.flatness,
        flux: specRaw.flux, skewness: specRaw.skewness, kurtosis: specRaw.kurtosis,
        bandwidth: specRaw.bandwidthHz, zcr: specRaw.zcr, dynamicRange: specRaw.spectralCrestFactor,
        rmsMean: specRaw.rmsMean, rmsMax: specRaw.rmsMax, brightnessDescription: "",
        fullMagnitudes: []
    )
    let mel = MelSpectrogramEngine(stftEngine: stftEngine, nMels: 128, metalEngine: sharedMetalEngine)
    let mfccEngine = MFCCEngine(melEngine: mel, nMFCC: 20, metalEngine: sharedMetalEngine)
    let mfcc = await mfccEngine.createMFCC(from: samples)
    let lowBand = DSPHelpers.lowBandEnergyRatio(stft: stft, cutoffHz: 250)
    let hpss = HPSSEngine(winHarm: 31, winPerc: 31, metalEngine: sharedMetalEngine).analyze(stft: stft)
    let result = InstrumentEngine().predict(spectral: spectral, mfcc: Array(mfcc.mfcc.prefix(10)), lowBandEnergyRatio: lowBand, percussiveEnergyRatio: hpss.percussiveEnergyRatio)
    return result.primaryLabel
}

/// Feature-level diagnostic for the production-vs-isolated divergence (DEVLOG Phase 35): the
/// GPU/CPU discriminator (`predictInstrumentGPU`) came back 100% agreement with isolated-CPU on
/// the same 150-file sample, ruling out compute backend -- so the real difference is somewhere
/// else in the wiring. Dumps the isolated path's exact `InstrumentEngine.predict()` inputs for one
/// file; run with `AI_DEBUG_INSTRUMENT_FEATURES=1` in the same process environment so
/// `DNAReportBuilder.swift`'s matching diagnostic print fires too, giving both sides' numbers in
/// one pass to compare by eye.
func runInstrumentFeatureDump(root: String, key: String) async {
    let base = URL(fileURLWithPath: root).resolvingSymlinksInPath()
    let prefix = String(key.prefix(3))
    let audioURL = base.appendingPathComponent("audio/\(prefix)/\(key).ogg")
    guard let buf = try? await AudioLoader.load(url: audioURL, targetSampleRate: 22050) else {
        print("ERROR: could not load \(audioURL.path)"); return
    }

    let stftEngine = STFTEngine(nFFT: 2048, hopLength: 512, sampleRate: 22050)
    let stft = await stftEngine.analyze(buf.samples)
    let specRaw = SpectralEngine(sampleRate: 22050).analyze(stft: stft, samples: buf.samples)
    let mel = MelSpectrogramEngine(stftEngine: stftEngine, nMels: 128)
    let mfccEngine = MFCCEngine(melEngine: mel, nMFCC: 20)
    let mfcc = await mfccEngine.createMFCC(from: buf.samples)
    let lowBand = DSPHelpers.lowBandEnergyRatio(stft: stft, cutoffHz: 250)
    let hpss = HPSSEngine(winHarm: 31, winPerc: 31, metalEngine: sharedMetalEngine).analyze(stft: stft)

    print("🔬 [ISOLATED-FEATURES] key=\(key) centroid=\(specRaw.centroidHz) flatness=\(specRaw.flatness) lowBand=\(lowBand) percussive=\(hpss.percussiveEnergyRatio) mfcc[0..<5]=\(Array(mfcc.mfcc.prefix(5)))")
    print("   (isolated audio: \(buf.samples.count) samples @ 22050Hz = \(Double(buf.samples.count)/22050.0)s, single-chunk since it's short)")

    print("\nNow running production pipeline on the same file (set AI_DEBUG_INSTRUMENT_FEATURES=1 to see its matching dump)...")
    guard let analysis = try? await AudioIntelligence().analyzeRawAggregate(url: audioURL) else {
        print("ERROR: production pipeline failed on this file"); return
    }
    print("🔬 [PRODUCTION-RESULT] primaryLabel=\(analysis.instruments.primaryLabel) predictions=\(analysis.instruments.predictions.map { "\($0.label)=\($0.confidence)" })")
}

// MARK: - Task 1: Tempo (GiantSteps)

struct GiantStepsManifest: Codable { let files: [GiantStepsEntry] }
struct GiantStepsEntry: Codable { let id: String; let file: String; let key: String; let bpm: Int? }

func tempoAcc(measured: Double, ref: Double) -> (acc1: Bool, acc2: Bool) {
    let acc1 = abs(measured - ref) / ref <= 0.04
    let multiples: [Double] = [1.0 / 3.0, 0.5, 1.0, 2.0, 3.0]
    var acc2 = false
    for m in multiples {
        let target = ref * m
        if target > 0 && abs(measured - target) / target <= 0.04 { acc2 = true; break }
    }
    return (acc1, acc2)
}

func runTempoTask(goldenRoot: String) async -> [TaskResult] {
    let manifestURL = URL(fileURLWithPath: "\(goldenRoot)/manifest.json")
    guard let data = try? Data(contentsOf: manifestURL),
          let manifest = try? JSONDecoder().decode(GiantStepsManifest.self, from: data) else {
        return [TaskResult(name: "tempo", status: "not_available", metric: nil, value: nil,
                            sampleCount: nil, dataset: "GiantSteps",
                            note: "manifest.json not found at \(manifestURL.path)")]
    }
    let withBpm = manifest.files.filter { $0.bpm != nil }
    let limit = envLimit("RA_TEMPO_LIMIT", default: 15)
    let entries = thinned(withBpm, limit: limit)

    var a1c = 0, a2c = 0, n = 0
    for e in entries {
        guard let refBpm = e.bpm else { continue }
        let url = URL(fileURLWithPath: "\(goldenRoot)/\(e.file)")
        guard FileManager.default.fileExists(atPath: url.path),
              let buf = try? await AudioLoader.load(url: url, targetSampleRate: 22050) else { continue }
        let samples = buf.samples.count > 60 * 22050 ? Array(buf.samples.prefix(60 * 22050)) : buf.samples
        let onset = await OnsetEngine(sampleRate: 22050).onsetStrength(samples)
        let bpm = Double(RhythmEngine.estimateTempo(onsetStrength: onset.envelope, sr: 22050, hopLength: 512).bpm)
        let (a1, a2) = tempoAcc(measured: bpm, ref: Double(refBpm))
        if a1 { a1c += 1 }; if a2 { a2c += 1 }; n += 1
    }
    guard n > 0 else {
        return [TaskResult(name: "tempo", status: "not_available", metric: nil, value: nil,
                            sampleCount: 0, dataset: "GiantSteps", note: "no tracks loaded")]
    }
    let d = Double(n)
    return [
        TaskResult(name: "tempo_acc1", status: "measured", metric: "MIREX Acc1 (%)",
                   value: Double(a1c) / d * 100, sampleCount: n, dataset: "GiantSteps (\(withBpm.count) total, 43 have MIREX BPM)", note: nil),
        TaskResult(name: "tempo_acc2", status: "measured", metric: "MIREX Acc2 (%)",
                   value: Double(a2c) / d * 100, sampleCount: n, dataset: "GiantSteps", note: nil),
    ]
}

/// Direction-determining measurement for Tempo (DEVLOG Phase 35 open-items list item 3, the
/// direct follow-up to Instrument's fix): `runTempoTask` always resamples to 22050Hz
/// (`GoldenDatasetValidationTests` does too, the source of the README's Acc1/Acc2 numbers), but
/// `DNAReportBuilder.swift`'s real per-chunk tempo call uses the file's native rate (GiantSteps
/// confirmed natively 44100Hz via `afinfo`) -- the same mismatch shape Instrument had. Unlike
/// Instrument, Tempo is algorithmic (onset-envelope autocorrelation), not a fitted model, so
/// "22050 wins" is NOT assumed here even though it's the tested convention -- measured the same
/// way Instrument's direction was: the identical isolated pipeline, run at both rates, scored
/// against MIREX ground truth.
func runTempoSampleRateComparison(goldenRoot: String) async {
    let manifestURL = URL(fileURLWithPath: "\(goldenRoot)/manifest.json")
    guard let data = try? Data(contentsOf: manifestURL),
          let manifest = try? JSONDecoder().decode(GiantStepsManifest.self, from: data) else {
        print("ERROR: manifest.json not found at \(manifestURL.path)"); return
    }
    let withBpm = manifest.files.filter { $0.bpm != nil }

    func measure(rate: Double) async -> (acc1: Int, acc2: Int, n: Int) {
        var a1c = 0, a2c = 0, n = 0
        for e in withBpm {
            guard let refBpm = e.bpm else { continue }
            let url = URL(fileURLWithPath: "\(goldenRoot)/\(e.file)")
            guard FileManager.default.fileExists(atPath: url.path),
                  let buf = try? await AudioLoader.load(url: url, targetSampleRate: rate) else { continue }
            let cap = Int(60 * rate)
            let samples = buf.samples.count > cap ? Array(buf.samples.prefix(cap)) : buf.samples
            let onset = await OnsetEngine(sampleRate: rate).onsetStrength(samples)
            let bpm = Double(RhythmEngine.estimateTempo(onsetStrength: onset.envelope, sr: rate, hopLength: 512).bpm)
            let (a1, a2) = tempoAcc(measured: bpm, ref: Double(refBpm))
            if a1 { a1c += 1 }; if a2 { a2c += 1 }; n += 1
        }
        return (a1c, a2c, n)
    }

    let at22050 = await measure(rate: 22050)
    let at44100 = await measure(rate: 44100)

    print("\n=== Tempo: which sample rate does the real algorithm perform better at? ===")
    print("GiantSteps, \(withBpm.count) MIREX-BPM-annotated tracks, same isolated pipeline at two rates")
    guard at22050.n > 0 else { print("no tracks evaluated"); return }
    print(String(format: "  @ 22050Hz: Acc1=%d/%d (%.1f%%)  Acc2=%d/%d (%.1f%%)", at22050.acc1, at22050.n, Double(at22050.acc1)/Double(at22050.n)*100, at22050.acc2, at22050.n, Double(at22050.acc2)/Double(at22050.n)*100))
    print(String(format: "  @ 44100Hz: Acc1=%d/%d (%.1f%%)  Acc2=%d/%d (%.1f%%)", at44100.acc1, at44100.n, Double(at44100.acc1)/Double(at44100.n)*100, at44100.acc2, at44100.n, Double(at44100.acc2)/Double(at44100.n)*100))
}

// MARK: - Task 2: Key (GiantSteps)

func parseKey(_ s: String) -> (pc: Int, minor: Bool)? {
    let parts = s.split(separator: " ")
    guard parts.count == 2 else { return nil }
    let names = ["C": 0, "C#": 1, "DB": 1, "D": 2, "D#": 3, "EB": 3, "E": 4, "F": 5,
                 "F#": 6, "GB": 6, "G": 7, "G#": 8, "AB": 8, "A": 9, "A#": 10, "BB": 10, "B": 11]
    guard let pc = names[parts[0].uppercased()] else { return nil }
    return (pc, parts[1].lowercased().hasPrefix("min"))
}

func keyRelation(ref: (pc: Int, minor: Bool), det: (pc: Int, minor: Bool)) -> String {
    if ref.pc == det.pc && ref.minor == det.minor { return "exact" }
    if ref.pc == det.pc && ref.minor != det.minor { return "parallel" }
    let diff = ((det.pc - ref.pc) % 12 + 12) % 12
    if ref.minor == det.minor && (diff == 7 || diff == 5) { return "fifth" }
    if !ref.minor && det.minor && diff == 9 { return "relative" }
    if ref.minor && !det.minor && diff == 3 { return "relative" }
    return "none"
}

func runKeyTask(goldenRoot: String) async -> [TaskResult] {
    let manifestURL = URL(fileURLWithPath: "\(goldenRoot)/manifest.json")
    guard let data = try? Data(contentsOf: manifestURL),
          let manifest = try? JSONDecoder().decode(GiantStepsManifest.self, from: data) else {
        return [TaskResult(name: "key", status: "not_available", metric: nil, value: nil,
                            sampleCount: nil, dataset: "GiantSteps", note: "manifest.json not found")]
    }
    let limit = envLimit("RA_KEY_LIMIT", default: 15)
    let entries = thinned(manifest.files, limit: limit)

    var exact = 0, n = 0
    var mirexSum = 0.0
    func mirexW(_ rel: String) -> Double { rel == "exact" ? 1.0 : (rel == "fifth" ? 0.5 : (rel == "relative" ? 0.3 : (rel == "parallel" ? 0.2 : 0.0))) }

    for e in entries {
        guard let refK = parseKey(e.key) else { continue }
        let url = URL(fileURLWithPath: "\(goldenRoot)/\(e.file)")
        guard FileManager.default.fileExists(atPath: url.path),
              let buf = try? await AudioLoader.load(url: url, targetSampleRate: 22050) else { continue }
        let samples = buf.samples.count > 60 * 22050 ? Array(buf.samples.prefix(60 * 22050)) : buf.samples
        // Key uses the real production chroma path: nFFT=8192 high-resolution STFT (matches
        // DNAReportBuilder.swift ~line 182-183), not the coarser nFFT=2048 STFT used for
        // tempo/onset elsewhere. Using nFFT=2048 here silently measured a code path production
        // doesn't use — full-599 GiantSteps: 37.2%/49.9% (wrong, nFFT=2048) vs 50.9%/63.3%
        // (correct, nFFT=8192, matches production).
        let stft = await STFTEngine(nFFT: 8192, hopLength: 512, sampleRate: 22050).analyze(samples)
        let chroma = ChromaEngine(nFFT: 8192, sampleRate: 22050).chromagram(stft: stft)
        let mean = (0..<12).map { c in chroma[c].isEmpty ? 0 : chroma[c].reduce(0, +) / Float(chroma[c].count) }
        guard let detK = parseKey(ModulationEngine().detectKey(mean)) else { continue }
        let rel = keyRelation(ref: refK, det: detK)
        if rel == "exact" { exact += 1 }
        mirexSum += mirexW(rel)
        n += 1
    }
    guard n > 0 else {
        return [TaskResult(name: "key", status: "not_available", metric: nil, value: nil,
                            sampleCount: 0, dataset: "GiantSteps", note: "no tracks loaded")]
    }
    let d = Double(n)
    return [
        TaskResult(name: "key_exact", status: "measured", metric: "Key exact (%)",
                   value: Double(exact) / d * 100, sampleCount: n, dataset: "GiantSteps (599 MIREX-annotated)", note: nil),
        TaskResult(name: "key_mirex_weighted", status: "measured", metric: "Key MIREX-weighted (%)",
                   value: mirexSum / d * 100, sampleCount: n, dataset: "GiantSteps", note: nil),
    ]
}

/// Direction-determining measurement for Key (DEVLOG Phase 35 open-items list item 3): same
/// question as Tempo's comparison above -- `runKeyTask`/`GoldenDatasetValidationTests` always
/// resample to 22050Hz, production uses native rate (GiantSteps confirmed 44100Hz). Key detection
/// is chroma-correlation, not a fitted model either -- measured, not assumed.
func runKeySampleRateComparison(goldenRoot: String, limit: Int) async {
    let manifestURL = URL(fileURLWithPath: "\(goldenRoot)/manifest.json")
    guard let data = try? Data(contentsOf: manifestURL),
          let manifest = try? JSONDecoder().decode(GiantStepsManifest.self, from: data) else {
        print("ERROR: manifest.json not found at \(manifestURL.path)"); return
    }
    let entries = thinned(manifest.files, limit: limit)
    func mirexW(_ rel: String) -> Double { rel == "exact" ? 1.0 : (rel == "fifth" ? 0.5 : (rel == "relative" ? 0.3 : (rel == "parallel" ? 0.2 : 0.0))) }

    func measure(rate: Double) async -> (exact: Int, mirexSum: Double, n: Int) {
        var exact = 0, n = 0
        var mirexSum = 0.0
        for e in entries {
            guard let refK = parseKey(e.key) else { continue }
            let url = URL(fileURLWithPath: "\(goldenRoot)/\(e.file)")
            guard FileManager.default.fileExists(atPath: url.path),
                  let buf = try? await AudioLoader.load(url: url, targetSampleRate: rate) else { continue }
            let cap = Int(60 * rate)
            let samples = buf.samples.count > cap ? Array(buf.samples.prefix(cap)) : buf.samples
            let stft = await STFTEngine(nFFT: 8192, hopLength: 512, sampleRate: rate).analyze(samples)
            let chroma = ChromaEngine(nFFT: 8192, sampleRate: rate).chromagram(stft: stft)
            let mean = (0..<12).map { c in chroma[c].isEmpty ? 0 : chroma[c].reduce(0, +) / Float(chroma[c].count) }
            guard let detK = parseKey(ModulationEngine().detectKey(mean)) else { continue }
            let rel = keyRelation(ref: refK, det: detK)
            if rel == "exact" { exact += 1 }
            mirexSum += mirexW(rel)
            n += 1
        }
        return (exact, mirexSum, n)
    }

    let at22050 = await measure(rate: 22050)
    let at44100 = await measure(rate: 44100)

    print("\n=== Key: which sample rate does the real algorithm perform better at? ===")
    print("GiantSteps, \(entries.count)-track sample, same isolated pipeline (nFFT=8192) at two rates")
    guard at22050.n > 0 else { print("no tracks evaluated"); return }
    print(String(format: "  @ 22050Hz: exact=%d/%d (%.1f%%)  MIREX-weighted=%.1f%%", at22050.exact, at22050.n, Double(at22050.exact)/Double(at22050.n)*100, at22050.mirexSum/Double(at22050.n)*100))
    print(String(format: "  @ 44100Hz: exact=%d/%d (%.1f%%)  MIREX-weighted=%.1f%%", at44100.exact, at44100.n, Double(at44100.exact)/Double(at44100.n)*100, at44100.mirexSum/Double(at44100.n)*100))
}

// MARK: - Task 3: Instrument (IRMAS)

/// Prints a full confusion matrix (rows = true fine-grained class, columns = predicted coarse
/// label, raw counts) plus per-true-class recall and per-predicted-label precision.
/// `trueClassAcceptable` defines which predicted label(s) count as "correct" for each true row
/// (IRMAS/OpenMIC coarse classes are coarser than the fine-grained ground truth, so some true
/// classes accept more than one predicted column — e.g. IRMAS "cla"/"flu" accept either
/// Brass/Trumpet or Strings/Synth).
func printConfusionMatrix(_ confusion: [String: [String: Int]], trueClassAcceptable: [String: [String]]) {
    let trueClasses = confusion.keys.sorted()
    let predictedLabels = Set(confusion.values.flatMap { $0.keys }).sorted()

    print("\n=== CONFUSION MATRIX (rows = true class, columns = predicted label, raw counts) ===")
    let colWidth = 8
    var header = "true\\pred".padding(toLength: 12, withPad: " ", startingAt: 0)
    for p in predictedLabels {
        header += String(p.prefix(colWidth)).padding(toLength: colWidth, withPad: " ", startingAt: 0)
    }
    print(header)
    for t in trueClasses {
        var row = t.padding(toLength: 12, withPad: " ", startingAt: 0)
        for p in predictedLabels {
            let c = confusion[t]?[p] ?? 0
            row += String(c).padding(toLength: colWidth, withPad: " ", startingAt: 0)
        }
        print(row)
    }

    print("\n=== PER-TRUE-CLASS RECALL (of this true class's audio, % predicted into an acceptable label) ===")
    for t in trueClasses {
        let row = confusion[t] ?? [:]
        let total = row.values.reduce(0, +)
        guard total > 0 else { continue }
        let acceptable = Set(trueClassAcceptable[t] ?? [])
        let hit = row.filter { acceptable.contains($0.key) }.values.reduce(0, +)
        print("  \(t): \(hit)/\(total) (\(Int(Double(hit) / Double(total) * 100))%)")
    }

    print("\n=== PER-PREDICTED-LABEL PRECISION (of everything predicted this label, % truly from an acceptable true class) ===")
    for p in predictedLabels {
        var totalPredicted = 0, truePositive = 0
        for t in trueClasses {
            let c = confusion[t]?[p] ?? 0
            totalPredicted += c
            if (trueClassAcceptable[t] ?? []).contains(p) { truePositive += c }
        }
        guard totalPredicted > 0 else { continue }
        print("  \(p): \(truePositive)/\(totalPredicted) (\(Int(Double(truePositive) / Double(totalPredicted) * 100))%)")
    }
    print("")
}

/// For the first `perClass` MISCLASSIFIED files in each of `codes` (an IRMAS class code),
/// prints the full `InstrumentEngine` score-component breakdown (centroidScore, flatnessScore,
/// timbreScore) for both the winning (wrong) label and every label in the true class's
/// acceptable set — isolates which component actually drove the wrong decision, rather than
/// guessing from aggregate confusion-matrix statistics alone.
func runScoreBreakdownDiagnostic(root: String, codes: [String], perClass: Int) async {
    let base = URL(fileURLWithPath: root).resolvingSymlinksInPath()
    for code in codes {
        guard let acceptable = irmasToCoarse[code] else { continue }
        let dir = base.appendingPathComponent(code)
        guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            .filter({ $0.pathExtension.lowercased() == "wav" }).sorted(by: { $0.path < $1.path }) else { continue }

        print("\n### [\(code)] acceptable=\(acceptable) — first \(perClass) MISCLASSIFIED examples ###")
        var shown = 0
        for f in files {
            if shown >= perClass { break }
            guard let buf = try? await AudioLoader.load(url: f, targetSampleRate: 22050) else { continue }

            let stftEngine = STFTEngine(nFFT: 2048, hopLength: 512, sampleRate: 22050)
            let stft = await stftEngine.analyze(buf.samples)
            let specRaw = SpectralEngine(sampleRate: 22050).analyze(stft: stft, samples: buf.samples)
            let spectral = AdvancedSpectralMetrics(
                centroid: specRaw.centroidHz, rolloff: specRaw.rolloffHz, flatness: specRaw.flatness,
                flux: specRaw.flux, skewness: specRaw.skewness, kurtosis: specRaw.kurtosis,
                bandwidth: specRaw.bandwidthHz, zcr: specRaw.zcr, dynamicRange: specRaw.spectralCrestFactor,
                rmsMean: specRaw.rmsMean, rmsMax: specRaw.rmsMax, brightnessDescription: "", fullMagnitudes: []
            )
            let mel = MelSpectrogramEngine(stftEngine: stftEngine, nMels: 128)
            let mfccEngine = MFCCEngine(melEngine: mel, nMFCC: 20)
            let mfcc = await mfccEngine.createMFCC(from: buf.samples)
            let lowBand = DSPHelpers.lowBandEnergyRatio(stft: stft, cutoffHz: 250)
            let hpss = HPSSEngine(winHarm: 31, winPerc: 31, metalEngine: sharedMetalEngine).analyze(stft: stft)
            let breakdown = InstrumentEngine().predictWithBreakdown(spectral: spectral, mfcc: Array(mfcc.mfcc.prefix(10)), lowBandEnergyRatio: lowBand, percussiveEnergyRatio: hpss.percussiveEnergyRatio)
            let winner = breakdown.max(by: { $0.total < $1.total })!

            guard !acceptable.contains(winner.label) else { continue } // only show genuine misclassifications
            shown += 1

            func fmt(_ label: String, _ b: InstrumentEngine.ScoreBreakdown) -> String {
                let l = label.padding(toLength: 26, withPad: " ", startingAt: 0)
                return "    \(l) centroid=\(String(format: "%.3f", b.centroidScore)) flatness=\(String(format: "%.3f", b.flatnessScore)) lowBand=\(String(format: "%.3f", b.lowBandScore)) percussive=\(String(format: "%.3f", b.percussiveScore)) timbre=\(String(format: "%.3f", b.timbreScore)) total=\(String(format: "%.3f", b.total))"
            }
            print("  \(f.lastPathComponent): centroid=\(Int(spectral.centroid))Hz flatness=\(String(format: "%.3f", spectral.flatness))")
            print(fmt("WINNER (\(winner.label))", winner))
            for accLabel in acceptable {
                if let b = breakdown.first(where: { $0.label == accLabel }) {
                    print(fmt("true[\(code)] (\(b.label))", b))
                }
            }
        }
    }
}

// IRMAS classes whose instrument had a direct, unambiguous OpenMIC training prototype
// (Examples/PrototypeTrainer's `openmicToSingleCoarse`) vs those that didn't (clarinet, flute
// were excluded from training as ambiguous/multi-coarse-class). Used to separate "the model
// never had a prototype for this" from genuine scoring/domain-shift error.
let irmasTrainedClasses: Set<String> = ["cel", "gac", "gel", "org", "pia", "sax", "tru", "vio", "voi"]
let irmasUntrainedClasses: Set<String> = ["cla", "flu"]

/// Two measurements over the full IRMAS set, in one pass:
///   1. Histogram of each file's MINIMUM mfccDistance to any of the 6 trained prototypes —
///      quantifies how often `timbreScore` is genuinely zero-information (distance >= 100)
///      versus contributing real signal, instead of inferring this from a handful of examples.
///   2. Accuracy (recall) split by whether the true class had a direct training prototype
///      (`irmasTrainedClasses`) versus not (`irmasUntrainedClasses`) — separates "the
///      classifier is wrong" from "this class was never represented in training at all."
func runMFCCDistanceDiagnostic(root: String, perClassLimit: Int) async {
    let base = URL(fileURLWithPath: root).resolvingSymlinksInPath()
    guard let classDirs = try? FileManager.default.contentsOfDirectory(at: base, includingPropertiesForKeys: nil) else {
        print("ERROR: \(root) not found"); return
    }

    var minDistances: [Float] = []
    var trainedHit = 0, trainedN = 0
    var untrainedHit = 0, untrainedN = 0

    for dir in classDirs.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
        let code = dir.lastPathComponent
        guard let acceptable = irmasToCoarse[code] else { continue }
        guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            .filter({ $0.pathExtension.lowercased() == "wav" }) else { continue }

        for f in thinned(files.sorted { $0.path < $1.path }, limit: perClassLimit) {
            guard let buf = try? await AudioLoader.load(url: f, targetSampleRate: 22050) else { continue }
            let stftEngine = STFTEngine(nFFT: 2048, hopLength: 512, sampleRate: 22050)
            let stft = await stftEngine.analyze(buf.samples)
            let specRaw = SpectralEngine(sampleRate: 22050).analyze(stft: stft, samples: buf.samples)
            let spectral = AdvancedSpectralMetrics(
                centroid: specRaw.centroidHz, rolloff: specRaw.rolloffHz, flatness: specRaw.flatness,
                flux: specRaw.flux, skewness: specRaw.skewness, kurtosis: specRaw.kurtosis,
                bandwidth: specRaw.bandwidthHz, zcr: specRaw.zcr, dynamicRange: specRaw.spectralCrestFactor,
                rmsMean: specRaw.rmsMean, rmsMax: specRaw.rmsMax, brightnessDescription: "", fullMagnitudes: []
            )
            let mel = MelSpectrogramEngine(stftEngine: stftEngine, nMels: 128)
            let mfccEngine = MFCCEngine(melEngine: mel, nMFCC: 20)
            let mfcc = await mfccEngine.createMFCC(from: buf.samples)
            let lowBand = DSPHelpers.lowBandEnergyRatio(stft: stft, cutoffHz: 250)
            let hpss = HPSSEngine(winHarm: 31, winPerc: 31, metalEngine: sharedMetalEngine).analyze(stft: stft)
            let breakdown = InstrumentEngine().predictWithBreakdown(spectral: spectral, mfcc: Array(mfcc.mfcc.prefix(10)), lowBandEnergyRatio: lowBand, percussiveEnergyRatio: hpss.percussiveEnergyRatio)

            let minDist = breakdown.map(\.mfccDistance).min() ?? .infinity
            minDistances.append(minDist)

            let winner = breakdown.max(by: { $0.total < $1.total })!
            let isHit = acceptable.contains(winner.label)
            if irmasTrainedClasses.contains(code) {
                trainedN += 1; if isHit { trainedHit += 1 }
            } else if irmasUntrainedClasses.contains(code) {
                untrainedN += 1; if isHit { untrainedHit += 1 }
            }
        }
    }

    guard !minDistances.isEmpty else { print("no files processed"); return }
    let buckets: [(String, (Float) -> Bool)] = [
        ("<50", { $0 < 50 }), ("50-100", { $0 >= 50 && $0 < 100 }),
        ("100-150", { $0 >= 100 && $0 < 150 }), ("150-200", { $0 >= 150 && $0 < 200 }),
        ("200-250", { $0 >= 200 && $0 < 250 }), (">=250", { $0 >= 250 }),
    ]
    let total = minDistances.count
    print("\n=== MIN-MFCC-DISTANCE HISTOGRAM (n=\(total), full IRMAS set, min distance to any of the 6 trained prototypes) ===")
    for (label, pred) in buckets {
        let c = minDistances.filter(pred).count
        print("  \(label.padding(toLength: 8, withPad: " ", startingAt: 0)): \(c) (\(Int(Double(c) / Double(total) * 100))%)")
    }
    let zeroInfoCount = minDistances.filter { $0 >= 100 }.count
    print("  --> timbreScore is EXACTLY zero (min distance >= 100) for \(zeroInfoCount)/\(total) (\(Int(Double(zeroInfoCount) / Double(total) * 100))%) of all files")

    print("\n=== ACCURACY SPLIT: trained-class vs untrained-class true labels ===")
    if trainedN > 0 {
        print("  Trained classes   (\(irmasTrainedClasses.sorted().joined(separator: ","))): \(trainedHit)/\(trainedN) (\(Int(Double(trainedHit) / Double(trainedN) * 100))%)")
    }
    if untrainedN > 0 {
        print("  Untrained classes (\(irmasUntrainedClasses.sorted().joined(separator: ","))): \(untrainedHit)/\(untrainedN) (\(Int(Double(untrainedHit) / Double(untrainedN) * 100))%)")
    }
    print("")
}

// MARK: - Candidate feature discrimination check (Bass/Drums, Phase 16 follow-up)
//
// Measures whether two CANDIDATE features (not yet used anywhere in scoring) actually separate
// their target class from everything else, on real OpenMIC-2018 audio — before writing any
// scoring code. Same unambiguous single-coarse-class OpenMIC labels `PrototypeTrainer` uses for
// training (IRMAS has no true Bass/Drums examples at all, so it can't answer this question).

let openmicToSingleCoarseForDiscrimination: [String: String] = [
    "accordion": "Piano/Keyboard", "banjo": "Strings/Synth", "bass": "Bass (Acoustic/Electric)",
    "cello": "Strings/Synth", "cymbals": "Drums/Percussion", "drums": "Drums/Percussion",
    "guitar": "Strings/Synth", "mandolin": "Strings/Synth", "organ": "Piano/Keyboard",
    "piano": "Piano/Keyboard", "saxophone": "Brass/Trumpet", "trombone": "Brass/Trumpet",
    "trumpet": "Brass/Trumpet", "ukulele": "Strings/Synth", "violin": "Strings/Synth", "voice": "Vocals/Chorus",
]

struct Stats { let mean: Double; let sd: Double; let min: Double; let max: Double; let n: Int }
func stats(_ values: [Double]) -> Stats {
    guard !values.isEmpty else { return Stats(mean: 0, sd: 0, min: 0, max: 0, n: 0) }
    let n = Double(values.count)
    let mean = values.reduce(0, +) / n
    let variance = values.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / n
    return Stats(mean: mean, sd: variance.squareRoot(), min: values.min()!, max: values.max()!, n: values.count)
}

func runFeatureDiscriminationDiagnostic(root: String, perGroupLimit: Int) async {
    let base = URL(fileURLWithPath: root).resolvingSymlinksInPath()
    let csvURL = base.appendingPathComponent("openmic-2018-aggregated-labels.csv")
    let trainURL = base.appendingPathComponent("partitions/split01_train.csv")
    guard let csv = try? String(contentsOf: csvURL, encoding: .utf8),
          let trainList = try? String(contentsOf: trainURL, encoding: .utf8) else {
        print("ERROR: could not read OpenMIC CSVs"); return
    }
    let trainKeys = Set(trainList.split(separator: "\n").map(String.init))
    var positives: [String: Set<String>] = [:]
    for line in csv.split(separator: "\n").dropFirst() {
        let cols = line.split(separator: ",")
        guard cols.count >= 3, let relevance = Double(cols[2]) else { continue }
        if relevance >= 0.5 { positives[String(cols[0]), default: []].insert(String(cols[1])) }
    }

    // key -> single unambiguous coarse label, restricted to train partition (same eligibility
    // PrototypeTrainer used).
    var keyToCoarse: [String: String] = [:]
    for key in trainKeys {
        guard let fine = positives[key] else { continue }
        let mapped = Set(fine.compactMap { openmicToSingleCoarseForDiscrimination[$0] })
        guard mapped.count == 1, let coarse = mapped.first else { continue }
        keyToCoarse[key] = coarse
    }

    func sampleKeys(forCoarse target: String?, limit: Int) -> [String] {
        let matching = keyToCoarse.filter { target == nil ? $0.value != "Bass (Acoustic/Electric)" && $0.value != "Drums/Percussion" : $0.value == target }
        return thinned(matching.keys.sorted(), limit: limit)
    }

    func loadAndMeasure(_ keys: [String]) async -> (lowBand: [Double], onsetDensity: [Double], percussiveRatio: [Double]) {
        var lowBand: [Double] = [], onsetDensity: [Double] = [], percussiveRatio: [Double] = []
        for key in keys {
            let prefix = String(key.prefix(3))
            let audioURL = base.appendingPathComponent("audio/\(prefix)/\(key).ogg")
            guard let buf = try? await AudioLoader.load(url: audioURL, targetSampleRate: 22050) else { continue }
            let stft = await STFTEngine(nFFT: 2048, hopLength: 512, sampleRate: 22050).analyze(buf.samples)
            lowBand.append(Double(DSPHelpers.lowBandEnergyRatio(stft: stft, cutoffHz: 250)))
            let onsets = await OnsetEngine(sampleRate: 22050).onsetStrength(buf.samples)
            let duration = Double(buf.samples.count) / 22050.0
            onsetDensity.append(duration > 0 ? Double(onsets.onsetTimes.count) / duration : 0)
            let hpss = HPSSEngine(winHarm: 31, winPerc: 31, metalEngine: sharedMetalEngine).analyze(stft: stft)
            percussiveRatio.append(Double(hpss.percussiveEnergyRatio))
        }
        return (lowBand, onsetDensity, percussiveRatio)
    }

    func cohenD(_ a: Stats, _ b: Stats) -> Double {
        let pooledSD = ((a.sd * a.sd + b.sd * b.sd) / 2).squareRoot()
        return pooledSD > 0 ? (a.mean - b.mean) / pooledSD : 0
    }

    func pearsonCorrelation(_ x: [Double], _ y: [Double]) -> Double {
        guard x.count == y.count, x.count > 1 else { return 0 }
        let n = Double(x.count)
        let meanX = x.reduce(0, +) / n, meanY = y.reduce(0, +) / n
        var cov = 0.0, varX = 0.0, varY = 0.0
        for i in 0..<x.count {
            let dx = x[i] - meanX, dy = y[i] - meanY
            cov += dx * dy; varX += dx * dx; varY += dy * dy
        }
        let denom = (varX * varY).squareRoot()
        return denom > 0 ? cov / denom : 0
    }

    print("\n=== FEATURE DISCRIMINATION CHECK (OpenMIC train partition, unambiguous single-coarse labels) ===")

    let bassKeys = sampleKeys(forCoarse: "Bass (Acoustic/Electric)", limit: perGroupLimit)
    let nonBassKeys = sampleKeys(forCoarse: nil, limit: perGroupLimit)
    let bassMeasured = await loadAndMeasure(bassKeys)
    let nonBassMeasured = await loadAndMeasure(nonBassKeys)
    let bassStats = stats(bassMeasured.lowBand)
    let nonBassStats = stats(nonBassMeasured.lowBand)
    print("\nLow-band (<250Hz) energy ratio:")
    print(String(format: "  Bass       (n=%d): mean=%.3f sd=%.3f range=[%.3f, %.3f]", bassStats.n, bassStats.mean, bassStats.sd, bassStats.min, bassStats.max))
    print(String(format: "  Non-Bass   (n=%d): mean=%.3f sd=%.3f range=[%.3f, %.3f]", nonBassStats.n, nonBassStats.mean, nonBassStats.sd, nonBassStats.min, nonBassStats.max))
    print(String(format: "  Cohen's d = %.3f", cohenD(bassStats, nonBassStats)))

    let drumsKeys = sampleKeys(forCoarse: "Drums/Percussion", limit: perGroupLimit)
    let nonDrumsKeys = sampleKeys(forCoarse: nil, limit: perGroupLimit)
    let drumsMeasured = await loadAndMeasure(drumsKeys)
    let nonDrumsMeasured = await loadAndMeasure(nonDrumsKeys)
    let drumsOnsetStats = stats(drumsMeasured.onsetDensity)
    let nonDrumsOnsetStats = stats(nonDrumsMeasured.onsetDensity)
    print("\nOnset density (onsets/sec):")
    print(String(format: "  Drums      (n=%d): mean=%.3f sd=%.3f range=[%.3f, %.3f]", drumsOnsetStats.n, drumsOnsetStats.mean, drumsOnsetStats.sd, drumsOnsetStats.min, drumsOnsetStats.max))
    print(String(format: "  Non-Drums  (n=%d): mean=%.3f sd=%.3f range=[%.3f, %.3f]", nonDrumsOnsetStats.n, nonDrumsOnsetStats.mean, nonDrumsOnsetStats.sd, nonDrumsOnsetStats.min, nonDrumsOnsetStats.max))
    print(String(format: "  Cohen's d = %.3f", cohenD(drumsOnsetStats, nonDrumsOnsetStats)))

    let drumsPercStats = stats(drumsMeasured.percussiveRatio)
    let nonDrumsPercStats = stats(nonDrumsMeasured.percussiveRatio)
    print("\nHPSS percussive energy ratio:")
    print(String(format: "  Drums      (n=%d): mean=%.3f sd=%.3f range=[%.3f, %.3f]", drumsPercStats.n, drumsPercStats.mean, drumsPercStats.sd, drumsPercStats.min, drumsPercStats.max))
    print(String(format: "  Non-Drums  (n=%d): mean=%.3f sd=%.3f range=[%.3f, %.3f]", nonDrumsPercStats.n, nonDrumsPercStats.mean, nonDrumsPercStats.sd, nonDrumsPercStats.min, nonDrumsPercStats.max))
    print(String(format: "  Cohen's d = %.3f", cohenD(drumsPercStats, nonDrumsPercStats)))

    let combinedOnset = drumsMeasured.onsetDensity + nonDrumsMeasured.onsetDensity
    let combinedPerc = drumsMeasured.percussiveRatio + nonDrumsMeasured.percussiveRatio
    print(String(format: "\n  Pearson correlation (onset density, HPSS percussive ratio), n=%d combined: r = %.3f", combinedOnset.count, pearsonCorrelation(combinedOnset, combinedPerc)))
    print("")
}

// MARK: - Bass score-breakdown diagnostic (why does Bass stay at 0% precision despite d=1.50?)
//
// For real OpenMIC "bass"-labeled clips (train partition — the same clips whose statistics
// Bass's own Gaussian was fit from, making this the cleanest possible test: if even these don't
// score well under Bass's own fitted profile, the scoring formula itself is implicated, not the
// feature or the data), prints three numbers side by side per file:
//   1. The clip's raw low-band-energy-ratio value.
//   2. Bass profile's low-band Gaussian score for that value, vs. the WINNING profile's low-band
//      score for that same value — is Bass's own score high, or flattened by its own SD?
//   3. Bass's total score vs. the winner's total score, broken into which component the gap
//      comes from.
func runBassScoreBreakdownDiagnostic(root: String, limit: Int) async {
    let base = URL(fileURLWithPath: root).resolvingSymlinksInPath()
    let csvURL = base.appendingPathComponent("openmic-2018-aggregated-labels.csv")
    let trainURL = base.appendingPathComponent("partitions/split01_train.csv")
    guard let csv = try? String(contentsOf: csvURL, encoding: .utf8),
          let trainList = try? String(contentsOf: trainURL, encoding: .utf8) else {
        print("ERROR: could not read OpenMIC CSVs"); return
    }
    let trainKeys = Set(trainList.split(separator: "\n").map(String.init))
    var positives: [String: Set<String>] = [:]
    for line in csv.split(separator: "\n").dropFirst() {
        let cols = line.split(separator: ",")
        guard cols.count >= 3, let relevance = Double(cols[2]) else { continue }
        if relevance >= 0.5 { positives[String(cols[0]), default: []].insert(String(cols[1])) }
    }
    var bassKeys: [String] = []
    for key in trainKeys.sorted() {
        guard let fine = positives[key] else { continue }
        let mapped = Set(fine.compactMap { openmicToSingleCoarseForDiscrimination[$0] })
        if mapped == ["Bass (Acoustic/Electric)"] { bassKeys.append(key) }
    }
    bassKeys = thinned(bassKeys, limit: limit)

    print("\n=== BASS SCORE BREAKDOWN (real OpenMIC 'bass' clips, train partition, n=\(bassKeys.count)) ===")
    for key in bassKeys {
        let prefix = String(key.prefix(3))
        let audioURL = base.appendingPathComponent("audio/\(prefix)/\(key).ogg")
        guard let buf = try? await AudioLoader.load(url: audioURL, targetSampleRate: 22050) else { continue }
        let stftEngine = STFTEngine(nFFT: 2048, hopLength: 512, sampleRate: 22050)
        let stft = await stftEngine.analyze(buf.samples)
        let specRaw = SpectralEngine(sampleRate: 22050).analyze(stft: stft, samples: buf.samples)
        let spectral = AdvancedSpectralMetrics(
            centroid: specRaw.centroidHz, rolloff: specRaw.rolloffHz, flatness: specRaw.flatness,
            flux: specRaw.flux, skewness: specRaw.skewness, kurtosis: specRaw.kurtosis,
            bandwidth: specRaw.bandwidthHz, zcr: specRaw.zcr, dynamicRange: specRaw.spectralCrestFactor,
            rmsMean: specRaw.rmsMean, rmsMax: specRaw.rmsMax, brightnessDescription: "", fullMagnitudes: []
        )
        let mel = MelSpectrogramEngine(stftEngine: stftEngine, nMels: 128)
        let mfccEngine = MFCCEngine(melEngine: mel, nMFCC: 20)
        let mfcc = await mfccEngine.createMFCC(from: buf.samples)
        let lowBand = DSPHelpers.lowBandEnergyRatio(stft: stft, cutoffHz: 250)
        let hpss = HPSSEngine(winHarm: 31, winPerc: 31, metalEngine: sharedMetalEngine).analyze(stft: stft)
        let breakdown = InstrumentEngine().predictWithBreakdown(spectral: spectral, mfcc: Array(mfcc.mfcc.prefix(10)), lowBandEnergyRatio: lowBand, percussiveEnergyRatio: hpss.percussiveEnergyRatio)

        guard let bassEntry = breakdown.first(where: { $0.label == "Bass (Acoustic/Electric)" }) else { continue }
        let winner = breakdown.max(by: { $0.total < $1.total })!

        print("\n  \(key): raw lowBand=\(String(format: "%.3f", lowBand))  raw centroid=\(Int(spectral.centroid))Hz  raw flatness=\(String(format: "%.3f", spectral.flatness))  raw percussive=\(String(format: "%.3f", hpss.percussiveEnergyRatio))")
        print("    Bass    total=\(String(format: "%.3f", bassEntry.total))  centroid=\(String(format: "%.3f", bassEntry.centroidScore)) flatness=\(String(format: "%.3f", bassEntry.flatnessScore)) lowBand=\(String(format: "%.3f", bassEntry.lowBandScore)) percussive=\(String(format: "%.3f", bassEntry.percussiveScore)) timbre=\(String(format: "%.3f", bassEntry.timbreScore))")
        if winner.label != "Bass (Acoustic/Electric)" {
            print("    WINNER(\(winner.label)) total=\(String(format: "%.3f", winner.total))  centroid=\(String(format: "%.3f", winner.centroidScore)) flatness=\(String(format: "%.3f", winner.flatnessScore)) lowBand=\(String(format: "%.3f", winner.lowBandScore)) percussive=\(String(format: "%.3f", winner.percussiveScore)) timbre=\(String(format: "%.3f", winner.timbreScore))")
        } else {
            print("    (Bass won)")
        }
    }
    print("")
}

/// Bass/Drums evaluation on OpenMIC-2018's official HELD-OUT TEST partition (never touched by
/// `PrototypeTrainer` — verified: 0 key overlap and 0 track-ID overlap with the train partition
/// used to fit prototypes). Matching rule (identical to training's own eligibility rule, for
/// consistency): a clip counts only if its ENTIRE set of relevance>=0.5 positive labels maps to
/// a SINGLE coarse class — avoids the undefined "clip is positive for both bass and guitar, is a
/// Bass prediction right or wrong?" ambiguity of OpenMIC's real multi-label data entirely, by
/// only scoring genuinely single-source examples.
///
/// This is an IN-DISTRIBUTION test (same source distribution the prototypes were fit from) —
/// NOT comparable to IRMAS's cross-dataset numbers. Do not rank Bass/Drums' OpenMIC accuracy
/// against Piano/Brass/Vocals/Strings' IRMAS accuracy as if they were the same exam.
func runOpenMICTestPartitionEval(root: String, perClassLimit: Int) async {
    let coarseClasses = ["Piano/Keyboard", "Bass (Acoustic/Electric)", "Brass/Trumpet",
                          "Vocals/Chorus", "Drums/Percussion", "Strings/Synth"]
    let base = URL(fileURLWithPath: root).resolvingSymlinksInPath()
    let csvURL = base.appendingPathComponent("openmic-2018-aggregated-labels.csv")
    let testURL = base.appendingPathComponent("partitions/split01_test.csv")
    guard let csv = try? String(contentsOf: csvURL, encoding: .utf8),
          let testList = try? String(contentsOf: testURL, encoding: .utf8) else {
        print("ERROR: could not read OpenMIC CSVs"); return
    }
    let testKeys = Set(testList.split(separator: "\n").map(String.init))
    var positives: [String: Set<String>] = [:]
    for line in csv.split(separator: "\n").dropFirst() {
        let cols = line.split(separator: ",")
        guard cols.count >= 3, let relevance = Double(cols[2]) else { continue }
        if relevance >= 0.5 { positives[String(cols[0]), default: []].insert(String(cols[1])) }
    }

    // Group eligible (single-coarse-class) test keys by true class first, then thin each
    // class's list independently to `perClassLimit` — a plain global thin would under-sample
    // small classes like Bass relative to large ones like Strings/Synth.
    var keysByCoarse: [String: [String]] = [:]
    var skippedAmbiguous = 0
    for key in testKeys.sorted() {
        guard let fine = positives[key] else { continue }
        let mapped = Set(fine.compactMap { openmicToSingleCoarseForDiscrimination[$0] })
        guard mapped.count == 1, let trueCoarse = mapped.first else { skippedAmbiguous += 1; continue }
        keysByCoarse[trueCoarse, default: []].append(key)
    }

    var confusion: [String: [String: Int]] = [:] // [trueCoarse][predictedLabel] = count
    var evaluated = 0, skippedMissing = 0

    for coarse in coarseClasses {
        let keys = thinned(keysByCoarse[coarse] ?? [], limit: perClassLimit)
        for key in keys {
            let prefix = String(key.prefix(3))
            let audioURL = base.appendingPathComponent("audio/\(prefix)/\(key).ogg")
            guard let buf = try? await AudioLoader.load(url: audioURL, targetSampleRate: 22050) else { skippedMissing += 1; continue }
            let label = await predictInstrument(samples: buf.samples, sampleRate: 22050)
            confusion[coarse, default: [:]][label, default: 0] += 1
            evaluated += 1
        }
    }

    print("\n=== OpenMIC-2018 TEST PARTITION eval (held-out, never used for prototype training) ===")
    print("evaluated=\(evaluated) (single-coarse-class clips only), skipped ambiguous/multi-label=\(skippedAmbiguous), skipped missing=\(skippedMissing)")
    print("⚠️  IN-DISTRIBUTION test — NOT comparable to IRMAS's cross-dataset numbers.\n")

    for coarse in coarseClasses {
        let row = confusion[coarse] ?? [:]
        let total = row.values.reduce(0, +)
        guard total > 0 else { print("  \(coarse): no test examples"); continue }
        let correct = row[coarse] ?? 0
        print(String(format: "  %@ recall: %d/%d (%.0f%%)", coarse, correct, total, Double(correct) / Double(total) * 100))
    }
    print("")
    for coarse in coarseClasses {
        var totalPredicted = 0, truePositive = 0
        for trueCoarse in coarseClasses {
            let c = confusion[trueCoarse]?[coarse] ?? 0
            totalPredicted += c
            if trueCoarse == coarse { truePositive += c }
        }
        guard totalPredicted > 0 else { continue }
        print(String(format: "  %@ precision: %d/%d (%.0f%%)", coarse, truePositive, totalPredicted, Double(truePositive) / Double(totalPredicted) * 100))
    }
    print("")
}

/// Closes a real methodology gap found while investigating open-items list item 2's Stage 1
/// (the `DNAReportBuilder.swift` frame-0-snapshot MFCC fix, DEVLOG Phase 34): every ReliabilityAudit
/// instrument measurement (`predictInstrument`) calls `InstrumentEngine.predict()` through its OWN
/// independent STFT/MFCC/HPSS pipeline, never through `DNAReportBuilder`'s real per-chunk wiring --
/// so it could never have caught (or ruled out) that bug, and no measurement here has ever actually
/// characterized what a real user of the library gets. This runs BOTH paths on the SAME small,
/// class-balanced, held-out sample (not the full ~14k/20k corpus -- that's what the isolated tasks
/// are for) and reports: does production's `AudioIntelligence.analyzeRawAggregate` primaryLabel
/// agree with the isolated engine's, and does either one's own accuracy against ground truth differ.
/// If they converge, the isolated numbers elsewhere in this tool are a legitimate proxy for
/// production, now actually checked rather than assumed. If they diverge, that's a real production
/// bug distinct from anything the isolated path can see.
/// Direction-determining measurement for the sample-rate mismatch found by
/// `runInstrumentFeatureDump` (DEVLOG Phase 35): isolated evaluation (`predictInstrument`,
/// `PrototypeTrainer`) always resamples to 22050Hz; `DNAReportBuilder.swift`'s real production path
/// never resamples at all, analyzing at whatever native rate the file has (44100Hz for the OpenMIC
/// file checked). Before "fixing" anything, this answers: which rate does `InstrumentEngine`'s
/// already-fitted profiles actually perform better at? Runs the SAME isolated pipeline
/// (`predictInstrument`, unchanged) at two different, internally-consistent input rates (all files
/// loaded at 22050Hz, then the identical set reloaded at 44100Hz) over the same class-balanced,
/// held-out sample, and reports each rate's real accuracy against ground truth. Whichever rate
/// wins tells us the correction direction -- resample production to match the model's fitted rate,
/// or (if 44100 wins) retrain the model's profiles at native rate instead.
func runInstrumentSampleRateComparison(root: String, perClassLimit: Int) async {
    let coarseClasses = ["Piano/Keyboard", "Bass (Acoustic/Electric)", "Brass/Trumpet",
                          "Vocals/Chorus", "Drums/Percussion", "Strings/Synth"]
    let base = URL(fileURLWithPath: root).resolvingSymlinksInPath()
    let csvURL = base.appendingPathComponent("openmic-2018-aggregated-labels.csv")
    let testURL = base.appendingPathComponent("partitions/split01_test.csv")
    guard let csv = try? String(contentsOf: csvURL, encoding: .utf8),
          let testList = try? String(contentsOf: testURL, encoding: .utf8) else {
        print("ERROR: could not read OpenMIC CSVs"); return
    }
    let testKeys = Set(testList.split(separator: "\n").map(String.init))
    var positives: [String: Set<String>] = [:]
    for line in csv.split(separator: "\n").dropFirst() {
        let cols = line.split(separator: ",")
        guard cols.count >= 3, let relevance = Double(cols[2]) else { continue }
        if relevance >= 0.5 { positives[String(cols[0]), default: []].insert(String(cols[1])) }
    }

    var keysByCoarse: [String: [String]] = [:]
    for key in testKeys.sorted() {
        guard let fine = positives[key] else { continue }
        let mapped = Set(fine.compactMap { openmicToSingleCoarseForDiscrimination[$0] })
        guard mapped.count == 1, let trueCoarse = mapped.first else { continue }
        keysByCoarse[trueCoarse, default: []].append(key)
    }

    var evaluated = 0
    var correct22k = 0, correct44k = 0
    var confusion22k: [String: [String: Int]] = [:], confusion44k: [String: [String: Int]] = [:]

    for coarse in coarseClasses {
        let keys = thinned(keysByCoarse[coarse] ?? [], limit: perClassLimit)
        for key in keys {
            let prefix = String(key.prefix(3))
            let audioURL = base.appendingPathComponent("audio/\(prefix)/\(key).ogg")
            guard let buf22k = try? await AudioLoader.load(url: audioURL, targetSampleRate: 22050),
                  let buf44k = try? await AudioLoader.load(url: audioURL, targetSampleRate: 44100) else { continue }

            let label22k = await predictInstrument(samples: buf22k.samples, sampleRate: 22050)
            let label44k = await predictInstrument(samples: buf44k.samples, sampleRate: 44100)

            evaluated += 1
            if label22k == coarse { correct22k += 1 }
            if label44k == coarse { correct44k += 1 }
            confusion22k[coarse, default: [:]][label22k, default: 0] += 1
            confusion44k[coarse, default: [:]][label44k, default: 0] += 1
        }
    }

    print("\n=== Instrument: which sample rate does InstrumentEngine actually perform better at? ===")
    print("evaluated=\(evaluated) (single-coarse-class, held-out test partition, SAME isolated pipeline at two rates)")
    guard evaluated > 0 else { print("no files evaluated"); return }
    print(String(format: "  accuracy @ 22050Hz (PrototypeTrainer's fitting rate): %d/%d (%.1f%%)", correct22k, evaluated, Double(correct22k) / Double(evaluated) * 100))
    print(String(format: "  accuracy @ 44100Hz (typical native rate):            %d/%d (%.1f%%)", correct44k, evaluated, Double(correct44k) / Double(evaluated) * 100))
    print("\n--- per-class recall @ 22050Hz vs @ 44100Hz ---")
    for coarse in coarseClasses {
        let row22 = confusion22k[coarse] ?? [:], row44 = confusion44k[coarse] ?? [:]
        let total22 = row22.values.reduce(0, +), total44 = row44.values.reduce(0, +)
        guard total22 > 0 else { continue }
        let hit22 = row22[coarse] ?? 0, hit44 = row44[coarse] ?? 0
        print(String(format: "  %@: 22050Hz=%d/%d (%.0f%%)  44100Hz=%d/%d (%.0f%%)",
                      coarse, hit22, total22, Double(hit22)/Double(total22)*100, hit44, total44, total44 > 0 ? Double(hit44)/Double(total44)*100 : 0))
    }
}

func runInstrumentProductionParityCheck(root: String, perClassLimit: Int) async {
    let coarseClasses = ["Piano/Keyboard", "Bass (Acoustic/Electric)", "Brass/Trumpet",
                          "Vocals/Chorus", "Drums/Percussion", "Strings/Synth"]
    let base = URL(fileURLWithPath: root).resolvingSymlinksInPath()
    let csvURL = base.appendingPathComponent("openmic-2018-aggregated-labels.csv")
    let testURL = base.appendingPathComponent("partitions/split01_test.csv")
    guard let csv = try? String(contentsOf: csvURL, encoding: .utf8),
          let testList = try? String(contentsOf: testURL, encoding: .utf8) else {
        print("ERROR: could not read OpenMIC CSVs"); return
    }
    let testKeys = Set(testList.split(separator: "\n").map(String.init))
    var positives: [String: Set<String>] = [:]
    for line in csv.split(separator: "\n").dropFirst() {
        let cols = line.split(separator: ",")
        guard cols.count >= 3, let relevance = Double(cols[2]) else { continue }
        if relevance >= 0.5 { positives[String(cols[0]), default: []].insert(String(cols[1])) }
    }

    var keysByCoarse: [String: [String]] = [:]
    for key in testKeys.sorted() {
        guard let fine = positives[key] else { continue }
        let mapped = Set(fine.compactMap { openmicToSingleCoarseForDiscrimination[$0] })
        guard mapped.count == 1, let trueCoarse = mapped.first else { continue }
        keysByCoarse[trueCoarse, default: []].append(key)
    }

    var evaluated = 0
    var agreeCpuProd = 0, agreeCpuGpu = 0, agreeGpuProd = 0
    var cpuCorrect = 0, gpuCorrect = 0, productionCorrect = 0
    var disagreements: [String] = []

    for coarse in coarseClasses {
        let keys = thinned(keysByCoarse[coarse] ?? [], limit: perClassLimit)
        for key in keys {
            let prefix = String(key.prefix(3))
            let audioURL = base.appendingPathComponent("audio/\(prefix)/\(key).ogg")
            guard let buf = try? await AudioLoader.load(url: audioURL, targetSampleRate: 22050) else { continue }

            // Three variants on the SAME file: isolated-CPU (existing baseline), isolated-GPU
            // (identical wiring, only STFT/Mel/MFCC given `sharedMetalEngine` -- the cheap
            // discriminator for whether the production divergence is a GPU/CPU numerical
            // difference upstream of Phase 19's already-verified DCT-scale fix), and real
            // production. See `predictInstrumentGPU`'s doc comment.
            let cpuLabel = await predictInstrument(samples: buf.samples, sampleRate: 22050)
            let gpuLabel = await predictInstrumentGPU(samples: buf.samples, sampleRate: 22050)
            guard let analysis = try? await AudioIntelligence().analyzeRawAggregate(url: audioURL) else { continue }
            let productionLabel = analysis.instruments.primaryLabel

            evaluated += 1
            if cpuLabel == productionLabel { agreeCpuProd += 1 }
            if cpuLabel == gpuLabel { agreeCpuGpu += 1 }
            if gpuLabel == productionLabel { agreeGpuProd += 1 }
            if cpuLabel != productionLabel {
                disagreements.append("\(key) [true=\(coarse)]: isolated-CPU=\(cpuLabel) isolated-GPU=\(gpuLabel) production=\(productionLabel)")
            }
            if cpuLabel == coarse { cpuCorrect += 1 }
            if gpuLabel == coarse { gpuCorrect += 1 }
            if productionLabel == coarse { productionCorrect += 1 }
        }
    }

    print("\n=== Instrument: production (DNAReportBuilder) vs isolated engine (CPU and GPU variants), same files (held-out) ===")
    print("evaluated=\(evaluated) (single-coarse-class, held-out test partition)")
    guard evaluated > 0 else { print("no files evaluated"); return }
    print(String(format: "  agreement isolated-CPU vs production: %d/%d (%.1f%%)  [original finding]", agreeCpuProd, evaluated, Double(agreeCpuProd) / Double(evaluated) * 100))
    print(String(format: "  agreement isolated-CPU vs isolated-GPU: %d/%d (%.1f%%)  [same wiring, only compute backend differs]", agreeCpuGpu, evaluated, Double(agreeCpuGpu) / Double(evaluated) * 100))
    print(String(format: "  agreement isolated-GPU vs production: %d/%d (%.1f%%)  [if this is high, GPU/CPU explains the gap]", agreeGpuProd, evaluated, Double(agreeGpuProd) / Double(evaluated) * 100))
    print(String(format: "  isolated-CPU accuracy vs ground truth: %d/%d (%.1f%%)", cpuCorrect, evaluated, Double(cpuCorrect) / Double(evaluated) * 100))
    print(String(format: "  isolated-GPU accuracy vs ground truth: %d/%d (%.1f%%)", gpuCorrect, evaluated, Double(gpuCorrect) / Double(evaluated) * 100))
    print(String(format: "  production accuracy vs ground truth:   %d/%d (%.1f%%)", productionCorrect, evaluated, Double(productionCorrect) / Double(evaluated) * 100))
    if !disagreements.isEmpty {
        print("\n--- disagreements (isolated vs production predicted different labels) ---")
        disagreements.forEach { print("  \($0)") }
    }
}

/// Step A of DEVLOG item 2 Stage 2 / Phase 37: does the isolated path's FULL multi-label
/// prediction set (not just `primaryLabel`) agree with production closely enough to serve as a
/// proxy for a larger-scale OpenMIC multi-label F1 measurement? `runInstrumentProductionParityCheck`
/// only ever established primaryLabel (argmax) agreement (88.7%) -- a different, easier question
/// than whether the SECONDARY labels (threshold-crossing but not top-1) also agree, which is what
/// Stage 2's F1 actually depends on. Measures primary and secondary agreement SEPARATELY so a
/// high blended average can't hide a collapsed secondary-label channel. The pass/fail bar
/// (per-class agreement ≥85%, <70% flagged as "collapsed") was fixed in DEVLOG Phase 37 BEFORE
/// this was run -- do not adjust it based on the result below.
func runInstrumentMultiLabelParityCheck(root: String, perClassLimit: Int) async {
    let coarseClasses = ["Piano/Keyboard", "Bass (Acoustic/Electric)", "Brass/Trumpet",
                          "Vocals/Chorus", "Drums/Percussion", "Strings/Synth"]
    let base = URL(fileURLWithPath: root).resolvingSymlinksInPath()
    let csvURL = base.appendingPathComponent("openmic-2018-aggregated-labels.csv")
    let testURL = base.appendingPathComponent("partitions/split01_test.csv")
    guard let csv = try? String(contentsOf: csvURL, encoding: .utf8),
          let testList = try? String(contentsOf: testURL, encoding: .utf8) else {
        print("ERROR: could not read OpenMIC CSVs"); return
    }
    let testKeys = Set(testList.split(separator: "\n").map(String.init))
    var positives: [String: Set<String>] = [:]
    for line in csv.split(separator: "\n").dropFirst() {
        let cols = line.split(separator: ",")
        guard cols.count >= 3, let relevance = Double(cols[2]) else { continue }
        if relevance >= 0.5 { positives[String(cols[0]), default: []].insert(String(cols[1])) }
    }

    var keysByCoarse: [String: [String]] = [:]
    for key in testKeys.sorted() {
        guard let fine = positives[key] else { continue }
        let mapped = Set(fine.compactMap { openmicToSingleCoarseForDiscrimination[$0] })
        guard mapped.count == 1, let trueCoarse = mapped.first else { continue }
        keysByCoarse[trueCoarse, default: []].append(key)
    }

    var evaluated = 0
    var primaryAgree = 0
    // Per-class full-label agreement: does isolated's above/below-0.3 decision for class C match
    // production's, for every clip evaluated (not just clips whose TRUE label is C).
    var classAgree: [String: Int] = [:], classTotal: [String: Int] = [:]
    // Secondary-only: same question, restricted to (clip, class) pairs where class is NOT the
    // top-1 in EITHER path -- isolates the threshold-crossing-only signal from the argmax signal.
    var secondaryAgree = 0, secondaryTotal = 0
    var jaccardSum = 0.0

    for coarse in coarseClasses {
        let keys = thinned(keysByCoarse[coarse] ?? [], limit: perClassLimit)
        for key in keys {
            let prefix = String(key.prefix(3))
            let audioURL = base.appendingPathComponent("audio/\(prefix)/\(key).ogg")
            guard let buf = try? await AudioLoader.load(url: audioURL, targetSampleRate: 22050) else { continue }
            let isolated = await predictInstrumentFull(samples: buf.samples, sampleRate: 22050)
            guard let analysis = try? await AudioIntelligence().analyzeRawAggregate(url: audioURL) else { continue }
            let production = analysis.instruments

            let isoSet = Set(isolated.predictions.map { $0.label })
            let prodSet = Set(production.predictions.map { $0.label })
            evaluated += 1
            if isolated.primaryLabel == production.primaryLabel { primaryAgree += 1 }

            let union = isoSet.union(prodSet)
            let intersection = isoSet.intersection(prodSet)
            jaccardSum += union.isEmpty ? 1.0 : Double(intersection.count) / Double(union.count)

            for c in coarseClasses {
                let isoHas = isoSet.contains(c), prodHas = prodSet.contains(c)
                classTotal[c, default: 0] += 1
                if isoHas == prodHas { classAgree[c, default: 0] += 1 }
                if c != isolated.primaryLabel && c != production.primaryLabel {
                    secondaryTotal += 1
                    if isoHas == prodHas { secondaryAgree += 1 }
                }
            }
        }
    }

    guard evaluated > 0 else { print("no files evaluated"); return }
    print("\n=== Instrument Stage 2 Step A: isolated vs production, FULL multi-label set (held-out, \(evaluated) files) ===")
    print(String(format: "  primaryLabel agreement (argmax, re-confirms Phase 35's 88.7%%):     %d/%d (%.1f%%)", primaryAgree, evaluated, Double(primaryAgree) / Double(evaluated) * 100))
    print(String(format: "  secondary-label agreement (non-top-1 positions only, both paths):  %d/%d (%.1f%%)", secondaryAgree, secondaryTotal, secondaryTotal > 0 ? Double(secondaryAgree) / Double(secondaryTotal) * 100 : 0))
    print(String(format: "  mean per-clip Jaccard(isolated, production) [informational only]:  %.1f%%", jaccardSum / Double(evaluated) * 100))
    print("\n  --- per-class full-label agreement (the number the Phase 37 pre-registered threshold applies to) ---")
    var anyFail = false
    for c in coarseClasses {
        let a = classAgree[c] ?? 0, t = classTotal[c] ?? 0
        let pct = t > 0 ? Double(a) / Double(t) * 100 : 0
        let verdict = pct < 70 ? "COLLAPSED" : (pct < 85 ? "FAIL (<85%)" : "PASS")
        if pct < 85 { anyFail = true }
        print(String(format: "  [%@] %d/%d (%.1f%%) -- %@", c, a, t, pct, verdict))
    }
    print("\n  Phase 37 proxy-legitimacy verdict: \(anyFail ? "FAILS -- at least one class below 85%; do NOT use isolated path as an F1 proxy without investigating the failing class(es) first (Step C)." : "PASSES -- all 6 classes ≥85%; isolated path may be used as a documented proxy for Stage 2's larger-scale F1 (Step B).")")
}

/// Step B of DEVLOG item 2 Stage 2 / Phase 37: real OpenMIC multi-label F1 (precision/recall/F1
/// per coarse class, macro-averaged), computed on the isolated path over the held-out test
/// partition -- legitimate as a proxy for production per Step A's measured ≥85%-per-class
/// agreement (Phase 37 DEVLOG). Ground truth is reconstructed with THREE states per
/// (clip, fine-instrument), not two: positive (relevance≥0.5), known-negative (reviewed,
/// relevance<0.5), unknown (never reviewed, absent from the CSV). This reconstruction was
/// verified against OpenMIC's official `openmic-2018.npz` Y_true/Y_mask arrays: 41,268/41,268
/// known pairs match exactly. Aggregated to coarse level via `openmicToCoarse`'s existing
/// OR-for-positive convention, extended symmetrically: a coarse class is positive if ANY mapped
/// fine label is positive; known-negative if ANY mapped fine label was reviewed and none was
/// positive; unknown (excluded from F1 entirely, not counted as TP/FP/FN/TN) if no mapped fine
/// label was ever reviewed for that clip. Unknown pairs must be excluded, not treated as
/// negative -- OpenMIC is weakly/crowd-labeled and most (clip, instrument) pairs were never
/// queried; counting a correctly-detected-but-unqueried instrument as a false positive would
/// artificially depress precision and F1 for reasons that have nothing to do with the model.
func runInstrumentMultiLabelF1(root: String) async {
    let coarseClasses = ["Piano/Keyboard", "Bass (Acoustic/Electric)", "Brass/Trumpet",
                          "Vocals/Chorus", "Drums/Percussion", "Strings/Synth"]
    let base = URL(fileURLWithPath: root).resolvingSymlinksInPath()
    let csvURL = base.appendingPathComponent("openmic-2018-aggregated-labels.csv")
    let testURL = base.appendingPathComponent("partitions/split01_test.csv")
    guard let csv = try? String(contentsOf: csvURL, encoding: .utf8),
          let testList = try? String(contentsOf: testURL, encoding: .utf8) else {
        print("ERROR: could not read OpenMIC CSVs"); return
    }
    let testKeys = Set(testList.split(separator: "\n").map(String.init))

    // ALL rows this time (not just relevance>=0.5) -- `known` tracks every fine label actually
    // reviewed for a clip (positive or negative), `positiveFine` the relevance>=0.5 subset.
    var known: [String: Set<String>] = [:]
    var positiveFine: [String: Set<String>] = [:]
    for line in csv.split(separator: "\n").dropFirst() {
        let cols = line.split(separator: ",")
        guard cols.count >= 3, let relevance = Double(cols[2]) else { continue }
        let key = String(cols[0]), inst = String(cols[1])
        known[key, default: []].insert(inst)
        if relevance >= 0.5 { positiveFine[key, default: []].insert(inst) }
    }

    // relevantFine[C] = every fine label that maps to coarse class C (inverse of openmicToCoarse).
    var relevantFine: [String: [String]] = [:]
    for (fine, coarses) in openmicToCoarse {
        for c in coarses { relevantFine[c, default: []].append(fine) }
    }

    enum Truth { case positive, negative, unknown }
    func truth(coarse: String, clip: String) -> Truth {
        let rel = relevantFine[coarse] ?? []
        let pos = positiveFine[clip] ?? []
        if rel.contains(where: { pos.contains($0) }) { return .positive }
        let kn = known[clip] ?? []
        if rel.contains(where: { kn.contains($0) }) { return .negative }
        return .unknown
    }

    struct Confusion { var tp = 0, fp = 0, fn = 0, tn = 0 }
    var confusion: [String: Confusion] = [:]
    for c in coarseClasses { confusion[c] = Confusion() }

    var evaluated = 0, loadFailures = 0
    let keys = testKeys.sorted()
    for key in keys {
        // Skip clips with zero known coarse-level ground truth entirely (nothing to score).
        guard coarseClasses.contains(where: { truth(coarse: $0, clip: key) != .unknown }) else { continue }
        let prefix = String(key.prefix(3))
        let audioURL = base.appendingPathComponent("audio/\(prefix)/\(key).ogg")
        guard FileManager.default.fileExists(atPath: audioURL.path) else { continue }
        guard let buf = try? await AudioLoader.load(url: audioURL, targetSampleRate: 22050) else {
            loadFailures += 1; continue
        }
        let isolated = await predictInstrumentFull(samples: buf.samples, sampleRate: 22050)
        let predictedPositive = Set(isolated.predictions.map { $0.label })
        evaluated += 1

        for c in coarseClasses {
            let t = truth(coarse: c, clip: key)
            guard t != .unknown else { continue }
            let predicted = predictedPositive.contains(c)
            switch (predicted, t) {
            case (true, .positive): confusion[c]!.tp += 1
            case (true, .negative): confusion[c]!.fp += 1
            case (false, .positive): confusion[c]!.fn += 1
            case (false, .negative): confusion[c]!.tn += 1
            case (_, .unknown): break
            }
        }
        if evaluated % 500 == 0 {
            print("  ... \(evaluated) clips scored (\(key))")
        }
    }

    guard evaluated > 0 else { print("no files evaluated"); return }
    print("\n=== Instrument Stage 2: OpenMIC multi-label F1 (held-out test partition, isolated path, proxy per Phase 37 Step A) ===")
    print("evaluated=\(evaluated) clips (of \(testKeys.count) in the test partition; \(loadFailures) load failures, rest had zero known coarse-level labels and were skipped)")
    print("\n  class                         TP   FP   FN   TN  | precision  recall     F1")
    func pad(_ s: String, _ w: Int) -> String { s.count >= w ? s : s + String(repeating: " ", count: w - s.count) }
    var f1Sum = 0.0, f1Count = 0
    for c in coarseClasses {
        let m = confusion[c]!
        let precDenom = m.tp + m.fp, recDenom = m.tp + m.fn
        let precision = precDenom > 0 ? Double(m.tp) / Double(precDenom) : Double.nan
        let recall = recDenom > 0 ? Double(m.tp) / Double(recDenom) : Double.nan
        let f1 = (precision.isNaN || recall.isNaN || (precision + recall) == 0) ? Double.nan : 2 * precision * recall / (precision + recall)
        if !f1.isNaN { f1Sum += f1; f1Count += 1 }
        let precStr = precision.isNaN ? "  N/A " : String(format: "%6.1f%%", precision * 100)
        let recStr = recall.isNaN ? "  N/A " : String(format: "%6.1f%%", recall * 100)
        let f1Str = f1.isNaN ? "  N/A " : String(format: "%6.1f%%", f1 * 100)
        print("  \(pad(c, 28)) \(String(format: "%4d %4d %4d %4d", m.tp, m.fp, m.fn, m.tn))  | \(precStr)   \(recStr)   \(f1Str)")
    }
    let macroF1 = f1Count > 0 ? f1Sum / Double(f1Count) : Double.nan
    print(String(format: "\n  Macro-F1 (mean of the %d classes with a defined F1): %.1f%%", f1Count, macroF1 * 100))
    print("  Ground truth: relevance>=0.5 positive / reviewed-but-negative known-negative / never-reviewed excluded entirely (verified vs. official Y_true/Y_mask, 41,268/41,268 match).")
    print("  This F1 is measured on the ISOLATED path -- a documented proxy for production, backed by Phase 37 Step A's per-class agreement (all 6 classes >=85%, see DEVLOG).")
}

/// Pre-check for DEVLOG item 3 (multi-label threshold recalibration), run BEFORE any calibration
/// fitting: does each coarse class's raw (unthresholded) score actually carry monotonic
/// discriminating information, or is precision flat across the score range for some class? If
/// flat, no monotonic recalibration (Platt/isotonic/temperature scaling) can fix that class --
/// the defect would be the profile itself (a madde 4/5-type problem), and calibrating over it
/// would just relabel the same bad signal with false confidence. Uses ONLY OpenMIC's official
/// TRAIN partition (`split01_train.csv`) -- this function has no access to `split01_test.csv` at
/// all, by construction, so it cannot leak into the held-out set the actual F1 was measured on.
///
/// Reports, per class: an AUC (Mann-Whitney U / rank-sum form -- the probability a random true
/// positive scores higher than a random true negative; 0.5 = no discriminating power, 1.0 =
/// perfect separation) and a 10-bin reliability table (score range, n, empirical precision per
/// bin) for visual confirmation that precision actually climbs with score.
func runInstrumentReliabilityPrecheck(root: String) async {
    // The first unbounded run over all 14,915 train clips was SIGKILLed by the OS (exit 137,
    // OOM) -- same failure class documented for the full-OpenMIC-corpus run in DEVLOG. Bounded
    // to a large-but-safe evenly-thinned sample instead (matches that established mitigation).
    // Unbuffered stdout so a future kill (OOM or otherwise) can't lose progress output again --
    // an earlier background-process loss taught this the hard way (DEVLOG).
    setvbuf(stdout, nil, _IONBF, 0)
    let coarseClasses = ["Piano/Keyboard", "Bass (Acoustic/Electric)", "Brass/Trumpet",
                          "Vocals/Chorus", "Drums/Percussion", "Strings/Synth"]
    let base = URL(fileURLWithPath: root).resolvingSymlinksInPath()
    let csvURL = base.appendingPathComponent("openmic-2018-aggregated-labels.csv")
    let trainURL = base.appendingPathComponent("partitions/split01_train.csv")
    guard let csv = try? String(contentsOf: csvURL, encoding: .utf8),
          let trainList = try? String(contentsOf: trainURL, encoding: .utf8) else {
        print("ERROR: could not read OpenMIC CSVs"); return
    }
    // TRAIN ONLY -- split01_test.csv is never read anywhere in this function.
    let allTrainKeys = trainList.split(separator: "\n").map(String.init)
    let limit = envLimit("RA_INSTRUMENT_RELIABILITY_LIMIT", default: 5000)
    let trainKeys = Set(thinned(allTrainKeys, limit: limit))
    print("Scanning \(trainKeys.count) of \(allTrainKeys.count) train clips (evenly thinned, RA_INSTRUMENT_RELIABILITY_LIMIT to change).")

    var known: [String: Set<String>] = [:]
    var positiveFine: [String: Set<String>] = [:]
    for line in csv.split(separator: "\n").dropFirst() {
        let cols = line.split(separator: ",")
        guard cols.count >= 3, let relevance = Double(cols[2]) else { continue }
        let key = String(cols[0]), inst = String(cols[1])
        guard trainKeys.contains(key) else { continue }
        known[key, default: []].insert(inst)
        if relevance >= 0.5 { positiveFine[key, default: []].insert(inst) }
    }

    var relevantFine: [String: [String]] = [:]
    for (fine, coarses) in openmicToCoarse {
        for c in coarses { relevantFine[c, default: []].append(fine) }
    }
    enum Truth { case positive, negative, unknown }
    func truth(coarse: String, clip: String) -> Truth {
        let rel = relevantFine[coarse] ?? []
        if rel.contains(where: { (positiveFine[clip] ?? []).contains($0) }) { return .positive }
        if rel.contains(where: { (known[clip] ?? []).contains($0) }) { return .negative }
        return .unknown
    }

    // Per-class (score, isPositive) pairs, collected once per clip (one predictWithBreakdown
    // call gives all 6 classes' scores at once).
    var samples: [String: [(score: Float, positive: Bool)]] = [:]
    for c in coarseClasses { samples[c] = [] }

    let keys = trainKeys.sorted()
    var evaluated = 0
    for key in keys {
        guard coarseClasses.contains(where: { truth(coarse: $0, clip: key) != .unknown }) else { continue }
        let prefix = String(key.prefix(3))
        let audioURL = base.appendingPathComponent("audio/\(prefix)/\(key).ogg")
        guard FileManager.default.fileExists(atPath: audioURL.path) else { continue }
        guard let buf = try? await AudioLoader.load(url: audioURL, targetSampleRate: 22050) else { continue }
        let breakdown = await predictInstrumentBreakdown(samples: buf.samples, sampleRate: 22050)
        var scoreByLabel: [String: Float] = [:]
        for b in breakdown { scoreByLabel[b.label] = b.total }
        evaluated += 1
        for c in coarseClasses {
            let t = truth(coarse: c, clip: key)
            guard t != .unknown, let s = scoreByLabel[c] else { continue }
            samples[c]!.append((score: s, positive: t == .positive))
        }
        if evaluated % 1000 == 0 { print("  ... \(evaluated) train clips scored (\(key))") }
    }

    guard evaluated > 0 else { print("no files evaluated"); return }
    print("\n=== Instrument threshold-recalibration pre-check: is each class's raw score monotonic with true precision? (TRAIN partition only, \(evaluated) clips, NEVER touches split01_test.csv) ===")

    func auc(_ pairs: [(score: Float, positive: Bool)]) -> (auc: Double, nPos: Int, nNeg: Int) {
        let pos = pairs.filter { $0.positive }.map { $0.score }
        let neg = pairs.filter { !$0.positive }.map { $0.score }
        guard !pos.isEmpty, !neg.isEmpty else { return (Double.nan, pos.count, neg.count) }
        // Rank-sum (Mann-Whitney U) form of AUC: average, over all (pos,neg) pairs, of
        // 1 if pos>neg, 0.5 if tied, 0 if pos<neg.
        let sortedAll = (pos.map { ($0, true) } + neg.map { ($0, false) }).sorted { $0.0 < $1.0 }
        var ranks = [Double](repeating: 0, count: sortedAll.count)
        var i = 0
        while i < sortedAll.count {
            var j = i
            while j + 1 < sortedAll.count && sortedAll[j + 1].0 == sortedAll[i].0 { j += 1 }
            let avgRank = Double(i + j) / 2.0 + 1.0
            for k in i...j { ranks[k] = avgRank }
            i = j + 1
        }
        var rankSumPos = 0.0
        for (idx, (_, isPos)) in sortedAll.enumerated() where isPos { rankSumPos += ranks[idx] }
        let n1 = Double(pos.count), n2 = Double(neg.count)
        let u = rankSumPos - n1 * (n1 + 1) / 2
        return (u / (n1 * n2), pos.count, neg.count)
    }

    for c in coarseClasses {
        let pairs = samples[c] ?? []
        let (aucVal, nPos, nNeg) = auc(pairs)
        let verdict = aucVal.isNaN ? "N/A (insufficient data)" : (aucVal >= 0.65 ? "MONOTONIC -- calibration-amenable" : (aucVal >= 0.55 ? "WEAK -- marginal, inspect table" : "FLAT -- score carries little/no discriminating info; this is a PROFILE problem, not fixable by calibration"))
        print("\n  [\(c)] n=\(pairs.count) (pos=\(nPos) neg=\(nNeg))  AUC=\(aucVal.isNaN ? "N/A" : String(format: "%.3f", aucVal))  -- \(verdict)")
        guard pairs.count >= 20 else { print("    (too few samples for a reliability table)"); continue }
        let sorted = pairs.sorted { $0.score < $1.score }
        let nBins = 10
        let binSize = max(1, sorted.count / nBins)
        var idx = 0
        var binNum = 1
        while idx < sorted.count {
            let end = min(idx + binSize, sorted.count)
            let bin = sorted[idx..<end]
            let n = bin.count
            let hits = bin.filter { $0.positive }.count
            let prec = Double(hits) / Double(n) * 100
            let scoreLo = bin.first!.score, scoreHi = bin.last!.score
            print(String(format: "    bin %2d: score[%6.3f, %6.3f]  n=%4d  precision=%.1f%%", binNum, scoreLo, scoreHi, n, prec))
            idx = end
            binNum += 1
        }
    }
}

// MARK: - Instrument multi-label threshold recalibration (DEVLOG item 3)

/// Platt scaling: `P(y=1|score) = 1 / (1 + exp(A*score + B))`, fit by Newton's method (2
/// parameters, converges in a handful of iterations) with Platt's own target-smoothing
/// (`(n_pos+1)/(n_pos+2)` / `1/(n_neg+2)` instead of raw 0/1 labels) to avoid the fit collapsing
/// onto perfectly-separable regions of a small sample.
struct PlattModel { let A: Double, B: Double
    func predict(_ score: Double) -> Double { 1.0 / (1.0 + exp(A * score + B)) }
}

/// Fits by damped, L2-regularized Newton's method. Plain unregularized Newton on this data
/// diverged (verified, not assumed): Bass and Vocals -- both small (n=440/407) and moderately
/// separable (raw AUC 0.71/0.83) -- pushed the fit toward p≈0/p≈1 for most points, collapsing
/// `w = p(1-p)` toward zero, making the Hessian near-singular and the raw Newton step explode,
/// landing on a sign-flipped A that INVERTED the calibrated confidence (held-out AUC dropped to
/// 0.35/0.28 -- below chance, not just imprecise). A small ridge term keeps the Hessian
/// bounded away from singular; backtracking line search keeps each step from overshooting even
/// when the (regularized) Newton direction is still large. Both are standard fixes for exactly
/// this quasi-separable-small-sample failure mode.
func fitPlatt(_ pairs: [(score: Double, positive: Bool)]) -> PlattModel {
    let nPos = pairs.filter { $0.positive }.count
    let nNeg = pairs.count - nPos
    let hiTarget = Double(nPos + 1) / Double(nPos + 2)
    let loTarget = 1.0 / Double(nNeg + 2)
    let lambda = 1e-2 // L2 ridge on (A,B)

    // With p = 1/(1+exp(z)): log(p) = -softplus(z), log(1-p) = z - softplus(z), so
    // NLL_i = -[t*log(p) + (1-t)*log(1-p)] = softplus(z) - (1-t)*z. (Verified by hand --
    // an earlier version of this that tried to inline-simplify the same expression had the
    // (1-t)*z terms cancel out entirely, silently dropping real information from the loss.)
    func negLogLik(_ A: Double, _ B: Double) -> Double {
        var nll = 0.0
        for p in pairs {
            let z = A * p.score + B
            let t = p.positive ? hiTarget : loTarget
            let softplus = z > 30 ? z : log1p(exp(z))
            nll += softplus - (1 - t) * z
        }
        return nll + 0.5 * lambda * (A * A + B * B)
    }

    var A = 0.0
    var B = log(Double(nNeg + 1) / Double(nPos + 1))
    var loss = negLogLik(A, B)
    for _ in 0..<100 {
        var gA = lambda * A, gB = lambda * B
        var hAA = lambda, hAB = 0.0, hBB = lambda
        for p in pairs {
            let z = A * p.score + B
            let pr = 1.0 / (1.0 + exp(z))
            let t = p.positive ? hiTarget : loTarget
            // d(loss)/dz = t - pr (verified by hand from softplus(z) - (1-t)*z; the previous
            // version used `pr - t`, the flipped sign, which drove Newton's step in the wrong
            // direction entirely -- see the fitPlatt doc comment for how that surfaced).
            let diff = t - pr
            gA += diff * p.score
            gB += diff
            let w = pr * (1 - pr)
            hAA += w * p.score * p.score
            hAB += w * p.score
            hBB += w
        }
        let det = hAA * hBB - hAB * hAB
        guard abs(det) > 1e-12 else { break }
        var dA = (hBB * gA - hAB * gB) / det
        var dB = (hAA * gB - hAB * gA) / det

        // Backtracking line search: halve the step until the (regularized) loss actually drops.
        var newLoss = negLogLik(A - dA, B - dB)
        var backtracks = 0
        while newLoss > loss && backtracks < 30 {
            dA /= 2; dB /= 2
            newLoss = negLogLik(A - dA, B - dB)
            backtracks += 1
        }
        guard newLoss <= loss else { break } // no improving step found -- stop, keep last-good params
        A -= dA; B -= dB; loss = newLoss
        if abs(dA) < 1e-9 && abs(dB) < 1e-9 { break }
    }
    return PlattModel(A: A, B: B)
}

/// Isotonic regression via pool-adjacent-violators (PAVA): a free-form non-decreasing step
/// function, chosen (per DEVLOG item 3's design) for the larger classes where Strings/Synth's
/// climb-then-plateau shape doesn't fit Platt's sigmoid assumption well, and where sample size
/// makes isotonic's extra flexibility low-risk rather than overfitting.
struct IsotonicModel {
    let blocks: [(xMin: Double, xMax: Double, y: Double)] // ascending xMin, non-decreasing y
    func predict(_ score: Double) -> Double {
        guard let first = blocks.first, let last = blocks.last else { return 0.5 }
        if score <= first.xMin { return first.y }
        if score >= last.xMax { return last.y }
        for b in blocks where score <= b.xMax { return b.y }
        return last.y
    }
}

func fitIsotonic(_ pairs: [(score: Double, positive: Bool)]) -> IsotonicModel {
    let sorted = pairs.sorted { $0.score < $1.score }
    var blocks: [(sumY: Double, weight: Double, xMin: Double, xMax: Double)] = []
    for p in sorted {
        blocks.append((sumY: p.positive ? 1 : 0, weight: 1, xMin: p.score, xMax: p.score))
        while blocks.count >= 2 {
            let last = blocks[blocks.count - 1], prev = blocks[blocks.count - 2]
            if prev.sumY / prev.weight > last.sumY / last.weight {
                let merged = (sumY: prev.sumY + last.sumY, weight: prev.weight + last.weight, xMin: prev.xMin, xMax: last.xMax)
                blocks.removeLast(2); blocks.append(merged)
            } else { break }
        }
    }
    return IsotonicModel(blocks: blocks.map { (xMin: $0.xMin, xMax: $0.xMax, y: $0.sumY / $0.weight) })
}

enum CalibModel {
    case platt(PlattModel), isotonic(IsotonicModel)
    var name: String { switch self { case .platt: return "Platt"; case .isotonic: return "isotonic" } }
    func predict(_ score: Double) -> Double {
        switch self {
        case .platt(let m): return m.predict(score)
        case .isotonic(let m): return m.predict(score)
        }
    }
}

func computeECE(_ pairs: [(conf: Double, positive: Bool)], bins: Int = 10) -> Double {
    guard !pairs.isEmpty else { return Double.nan }
    var binConfSum = [Double](repeating: 0, count: bins)
    var binCount = [Int](repeating: 0, count: bins)
    var binHits = [Int](repeating: 0, count: bins)
    for p in pairs {
        let b = min(bins - 1, max(0, Int(p.conf * Double(bins))))
        binConfSum[b] += p.conf; binCount[b] += 1
        if p.positive { binHits[b] += 1 }
    }
    var ece = 0.0
    for b in 0..<bins where binCount[b] > 0 {
        let avgConf = binConfSum[b] / Double(binCount[b])
        let prec = Double(binHits[b]) / Double(binCount[b])
        ece += Double(binCount[b]) / Double(pairs.count) * abs(avgConf - prec)
    }
    return ece
}

func aucOf(_ pairs: [(score: Double, positive: Bool)]) -> Double {
    let pos = pairs.filter { $0.positive }, neg = pairs.filter { !$0.positive }
    guard !pos.isEmpty, !neg.isEmpty else { return Double.nan }
    let sortedAll = (pos.map { ($0.score, true) } + neg.map { ($0.score, false) }).sorted { $0.0 < $1.0 }
    var ranks = [Double](repeating: 0, count: sortedAll.count)
    var i = 0
    while i < sortedAll.count {
        var j = i
        while j + 1 < sortedAll.count && sortedAll[j + 1].0 == sortedAll[i].0 { j += 1 }
        let avgRank = Double(i + j) / 2.0 + 1.0
        for k in i...j { ranks[k] = avgRank }
        i = j + 1
    }
    var rankSumPos = 0.0
    for (idx, (_, isPos)) in sortedAll.enumerated() where isPos { rankSumPos += ranks[idx] }
    let n1 = Double(pos.count), n2 = Double(neg.count)
    return (rankSumPos - n1 * (n1 + 1) / 2) / (n1 * n2)
}

/// Fits + validates per-class confidence calibration for `InstrumentEngine`'s multi-label output
/// (DEVLOG item 3 / Phase 37 follow-up). Design fixed BEFORE this ran, per the pre-check's
/// findings: method chosen by train sample size (n<600 -> Platt, robust on small classes
/// Bass/Vocals; n>=600 -> isotonic, flexible enough for Strings/Synth's climb-then-plateau shape
/// that a sigmoid would misfit). Fit uses ONLY `split01_train.csv` (bounded, same OOM-safe
/// thinning as the pre-check); `split01_test.csv` is read in a SEPARATE code block below, only
/// for validation, never passed to `fitPlatt`/`fitIsotonic`.
///
/// Reports two DIFFERENT closing metrics on purpose, not one: (1) ECE per class, train vs.
/// held-out (large gap = overfit, esp. watch Bass/Vocals, the small classes) -- this measures
/// whether confidence became HONEST. (2) cross-class precision at confidence~=0.6 on held-out,
/// before vs. after calibration -- this measures whether the actual goal (comparable confidence
/// across classes) was achieved. Also reports AUC before/after per class as a sanity check --
/// calibration is a monotonic transform, so AUC should not move (a real change signals a bug).
/// Strings/Synth is EXPECTED to end up "honest but low-ceiling" (ECE improves, but its
/// precision-at-confidence never reaches Vocals/Drums' level) -- that is calibration succeeding
/// at its actual job, not a shortfall; raising that ceiling is a `InstrumentEngine` profile-
/// quality question (open item 5), out of scope here.
func runInstrumentThresholdCalibration(root: String) async {
    setvbuf(stdout, nil, _IONBF, 0)
    let coarseClasses = ["Piano/Keyboard", "Bass (Acoustic/Electric)", "Brass/Trumpet",
                          "Vocals/Chorus", "Drums/Percussion", "Strings/Synth"]
    let base = URL(fileURLWithPath: root).resolvingSymlinksInPath()
    let csvURL = base.appendingPathComponent("openmic-2018-aggregated-labels.csv")
    guard let csv = try? String(contentsOf: csvURL, encoding: .utf8) else {
        print("ERROR: could not read OpenMIC CSVs"); return
    }
    var relevantFine: [String: [String]] = [:]
    for (fine, coarses) in openmicToCoarse { for c in coarses { relevantFine[c, default: []].append(fine) } }
    enum Truth { case positive, negative, unknown }

    func collect(keys keySet: Set<String>) async -> [String: [(score: Double, positive: Bool)]] {
        var known: [String: Set<String>] = [:]
        var positiveFine: [String: Set<String>] = [:]
        for line in csv.split(separator: "\n").dropFirst() {
            let cols = line.split(separator: ",")
            guard cols.count >= 3, let relevance = Double(cols[2]) else { continue }
            let key = String(cols[0]), inst = String(cols[1])
            guard keySet.contains(key) else { continue }
            known[key, default: []].insert(inst)
            if relevance >= 0.5 { positiveFine[key, default: []].insert(inst) }
        }
        func truth(coarse: String, clip: String) -> Truth {
            let rel = relevantFine[coarse] ?? []
            if rel.contains(where: { (positiveFine[clip] ?? []).contains($0) }) { return .positive }
            if rel.contains(where: { (known[clip] ?? []).contains($0) }) { return .negative }
            return .unknown
        }
        var out: [String: [(score: Double, positive: Bool)]] = [:]
        for c in coarseClasses { out[c] = [] }
        var evaluated = 0
        for key in keySet.sorted() {
            guard coarseClasses.contains(where: { truth(coarse: $0, clip: key) != .unknown }) else { continue }
            let prefix = String(key.prefix(3))
            let audioURL = base.appendingPathComponent("audio/\(prefix)/\(key).ogg")
            guard FileManager.default.fileExists(atPath: audioURL.path) else { continue }
            guard let breakdown = await predictInstrumentBreakdownProductionMix(url: audioURL, sampleRate: 22050) else { continue }
            var scoreByLabel: [String: Float] = [:]
            for b in breakdown { scoreByLabel[b.label] = b.total }
            evaluated += 1
            for c in coarseClasses {
                let t = truth(coarse: c, clip: key)
                guard t != .unknown, let s = scoreByLabel[c] else { continue }
                out[c]!.append((score: Double(s), positive: t == .positive))
            }
            if evaluated % 1000 == 0 { print("  ... \(evaluated) clips scored") }
        }
        return out
    }

    // ---- FIT: train partition only, bounded (same OOM-safe limit as the pre-check) ----
    let trainURL = base.appendingPathComponent("partitions/split01_train.csv")
    guard let trainList = try? String(contentsOf: trainURL, encoding: .utf8) else {
        print("ERROR: could not read split01_train.csv"); return
    }
    let allTrainKeys = trainList.split(separator: "\n").map(String.init)
    let limit = envLimit("RA_INSTRUMENT_CALIBRATION_LIMIT", default: 5000)
    let trainKeys = Set(thinned(allTrainKeys, limit: limit))
    print("=== Fitting calibration on \(trainKeys.count) of \(allTrainKeys.count) TRAIN clips (split01_test.csv not read in this block) ===")
    let trainSamples = await collect(keys: trainKeys)

    var models: [String: CalibModel] = [:]
    for c in coarseClasses {
        let pairs = trainSamples[c] ?? []
        let n = pairs.count
        let model: CalibModel = n < 600 ? .platt(fitPlatt(pairs)) : .isotonic(fitIsotonic(pairs))
        models[c] = model
        let rawTrainECE = computeECE(pairs.map { (conf: $0.score, positive: $0.positive) })
        let calTrainPairs = pairs.map { (conf: model.predict($0.score), positive: $0.positive) }
        let calTrainECE = computeECE(calTrainPairs)
        // Self-check, on train, BEFORE the expensive held-out run: calibration is a monotonic
        // transform, so AUC must not move (beyond isotonic's expected small tie-collapse
        // effect). A large drop here means the fit itself is broken (e.g. Platt's Newton step
        // diverging on a small/separable class) -- catch that now, not after re-running held-out.
        let aucRawTrain = aucOf(pairs)
        let aucCalTrain = aucOf(pairs.map { (score: model.predict($0.score), positive: $0.positive) })
        let selfCheck = (aucCalTrain - aucRawTrain).magnitude > 0.05 ? "  <-- SELF-CHECK FAILED: AUC moved by more than 0.05, fit is likely broken for this class" : ""
        print(String(format: "  [%@] n=%d -> %@  |  train ECE raw=%.3f -> calibrated=%.3f  |  train AUC raw=%.3f cal=%.3f%@", c, n, model.name, rawTrainECE, calTrainECE, aucRawTrain, aucCalTrain, selfCheck))
    }

    // ---- VALIDATE: held-out test partition only, never used above ----
    let testURL = base.appendingPathComponent("partitions/split01_test.csv")
    guard let testList = try? String(contentsOf: testURL, encoding: .utf8) else {
        print("ERROR: could not read split01_test.csv"); return
    }
    let testKeys = Set(testList.split(separator: "\n").map(String.init))
    print("\n=== Validating on \(testKeys.count) HELD-OUT clips (fit above never saw this partition) ===")
    let heldOutSamples = await collect(keys: testKeys)

    // This is the CLOSING evidence (full held-out sample per class, hundreds-to-thousands of
    // points, not a single low-n bin): raw-score ECE vs. calibrated ECE, same held-out partition,
    // same clips -- a true before/after, unlike the single-confidence-point table below which
    // remaps which clips even fall in the window. Cross-class ECE SPREAD (max-min across the 6
    // classes) answers the actual question item 3 was about: is confidence comparable across
    // classes now, measured over each class's whole calibration curve, not one noisy point.
    print("\n=== CLOSING EVIDENCE: per-class ECE, raw vs. calibrated, same held-out partition (full n, not a single bin) ===")
    var rawECEs: [Double] = [], calECEs: [Double] = []
    for c in coarseClasses {
        let raw = heldOutSamples[c] ?? []
        guard let model = models[c], !raw.isEmpty else { continue }
        let calibrated = raw.map { (conf: model.predict($0.score), positive: $0.positive) }
        let aucRaw = aucOf(raw)
        let aucCal = aucOf(raw.map { (score: model.predict($0.score), positive: $0.positive) })
        let trainECE = computeECE((trainSamples[c] ?? []).map { (conf: model.predict($0.score), positive: $0.positive) })
        let rawHeldOutECE = computeECE(raw.map { (conf: $0.score, positive: $0.positive) })
        let calHeldOutECE = computeECE(calibrated)
        rawECEs.append(rawHeldOutECE); calECEs.append(calHeldOutECE)
        let overfitFlag = calHeldOutECE > trainECE + 0.05 ? "  <-- WATCH: held-out ECE notably worse than train, possible overfit" : ""
        print(String(format: "  [%@] n=%d  AUC raw=%.3f cal=%.3f (should match)  |  ECE raw=%.3f -> calibrated=%.3f (train was %.3f)%@",
                      c, raw.count, aucRaw, aucCal, rawHeldOutECE, calHeldOutECE, trainECE, overfitFlag))
    }
    if rawECEs.count >= 2 && calECEs.count >= 2 {
        let rawSpread = rawECEs.max()! - rawECEs.min()!
        let calSpread = calECEs.max()! - calECEs.min()!
        print(String(format: "\n  Cross-class ECE spread (max-min across all 6 classes, held-out, full n): raw=%.3f -> calibrated=%.3f", rawSpread, calSpread))
        print("  This is the item-3 closing metric: is confidence comparable across classes, measured over each class's full curve.")
    }

    func precisionInWindow(_ pairs: [(conf: Double, positive: Bool)], lo: Double, hi: Double) -> (n: Int, prec: Double) {
        let inWindow = pairs.filter { $0.conf >= lo && $0.conf < hi }
        guard !inWindow.isEmpty else { return (0, Double.nan) }
        let hits = inWindow.filter { $0.positive }.count
        return (inWindow.count, Double(hits) / Double(inWindow.count) * 100)
    }

    print("\n=== ILLUSTRATION ONLY, not closing evidence -- single-point cross-class precision at confidence in [0.55, 0.65), held-out ===")
    print("(small per-class n here, esp. after calibration remaps which clips fall in this window -- see the ECE spread above for the real evidence)")
    var beforeVals: [Double] = [], afterVals: [Double] = []
    for c in coarseClasses {
        guard let model = models[c], let raw = heldOutSamples[c] else { continue }
        let before = precisionInWindow(raw.map { (conf: $0.score, positive: $0.positive) }, lo: 0.55, hi: 0.65)
        let after = precisionInWindow(raw.map { (conf: model.predict($0.score), positive: $0.positive) }, lo: 0.55, hi: 0.65)
        if !before.prec.isNaN { beforeVals.append(before.prec) }
        if !after.prec.isNaN { afterVals.append(after.prec) }
        print(String(format: "  [%@] before: n=%d precision=%@   |   after: n=%d precision=%@",
                      c, before.n, before.prec.isNaN ? "N/A" : String(format: "%.1f%%", before.prec),
                      after.n, after.prec.isNaN ? "N/A" : String(format: "%.1f%%", after.prec)))
    }
    if beforeVals.count >= 2 && afterVals.count >= 2 {
        let beforeSpread = beforeVals.max()! - beforeVals.min()!
        let afterSpread = afterVals.max()! - afterVals.min()!
        print(String(format: "\n  (illustration only) cross-class spread at confidence~=0.6: before=%.1fpp -> after=%.1fpp -- noisy, low-n, not the closing metric", beforeSpread, afterSpread))
    }
    print("\n  Note: Strings/Synth is expected to remain the lowest 'after' value here even once honest --")
    print("  calibration fixes what confidence MEANS, not the profile's underlying separating power (AUC).")
}

/// Wiring pre-check (DEVLOG item 3, wiring's first step, per explicit user instruction): "same
/// sample rate" was already verified (calibration fit on `predictInstrumentBreakdown`'s 22050Hz
/// features, matching `DNAReportBuilder`'s `analyticalChunk` branch) -- but rate-equivalence is
/// not feature-VALUE-equivalence. The fit used CPU-only STFT/Mel/MFCC (only HPSS was GPU);
/// production's analytical branch runs the ENTIRE chain (STFT/Mel/MFCC/HPSS) on GPU. This
/// measures, on the same held-out clips: (1) does the raw score value actually match between the
/// CPU path calibration was fit on and the GPU path production actually runs, and (2) does the
/// already-fit (CPU-trained) calibration STAY honest (low ECE) when applied to GPU-computed
/// scores -- the real question wiring depends on, since wiring will apply these exact fitted
/// curves to GPU-computed production scores.
func runInstrumentCalibrationFeaturePathCheck(root: String) async {
    setvbuf(stdout, nil, _IONBF, 0)
    let coarseClasses = ["Piano/Keyboard", "Bass (Acoustic/Electric)", "Brass/Trumpet",
                          "Vocals/Chorus", "Drums/Percussion", "Strings/Synth"]
    let base = URL(fileURLWithPath: root).resolvingSymlinksInPath()
    let csvURL = base.appendingPathComponent("openmic-2018-aggregated-labels.csv")
    guard let csv = try? String(contentsOf: csvURL, encoding: .utf8) else {
        print("ERROR: could not read OpenMIC CSVs"); return
    }
    var relevantFine: [String: [String]] = [:]
    for (fine, coarses) in openmicToCoarse { for c in coarses { relevantFine[c, default: []].append(fine) } }
    enum Truth { case positive, negative, unknown }

    func loadTruth(keys keySet: Set<String>) -> (known: [String: Set<String>], positiveFine: [String: Set<String>]) {
        var known: [String: Set<String>] = [:]
        var positiveFine: [String: Set<String>] = [:]
        for line in csv.split(separator: "\n").dropFirst() {
            let cols = line.split(separator: ",")
            guard cols.count >= 3, let relevance = Double(cols[2]) else { continue }
            let key = String(cols[0]), inst = String(cols[1])
            guard keySet.contains(key) else { continue }
            known[key, default: []].insert(inst)
            if relevance >= 0.5 { positiveFine[key, default: []].insert(inst) }
        }
        return (known, positiveFine)
    }
    func truth(coarse: String, clip: String, known: [String: Set<String>], positiveFine: [String: Set<String>]) -> Truth {
        let rel = relevantFine[coarse] ?? []
        if rel.contains(where: { (positiveFine[clip] ?? []).contains($0) }) { return .positive }
        if rel.contains(where: { (known[clip] ?? []).contains($0) }) { return .negative }
        return .unknown
    }

    // ---- FIT: identical to runInstrumentThresholdCalibration -- same train sample, same method
    // rule, so the models applied below are the EXACT ones item 3's closing evidence covers. ----
    let trainURL = base.appendingPathComponent("partitions/split01_train.csv")
    guard let trainList = try? String(contentsOf: trainURL, encoding: .utf8) else {
        print("ERROR: could not read split01_train.csv"); return
    }
    let allTrainKeys = trainList.split(separator: "\n").map(String.init)
    let trainLimit = envLimit("RA_INSTRUMENT_CALIBRATION_LIMIT", default: 5000)
    let trainKeys = Set(thinned(allTrainKeys, limit: trainLimit))
    print("=== Re-fitting calibration on \(trainKeys.count) TRAIN clips (same as item 3's closing evidence) ===")
    let (trainKnown, trainPos) = loadTruth(keys: trainKeys)
    var trainSamples: [String: [(score: Double, positive: Bool)]] = [:]
    for c in coarseClasses { trainSamples[c] = [] }
    var trainEvaluated = 0
    for key in trainKeys.sorted() {
        guard coarseClasses.contains(where: { truth(coarse: $0, clip: key, known: trainKnown, positiveFine: trainPos) != .unknown }) else { continue }
        let prefix = String(key.prefix(3))
        let audioURL = base.appendingPathComponent("audio/\(prefix)/\(key).ogg")
        guard FileManager.default.fileExists(atPath: audioURL.path) else { continue }
        guard let buf = try? await AudioLoader.load(url: audioURL, targetSampleRate: 22050) else { continue }
        let breakdown = await predictInstrumentBreakdown(samples: buf.samples, sampleRate: 22050)
        var scoreByLabel: [String: Float] = [:]
        for b in breakdown { scoreByLabel[b.label] = b.total }
        trainEvaluated += 1
        for c in coarseClasses {
            let t = truth(coarse: c, clip: key, known: trainKnown, positiveFine: trainPos)
            guard t != .unknown, let s = scoreByLabel[c] else { continue }
            trainSamples[c]!.append((score: Double(s), positive: t == .positive))
        }
        if trainEvaluated % 1000 == 0 { print("  ... \(trainEvaluated) train clips scored") }
    }
    var models: [String: CalibModel] = [:]
    for c in coarseClasses {
        let pairs = trainSamples[c] ?? []
        models[c] = pairs.count < 600 ? .platt(fitPlatt(pairs)) : .isotonic(fitIsotonic(pairs))
    }
    print("  Fit done: \(coarseClasses.map { "\($0)=\(models[$0]!.name)" }.joined(separator: ", "))")

    // ---- HELD-OUT: CPU (fit path) vs GPU (production's real analytical-branch path), same clips ----
    let testURL = base.appendingPathComponent("partitions/split01_test.csv")
    guard let testList = try? String(contentsOf: testURL, encoding: .utf8) else {
        print("ERROR: could not read split01_test.csv"); return
    }
    let allTestKeys = testList.split(separator: "\n").map(String.init)
    let heldOutLimit = envLimit("RA_INSTRUMENT_FEATUREPATH_LIMIT", default: 2000)
    let testKeys = Set(thinned(allTestKeys, limit: heldOutLimit))
    print("\n=== Comparing CPU (fit path) vs GPU (production path) on \(testKeys.count) HELD-OUT clips (fit above never saw this partition) ===")
    let (testKnown, testPos) = loadTruth(keys: testKeys)

    var cpuSamples: [String: [(score: Double, positive: Bool)]] = [:]
    var gpuSamples: [String: [(score: Double, positive: Bool)]] = [:]
    var absDiffSum: [String: Double] = [:], absDiffMax: [String: Double] = [:], diffN: [String: Int] = [:]
    for c in coarseClasses { cpuSamples[c] = []; gpuSamples[c] = []; absDiffSum[c] = 0; absDiffMax[c] = 0; diffN[c] = 0 }

    var evaluated = 0
    for key in testKeys.sorted() {
        guard coarseClasses.contains(where: { truth(coarse: $0, clip: key, known: testKnown, positiveFine: testPos) != .unknown }) else { continue }
        let prefix = String(key.prefix(3))
        let audioURL = base.appendingPathComponent("audio/\(prefix)/\(key).ogg")
        guard FileManager.default.fileExists(atPath: audioURL.path) else { continue }
        guard let buf = try? await AudioLoader.load(url: audioURL, targetSampleRate: 22050) else { continue }
        let cpuBreakdown = await predictInstrumentBreakdown(samples: buf.samples, sampleRate: 22050)
        let gpuBreakdown = await predictInstrumentBreakdownGPU(samples: buf.samples, sampleRate: 22050)
        var cpuScore: [String: Float] = [:], gpuScore: [String: Float] = [:]
        for b in cpuBreakdown { cpuScore[b.label] = b.total }
        for b in gpuBreakdown { gpuScore[b.label] = b.total }
        evaluated += 1
        for c in coarseClasses {
            let t = truth(coarse: c, clip: key, known: testKnown, positiveFine: testPos)
            guard t != .unknown, let cs = cpuScore[c], let gs = gpuScore[c] else { continue }
            cpuSamples[c]!.append((score: Double(cs), positive: t == .positive))
            gpuSamples[c]!.append((score: Double(gs), positive: t == .positive))
            let d = Double(abs(cs - gs))
            absDiffSum[c]! += d; absDiffMax[c] = max(absDiffMax[c]!, d); diffN[c]! += 1
        }
        if evaluated % 500 == 0 { print("  ... \(evaluated) clips scored") }
    }

    guard evaluated > 0 else { print("no files evaluated"); return }
    print("\n=== Feature-value equivalence: |CPU score - GPU score|, same clips, same class ===")
    for c in coarseClasses {
        let n = diffN[c] ?? 0
        guard n > 0 else { continue }
        let meanDiff = absDiffSum[c]! / Double(n)
        print(String(format: "  [%@] n=%d  mean|CPU-GPU|=%.4f  max|CPU-GPU|=%.4f", c, n, meanDiff, absDiffMax[c]!))
    }

    print("\n=== The real wiring question: does the CPU-fit calibration stay honest when applied to GPU (production) scores? ===")
    for c in coarseClasses {
        guard let model = models[c] else { continue }
        let cpuPairs = cpuSamples[c] ?? [], gpuPairs = gpuSamples[c] ?? []
        guard !cpuPairs.isEmpty, !gpuPairs.isEmpty else { continue }
        let cpuECE = computeECE(cpuPairs.map { (conf: model.predict($0.score), positive: $0.positive) })
        let gpuECE = computeECE(gpuPairs.map { (conf: model.predict($0.score), positive: $0.positive) })
        let aucCpuRaw = aucOf(cpuPairs), aucGpuRaw = aucOf(gpuPairs)
        let flag = gpuECE > cpuECE + 0.03 ? "  <-- WATCH: calibration meaningfully less honest on GPU (production) path than on the CPU path it was fit on" : ""
        print(String(format: "  [%@] n=%d  ECE via CPU-scores=%.3f  ECE via GPU-scores=%.3f  (raw AUC CPU=%.3f GPU=%.3f)%@",
                      c, cpuPairs.count, cpuECE, gpuECE, aucCpuRaw, aucGpuRaw, flag))
    }
    print("\n  If no WATCH flags above: the CPU-fit calibration parameters are safe to embed as-is for production wiring.")
    print("  If any WATCH flag: refit calibration using predictInstrumentBreakdownGPU (GPU features) instead, before wiring.")
}

/// Fits calibration (same train sample, same method rule as item 3's closing evidence) and
/// prints the EXACT fitted parameters as ready-to-paste Swift literals, for embedding into
/// `InstrumentCalibration.swift` -- avoids hand-transcribing numbers from log output, which is
/// itself exactly the kind of silent-copy-error this session's discipline exists to prevent.
func runInstrumentCalibrationDump(root: String) async {
    setvbuf(stdout, nil, _IONBF, 0)
    let coarseClasses = ["Piano/Keyboard", "Bass (Acoustic/Electric)", "Brass/Trumpet",
                          "Vocals/Chorus", "Drums/Percussion", "Strings/Synth"]
    let base = URL(fileURLWithPath: root).resolvingSymlinksInPath()
    let csvURL = base.appendingPathComponent("openmic-2018-aggregated-labels.csv")
    guard let csv = try? String(contentsOf: csvURL, encoding: .utf8) else {
        print("ERROR: could not read OpenMIC CSVs"); return
    }
    var relevantFine: [String: [String]] = [:]
    for (fine, coarses) in openmicToCoarse { for c in coarses { relevantFine[c, default: []].append(fine) } }
    enum Truth { case positive, negative, unknown }
    func truth(coarse: String, clip: String, known: [String: Set<String>], positiveFine: [String: Set<String>]) -> Truth {
        let rel = relevantFine[coarse] ?? []
        if rel.contains(where: { (positiveFine[clip] ?? []).contains($0) }) { return .positive }
        if rel.contains(where: { (known[clip] ?? []).contains($0) }) { return .negative }
        return .unknown
    }

    let trainURL = base.appendingPathComponent("partitions/split01_train.csv")
    guard let trainList = try? String(contentsOf: trainURL, encoding: .utf8) else {
        print("ERROR: could not read split01_train.csv"); return
    }
    let allTrainKeys = trainList.split(separator: "\n").map(String.init)
    let trainLimit = envLimit("RA_INSTRUMENT_CALIBRATION_LIMIT", default: 5000)
    let trainKeys = Set(thinned(allTrainKeys, limit: trainLimit))
    var known: [String: Set<String>] = [:]
    var positiveFine: [String: Set<String>] = [:]
    for line in csv.split(separator: "\n").dropFirst() {
        let cols = line.split(separator: ",")
        guard cols.count >= 3, let relevance = Double(cols[2]) else { continue }
        let key = String(cols[0]), inst = String(cols[1])
        guard trainKeys.contains(key) else { continue }
        known[key, default: []].insert(inst)
        if relevance >= 0.5 { positiveFine[key, default: []].insert(inst) }
    }
    var trainSamples: [String: [(score: Double, positive: Bool)]] = [:]
    for c in coarseClasses { trainSamples[c] = [] }
    var evaluated = 0
    for key in trainKeys.sorted() {
        guard coarseClasses.contains(where: { truth(coarse: $0, clip: key, known: known, positiveFine: positiveFine) != .unknown }) else { continue }
        let prefix = String(key.prefix(3))
        let audioURL = base.appendingPathComponent("audio/\(prefix)/\(key).ogg")
        guard FileManager.default.fileExists(atPath: audioURL.path) else { continue }
        guard let breakdown = await predictInstrumentBreakdownProductionMix(url: audioURL, sampleRate: 22050) else { continue }
        var scoreByLabel: [String: Float] = [:]
        for b in breakdown { scoreByLabel[b.label] = b.total }
        evaluated += 1
        for c in coarseClasses {
            let t = truth(coarse: c, clip: key, known: known, positiveFine: positiveFine)
            guard t != .unknown, let s = scoreByLabel[c] else { continue }
            trainSamples[c]!.append((score: Double(s), positive: t == .positive))
        }
        if evaluated % 1000 == 0 { print("  ... \(evaluated) train clips scored") }
    }

    print("\n=== Swift literals for InstrumentCalibration.swift ===\n")
    for c in coarseClasses {
        let pairs = trainSamples[c] ?? []
        if pairs.count < 600 {
            let m = fitPlatt(pairs)
            print("    \"\(c)\": .platt(Platt(A: \(m.A), B: \(m.B))),")
        } else {
            let m = fitIsotonic(pairs)
            let blockStrs = m.blocks.map { "(xMin: \($0.xMin), xMax: \($0.xMax), y: \($0.y))" }
            print("    \"\(c)\": .isotonic(Isotonic(blocks: [ // \(m.blocks.count) blocks")
            for s in blockStrs { print("        \(s),") }
            print("    ])),")
        }
    }
    print("\n=== end literals ===")
}

/// Wiring's closing evidence (DEVLOG item 3, requested explicitly before treating wiring as
/// done): does production's REAL calibrated confidence (`AudioIntelligence().
/// analyzeRawAggregate(url:)` -> `analysis.instruments.predictions`, i.e. the full
/// `DNAReportBuilder` -> `InstrumentEngine.predict()` -> `InstrumentCalibration.calibrate()`
/// path) match the offline pipeline's calibrated confidence (a fresh deterministic re-fit on the
/// same train sample, applied to `predictInstrumentBreakdown`'s raw score) on the same held-out
/// clips? The earlier feature-path check confirmed the INPUT (raw score) is byte-identical
/// between CPU (fit path) and GPU (production path); this checks the OUTPUT/transform --
/// specifically whether the parameters embedded in `InstrumentCalibration.swift` are the right
/// numbers, mapped to the right class, applied with the right (isotonic-interpolation / Platt)
/// logic. Two independent implementations (production's `InstrumentCalibration` vs. this file's
/// own `PlattModel`/`IsotonicModel`) producing the same number is real evidence, not a tautology.
func runInstrumentCalibrationWiringIdentityCheck(root: String, perClassLimit: Int) async {
    setvbuf(stdout, nil, _IONBF, 0)
    let coarseClasses = ["Piano/Keyboard", "Bass (Acoustic/Electric)", "Brass/Trumpet",
                          "Vocals/Chorus", "Drums/Percussion", "Strings/Synth"]
    let base = URL(fileURLWithPath: root).resolvingSymlinksInPath()
    let csvURL = base.appendingPathComponent("openmic-2018-aggregated-labels.csv")
    let testURL = base.appendingPathComponent("partitions/split01_test.csv")
    guard let csv = try? String(contentsOf: csvURL, encoding: .utf8),
          let testList = try? String(contentsOf: testURL, encoding: .utf8) else {
        print("ERROR: could not read OpenMIC CSVs"); return
    }
    let testKeys = Set(testList.split(separator: "\n").map(String.init))
    var positives: [String: Set<String>] = [:]
    for line in csv.split(separator: "\n").dropFirst() {
        let cols = line.split(separator: ",")
        guard cols.count >= 3, let relevance = Double(cols[2]) else { continue }
        if relevance >= 0.5 { positives[String(cols[0]), default: []].insert(String(cols[1])) }
    }
    var keysByCoarse: [String: [String]] = [:]
    for key in testKeys.sorted() {
        guard let fine = positives[key] else { continue }
        let mapped = Set(fine.compactMap { openmicToSingleCoarseForDiscrimination[$0] })
        guard mapped.count == 1, let trueCoarse = mapped.first else { continue }
        keysByCoarse[trueCoarse, default: []].append(key)
    }

    // Re-fit (deterministic: same train sample, same Newton's/PAVA fit -> same numbers every
    // time, already confirmed identical across three separate earlier runs of this exact fit).
    let trainURL = base.appendingPathComponent("partitions/split01_train.csv")
    guard let trainList = try? String(contentsOf: trainURL, encoding: .utf8) else {
        print("ERROR: could not read split01_train.csv"); return
    }
    var trainKnown: [String: Set<String>] = [:], trainPos: [String: Set<String>] = [:]
    var relevantFine: [String: [String]] = [:]
    for (fine, coarses) in openmicToCoarse { for c in coarses { relevantFine[c, default: []].append(fine) } }
    let allTrainKeys = trainList.split(separator: "\n").map(String.init)
    let trainLimit = envLimit("RA_INSTRUMENT_CALIBRATION_LIMIT", default: 5000)
    let trainKeys = Set(thinned(allTrainKeys, limit: trainLimit))
    for line in csv.split(separator: "\n").dropFirst() {
        let cols = line.split(separator: ",")
        guard cols.count >= 3, let relevance = Double(cols[2]) else { continue }
        let key = String(cols[0]), inst = String(cols[1])
        guard trainKeys.contains(key) else { continue }
        trainKnown[key, default: []].insert(inst)
        if relevance >= 0.5 { trainPos[key, default: []].insert(inst) }
    }
    enum Truth { case positive, negative, unknown }
    func truth(coarse: String, clip: String, known: [String: Set<String>], pos: [String: Set<String>]) -> Truth {
        let rel = relevantFine[coarse] ?? []
        if rel.contains(where: { (pos[clip] ?? []).contains($0) }) { return .positive }
        if rel.contains(where: { (known[clip] ?? []).contains($0) }) { return .negative }
        return .unknown
    }
    var trainSamples: [String: [(score: Double, positive: Bool)]] = [:]
    for c in coarseClasses { trainSamples[c] = [] }
    // NOT actually bit-for-bit reproducible run-to-run: DEVLOG Phase 39 confirmed (not just
    // hypothesized) that two re-fits on this same nominal 5000-clip sample can produce
    // different isotonic block y-values, traced to AVFoundation decode noise propagating into
    // training raw scores. Left un-renamed as a marker of that finding, not a correctness claim.
    print("=== Re-fitting (\"deterministic\") on \(trainKeys.count) train clips ===")
    var trainEvaluated = 0
    for key in trainKeys.sorted() {
        guard coarseClasses.contains(where: { truth(coarse: $0, clip: key, known: trainKnown, pos: trainPos) != .unknown }) else { continue }
        let prefix = String(key.prefix(3))
        let audioURL = base.appendingPathComponent("audio/\(prefix)/\(key).ogg")
        guard FileManager.default.fileExists(atPath: audioURL.path) else { continue }
        guard let breakdown = await predictInstrumentBreakdownProductionMix(url: audioURL, sampleRate: 22050) else { continue }
        var scoreByLabel: [String: Float] = [:]
        for b in breakdown { scoreByLabel[b.label] = b.total }
        trainEvaluated += 1
        for c in coarseClasses {
            let t = truth(coarse: c, clip: key, known: trainKnown, pos: trainPos)
            guard t != .unknown, let s = scoreByLabel[c] else { continue }
            trainSamples[c]!.append((score: Double(s), positive: t == .positive))
        }
        if trainEvaluated % 1000 == 0 { print("  ... \(trainEvaluated) train clips") }
    }
    var offlineModels: [String: CalibModel] = [:]
    for c in coarseClasses {
        let pairs = trainSamples[c] ?? []
        offlineModels[c] = pairs.count < 600 ? .platt(fitPlatt(pairs)) : .isotonic(fitIsotonic(pairs))
    }

    print("\n=== Identity check: production predict() calibrated confidence vs. offline pipeline, same clips ===")
    var evaluated = 0
    var maxDiff = 0.0
    var mismatches: [String] = []
    for coarse in coarseClasses {
        let keys = thinned(keysByCoarse[coarse] ?? [], limit: perClassLimit)
        for key in keys {
            let prefix = String(key.prefix(3))
            let audioURL = base.appendingPathComponent("audio/\(prefix)/\(key).ogg")
            guard let offlineBreakdown = await predictInstrumentBreakdownProductionMix(url: audioURL, sampleRate: 22050) else { continue }
            guard let offlineScore = offlineBreakdown.first(where: { $0.label == coarse })?.total,
                  let offlineModel = offlineModels[coarse] else { continue }
            let offlineCalibrated = offlineModel.predict(Double(offlineScore))

            guard let analysis = try? await AudioIntelligence().analyzeRawAggregate(url: audioURL) else { continue }
            guard let productionPred = analysis.instruments.predictions.first(where: { $0.label == coarse }) else {
                // Below the 0.3 inclusion cutoff in production for this clip/class -- can't compare confidence.
                continue
            }
            let productionCalibrated = Double(productionPred.confidence)

            evaluated += 1
            let diff = abs(offlineCalibrated - productionCalibrated)
            maxDiff = max(maxDiff, diff)
            if diff > 1e-6 {
                mismatches.append("\(key) [\(coarse)]: offline=\(offlineCalibrated) production=\(productionCalibrated) diff=\(diff)")
            }
        }
    }
    guard evaluated > 0 else { print("no comparable (clip, class) pairs found -- check inclusion cutoffs"); return }
    print("evaluated=\(evaluated) (clip, class) pairs where both paths included the label")
    print(String(format: "max|offline - production| = %.8f", maxDiff))
    if mismatches.isEmpty {
        print("PASS: production's calibrated confidence matches the offline pipeline's exactly, on every evaluated pair. Wiring is correct.")
    } else {
        print("FAIL: \(mismatches.count) mismatches found -- the embedded InstrumentCalibration parameters or class mapping have a bug:")
        mismatches.prefix(20).forEach { print("  \($0)") }
    }
}

func runIRMASTask(root: String) async -> TaskResult {
    let base = URL(fileURLWithPath: root).resolvingSymlinksInPath()
    guard let classDirs = try? FileManager.default.contentsOfDirectory(at: base, includingPropertiesForKeys: nil) else {
        return TaskResult(name: "instrument_irmas", status: "not_available", metric: nil, value: nil,
                           sampleCount: nil, dataset: "IRMAS", note: "\(root) not found")
    }
    let perClassLimit = envLimit("RA_IRMAS_PER_CLASS", default: 15)
    let verbose = ProcessInfo.processInfo.environment["RA_IRMAS_VERBOSE"] == "1"
    // [trueIRMAScode][predictedCoarseLabel] = count — full confusion matrix, raw counts.
    var confusion: [String: [String: Int]] = [:]
    var hit = 0, n = 0
    for dir in classDirs.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
        let code = dir.lastPathComponent
        guard let acceptable = irmasToCoarse[code] else { continue }
        guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            .filter({ $0.pathExtension.lowercased() == "wav" }) else { continue }
        var classHit = 0, classN = 0
        var labelCounts: [String: Int] = [:]
        for f in thinned(files.sorted { $0.path < $1.path }, limit: perClassLimit) {
            guard let buf = try? await AudioLoader.load(url: f, targetSampleRate: 22050) else { continue }
            let label = await predictInstrument(samples: buf.samples, sampleRate: 22050)
            if acceptable.contains(label) { hit += 1; classHit += 1 }
            n += 1; classN += 1
            labelCounts[label, default: 0] += 1
            confusion[code, default: [:]][label, default: 0] += 1
        }
        if verbose && classN > 0 {
            let dist = labelCounts.sorted { $0.value > $1.value }.map { "\($0.key)=\($0.value)" }.joined(separator: ", ")
            print("  [\(code)] acceptable=\(acceptable) hit=\(classHit)/\(classN) (\(Int(Double(classHit)/Double(classN)*100))%) predicted: \(dist)")
        }
    }
    if verbose {
        printConfusionMatrix(confusion, trueClassAcceptable: irmasToCoarse)
    }
    guard n > 0 else {
        return TaskResult(name: "instrument_irmas", status: "not_available", metric: nil, value: nil,
                           sampleCount: 0, dataset: "IRMAS", note: "no files loaded")
    }
    return TaskResult(name: "instrument_irmas", status: "measured",
                       metric: "primaryLabel in acceptable set (%)",
                       value: Double(hit) / Double(n) * 100, sampleCount: n,
                       dataset: "IRMAS (11-class, single predominant label, 6,718 files total)", note: nil)
}

// MARK: - Task 4: Instrument (OpenMIC)

func runOpenMICTask(root: String) async -> TaskResult {
    let base = URL(fileURLWithPath: root).resolvingSymlinksInPath()
    let csvURL = base.appendingPathComponent("openmic-2018-aggregated-labels.csv")
    guard let csv = try? String(contentsOf: csvURL, encoding: .utf8) else {
        return TaskResult(name: "instrument_openmic", status: "not_available", metric: nil, value: nil,
                           sampleCount: nil, dataset: "OpenMIC-2018", note: "aggregated-labels.csv not found at \(csvURL.path)")
    }
    // sample_key -> set of positive (relevance >= 0.5) fine-grained instrument labels.
    // Per the OpenMIC-2018 paper (Fig. 5): 0.5 relevance is the paper's own majority-vote
    // threshold for "present". Pairs never annotated simply never appear in this CSV — they
    // are NOT treated as negative, only rows that exist are used.
    var positives: [String: Set<String>] = [:]
    for line in csv.split(separator: "\n").dropFirst() {
        let cols = line.split(separator: ",")
        guard cols.count >= 3, let relevance = Double(cols[2]) else { continue }
        if relevance >= 0.5 {
            positives[String(cols[0]), default: []].insert(String(cols[1]))
        }
    }

    // RA_OPENMIC_TEST_ONLY=1 restricts evaluation to OpenMIC-2018's official held-out test
    // partition (`partitions/split01_test.csv`) — the partition `Examples/PrototypeTrainer`
    // never touches. Since `InstrumentEngine`'s fingerprints (Phase 16) were fit on the TRAIN
    // partition, this is what makes a post-training accuracy measurement fair rather than
    // contaminated (the classifier being tested on data it was fit to).
    var candidateKeys = Array(positives.keys).sorted()
    if ProcessInfo.processInfo.environment["RA_OPENMIC_TEST_ONLY"] == "1" {
        let testURL = base.appendingPathComponent("partitions/split01_test.csv")
        guard let testList = try? String(contentsOf: testURL, encoding: .utf8) else {
            return TaskResult(name: "instrument_openmic", status: "not_available", metric: nil, value: nil,
                               sampleCount: nil, dataset: "OpenMIC-2018", note: "split01_test.csv not found at \(testURL.path)")
        }
        let testKeys = Set(testList.split(separator: "\n").map(String.init))
        candidateKeys = candidateKeys.filter { testKeys.contains($0) }
    }

    let limit = envLimit("RA_OPENMIC_LIMIT", default: 60)
    let keys = thinned(candidateKeys, limit: limit)

    // RA_OPENMIC_VERBOSE=1: per-fine-class recall, restricted to clips whose ENTIRE positive
    // label set maps unambiguously to a single coarse class (same purity filter PrototypeTrainer
    // uses for training) — the cleanest apples-to-apples per-class comparison against the
    // Phase 16 baseline numbers (Bass 48%/62%, Brass 13%, etc.), not muddied by OpenMIC's
    // multi-label "acceptable set" leniency.
    let verbose = ProcessInfo.processInfo.environment["RA_OPENMIC_VERBOSE"] == "1"
    var classHit: [String: Int] = [:], classN: [String: Int] = [:]

    var hit = 0, n = 0, loadFailures = 0
    for key in keys {
        guard let fine = positives[key] else { continue }
        let acceptable = Set(fine.flatMap { openmicToCoarse[$0] ?? [] })
        guard !acceptable.isEmpty else { continue }
        let prefix = String(key.prefix(3))
        let audioURL = base.appendingPathComponent("audio/\(prefix)/\(key).ogg")
        guard FileManager.default.fileExists(atPath: audioURL.path) else { continue }
        guard let buf = try? await AudioLoader.load(url: audioURL, targetSampleRate: 22050) else {
            loadFailures += 1
            continue
        }
        let label = await predictInstrument(samples: buf.samples, sampleRate: 22050)
        if acceptable.contains(label) { hit += 1 }
        n += 1

        if verbose {
            let single = Set(fine.compactMap { openmicToSingleCoarseForDiscrimination[$0] })
            if single.count == 1, let coarse = single.first {
                classN[coarse, default: 0] += 1
                if label == coarse { classHit[coarse, default: 0] += 1 }
            }
        }
    }
    if verbose {
        print("  --- OpenMIC per-class recall (unambiguous single-coarse-class clips only) ---")
        for cls in classN.keys.sorted() {
            let c = classHit[cls] ?? 0, total = classN[cls] ?? 0
            print("  [\(cls)] recall=\(c)/\(total) (\(total > 0 ? Int(Double(c)/Double(total)*100) : 0)%)")
        }
    }
    guard n > 0 else {
        let note = loadFailures > 0
            ? "\(loadFailures) file(s) found but failed to decode (likely missing OGG/Vorbis codec support) — audio format may not be readable on this platform"
            : "no matching audio files found under \(base.path)/audio/"
        return TaskResult(name: "instrument_openmic", status: "not_available", metric: nil, value: nil,
                           sampleCount: 0, dataset: "OpenMIC-2018", note: note)
    }
    let testOnly = ProcessInfo.processInfo.environment["RA_OPENMIC_TEST_ONLY"] == "1"
    let note = loadFailures > 0 ? "\(loadFailures) file(s) failed to decode and were skipped" : nil
    return TaskResult(name: "instrument_openmic", status: "measured",
                       metric: "primaryLabel in acceptable set (%)",
                       value: Double(hit) / Double(n) * 100, sampleCount: n,
                       dataset: "OpenMIC-2018 (20-class, multi-label, relevance≥0.5 threshold, 20,000 clips total\(testOnly ? " — held-out test partition only" : ""))", note: note)
}

// MARK: - Task 5: Pitch / f0 (MDB-stem-synth)

/// Was plain `YINEngine.analyze()` -- silently stale as of DEVLOG Phase 33, which switched
/// `DNAReportBuilder.swift`'s real per-chunk pitch call to pYIN (RPA/voicing measured there at
/// 61.6%/85.3% vs. YIN's 50.6%/77.8%, on a 20-stem sample in `PYINEngineTests.swift`). This
/// scorecard task reported YIN's number as "current" even after production moved on -- exactly
/// the isolated-vs-production drift found while investigating open-items list item 2's Stage 1.
/// Switched to `analyzePYINCandidates` + `PYINDecoder`, matching production's real call, and
/// reports voicing accuracy alongside RPA (not just RPA) since that's pYIN's larger real gain.
func runPitchTask(root: String) async -> [TaskResult] {
    let audioDir = URL(fileURLWithPath: root).resolvingSymlinksInPath().appendingPathComponent("audio_stems")
    let annotDir = URL(fileURLWithPath: root).resolvingSymlinksInPath().appendingPathComponent("annotation_stems")
    guard let files = try? FileManager.default.contentsOfDirectory(at: audioDir, includingPropertiesForKeys: nil)
        .filter({ $0.pathExtension.lowercased() == "wav" }) else {
        return [TaskResult(name: "pitch_f0", status: "not_available", metric: nil, value: nil,
                            sampleCount: nil, dataset: "MDB-stem-synth", note: "\(audioDir.path) not found")]
    }
    let limit = envLimit("RA_PITCH_LIMIT", default: 12)
    let sr = 44100.0, hop = 512
    let gtHopSeconds = 128.0 / 44100.0 // MDB-stem-synth annotation grid: hop=128 @ 44.1kHz
    let decoder = PYINDecoder()

    var rpaCorrect = 0, rpaTotal = 0
    var voicingCorrect = 0, voicingTotal = 0
    for f in thinned(files.sorted { $0.path < $1.path }, limit: limit) {
        let stem = f.deletingPathExtension().lastPathComponent
        let annotURL = annotDir.appendingPathComponent("\(stem).csv")
        guard let csv = try? String(contentsOf: annotURL, encoding: .utf8),
              let buf = try? await AudioLoader.load(url: f, targetSampleRate: sr) else { continue }

        var gtF0: [Float] = []
        for line in csv.split(separator: "\n") {
            let cols = line.split(separator: ",")
            guard cols.count >= 2, let f0 = Float(cols[1]) else { continue }
            gtF0.append(f0)
        }
        guard !gtF0.isEmpty else { continue }

        let yinEngine = YINEngine(sampleRate: sr, hopLength: hop)
        let candidates = yinEngine.analyzePYINCandidates(samples: buf.samples)
        let pyinPath = decoder.decode(candidatesPerFrame: candidates)

        for (i, estF0) in pyinPath.enumerated() {
            let t = Double(i * hop) / sr
            let gtIdx = Int((t / gtHopSeconds).rounded())
            guard gtIdx >= 0, gtIdx < gtF0.count else { continue }
            let trueF0 = gtF0[gtIdx]
            let trueVoiced = trueF0 > 0
            let estVoiced = estF0.isFinite && estF0 > 0

            voicingTotal += 1
            if trueVoiced == estVoiced { voicingCorrect += 1 }

            guard trueVoiced else { continue } // RPA only scored over true-voiced frames
            rpaTotal += 1
            guard estVoiced else { continue } // ours says unvoiced -> miss
            let cents = abs(1200.0 * log2f(estF0 / trueF0))
            if cents < 50 { rpaCorrect += 1 } // standard Raw Pitch Accuracy (RPA) tolerance
        }
    }
    guard rpaTotal > 0 else {
        return [TaskResult(name: "pitch_f0", status: "not_available", metric: nil, value: nil,
                            sampleCount: 0, dataset: "MDB-stem-synth", note: "no voiced frames scored")]
    }
    let dataset = "MDB-stem-synth (synthesis-derived ground truth, 230 stems total)"
    return [
        TaskResult(name: "pitch_f0_rpa", status: "measured", metric: "pYIN Raw Pitch Accuracy, <50 cents (%)",
                   value: Double(rpaCorrect) / Double(rpaTotal) * 100, sampleCount: rpaTotal, dataset: dataset, note: nil),
        TaskResult(name: "pitch_f0_voicing", status: "measured", metric: "pYIN voicing accuracy (%)",
                   value: Double(voicingCorrect) / Double(voicingTotal) * 100, sampleCount: voicingTotal, dataset: dataset, note: nil),
    ]
}

/// Cheap production-vs-isolated confirmation for Pitch (DEVLOG Phase 35): unlike Instrument,
/// `runPitchTask` and `DNAReportBuilder.swift` both already use pYIN at the file's native rate (no
/// forced 22050 resample in either), so they were EXPECTED to already agree -- but "expected to
/// agree" is exactly the assumption that hid Instrument's 45% disagreement for who knows how long,
/// so this checks rather than trusts it. Compares isolated pYIN's whole-track mean F0 (same
/// candidates+decoder call `runPitchTask` uses) against production's real `analysis.pitch.meanF0`
/// on the same small sample of files.
func runPitchProductionParityCheck(root: String, limit: Int) async {
    let audioDir = URL(fileURLWithPath: root).resolvingSymlinksInPath().appendingPathComponent("audio_stems")
    guard let files = try? FileManager.default.contentsOfDirectory(at: audioDir, includingPropertiesForKeys: nil)
        .filter({ $0.pathExtension.lowercased() == "wav" }) else {
        print("ERROR: \(audioDir.path) not found"); return
    }
    let decoder = PYINDecoder()
    var deltas: [Double] = []

    print("\n=== Pitch: production (DNAReportBuilder) vs isolated pYIN, same files ===")
    for f in thinned(files.sorted { $0.path < $1.path }, limit: limit) {
        guard let buf = try? await AudioLoader.load(url: f, targetSampleRate: 44100) else { continue }
        let yinEngine = YINEngine(sampleRate: 44100, hopLength: 512)
        let candidates = yinEngine.analyzePYINCandidates(samples: buf.samples)
        let pyinPath = decoder.decode(candidatesPerFrame: candidates)
        let voiced = pyinPath.filter { $0.isFinite && $0 > 0 }
        guard !voiced.isEmpty else { continue }
        let isolatedMeanF0 = voiced.reduce(0, +) / Float(voiced.count)

        guard let analysis = try? await AudioIntelligence().analyzeRawAggregate(url: f) else { continue }
        let productionMeanF0 = analysis.pitch.meanF0
        guard productionMeanF0.isFinite, productionMeanF0 > 0 else {
            print("  \(f.lastPathComponent): isolated=\(isolatedMeanF0)Hz production=UNVOICED/NaN"); continue
        }
        let pctDelta = abs(Double(isolatedMeanF0 - productionMeanF0)) / Double(isolatedMeanF0) * 100
        deltas.append(pctDelta)
        print(String(format: "  %@: isolated=%.1fHz production=%.1fHz delta=%.1f%%", f.lastPathComponent, isolatedMeanF0, productionMeanF0, pctDelta))
    }
    guard !deltas.isEmpty else { print("no files evaluated"); return }
    let meanDelta = deltas.reduce(0, +) / Double(deltas.count)
    print(String(format: "\nmean |isolated-production| relative delta across %d files: %.1f%%", deltas.count, meanDelta))
}

// MARK: - Task 6/7: Chord & Structure — honest gaps

func chordGapResult() -> TaskResult {
    TaskResult(name: "chord", status: "not_available", metric: nil, value: nil, sampleCount: nil,
               dataset: "Isophonics (Beatles) / McGill Billboard",
               note: "Both datasets distribute chord annotations only — no audio (copyright). "
                   + "Needs a legally-owned copy of the matching audio to pair with before this "
                   + "can run end-to-end through the real STFT→chroma→CQT pipeline.")
}

func structureGapResult() -> TaskResult {
    TaskResult(name: "structure", status: "not_available", metric: nil, value: nil, sampleCount: nil,
               dataset: "SALAMI",
               note: "Annotations are open, but audio is split across several original sources "
                   + "(Internet Archive Live Music Archive, RWC, Codaich, Isophonics) requiring "
                   + "per-track matching — no single bulk archive exists. Not yet fetched.")
}

// MARK: - Rendering

func renderTable(_ report: ReliabilityReport) -> String {
    var lines = ["", "┌─ RELIABILITY SCORECARD — \(report.date) ─────────────────────────────",
                 "│ TASK                       METRIC                              VALUE     N       DATASET"]
    for t in report.tasks {
        let status = t.status == "measured" ? "✅" : "⚠️ "
        let metric = t.metric ?? "—"
        let value = t.value.map { String(format: "%.1f", $0) } ?? "—"
        let n = t.sampleCount.map(String.init) ?? "—"
        lines.append("│ \(status) \(t.name.padding(toLength: 20, withPad: " ", startingAt: 0)) \(metric.padding(toLength: 32, withPad: " ", startingAt: 0)) \(value.padding(toLength: 8, withPad: " ", startingAt: 0)) \(n.padding(toLength: 6, withPad: " ", startingAt: 0)) \(t.dataset ?? "")")
        if let note = t.note { lines.append("│    → \(note)") }
    }
    lines.append("└──────────────────────────────────────────────────────────────────────")
    return lines.joined(separator: "\n")
}

// MARK: - Main

@main
struct ReliabilityAudit {
    static func main() async {
        if ProcessInfo.processInfo.environment["RA_SCORE_BREAKDOWN"] == "1" {
            let perClass = envLimit("RA_SCORE_BREAKDOWN_PER_CLASS", default: 5)
            // cla->Piano, org->Vocals are the clearest "black hole" columns from the confusion
            // matrix; gac/sax/pia are included to catch real Bass/Drums-winning misclassifications
            // (both showed 0% precision — need to see what actually wins in their place).
            await runScoreBreakdownDiagnostic(root: "Tests/Resources/IRMAS", codes: ["cla", "org", "gac", "sax", "pia"], perClass: perClass)
            return
        }
        if ProcessInfo.processInfo.environment["RA_MFCC_HISTOGRAM"] == "1" {
            let perClass = envLimit("RA_MFCC_HISTOGRAM_PER_CLASS", default: 0)
            await runMFCCDistanceDiagnostic(root: "Tests/Resources/IRMAS", perClassLimit: perClass)
            return
        }
        if ProcessInfo.processInfo.environment["RA_FEATURE_CHECK"] == "1" {
            let perGroup = envLimit("RA_FEATURE_CHECK_LIMIT", default: 60)
            await runFeatureDiscriminationDiagnostic(root: "Tests/Resources/OpenMIC", perGroupLimit: perGroup)
            return
        }
        if ProcessInfo.processInfo.environment["RA_BASS_BREAKDOWN"] == "1" {
            let limit = envLimit("RA_BASS_BREAKDOWN_LIMIT", default: 10)
            await runBassScoreBreakdownDiagnostic(root: "Tests/Resources/OpenMIC", limit: limit)
            return
        }
        if ProcessInfo.processInfo.environment["RA_OPENMIC_TEST_EVAL"] == "1" {
            let perClassLimit = envLimit("RA_OPENMIC_TEST_PER_CLASS", default: 100)
            await runOpenMICTestPartitionEval(root: "Tests/Resources/OpenMIC", perClassLimit: perClassLimit)
            return
        }
        if ProcessInfo.processInfo.environment["RA_INSTRUMENT_PARITY"] == "1" {
            let perClassLimit = envLimit("RA_INSTRUMENT_PARITY_PER_CLASS", default: 25)
            await runInstrumentProductionParityCheck(root: "Tests/Resources/OpenMIC", perClassLimit: perClassLimit)
            return
        }
        if ProcessInfo.processInfo.environment["RA_INSTRUMENT_MULTILABEL_PARITY"] == "1" {
            let perClassLimit = envLimit("RA_INSTRUMENT_MULTILABEL_PARITY_PER_CLASS", default: 30)
            await runInstrumentMultiLabelParityCheck(root: "Tests/Resources/OpenMIC", perClassLimit: perClassLimit)
            return
        }
        if ProcessInfo.processInfo.environment["RA_INSTRUMENT_MULTILABEL_F1"] == "1" {
            await runInstrumentMultiLabelF1(root: "Tests/Resources/OpenMIC")
            return
        }
        if ProcessInfo.processInfo.environment["RA_INSTRUMENT_RELIABILITY_PRECHECK"] == "1" {
            await runInstrumentReliabilityPrecheck(root: "Tests/Resources/OpenMIC")
            return
        }
        if ProcessInfo.processInfo.environment["RA_INSTRUMENT_CALIBRATION"] == "1" {
            await runInstrumentThresholdCalibration(root: "Tests/Resources/OpenMIC")
            return
        }
        if ProcessInfo.processInfo.environment["RA_INSTRUMENT_CALIBRATION_FEATUREPATH"] == "1" {
            await runInstrumentCalibrationFeaturePathCheck(root: "Tests/Resources/OpenMIC")
            return
        }
        if ProcessInfo.processInfo.environment["RA_INSTRUMENT_CALIBRATION_DUMP"] == "1" {
            await runInstrumentCalibrationDump(root: "Tests/Resources/OpenMIC")
            return
        }
        if ProcessInfo.processInfo.environment["RA_INSTRUMENT_CALIBRATION_WIRING_CHECK"] == "1" {
            let perClassLimit = envLimit("RA_INSTRUMENT_CALIBRATION_WIRING_CHECK_PER_CLASS", default: 25)
            await runInstrumentCalibrationWiringIdentityCheck(root: "Tests/Resources/OpenMIC", perClassLimit: perClassLimit)
            return
        }
        if ProcessInfo.processInfo.environment["RA_PLATT_SELFTEST"] == "1" {
            // Synthetic data shaped like Bass/Vocals: moderately separable, small n, to verify
            // the fitPlatt fix without waiting on the full ~20-40min real pipeline.
            var rng = SystemRandomNumberGenerator()
            func gaussian(mean: Double, sd: Double) -> Double {
                let u1 = Double.random(in: 1e-9...1, using: &rng), u2 = Double.random(in: 0...1, using: &rng)
                return mean + sd * (sqrt(-2 * log(u1)) * cos(2 * .pi * u2))
            }
            var pairs: [(score: Double, positive: Bool)] = []
            for _ in 0..<131 { pairs.append((score: max(0, min(1, gaussian(mean: 0.55, sd: 0.2))), positive: true)) }
            for _ in 0..<309 { pairs.append((score: max(0, min(1, gaussian(mean: 0.30, sd: 0.2))), positive: false)) }
            let aucRaw = aucOf(pairs)
            let model = fitPlatt(pairs)
            let aucCal = aucOf(pairs.map { (score: model.predict($0.score), positive: $0.positive) })
            print("Synthetic Bass-like data: n=\(pairs.count), A=\(model.A), B=\(model.B)")
            print("AUC raw=\(aucRaw)  AUC calibrated=\(aucCal)  (should match, both >0.5)")
            print(String(format: "predict(0.2)=%.3f  predict(0.5)=%.3f  predict(0.8)=%.3f  (should be increasing)", model.predict(0.2), model.predict(0.5), model.predict(0.8)))
            return
        }
        if let key = ProcessInfo.processInfo.environment["RA_INSTRUMENT_FEATURE_DUMP"] {
            await runInstrumentFeatureDump(root: "Tests/Resources/OpenMIC", key: key)
            return
        }
        if ProcessInfo.processInfo.environment["RA_INSTRUMENT_SAMPLE_RATE_COMPARISON"] == "1" {
            let perClassLimit = envLimit("RA_INSTRUMENT_PARITY_PER_CLASS", default: 25)
            await runInstrumentSampleRateComparison(root: "Tests/Resources/OpenMIC", perClassLimit: perClassLimit)
            return
        }
        if ProcessInfo.processInfo.environment["RA_PITCH_PARITY"] == "1" {
            let limit = envLimit("RA_PITCH_PARITY_LIMIT", default: 10)
            await runPitchProductionParityCheck(root: "Tests/Resources/MDBStemSynth", limit: limit)
            return
        }
        if ProcessInfo.processInfo.environment["RA_TEMPO_SAMPLE_RATE_COMPARISON"] == "1" {
            await runTempoSampleRateComparison(goldenRoot: "Examples/Golden")
            return
        }
        if ProcessInfo.processInfo.environment["RA_KEY_SAMPLE_RATE_COMPARISON"] == "1" {
            let limit = envLimit("RA_KEY_SAMPLE_RATE_LIMIT", default: 60)
            await runKeySampleRateComparison(goldenRoot: "Examples/Golden", limit: limit)
            return
        }

        print("🔎 AudioIntelligence Reliability Audit — starting (set RA_*_LIMIT env vars to size the run; 0 = full dataset)")

        var tasks: [TaskResult] = []
        tasks.append(contentsOf: await runTempoTask(goldenRoot: "Examples/Golden"))
        tasks.append(contentsOf: await runKeyTask(goldenRoot: "Examples/Golden"))
        tasks.append(await runIRMASTask(root: "Tests/Resources/IRMAS"))
        tasks.append(await runOpenMICTask(root: "Tests/Resources/OpenMIC"))
        tasks.append(contentsOf: await runPitchTask(root: "Tests/Resources/MDBStemSynth"))
        tasks.append(chordGapResult())
        tasks.append(structureGapResult())

        let report = ReliabilityReport(date: isoDate(), tasks: tasks)
        print(renderTable(report))

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(report) {
            let outURL = URL(fileURLWithPath: "Examples/ReliabilityAudit/reliability_report.json")
            try? data.write(to: outURL)
            print("\n📄 Wrote \(outURL.path)")

            // Append to history so accuracy trends over time/commits are visible.
            let historyURL = URL(fileURLWithPath: "Examples/ReliabilityAudit/history.jsonl")
            if let line = String(data: data, encoding: .utf8)?.replacingOccurrences(of: "\n", with: " ") {
                let existing = (try? String(contentsOf: historyURL, encoding: .utf8)) ?? ""
                try? (existing + line + "\n").write(to: historyURL, atomically: true, encoding: .utf8)
            }
        }
    }
}
