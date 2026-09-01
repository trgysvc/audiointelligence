import XCTest
@testable import AudioIntelligenceCore

/// First-ever real-ground-truth check for `StructureEngine.analyze()`'s boundary detection,
/// against real human-annotated SALAMI structure boundaries (444 tracks downloaded via
/// Internet Archive Live Music Archive, see DEVLOG Phase 28). Standard MIR boundary-detection
/// metrics: precision/recall/F-measure at 0.5s and 3.0s tolerance windows (the two standard
/// MIREX tolerances), computed against SALAMI's "uppercase" structural-layer annotation
/// (large-scale section boundaries: A/B/C/Z).
///
/// Measured result (15 tracks, evenly sampled): @0.5s precision=8.2% recall=21.9% F=11.9%;
/// @3.0s precision=25.7% recall=68.7% F=37.3%. Predicted boundary counts run 2-3x true counts
/// (e.g. 40 predicted vs. 12 true) — `StructureEngine` over-segments; the 3.0s recall (69%) shows
/// most true boundaries have SOME nearby prediction, but the collapse at 0.5s shows poor timing
/// precision even then. This is the first real measurement of this engine's boundary accuracy —
/// not previously possible (Isophonics/Billboard have no legally obtainable audio; SALAMI's does,
/// via Internet Archive). See DEVLOG for the open follow-up (peak-picking parameter tuning).
final class StructureEngineSALAMITests: XCTestCase {
    private struct BoundaryMetrics {
        var hits05 = 0, hits3 = 0
        var predictedTotal = 0
        var trueTotal = 0
    }

    func testStructureEngine_boundaryAccuracy_onRealSALAMI() async throws {
        let salamiRoot = URL(fileURLWithPath: "Tests/Resources/SALAMI")
        let manifestURL = salamiRoot.appendingPathComponent("metadata/ia_manifest.csv")
        guard let manifest = try? String(contentsOf: manifestURL, encoding: .utf8) else {
            throw XCTSkip("SALAMI manifest not available")
        }

        // `.components(separatedBy: .newlines)` (not `split(separator: "\n")`): the manifest was
        // originally written with CRLF line endings (Python csv.writer's default) — Swift's
        // String treats "\r\n" as a SINGLE extended grapheme cluster, so a plain "\n" separator
        // never matches at all and silently produces zero lines. `.newlines` handles any
        // line-ending convention correctly. (The manifest file itself was also normalized to
        // LF-only, and the generating script fixed with `lineterminator='\n'` — this is
        // defense in depth, not a substitute for that fix.)
        struct Entry { let songID: String; let localFile: String }
        var entries: [Entry] = []
        for line in manifest.components(separatedBy: .newlines).dropFirst() {
            let cols = line.split(separator: ",")
            guard cols.count >= 4 else { continue }
            entries.append(Entry(songID: String(cols[0]), localFile: String(cols[3])))
        }

        let sr = 22050.0
        let hop = 512
        let limit = 15
        let selected = stride(from: 0, to: entries.count, by: max(1, entries.count / limit)).map { entries[$0] }.prefix(limit)

        var overall = BoundaryMetrics()
        var usable = 0

        for entry in selected {
            let audioURL = salamiRoot.appendingPathComponent("audio/\(entry.localFile)")
            let annotURL = salamiRoot.appendingPathComponent("annotations/\(entry.songID)/parsed/textfile1_uppercase.txt")
            guard FileManager.default.fileExists(atPath: audioURL.path),
                  let annotText = try? String(contentsOf: annotURL, encoding: .utf8),
                  let buf = try? await AudioLoader.load(url: audioURL, targetSampleRate: sr) else { continue }

            var trueBoundaries: [Double] = []
            for line in annotText.split(separator: "\n") {
                let cols = line.split(separator: "\t")
                guard cols.count >= 1, let t = Double(cols[0]) else { continue }
                trueBoundaries.append(t)
            }
            guard trueBoundaries.count >= 2 else { continue }

            let stftEngine = STFTEngine(nFFT: 8192, hopLength: hop, sampleRate: sr)
            let stft = await stftEngine.analyze(buf.samples)
            let chroma = ChromaEngine(nFFT: 8192, sampleRate: sr).chromagram(stft: stft)

            let mel = MelSpectrogramEngine(stftEngine: STFTEngine(nFFT: 2048, hopLength: hop, sampleRate: sr), nMels: 128)
            let mfccEngine = MFCCEngine(melEngine: mel, nMFCC: 13)
            let mfccResult = await mfccEngine.createMFCC(from: buf.samples)
            let nMFCCFrames = mfccResult.fullData.count / 13
            var mfcc2D = [[Float]](repeating: [Float](repeating: 0, count: nMFCCFrames), count: 13)
            for t in 0..<nMFCCFrames {
                for c in 0..<13 { mfcc2D[c][t] = mfccResult.fullData[t * 13 + c] }
            }

            // Align frame counts (chroma and MFCC use different nFFT -> possibly different
            // nFrames); truncate to the shorter of the two, matching production's own pattern
            // of feeding same-length aligned feature streams into StructureEngine.
            let nFrames = min(chroma[0].count, mfcc2D[0].count)
            guard nFrames > 20 else { continue }
            let chromaAligned = chroma.map { Array($0.prefix(nFrames)) }
            let mfccAligned = mfcc2D.map { Array($0.prefix(nFrames)) }

            let result = StructureEngine(hopLength: hop, sampleRate: sr).analyze(chromagram: chromaAligned, mfccs: mfccAligned)
            guard !result.boundaryTimes.isEmpty else { continue }

            usable += 1
            var m = BoundaryMetrics()
            m.predictedTotal = result.boundaryTimes.count
            m.trueTotal = trueBoundaries.count
            var matched05 = Set<Int>(), matched3 = Set<Int>()
            for pt in result.boundaryTimes {
                for (i, tt) in trueBoundaries.enumerated() {
                    let d = abs(pt - tt)
                    if d <= 0.5 { matched05.insert(i) }
                    if d <= 3.0 { matched3.insert(i) }
                }
            }
            m.hits05 = matched05.count
            m.hits3 = matched3.count

            print("song \(entry.songID): predicted=\(m.predictedTotal) true=\(m.trueTotal) matched@0.5s=\(m.hits05) matched@3.0s=\(m.hits3)")

            overall.hits05 += m.hits05
            overall.hits3 += m.hits3
            overall.predictedTotal += m.predictedTotal
            overall.trueTotal += m.trueTotal
        }

        func prf(hits: Int, predicted: Int, trueN: Int) -> (p: Double, r: Double, f: Double) {
            let p = predicted > 0 ? Double(hits) / Double(predicted) : 0
            let r = trueN > 0 ? Double(hits) / Double(trueN) : 0
            let f = (p + r) > 0 ? 2 * p * r / (p + r) : 0
            return (p, r, f)
        }

        let m05 = prf(hits: overall.hits05, predicted: overall.predictedTotal, trueN: overall.trueTotal)
        let m3 = prf(hits: overall.hits3, predicted: overall.predictedTotal, trueN: overall.trueTotal)

        print("\n=== StructureEngine boundary accuracy on real SALAMI (\(usable) usable tracks) ===")
        print(String(format: "@0.5s: precision=%.1f%% recall=%.1f%% F=%.1f%%", m05.p*100, m05.r*100, m05.f*100))
        print(String(format: "@3.0s: precision=%.1f%% recall=%.1f%% F=%.1f%%", m3.p*100, m3.r*100, m3.f*100))

        XCTAssertGreaterThan(usable, 0, "no SALAMI tracks were usable — check dataset/symlink availability")
        // Loose sanity floor, not a tight regression contract: this is the first-ever real
        // measurement of this engine, and the current numbers (F@3.0s=37.3%) are themselves a
        // known-weak baseline, not a target. The purpose here is to catch a silent TOTAL collapse
        // (e.g. StructureEngine starts returning zero boundaries for everything), not to lock in
        // today's mediocre-but-nonzero performance as acceptable.
        XCTAssertGreaterThan(m3.f, 0.15, "F-measure@3.0s dropped well below its last-measured 37.3% -- investigate before assuming this is fine")
    }

    /// Direction check for DEVLOG item 3 (Tempo/Key/Structure sample-rate mismatch): does
    /// `StructureEngine.analyze()` — using the Phase 29 seconds-based `.calibrated`
    /// `StructurePeakPickConfig` (waitSeconds/preAvg/postAvg etc. converted to frame counts via
    /// hopLength/sampleRate internally) — perform as well at native 44100Hz as it does at the
    /// 22050Hz it was grid-searched at? Unlike Instrument (a fitted-threshold model) or Tempo
    /// (a from-scratch onset/tempo algorithm), Structure's config is expressed in SECONDS, so it
    /// should in principle self-adjust to any sample rate — this test measures whether that
    /// theoretical self-adjustment actually holds, rather than assuming it.
    func testStructureEngine_sampleRateComparison_onRealSALAMI() async throws {
        let salamiRoot = URL(fileURLWithPath: "Tests/Resources/SALAMI")
        let manifestURL = salamiRoot.appendingPathComponent("metadata/ia_manifest.csv")
        guard let manifest = try? String(contentsOf: manifestURL, encoding: .utf8) else {
            throw XCTSkip("SALAMI manifest not available")
        }

        struct Entry { let songID: String; let localFile: String }
        var entries: [Entry] = []
        for line in manifest.components(separatedBy: .newlines).dropFirst() {
            let cols = line.split(separator: ",")
            guard cols.count >= 4 else { continue }
            entries.append(Entry(songID: String(cols[0]), localFile: String(cols[3])))
        }

        let hop = 512
        let limit = 15
        let selected = stride(from: 0, to: entries.count, by: max(1, entries.count / limit)).map { entries[$0] }.prefix(limit)

        func measure(sr: Double) async -> (p: Double, r: Double, f: Double, usable: Int) {
            var overall = BoundaryMetrics()
            var usable = 0
            for entry in selected {
                let audioURL = salamiRoot.appendingPathComponent("audio/\(entry.localFile)")
                let annotURL = salamiRoot.appendingPathComponent("annotations/\(entry.songID)/parsed/textfile1_uppercase.txt")
                guard FileManager.default.fileExists(atPath: audioURL.path),
                      let annotText = try? String(contentsOf: annotURL, encoding: .utf8),
                      let buf = try? await AudioLoader.load(url: audioURL, targetSampleRate: sr) else { continue }

                var trueBoundaries: [Double] = []
                for line in annotText.split(separator: "\n") {
                    let cols = line.split(separator: "\t")
                    guard cols.count >= 1, let t = Double(cols[0]) else { continue }
                    trueBoundaries.append(t)
                }
                guard trueBoundaries.count >= 2 else { continue }

                let stftEngine = STFTEngine(nFFT: 8192, hopLength: hop, sampleRate: sr)
                let stft = await stftEngine.analyze(buf.samples)
                let chroma = ChromaEngine(nFFT: 8192, sampleRate: sr).chromagram(stft: stft)

                let mel = MelSpectrogramEngine(stftEngine: STFTEngine(nFFT: 2048, hopLength: hop, sampleRate: sr), nMels: 128)
                let mfccEngine = MFCCEngine(melEngine: mel, nMFCC: 13)
                let mfccResult = await mfccEngine.createMFCC(from: buf.samples)
                let nMFCCFrames = mfccResult.fullData.count / 13
                var mfcc2D = [[Float]](repeating: [Float](repeating: 0, count: nMFCCFrames), count: 13)
                for t in 0..<nMFCCFrames {
                    for c in 0..<13 { mfcc2D[c][t] = mfccResult.fullData[t * 13 + c] }
                }

                let nFrames = min(chroma[0].count, mfcc2D[0].count)
                guard nFrames > 20 else { continue }
                let chromaAligned = chroma.map { Array($0.prefix(nFrames)) }
                let mfccAligned = mfcc2D.map { Array($0.prefix(nFrames)) }

                let result = StructureEngine(hopLength: hop, sampleRate: sr).analyze(chromagram: chromaAligned, mfccs: mfccAligned)
                guard !result.boundaryTimes.isEmpty else { continue }

                usable += 1
                var matched05 = Set<Int>(), matched3 = Set<Int>()
                for pt in result.boundaryTimes {
                    for (i, tt) in trueBoundaries.enumerated() {
                        let d = abs(pt - tt)
                        if d <= 0.5 { matched05.insert(i) }
                        if d <= 3.0 { matched3.insert(i) }
                    }
                }
                overall.hits05 += matched05.count
                overall.hits3 += matched3.count
                overall.predictedTotal += result.boundaryTimes.count
                overall.trueTotal += trueBoundaries.count
            }
            let p = overall.predictedTotal > 0 ? Double(overall.hits3) / Double(overall.predictedTotal) : 0
            let r = overall.trueTotal > 0 ? Double(overall.hits3) / Double(overall.trueTotal) : 0
            let f = (p + r) > 0 ? 2 * p * r / (p + r) : 0
            return (p, r, f, usable)
        }

        let at22050 = await measure(sr: 22050)
        let at44100 = await measure(sr: 44100)

        print("\n=== Structure: which sample rate does the calibrated peak-pick perform better at? ===")
        print("SALAMI, \(selected.count)-track sample, same isolated pipeline (Phase 29 .calibrated config) at two rates")
        print(String(format: "  @ 22050Hz (%d usable): F@3.0s=%.1f%% (p=%.1f%% r=%.1f%%)", at22050.usable, at22050.f*100, at22050.p*100, at22050.r*100))
        print(String(format: "  @ 44100Hz (%d usable): F@3.0s=%.1f%% (p=%.1f%% r=%.1f%%)", at44100.usable, at44100.f*100, at44100.p*100, at44100.r*100))

        XCTAssertTrue(at22050.usable > 0 && at44100.usable > 0, "no SALAMI tracks usable at one of the two rates")
    }
}
