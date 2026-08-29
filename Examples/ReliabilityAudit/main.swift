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
import AudioIntelligenceCore

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

func predictInstrument(samples: [Float], sampleRate: Double) async -> String {
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
    let result = InstrumentEngine().predict(spectral: spectral, mfcc: Array(mfcc.mfcc.prefix(10)))
    return result.primaryLabel
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
        let stft = await STFTEngine(nFFT: 2048, hopLength: 512, sampleRate: 22050).analyze(samples)
        let chroma = ChromaEngine(sampleRate: 22050).chromagram(stft: stft)
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

func runPitchTask(root: String) async -> TaskResult {
    let audioDir = URL(fileURLWithPath: root).resolvingSymlinksInPath().appendingPathComponent("audio_stems")
    let annotDir = URL(fileURLWithPath: root).resolvingSymlinksInPath().appendingPathComponent("annotation_stems")
    guard let files = try? FileManager.default.contentsOfDirectory(at: audioDir, includingPropertiesForKeys: nil)
        .filter({ $0.pathExtension.lowercased() == "wav" }) else {
        return TaskResult(name: "pitch_f0", status: "not_available", metric: nil, value: nil,
                           sampleCount: nil, dataset: "MDB-stem-synth", note: "\(audioDir.path) not found")
    }
    let limit = envLimit("RA_PITCH_LIMIT", default: 12)
    let sr = 44100.0, hop = 512
    let gtHopSeconds = 128.0 / 44100.0 // MDB-stem-synth annotation grid: hop=128 @ 44.1kHz

    var correct = 0, total = 0
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

        let pitch = YINEngine(sampleRate: sr, hopLength: hop).analyze(samples: buf.samples)
        for (i, estF0) in pitch.f0Series.enumerated() {
            let t = Double(i * hop) / sr
            let gtIdx = Int((t / gtHopSeconds).rounded())
            guard gtIdx >= 0, gtIdx < gtF0.count else { continue }
            let trueF0 = gtF0[gtIdx]
            guard trueF0 > 0 else { continue } // only score frames the ground truth says are voiced
            total += 1
            guard estF0.isFinite, estF0 > 0 else { continue } // ours says unvoiced -> miss
            let cents = abs(1200.0 * log2f(estF0 / trueF0))
            if cents < 50 { correct += 1 } // standard Raw Pitch Accuracy (RPA) tolerance
        }
    }
    guard total > 0 else {
        return TaskResult(name: "pitch_f0", status: "not_available", metric: nil, value: nil,
                           sampleCount: 0, dataset: "MDB-stem-synth", note: "no voiced frames scored")
    }
    return TaskResult(name: "pitch_f0", status: "measured", metric: "Raw Pitch Accuracy, <50 cents (%)",
                       value: Double(correct) / Double(total) * 100, sampleCount: total,
                       dataset: "MDB-stem-synth (synthesis-derived ground truth, 230 stems total)", note: nil)
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
        print("🔎 AudioIntelligence Reliability Audit — starting (set RA_*_LIMIT env vars to size the run; 0 = full dataset)")

        var tasks: [TaskResult] = []
        tasks.append(contentsOf: await runTempoTask(goldenRoot: "Examples/Golden"))
        tasks.append(contentsOf: await runKeyTask(goldenRoot: "Examples/Golden"))
        tasks.append(await runIRMASTask(root: "Tests/Resources/IRMAS"))
        tasks.append(await runOpenMICTask(root: "Tests/Resources/OpenMIC"))
        tasks.append(await runPitchTask(root: "Tests/Resources/MDBStemSynth"))
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
