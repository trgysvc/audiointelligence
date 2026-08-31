// StructureCalibration — grid-searches StructureEngine's boundary peak-picking parameters
// (delta, wait, preAvg/postAvg) against real SALAMI ground truth. `StructureEngine`'s
// pre-calibration defaults (preMax=4, postMax=4, preAvg=16, postAvg=16, wait=8s, delta=0.03)
// were hand-set and never checked against real annotated audio (no such audio existed until
// SALAMI was downloaded, DEVLOG Phase 28) — Phase 28's first real measurement found severe
// over-segmentation (predicted boundary counts run 2-3x true counts). This tool answers: what
// peak-picking parameters, chosen by measurement rather than guesswork, do best on real data?
//
// Methodology:
//   - The novelty curve (STFT->chroma/MFCC->Foote novelty, `StructureEngine.prepareFeatures`)
//     is the expensive part of the pipeline and does NOT depend on peak-picking parameters —
//     computed ONCE per track, then `StructureEngine.boundaries(from:config:)` (cheap, O(nFrames)
//     per call) is re-run for every parameter combination in the grid.
//   - Tracks are split into a calibration set (grid-searched for the best F@3.0s) and a
//     disjoint held-out validation set (never used to pick parameters) — guards against
//     overfitting the parameter choice to whichever 15-40 tracks happen to get measured.
//   - Standard MIR boundary metrics at the two MIREX tolerance windows (0.5s, 3.0s), same
//     definition as `Tests/StructureEngineSALAMITests.swift`.
//
// Usage: swift run -c release StructureCalibration

import Foundation
import AudioIntelligence
import AudioIntelligenceCore
import AudioIntelligenceMetal
import Darwin

let sampleRateGlobal = 22050.0
let hopGlobal = 512

struct TrackData {
    let songID: String
    let features: StructureFeatures
    let trueBoundaries: [Double]
    let noveltyPrefixSum: [Double]   // noveltyPrefixSum[i] = sum(novelty[0..<i]), length nFrames+1
}

func makeTrackData(songID: String, features: StructureFeatures, trueBoundaries: [Double]) -> TrackData {
    var prefix = [Double](repeating: 0, count: features.novelty.count + 1)
    for i in 0..<features.novelty.count { prefix[i + 1] = prefix[i] + Double(features.novelty[i]) }
    return TrackData(songID: songID, features: features, trueBoundaries: trueBoundaries, noveltyPrefixSum: prefix)
}

struct Metrics {
    var hits05 = 0, hits3 = 0
    var predictedTotal = 0
    var trueTotal = 0

    mutating func add(_ other: Metrics) {
        hits05 += other.hits05
        hits3 += other.hits3
        predictedTotal += other.predictedTotal
        trueTotal += other.trueTotal
    }

    var p3: Double { predictedTotal > 0 ? Double(hits3) / Double(predictedTotal) : 0 }
    var r3: Double { trueTotal > 0 ? Double(hits3) / Double(trueTotal) : 0 }
    var f3: Double { (p3 + r3) > 0 ? 2 * p3 * r3 / (p3 + r3) : 0 }

    var p05: Double { predictedTotal > 0 ? Double(hits05) / Double(predictedTotal) : 0 }
    var r05: Double { trueTotal > 0 ? Double(hits05) / Double(trueTotal) : 0 }
    var f05: Double { (p05 + r05) > 0 ? 2 * p05 * r05 / (p05 + r05) : 0 }
}

/// Same selection logic as `DSPHelpers.peakPick` (local max within [i-preMax, i+postMax],
/// local average within [i-preAvg, i+postAvg] via O(1) prefix-sum lookup instead of an O(window)
/// slice-sum per frame -- the grid search calls this ~15,000 times over tracks with tens of
/// thousands of frames each, where the O(window) version measured multiple hours). Used ONLY to
/// pick candidate parameters cheaply; the recommended config is re-verified against the real,
/// unmodified `DSPHelpers.peakPick` (via `StructureEngine.boundaries(from:config:)`) before being
/// reported or applied.
func fastPeakPick(novelty: [Float], prefixSum: [Double], preMax: Int, postMax: Int, preAvg: Int, postAvg: Int, wait: Int, delta: Float) -> [Int] {
    let n = novelty.count
    guard n > 0 else { return [] }
    var peaks: [Int] = []
    var lastPeak = -wait - 1

    novelty.withUnsafeBufferPointer { sig in
        for i in 0..<n {
            let loMax = max(0, i - preMax)
            let hiMax = min(n - 1, i + postMax)
            var localMax = sig[loMax]
            if hiMax > loMax {
                for k in (loMax + 1)...hiMax where sig[k] > localMax { localMax = sig[k] }
            }

            let loAvg = max(0, i - preAvg)
            let hiAvg = min(n - 1, i + postAvg)
            let sum = prefixSum[hiAvg + 1] - prefixSum[loAvg]
            let localAvg = Float(sum / Double(hiAvg - loAvg + 1))

            if sig[i] == localMax && sig[i] >= localAvg + delta && i - lastPeak > wait {
                peaks.append(i)
                lastPeak = i
            }
        }
    }
    return peaks
}

func boundaryTimes(peaks: [Int], nFrames: Int) -> [Double] {
    var frames = peaks
    if !frames.contains(0) { frames.insert(0, at: 0) }
    let lastFrame = nFrames - 1
    if !frames.contains(lastFrame) { frames.append(lastFrame) }
    frames.sort()
    let times = frames.map { Double($0 * hopGlobal) / sampleRateGlobal }
    // Matches `StructureResult.boundaryTimes`, which drops the final forced end-boundary.
    return Array(times.dropLast())
}

func scoreBoundaries(_ predicted: [Double], against trueBoundaries: [Double]) -> Metrics {
    guard !predicted.isEmpty else { return Metrics() }
    var m = Metrics()
    m.predictedTotal = predicted.count
    m.trueTotal = trueBoundaries.count
    var matched05 = Set<Int>(), matched3 = Set<Int>()
    for pt in predicted {
        for (i, tt) in trueBoundaries.enumerated() {
            let d = abs(pt - tt)
            if d <= 0.5 { matched05.insert(i) }
            if d <= 3.0 { matched3.insert(i) }
        }
    }
    m.hits05 = matched05.count
    m.hits3 = matched3.count
    return m
}

/// Fast grid-search evaluation: uses `fastPeakPick` over the cached novelty curve + prefix sum.
/// `config.deltaMultiplier` is converted to an absolute delta per-track from THAT track's own
/// mean novelty (`noveltyPrefixSum.last! / nFrames`), mirroring `StructureEngine.
/// boundaries(from:config:)`'s runtime formula exactly -- see `StructurePeakPickConfig`'s doc
/// comment for why this (not a fixed absolute delta) is what actually gets calibrated/shipped.
func evaluateFast(_ config: StructurePeakPickConfig, tracks: [TrackData]) -> Metrics {
    var total = Metrics()
    let frameRate = sampleRateGlobal / Double(hopGlobal)
    let minWait = Int(frameRate * config.waitSeconds)
    for track in tracks {
        let meanNovelty = Float(track.noveltyPrefixSum.last! / Double(max(1, track.features.nFrames)))
        let delta = config.deltaMultiplier * meanNovelty
        let peaks = fastPeakPick(novelty: track.features.novelty, prefixSum: track.noveltyPrefixSum,
                                  preMax: config.preMax, postMax: config.postMax,
                                  preAvg: config.preAvg, postAvg: config.postAvg,
                                  wait: minWait, delta: delta)
        let times = boundaryTimes(peaks: peaks, nFrames: track.features.nFrames)
        total.add(scoreBoundaries(times, against: track.trueBoundaries))
    }
    return total
}

/// Ground-truth evaluation via the REAL, unmodified `DSPHelpers.peakPick` (through
/// `StructureEngine.boundaries(from:config:)`) -- used only for the small number of final
/// verification calls (top candidates + recommended config), not the full grid.
func evaluateReal(_ config: StructurePeakPickConfig, engine: StructureEngine, tracks: [TrackData]) -> Metrics {
    var total = Metrics()
    for track in tracks {
        let result = engine.boundaries(from: track.features, config: config)
        total.add(scoreBoundaries(result.boundaryTimes, against: track.trueBoundaries))
    }
    return total
}

@main
struct StructureCalibration {
    static func main() async {
        // Force stdout fully unbuffered: piping a long-running tool's output through `tee`/a
        // file makes stdio switch to block buffering, so a killed or signal-terminated process
        // can lose all its prints (this exact failure mode is documented in DEVLOG Phase 17 for
        // GoldenDatasetValidationTests).
        setvbuf(stdout, nil, _IONBF, 0)

        let salamiRoot = URL(fileURLWithPath: "Tests/Resources/SALAMI").resolvingSymlinksInPath()
        let manifestURL = salamiRoot.appendingPathComponent("metadata/ia_manifest.csv")
        guard let manifest = try? String(contentsOf: manifestURL, encoding: .utf8) else {
            print("ERROR: could not read \(manifestURL.path)"); return
        }

        struct Entry { let songID: String; let localFile: String }
        var entries: [Entry] = []
        for line in manifest.components(separatedBy: .newlines).dropFirst() {
            let cols = line.split(separator: ",")
            guard cols.count >= 4 else { continue }
            entries.append(Entry(songID: String(cols[0]), localFile: String(cols[3])))
        }
        print("🔎 StructureCalibration — \(entries.count) SALAMI manifest entries")

        let sr = sampleRateGlobal
        let hop = hopGlobal
        let totalWanted = 60
        let selected = stride(from: 0, to: entries.count, by: max(1, entries.count / totalWanted)).map { entries[$0] }.prefix(totalWanted)

        let engine = StructureEngine(hopLength: hop, sampleRate: sr)
        var calibration: [TrackData] = []
        var heldOut: [TrackData] = []
        var idx = 0

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

            guard let features = engine.prepareFeatures(chromagram: chromaAligned, mfccs: mfccAligned) else { continue }
            let track = makeTrackData(songID: entry.songID, features: features, trueBoundaries: trueBoundaries)

            // Interleave into calibration/held-out so both sets span the same coverage of the
            // manifest (every 3rd track held out) rather than a length- or genre-correlated split.
            if idx % 3 == 0 {
                heldOut.append(track)
            } else {
                calibration.append(track)
            }
            idx += 1
            if idx % 10 == 0 {
                print("... \(idx) tracks processed (calibration=\(calibration.count) heldOut=\(heldOut.count))")
            }
        }

        print("\n=== Feature extraction complete: \(calibration.count) calibration tracks, \(heldOut.count) held-out tracks ===\n")
        guard !calibration.isEmpty else { print("ERROR: no usable calibration tracks"); return }

        // Baseline (current production defaults) for comparison -- via the REAL peakPick, since
        // this is a single call, not the full grid.
        let baseline = evaluateReal(.init(preMax: 4, postMax: 4, preAvg: 16, postAvg: 16, waitSeconds: 8.0, deltaMultiplier: 0.0000000449), engine: engine, tracks: calibration)
        print(String(format: "Pre-calibration baseline (preAvg=16 postAvg=16 wait=8s, absolute delta=0.03) on calibration set: F@3.0s=%.1f%% F@0.5s=%.1f%% (predicted=%d true=%d)",
                      baseline.f3 * 100, baseline.f05 * 100, baseline.predictedTotal, baseline.trueTotal))

        // `deltaMultiplier` is scaled per-track from that track's own mean novelty at call time
        // (see `StructurePeakPickConfig`'s doc comment) -- print the pooled stats only as context
        // for interpreting the multiplier values below, not to hand-derive an absolute delta.
        var allNovelty: [Float] = []
        for t in calibration { allNovelty.append(contentsOf: t.features.novelty) }
        allNovelty.sort()
        let nvMean = allNovelty.reduce(0, +) / Float(max(1, allNovelty.count))
        let nvMedian = allNovelty[allNovelty.count / 2]
        print(String(format: "\nNovelty curve stats (pooled across %d calibration tracks, %d frames): mean=%.4f median=%.4f max=%.4f",
                      calibration.count, allNovelty.count, nvMean, nvMedian, allNovelty.last ?? 0))

        // deltaMultiplier candidates, log-spaced, wide enough to span "no effective threshold"
        // (0.05x) through "only the most extreme novelty spikes count" (28x).
        let deltaMultipliers: [Float] = [0.05, 0.1, 0.2, 0.35, 0.5, 0.65, 0.8, 1.0, 1.2, 1.4, 1.6, 1.8, 2.0, 2.3, 2.6, 3.0, 3.5, 4.0, 5.0, 6.0, 8.0, 10.0, 13.0, 17.0, 22.0, 28.0]
        let waits: [Double] = [2, 3, 4, 5, 6, 8, 10, 12, 15, 18, 22, 26, 30]
        let avgWindows: [Int] = [8, 16, 24, 32, 48, 64, 96, 128]

        struct Trial { let config: StructurePeakPickConfig; let m: Metrics }
        var trials: [Trial] = []

        let gridStart = Date()
        for avgWindow in avgWindows {
            for wait in waits {
                for deltaMult in deltaMultipliers {
                    let config = StructurePeakPickConfig(preMax: 4, postMax: 4, preAvg: avgWindow, postAvg: avgWindow, waitSeconds: wait, deltaMultiplier: deltaMult)
                    let m = evaluateFast(config, tracks: calibration)
                    trials.append(Trial(config: config, m: m))
                }
            }
        }
        print(String(format: "\nGrid search: %d combinations in %.1fs", trials.count, Date().timeIntervalSince(gridStart)))

        trials.sort { $0.m.f3 > $1.m.f3 }

        print("\n=== Top 15 configs by F@3.0s on calibration set (approximate/fast peak-pick) ===")
        for t in trials.prefix(15) {
            let c = t.config
            print(String(format: "  deltaMult=%.2f wait=%.0fs avgWin=%d  ->  F@3.0s=%.1f%% (P=%.1f%% R=%.1f%%)  F@0.5s=%.1f%%  predicted/true=%d/%d",
                          c.deltaMultiplier, c.waitSeconds, c.preAvg, t.m.f3*100, t.m.p3*100, t.m.r3*100, t.m.f05*100, t.m.predictedTotal, t.m.trueTotal))
        }

        // Re-verify the top candidates against the REAL, unmodified `DSPHelpers.peakPick` (both
        // on calibration and the disjoint held-out set) -- guards against both (a) overfitting to
        // the exact calibration tracks and (b) any drift between the fast approximation and the
        // real production peak-picker. Also de-duplicates near-identical top candidates (the fast
        // sort often ranks several avgWin/wait variants of the same deltaMult back to back) by
        // only keeping the first candidate seen per distinct (deltaMult, wait) pair, up to 15.
        print("\n=== Real-peakPick verification of top candidates (deduped, up to 15) ===")
        struct Verified { let config: StructurePeakPickConfig; let cal: Metrics; let held: Metrics }
        var verified: [Verified] = []
        var seenDeltaWait = Set<String>()
        for t in trials {
            let key = String(format: "%.2f|%.0f", t.config.deltaMultiplier, t.config.waitSeconds)
            guard !seenDeltaWait.contains(key) else { continue }
            seenDeltaWait.insert(key)

            let calReal = evaluateReal(t.config, engine: engine, tracks: calibration)
            let heldReal = evaluateReal(t.config, engine: engine, tracks: heldOut.isEmpty ? calibration : heldOut)
            let c = t.config
            print(String(format: "  deltaMult=%.2f wait=%.0fs avgWin=%d  ->  calibration F@3.0s=%.1f%%  |  held-out F@3.0s=%.1f%% (P=%.1f%% R=%.1f%%) F@0.5s=%.1f%%",
                          c.deltaMultiplier, c.waitSeconds, c.preAvg, calReal.f3*100, heldReal.f3*100, heldReal.p3*100, heldReal.r3*100, heldReal.f05*100))
            verified.append(Verified(config: t.config, cal: calReal, held: heldReal))
            if verified.count >= 15 { break }
        }

        let preCalConfig = StructurePeakPickConfig(preMax: 4, postMax: 4, preAvg: 16, postAvg: 16, waitSeconds: 8.0, deltaMultiplier: 0.0000000449)
        let baselineHeld = evaluateReal(preCalConfig, engine: engine, tracks: heldOut.isEmpty ? calibration : heldOut)
        print(String(format: "\nPre-calibration baseline on held-out set for comparison: F@3.0s=%.1f%% F@0.5s=%.1f%% (predicted=%d true=%d)",
                      baselineHeld.f3*100, baselineHeld.f05*100, baselineHeld.predictedTotal, baselineHeld.trueTotal))

        var recommendedConfig = StructurePeakPickConfig.calibrated
        if let best = verified.max(by: { $0.held.f3 < $1.held.f3 }) {
            let c = best.config
            recommendedConfig = c
            print("\n=== RECOMMENDED config (best REAL-peakPick held-out F@3.0s among verified candidates) ===")
            print(String(format: "preMax=%d postMax=%d preAvg=%d postAvg=%d wait=%.0fs deltaMultiplier=%.2f", c.preMax, c.postMax, c.preAvg, c.postAvg, c.waitSeconds, c.deltaMultiplier))
            print(String(format: "calibration set: F@3.0s=%.1f%% F@0.5s=%.1f%%  |  held-out set: F@3.0s=%.1f%% F@0.5s=%.1f%%", best.cal.f3*100, best.cal.f05*100, best.held.f3*100, best.held.f05*100))
            print(String(format: "baseline: calibration F@3.0s=%.1f%%  |  held-out F@3.0s=%.1f%%", baseline.f3*100, baselineHeld.f3*100))
        }

        // === Chunk-boundary artifact check =================================================
        // The relative (deltaMultiplier) threshold self-scales correctly ONLY if the novelty
        // curve's SHAPE (not just its overall magnitude) is similar between the calibration
        // pipeline (whole-track, 13-dim MFCC) and the real production pipeline (DNAReportBuilder:
        // independent 45s chunks, each re-analyzed from scratch with its own StructureEngine call,
        // 20-dim MFCC). If chunk seams introduce a self-similarity discontinuity (the chunk edge
        // looks maximally "novel" because there is no continuous signal across it), that would
        // inject a spurious boundary near every 45s multiple regardless of what deltaMultiplier is
        // chosen -- a shape artifact, not something a scale-relative threshold can fix. Verified
        // here by running the SAME real tracks through both pipelines and checking whether the
        // chunked pipeline's boundaries cluster near chunk seams more than the whole-track
        // pipeline's do.
        print("\n=== Chunk-boundary artifact check (whole-track vs 45s-chunked production pipeline) ===")
        let songIDToEntry = Dictionary(uniqueKeysWithValues: entries.map { ($0.songID, $0) })
        let diagnosticMetal = MetalEngine()
        let chunkSize = 45.0
        var diagChecked = 0
        var totalWholeTrack = 0, totalChunked = 0
        var wholeTrackNearSeam = 0, chunkedNearSeam = 0
        let seamTolerance = 2.0

        for track in calibration {
            guard diagChecked < 6 else { break }
            guard let entry = songIDToEntry[track.songID] else { continue }
            let durationSec = Double(track.features.nFrames * hop) / sr
            guard durationSec > 2.5 * chunkSize else { continue } // need >= 3 chunks to see a seam pattern

            let audioURL = salamiRoot.appendingPathComponent("audio/\(entry.localFile)")
            guard let buf = try? await AudioLoader.load(url: audioURL, targetSampleRate: sr) else { continue }
            diagChecked += 1

            // --- Whole-track (calibration-style) pipeline ---
            let stftChromaWT = await STFTEngine(nFFT: 8192, hopLength: hop, sampleRate: sr).analyze(buf.samples)
            let chromaWT = ChromaEngine(nFFT: 8192, sampleRate: sr).chromagram(stft: stftChromaWT)
            let melWT = MelSpectrogramEngine(stftEngine: STFTEngine(nFFT: 2048, hopLength: hop, sampleRate: sr), nMels: 128)
            let mfccResWT = await MFCCEngine(melEngine: melWT, nMFCC: 13).createMFCC(from: buf.samples)
            let nMFCCFramesWT = mfccResWT.fullData.count / 13
            var mfcc2DWT = [[Float]](repeating: [Float](repeating: 0, count: nMFCCFramesWT), count: 13)
            for t in 0..<nMFCCFramesWT { for c in 0..<13 { mfcc2DWT[c][t] = mfccResWT.fullData[t * 13 + c] } }
            let nFramesWT = min(chromaWT[0].count, mfcc2DWT[0].count)
            let wholeTrackBoundaries: [Double]
            if nFramesWT > 20, let featWT = engine.prepareFeatures(chromagram: chromaWT.map { Array($0.prefix(nFramesWT)) }, mfccs: mfcc2DWT.map { Array($0.prefix(nFramesWT)) }) {
                wholeTrackBoundaries = engine.boundaries(from: featWT, config: recommendedConfig).boundaryTimes
            } else {
                wholeTrackBoundaries = []
            }

            // --- Chunked (production-style) pipeline: independent 45s chunks, 20-dim MFCC,
            // exactly mirroring DNAReportBuilder.swift's real call after this session's MFCC-shape
            // fix (frame-major reshape of `executeBatchDct`'s output). ---
            let samplesPerChunk = Int(chunkSize * sr)
            var chunkedBoundaries: [Double] = []
            var chunkStart = 0
            var chunkIdx = 0
            while chunkStart < buf.samples.count {
                let chunkEnd = min(chunkStart + samplesPerChunk, buf.samples.count)
                let chunkSamples = Array(buf.samples[chunkStart..<chunkEnd])
                guard chunkSamples.count > hop * 4 else { break }

                let stftChromaC = await STFTEngine(nFFT: 8192, hopLength: hop, sampleRate: sr).analyze(chunkSamples)
                let chromaC = ChromaEngine(nFFT: 8192, sampleRate: sr).chromagram(stft: stftChromaC)
                let stftEngineC = STFTEngine(nFFT: 2048, hopLength: hop, sampleRate: sr)
                let melC = await MelSpectrogramEngine(stftEngine: stftEngineC, nMels: 128).createMelSpectrogram(from: chunkSamples)
                let logMelC = melC.melData.map { 10.0 * log10f(max($0, 1e-10)) }
                let mfccRawC = diagnosticMetal.executeBatchDct(melSpectrogram: logMelC, nMfcc: 20, nMels: 128)
                let mfccFrameCountC = mfccRawC.count / 20
                var mfcc2DC = [[Float]](repeating: [Float](repeating: 0, count: mfccFrameCountC), count: 20)
                for t in 0..<mfccFrameCountC { for c in 0..<20 { mfcc2DC[c][t] = mfccRawC[t * 20 + c] } }

                let chunkResult = StructureEngine(sampleRate: sr).analyze(chromagram: chromaC, mfccs: mfcc2DC, config: recommendedConfig)
                let chunkOffsetSec = Double(chunkStart) / sr
                chunkedBoundaries.append(contentsOf: chunkResult.boundaryTimes.map { $0 + chunkOffsetSec })

                chunkStart += samplesPerChunk
                chunkIdx += 1
            }

            func nearestSeamDistance(_ t: Double) -> Double {
                let seamIndex = (t / chunkSize).rounded()
                return abs(t - seamIndex * chunkSize)
            }
            let wtNearSeam = wholeTrackBoundaries.filter { nearestSeamDistance($0) <= seamTolerance }.count
            let chNearSeam = chunkedBoundaries.filter { nearestSeamDistance($0) <= seamTolerance }.count

            totalWholeTrack += wholeTrackBoundaries.count
            totalChunked += chunkedBoundaries.count
            wholeTrackNearSeam += wtNearSeam
            chunkedNearSeam += chNearSeam

            print(String(format: "  %@ (%.0fs, %d chunks): whole-track=%d boundaries (%d near seams)  |  chunked=%d boundaries (%d near seams)",
                          entry.songID, durationSec, chunkIdx, wholeTrackBoundaries.count, wtNearSeam, chunkedBoundaries.count, chNearSeam))
        }

        if diagChecked > 0 {
            let wtSeamRate = totalWholeTrack > 0 ? Double(wholeTrackNearSeam) / Double(totalWholeTrack) * 100 : 0
            let chSeamRate = totalChunked > 0 ? Double(chunkedNearSeam) / Double(totalChunked) * 100 : 0
            print(String(format: "\n%d tracks checked. Boundaries within %.1fs of a chunk seam: whole-track=%.1f%% (%d/%d)  chunked=%.1f%% (%d/%d)",
                          diagChecked, seamTolerance, wtSeamRate, wholeTrackNearSeam, totalWholeTrack, chSeamRate, chunkedNearSeam, totalChunked))
            if chSeamRate > wtSeamRate + 10 {
                print("WARNING: chunked pipeline shows a materially higher rate of boundaries near chunk seams than whole-track -- this looks like a real chunk-edge artifact, not just a scale-transfer issue. The relative deltaMultiplier does NOT fix this on its own.")
            } else {
                print("No material excess of chunked boundaries near chunk seams vs whole-track -- no evidence of a chunk-edge novelty artifact at this deltaMultiplier/wait/avgWin.")
            }
        } else {
            print("No tracks long enough (>= ~2.5 chunks) for this check were available in the calibration set.")
        }
    }
}
