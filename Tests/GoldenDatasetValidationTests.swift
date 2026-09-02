import XCTest
import Foundation
import Darwin
@testable import AudioIntelligenceCore
@testable import AudioIntelligence

/// Multi-source accuracy validation against the GiantSteps Key+Tempo dataset
/// (industry/academic reference, MIREX-standard human-corrected annotations).
///
/// Uses direct engine calls (onset→tempo, chroma→key) rather than the full 26-engine
/// pipeline, so 15 two-minute tracks validate in a reasonable time. This MEASURES real
/// accuracy (tempo MIREX Acc1/Acc2, key exact/enharmonic) to establish a baseline we then
/// optimize — it is a measurement board first, a hard gate second.
final class GoldenDatasetValidationTests: XCTestCase {

    struct Manifest: Codable { let files: [Entry] }
    struct Entry: Codable { let id: String; let file: String; let key: String; let bpm: Int? }

    let goldenRoot = "Examples/Golden"

    private func loadManifest() throws -> Manifest {
        let url = URL(fileURLWithPath: "\(goldenRoot)/manifest.json")
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(Manifest.self, from: data)
    }

    // Normalize a "Root Mode" key string to (pitchClass 0-11, isMinor) with enharmonic folding.
    private func parseKey(_ s: String) -> (pc: Int, minor: Bool)? {
        let parts = s.split(separator: " ")
        guard parts.count == 2 else { return nil }
        let names = ["C": 0, "C#": 1, "DB": 1, "D": 2, "D#": 3, "EB": 3, "E": 4, "F": 5,
                     "F#": 6, "GB": 6, "G": 7, "G#": 8, "AB": 8, "A": 9, "A#": 10, "BB": 10, "B": 11]
        let root = parts[0].uppercased()
        guard let pc = names[root] else { return nil }
        return (pc, parts[1].lowercased().hasPrefix("min"))
    }

    /// MIREX tempo accuracy: Acc1 within 4%; Acc2 also accepts 1/3, 1/2, 2, 3 octave multiples.
    private func tempoAcc(measured: Double, ref: Double) -> (acc1: Bool, acc2: Bool) {
        let acc1 = abs(measured - ref) / ref <= 0.04
        let multiples: [Double] = [1.0 / 3.0, 0.5, 1.0, 2.0, 3.0]
        var acc2 = false
        for m in multiples {
            let target = ref * m
            if target > 0 && abs(measured - target) / target <= 0.04 { acc2 = true; break }
        }
        return (acc1, acc2)
    }

    /// MIREX key relation between reference and detected key.
    private func keyRelation(ref: (pc: Int, minor: Bool), det: (pc: Int, minor: Bool)) -> String {
        if ref.pc == det.pc && ref.minor == det.minor { return "exact" }
        if ref.pc == det.pc && ref.minor != det.minor { return "parallel" }
        let diff = ((det.pc - ref.pc) % 12 + 12) % 12
        if ref.minor == det.minor && (diff == 7 || diff == 5) { return "fifth" }       // perfect fifth
        if !ref.minor && det.minor && diff == 9 { return "relative" }                  // major → relative minor
        if ref.minor && !det.minor && diff == 3 { return "relative" }                  // minor → relative major
        return "none"
    }

    /// Fair tempo baseline using the SAME onset path the pipeline uses (OnsetEngine
    /// SuperFlux), over all BPM-annotated tracks. Separated from the key test so the
    /// extra STFT only runs on the 43 tempo files.
    func testGiantStepsTempoSuperflux() async throws {
        let manifest = try loadManifest()
        let table = ValidationTable("GIANTSTEPS TEMPO (SuperFlux, MIREX annotations)")
        let withBpm = manifest.files.filter { $0.bpm != nil }

        var a1c = 0, a2c = 0, n = 0
        print("\n  id        ref-bpm  det-bpm  A1  A2")
        for e in withBpm {
            guard let refBpm = e.bpm else { continue }
            let url = URL(fileURLWithPath: "\(goldenRoot)/\(e.file)")
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            var buf = try await AudioLoader.load(url: url, targetSampleRate: 22050)
            if buf.samples.count > 60 * 22050 {
                buf = AudioBuffer(samples: Array(buf.samples.prefix(60 * 22050)), sampleRate: 22050, duration: 60)
            }
            let onset = await OnsetEngine(sampleRate: 22050).onsetStrength(buf.samples) // SuperFlux path
            let bpm = Double(RhythmEngine.estimateTempo(onsetStrength: onset.envelope, sr: 22050, hopLength: 512).bpm)
            let (a1, a2) = tempoAcc(measured: bpm, ref: Double(refBpm))
            if a1 { a1c += 1 }; if a2 { a2c += 1 }; n += 1
            func pad(_ s: String, _ w: Int) -> String { s.count >= w ? s : s + String(repeating: " ", count: w - s.count) }
            print("  \(pad(e.id, 9)) \(pad("\(refBpm)", 7)) \(pad(String(format: "%.1f", bpm), 8)) \(a1 ? "✓" : "✗")   \(a2 ? "✓" : "✗")")
        }
        let d = Double(max(1, n))
        table.check("Tempo MIREX Acc1 (%)", expected: 100, measured: Double(a1c) / d * 100, tol: 100)
        table.check("Tempo MIREX Acc2 (%)", expected: 100, measured: Double(a2c) / d * 100, tol: 100)
        table.printTable()
        print("📊 SuperFlux tempo over \(n) tracks: Acc1=\(a1c) Acc2=\(a2c)")
        XCTAssertGreaterThan(n, 0)
    }

    /// Diagnostic: shows ref vs detected BPM and the raw/prior-weighted autocorrelation
    /// peak structure, to see whether the true-period peak exists but is mis-ranked.
    func testTempoDiagnostic() async throws {
        let manifest = try loadManifest()
        let bpmFiles = manifest.files.filter { $0.bpm != nil }.prefix(10)
        let sr = 22050.0, hop = 512
        let refLag = 60.0 * sr / (Double(hop) * 120.0)
        for e in bpmFiles {
            let url = URL(fileURLWithPath: "\(goldenRoot)/\(e.file)")
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            var buf = try await AudioLoader.load(url: url, targetSampleRate: 22050)
            if buf.samples.count > 60 * 22050 { buf = AudioBuffer(samples: Array(buf.samples.prefix(60*22050)), sampleRate: 22050, duration: 60) }
            let onset = await OnsetEngine(sampleRate: 22050).onsetStrength(buf.samples)
            let env = onset.envelope
            var mean: Float = 0; for v in env { mean += v }; mean /= Float(max(1, env.count))
            let centered = env.map { $0 - mean }
            let acorr = DSPHelpers.autocorrelate(centered, maxSize: env.count)
            let minLag = Int(60.0 * sr / (Double(hop) * 240.0)), maxLag = Int(60.0 * sr / (Double(hop) * 40.0))
            var raw: [(bpm: Double, val: Float, wval: Float)] = []
            for lag in max(1, minLag)...min(acorr.count - 1, maxLag) {
                let prior = expf(-0.5 * powf(log2f(Float(lag)/Float(refLag)), 2)/0.25)
                raw.append((60.0*sr/(Double(hop)*Double(lag)), acorr[lag], acorr[lag]*prior))
            }
            let det = RhythmEngine.estimateTempo(onsetStrength: env, sr: 22050, hopLength: 512).bpm
            let topRaw = raw.sorted { $0.val > $1.val }.prefix(4).map { String(format: "%.0f(%.2f)", $0.bpm, $0.val) }.joined(separator: " ")
            let topW = raw.sorted { $0.wval > $1.wval }.prefix(4).map { String(format: "%.0f", $0.bpm) }.joined(separator: " ")
            print("  ref=\(e.bpm!) det=\(String(format: "%.1f", det)) | rawTop: \(topRaw) | priorTop: \(topW)")
        }
    }

    /// Experiment: key from HPSS-harmonic chroma (drums/percussion removed) vs raw chroma.
    /// Fifth confusion is driven by bass/percussion energy; isolating the harmonic part
    /// should clean the chroma. Compares both on the same files. GS_LIMIT caps the sample.
    func testGiantStepsKeyHPSS() async throws {
        let manifest = try loadManifest()
        let limit = Int(ProcessInfo.processInfo.environment["GS_LIMIT"] ?? "80") ?? 80
        let entries = limit > 0 ? Array(manifest.files.prefix(limit)) : manifest.files

        var rawExact = 0, rawMirex = 0.0, hpssExact = 0, hpssMirex = 0.0, total = 0
        func mirexW(_ rel: String) -> Double { rel == "exact" ? 1.0 : (rel == "fifth" ? 0.5 : (rel == "relative" ? 0.3 : (rel == "parallel" ? 0.2 : 0.0))) }

        for e in entries {
            let url = URL(fileURLWithPath: "\(goldenRoot)/\(e.file)")
            guard FileManager.default.fileExists(atPath: url.path), let refK = parseKey(e.key) else { continue }
            var buf = try await AudioLoader.load(url: url, targetSampleRate: 22050)
            if buf.samples.count > 60 * 22050 { buf = AudioBuffer(samples: Array(buf.samples.prefix(60*22050)), sampleRate: 22050, duration: 60) }
            let stft = await STFTEngine(nFFT: 2048, hopLength: 512, sampleRate: 22050).analyze(buf.samples)
            total += 1

            func keyFrom(_ matrix: STFTMatrix) -> String {
                let chroma = ChromaEngine(sampleRate: 22050).chromagram(stft: matrix)
                let mean = (0..<12).map { c in chroma[c].isEmpty ? 0 : chroma[c].reduce(0, +) / Float(chroma[c].count) }
                return ModulationEngine().detectKey(mean)
            }

            // Raw chroma key
            if let dk = parseKey(keyFrom(stft)) {
                let rel = keyRelation(ref: refK, det: dk); if rel == "exact" { rawExact += 1 }; rawMirex += mirexW(rel)
            }
            // HPSS-harmonic chroma key
            let hpss = HPSSEngine(winHarm: 31, winPerc: 31).analyze(stft: stft)
            if let dk = parseKey(keyFrom(hpss.harmonic)) {
                let rel = keyRelation(ref: refK, det: dk); if rel == "exact" { hpssExact += 1 }; hpssMirex += mirexW(rel)
            }
        }
        let n = Double(max(1, total))
        print("📊 KEY over \(total): RAW exact=\(rawExact) (\(String(format: "%.1f", Double(rawExact)/n*100))%) mirex=\(String(format: "%.1f", rawMirex/n*100))%  |  HPSS exact=\(hpssExact) (\(String(format: "%.1f", Double(hpssExact)/n*100))%) mirex=\(String(format: "%.1f", hpssMirex/n*100))%")
        XCTAssertGreaterThan(total, 0)
    }

    /// Experiment: STFT-linear chroma vs CQT (log-frequency) chroma for key. CQT resolves
    /// bass pitches (which define the key root) far better than linear STFT bins. Tuning = 0
    /// here; tuning correction is the next step. Default GS_LIMIT is small because CQT is heavy.
    func testGiantStepsKeyCQT() async throws {
        let manifest = try loadManifest()
        let limit = Int(ProcessInfo.processInfo.environment["GS_LIMIT"] ?? "40") ?? 40
        let entries = limit > 0 ? Array(manifest.files.prefix(limit)) : manifest.files

        var stftExact = 0, stftMirex = 0.0, cqtExact = 0, cqtMirex = 0.0, total = 0
        func mirexW(_ rel: String) -> Double { rel == "exact" ? 1.0 : (rel == "fifth" ? 0.5 : (rel == "relative" ? 0.3 : (rel == "parallel" ? 0.2 : 0.0))) }
        func keyFromChroma(_ chroma: [[Float]]) -> String {
            guard chroma.count == 12 else { return "Unclassified" }
            let mean = (0..<12).map { c in chroma[c].isEmpty ? 0 : chroma[c].reduce(0, +) / Float(chroma[c].count) }
            return ModulationEngine().detectKey(mean)
        }

        for e in entries {
            let url = URL(fileURLWithPath: "\(goldenRoot)/\(e.file)")
            guard FileManager.default.fileExists(atPath: url.path), let refK = parseKey(e.key) else { continue }
            var buf: AudioBuffer
            do { buf = try await AudioLoader.load(url: url, targetSampleRate: 22050) }
            catch { continue } // skip unreadable/corrupt files instead of aborting the run
            if buf.samples.count > 60 * 22050 { buf = AudioBuffer(samples: Array(buf.samples.prefix(60*22050)), sampleRate: 22050, duration: 60) }
            guard buf.samples.count > 8192 else { continue }
            total += 1

            let stft = await STFTEngine(nFFT: 2048, hopLength: 512, sampleRate: 22050).analyze(buf.samples)
            if let dk = parseKey(keyFromChroma(ChromaEngine(sampleRate: 22050).chromagram(stft: stft))) {
                let rel = keyRelation(ref: refK, det: dk); if rel == "exact" { stftExact += 1 }; stftMirex += mirexW(rel)
            }

            // Production key path: high-resolution STFT chroma (nFFT 8192, ~2.7 Hz bins).
            // This is what the pipeline uses; it reaches librosa-level key without the CQT.
            let stftHi = await STFTEngine(nFFT: 8192, hopLength: 512, sampleRate: 22050).analyze(buf.samples)
            let chromaHi = ChromaEngine(nFFT: 8192, sampleRate: 22050).chromagram(stft: stftHi)
            if let dk = parseKey(keyFromChroma(chromaHi)) {
                let rel = keyRelation(ref: refK, det: dk); if rel == "exact" { cqtExact += 1 }; cqtMirex += mirexW(rel)
            }
        }
        let n = Double(max(1, total))
        print("📊 KEY over \(total): STFT exact=\(stftExact) (\(String(format: "%.1f", Double(stftExact)/n*100))%) mirex=\(String(format: "%.1f", stftMirex/n*100))%  |  CQT exact=\(cqtExact) (\(String(format: "%.1f", Double(cqtExact)/n*100))%) mirex=\(String(format: "%.1f", cqtMirex/n*100))%")
        XCTAssertGreaterThan(total, 0)
    }

    func testGiantStepsKeyTempoAccuracy() async throws {
        // Root cause (DEVLOG Phase 17): long real-I/O runs with a large final printed summary
        // could silently lose that summary (and sometimes the last per-track row) to a race with
        // process/XCTest teardown. A single fflush(stdout) at the end did NOT fix it — verified
        // empirically. Forcing stdout fully unbuffered for the whole test (every print() becomes
        // an immediate write()) DID fix it — verified on the real, complete 599-track run.
        setvbuf(stdout, nil, _IONBF, 0)
        let manifest = try loadManifest()
        let table = ValidationTable("GIANTSTEPS KEY+TEMPO ACCURACY (MIREX annotations)")

        // GS_LIMIT caps the KEY sample size (0 = all). All BPM-annotated tracks are always
        // included so the tempo baseline is complete; the rest fill the key sample.
        let limit = Int(ProcessInfo.processInfo.environment["GS_LIMIT"] ?? "80") ?? 80
        let withBpm = manifest.files.filter { $0.bpm != nil }
        let noBpm = manifest.files.filter { $0.bpm == nil }
        let entries: [Entry]
        if limit <= 0 {
            entries = manifest.files
        } else {
            entries = withBpm + noBpm.prefix(max(0, limit - withBpm.count))
        }

        // Sample rate (DEVLOG item 3 / Phase 36): this test used to force-resample to 22050Hz,
        // which does NOT match `DNAReportBuilder`'s real per-chunk decode (native file rate —
        // GiantSteps is natively 44100Hz, confirmed via afinfo). Direction was measured, not
        // assumed, on the full 599-track set before changing this: Tempo native decisively
        // better (Acc1 58.1%→69.8%, Acc2 69.8%→81.4%) — production was already correct, only
        // this test under-reported it. Key: 22050 slightly better (+2.2pp exact / +1.9pp MIREX
        // at n=599) but within the established >300-sample/10pp tolerance band — not enough to
        // justify migrating Key onto Instrument's separate analytical-decode branch, so
        // production stays native and this test now measures what production actually runs,
        // consciously leaving that ~2pp on the table. See DEVLOG Phase 36.
        let sr = 44100.0
        let cap = Int(60 * sr)

        var keyExact = 0, keyFifth = 0, keyRelative = 0, keyParallel = 0
        var tempoA1 = 0, tempoA2 = 0, total = 0, tempoTotal = 0
        print("\n  id        ref-key    det-key     ref-bpm  det-bpm  key  A1  A2")
        for e in entries {
            let url = URL(fileURLWithPath: "\(goldenRoot)/\(e.file)")
            guard FileManager.default.fileExists(atPath: url.path) else {
                table.checkExact("\(e.id): present", expected: "yes", measured: "MISSING", pass: false); continue
            }
            var buf = try await AudioLoader.load(url: url, targetSampleRate: sr)
            // Analyze the first 60s — plenty for tempo/key, and keeps STFT size (hence the
            // disk-cache write) modest so a multi-file batch stays fast.
            if buf.samples.count > cap {
                buf = AudioBuffer(samples: Array(buf.samples.prefix(cap)), sampleRate: sr, duration: 60)
            }
            total += 1

            // Key uses a high-resolution nFFT=8192 STFT for chroma — this matches the real
            // production key path (DNAReportBuilder.swift ~line 182-183), not the coarser
            // nFFT=2048 chroma that was measured here before. Using the 2048 chroma for key
            // silently tested a code path production doesn't use — see DEVLOG for the
            // investigation this uncovered (real production key path scores materially higher:
            // 599-track full run went from 37.2%/49.9% (wrong, nFFT=2048) to 50.9%/63.3%
            // (correct, nFFT=8192, but still at the wrong 22050 sample rate — see the sr note
            // above for the subsequent native-rate correction)).
            let stftHi = await STFTEngine(nFFT: 8192, hopLength: 512, sampleRate: sr).analyze(buf.samples)

            // Key: mean chroma (high-resolution, production path) → Krumhansl key estimate.
            let chroma = ChromaEngine(nFFT: 8192, sampleRate: sr).chromagram(stft: stftHi)
            let meanChroma = (0..<12).map { c in chroma[c].isEmpty ? 0 : chroma[c].reduce(0, +) / Float(chroma[c].count) }
            let detKey = ModulationEngine().detectKey(meanChroma)
            let refK = parseKey(e.key), detK = parseKey(detKey)
            let rel = (refK != nil && detK != nil) ? keyRelation(ref: refK!, det: detK!) : "none"
            switch rel {
            case "exact": keyExact += 1
            case "fifth": keyFifth += 1
            case "relative": keyRelative += 1
            case "parallel": keyParallel += 1
            default: break
            }

            // Tempo: production's real onset algorithm (`OnsetEngine`'s default SuperFlux+mel
            // mode, matches `DNAReportBuilder.swift` ~line 186) → autocorrelation tempo. This
            // used to call `RhythmEngine.onsetStrength(from:)` -- a simpler linear-STFT
            // rectified spectral-flux function that is never called anywhere in Sources/
            // production code (test-only). That mismatch was independent of, and separate from,
            // the sample-rate mismatch this test was fixed for -- discovered only when a
            // Phase-36 closing-evidence number (Acc1 65.1%/Acc2 74.4%, from this test at native
            // rate but the WRONG onset algorithm) didn't match the already-approved direction-
            // measurement number (Acc1 69.8%/Acc2 81.4%, from `OnsetEngine` at native rate,
            // matching production). See DEVLOG for the correction. Scored only where a BPM
            // annotation exists.
            let onset = await OnsetEngine(sampleRate: sr).onsetStrength(buf.samples)
            let bpm = Double(RhythmEngine.estimateTempo(onsetStrength: onset.envelope, sr: sr, hopLength: 512).bpm)
            var a1 = false, a2 = false
            if let refBpm = e.bpm {
                tempoTotal += 1
                (a1, a2) = tempoAcc(measured: bpm, ref: Double(refBpm))
                if a1 { tempoA1 += 1 }; if a2 { tempoA2 += 1 }
            }

            func pad(_ s: String, _ w: Int) -> String { s.count >= w ? s : s + String(repeating: " ", count: w - s.count) }
            let refBpmStr = e.bpm.map { "\($0)" } ?? "—"
            print("  \(pad(e.id, 9)) \(pad(e.key, 10)) \(pad(detKey, 11)) \(pad(refBpmStr, 7)) \(pad(String(format: "%.1f", bpm), 8)) \(rel == "exact" ? "✓" : "✗")   \(e.bpm == nil ? "·" : (a1 ? "✓" : "✗"))   \(e.bpm == nil ? "·" : (a2 ? "✓" : "✗"))")
        }

        // MIREX-weighted key score: exact 1.0, fifth 0.5, relative 0.3, parallel 0.2.
        let kn = Double(max(1, total))
        let mirexKey = (Double(keyExact) + 0.5*Double(keyFifth) + 0.3*Double(keyRelative) + 0.2*Double(keyParallel)) / kn * 100
        let tn = Double(max(1, tempoTotal))
        table.check("Key exact match (%)",      expected: 100, measured: Double(keyExact) / kn * 100, tol: 100)
        table.check("Key MIREX-weighted score", expected: 100, measured: mirexKey, tol: 100)
        table.check("Tempo MIREX Acc1 (%)",     expected: 100, measured: Double(tempoA1) / tn * 100, tol: 100)
        table.check("Tempo MIREX Acc2 (%)",     expected: 100, measured: Double(tempoA2) / tn * 100, tol: 100)
        table.printTable()
        print("📊 Baseline: \(total) tracks | KeyExact=\(keyExact) fifth=\(keyFifth) rel=\(keyRelative) par=\(keyParallel) | Tempo(\(tempoTotal)) Acc1=\(tempoA1) Acc2=\(tempoA2)")

        XCTAssertGreaterThan(total, 0, "No golden files found — was the dataset downloaded?")
    }

    /// Open item 9 (Yapilacaklar madde 9 / DEVLOG Phase 41's direct follow-up): item 8's Key
    /// finding left two open questions -- how accurate is `ReductionEngine.fundamentalNote` (what
    /// `report.estimations.key.value` actually is) against real ground truth, and should
    /// `ModulationEngine.detectKey` (computed but never exposed) be wired there instead? Measures
    /// both, side by side, on the same files, to answer both at once.
    ///
    /// **Metric is deliberately NOT standard exact-match/MIREX-weighted key accuracy.**
    /// `ReductionEngine.fundamentalNote` never determines major/minor (`ChromaResult.
    /// noteNames[fundamentalBin]` is a bare tonic) -- scoring it against mode-qualified ground
    /// truth with a mode-sensitive metric would fail on mode by construction, and conflate "wrong
    /// tonic" with "no mode to be wrong about" into one misleading number. Both algorithms are
    /// scored on TONIC (pitch-class) agreement only, mode ignored on both sides -- exact tonic
    /// match, or a perfect-fifth-related tonic (the one MIREX partial-credit category that is
    /// itself mode-independent), else no credit. `detectKey`'s own accuracy under FULL
    /// (mode-inclusive) MIREX scoring is already on record from Phase 17/36 (48.8%/61.4%,
    /// N=599) -- not reproduced here; this measures a different question (tonic-only, both
    /// algorithms, same footing).
    ///
    /// **Reads `ReductionEngine`'s side from production's REAL output** (`AudioIntelligence().
    /// analyze(url:).estimations.key`), not an isolated `ReductionEngine` call -- item 8's own
    /// finding was that an isolated call can silently diverge from what production actually wires
    /// (that is exactly how the Key `method`-label bug was found). `detectKey` has no exposed path
    /// to read from at all (item 8 confirmed it never reaches `Estimations.key`), so it is
    /// necessarily computed via an isolated helper -- built to match `DNAReportBuilder`'s own
    /// internal computation as closely as possible (same whole-track STFT(8192)/`ChromaEngine`
    /// chroma, native rate) since that is the best available approximation of "what production
    /// would expose if this were wired instead."
    ///
    /// Sample size and rate follow Phase 36's already-settled Key precedent directly (native
    /// 44100Hz, not this project's most-repeated mistake of an isolated 22050Hz assumption) --
    /// capped to `GS_KEY_TONIC_LIMIT` (default 43) because `analyze(url:)` runs production's full
    /// pipeline per file (~50s/file measured directly, not assumed -- all 599 files would be
    /// hours), unlike the cheap isolated-engine-only calls the rest of this file uses.
    func testReductionEngineVsDetectKey_tonicOnlyAccuracy_realProductionPath() async throws {
        setvbuf(stdout, nil, _IONBF, 0) // Phase 39's lesson: long real-I/O runs lose buffered
                                         // output if interrupted -- unbuffered from the start.
        let manifest = try loadManifest()
        let limit = Int(ProcessInfo.processInfo.environment["GS_KEY_TONIC_LIMIT"] ?? "43") ?? 43
        let entries = limit <= 0 ? manifest.files : Array(manifest.files.prefix(limit))
        let sr = 44100.0

        // Tonic-only relation: mode-independent by construction, so no "relative"/"parallel"
        // categories (those are mode-relationship concepts -- meaningless once mode is dropped).
        func tonicRelation(ref: Int, det: Int) -> String {
            if ref == det { return "exact" }
            let diff = ((det - ref) % 12 + 12) % 12
            if diff == 7 || diff == 5 { return "fifth" }
            return "none"
        }

        var reductionExact = 0, reductionFifth = 0
        var detectKeyExact = 0, detectKeyFifth = 0
        var total = 0
        print("\n  id        truth-tonic  reduction  detectKey   red  dk")
        for e in entries {
            guard let refTonic = parseKey(e.key)?.pc else { continue }
            let url = URL(fileURLWithPath: "\(goldenRoot)/\(e.file)")
            guard FileManager.default.fileExists(atPath: url.path) else { continue }

            // Production's REAL output -- the actual `ReductionEngine.fundamentalNote` a caller
            // receives, not a hand-rolled isolated replica of it.
            guard let report = try? await AudioIntelligence().analyze(url: url) else { continue }
            let reductionTonicName = report.estimations.key.value
            guard let reductionTonic = parseKey("\(reductionTonicName) Major")?.pc else { continue }

            // `detectKey` has no exposed path -- isolated helper matching `DNAReportBuilder`'s own
            // internal whole-track chroma computation (STFT nFFT=8192, hop 512, native rate).
            guard let buf = try? await AudioLoader.load(url: url, targetSampleRate: sr) else { continue }
            let stft = await STFTEngine(nFFT: 8192, hopLength: 512, sampleRate: sr).analyze(buf.samples)
            let chroma = ChromaEngine(nFFT: 8192, sampleRate: sr).chromagram(stft: stft)
            let meanChroma = (0..<12).map { c in chroma[c].isEmpty ? 0 : chroma[c].reduce(0, +) / Float(chroma[c].count) }
            let detectKeyName = ModulationEngine().detectKey(meanChroma)
            let detectKeyTonic = parseKey(detectKeyName)?.pc

            total += 1
            let redRel = tonicRelation(ref: refTonic, det: reductionTonic)
            if redRel == "exact" { reductionExact += 1 } else if redRel == "fifth" { reductionFifth += 1 }
            let dkRel = detectKeyTonic.map { tonicRelation(ref: refTonic, det: $0) } ?? "none"
            if dkRel == "exact" { detectKeyExact += 1 } else if dkRel == "fifth" { detectKeyFifth += 1 }

            func pad(_ s: String, _ w: Int) -> String { s.count >= w ? s : s + String(repeating: " ", count: w - s.count) }
            print("  \(pad(e.id, 9)) \(pad(e.key, 12)) \(pad(reductionTonicName, 10)) \(pad(detectKeyName, 11)) \(redRel == "exact" ? "✓" : "✗")    \(dkRel == "exact" ? "✓" : "✗")")
        }

        guard total > 0 else { XCTFail("No golden files with valid key ground truth were measured — was the dataset downloaded?"); return }
        let n = Double(total)
        let reductionExactPct = Double(reductionExact) / n * 100
        let reductionWeighted = (Double(reductionExact) + 0.5 * Double(reductionFifth)) / n * 100
        let detectKeyExactPct = Double(detectKeyExact) / n * 100
        let detectKeyWeighted = (Double(detectKeyExact) + 0.5 * Double(detectKeyFifth)) / n * 100

        print("\n=== TONIC-ONLY KEY ACCURACY, PRODUCTION'S EXPOSED ALGORITHM vs. THE HIDDEN ONE (N=\(total)) ===")
        print(String(format: "ReductionEngine (EXPOSED, report.estimations.key.value): exact=%.1f%% fifth-weighted=%.1f%% (%d exact, %d fifth)",
                      reductionExactPct, reductionWeighted, reductionExact, reductionFifth))
        print(String(format: "ModulationEngine.detectKey (COMPUTED, NEVER EXPOSED):    exact=%.1f%% fifth-weighted=%.1f%% (%d exact, %d fifth)",
                      detectKeyExactPct, detectKeyWeighted, detectKeyExact, detectKeyFifth))
        print("Both scored tonic-only (mode ignored on both sides) -- NOT comparable to Phase 17/36's full mode-inclusive 48.8%/61.4% detectKey numbers.")

        // Loose sanity floor, not a regression contract -- this is the first measurement of
        // either algorithm's tonic-only accuracy; the point is a real number for both, and
        // which is higher, not locking in today's exact figure.
        XCTAssertGreaterThan(total, 0)
    }
}
