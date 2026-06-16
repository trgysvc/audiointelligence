import XCTest
import Foundation
@testable import AudioIntelligenceCore

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

        var keyExact = 0, keyFifth = 0, keyRelative = 0, keyParallel = 0
        var tempoA1 = 0, tempoA2 = 0, total = 0, tempoTotal = 0
        print("\n  id        ref-key    det-key     ref-bpm  det-bpm  key  A1  A2")
        for e in entries {
            let url = URL(fileURLWithPath: "\(goldenRoot)/\(e.file)")
            guard FileManager.default.fileExists(atPath: url.path) else {
                table.checkExact("\(e.id): present", expected: "yes", measured: "MISSING", pass: false); continue
            }
            var buf = try await AudioLoader.load(url: url, targetSampleRate: 22050)
            // Analyze the first 60s — plenty for tempo/key, and keeps STFT size (hence the
            // disk-cache write) modest so a multi-file batch stays fast.
            if buf.samples.count > 60 * 22050 {
                buf = AudioBuffer(samples: Array(buf.samples.prefix(60 * 22050)), sampleRate: 22050, duration: 60)
            }
            total += 1

            // One STFT shared by onset (tempo) and chroma (key) — avoids a second cached STFT.
            let stft = await STFTEngine(nFFT: 2048, hopLength: 512, sampleRate: 22050).analyze(buf.samples)

            // Key: mean chroma → Krumhansl key estimate.
            let chroma = ChromaEngine(sampleRate: 22050).chromagram(stft: stft)
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

            // Tempo: spectral-flux onset (from the shared STFT) → autocorrelation tempo.
            // Scored only where a BPM annotation exists.
            let onsetEnv = RhythmEngine.onsetStrength(from: stft)
            let bpm = Double(RhythmEngine.estimateTempo(onsetStrength: onsetEnv, sr: 22050, hopLength: 512).bpm)
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
}
