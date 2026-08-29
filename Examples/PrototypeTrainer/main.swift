// PrototypeTrainer — computes InstrumentEngine's 6 coarse-class prototype fingerprints
// (centroid range, flatness ceiling, mean MFCC) from real OpenMIC-2018 TRAINING data,
// replacing the original hand-typed placeholder values (which were never fit to any real
// audio at all). See DEVLOG Phase 16.
//
// Methodology:
//   - Uses OpenMIC-2018's OFFICIAL train/test split (`partitions/split01_train.csv`) — only
//     TRAIN-partition audio is used here, so the held-out test partition (and all of IRMAS,
//     a separate dataset never touched by this trainer) remain a fair, uncontaminated
//     accuracy measurement.
//   - Only OpenMIC fine-grained instrument labels with an UNAMBIGUOUS single coarse-class
//     mapping are used (14 of OpenMIC's 20 classes — e.g. "piano"->Piano/Keyboard,
//     "trumpet"->Brass/Trumpet). Fine classes that map to two coarse classes in
//     ReliabilityAudit's evaluation mapping (clarinet, flute, mallet_percussion, synthesizer)
//     are excluded from training to keep prototypes clean, though they still count normally
//     during evaluation's lenient "acceptable set" scoring.
//   - A clip is used only if its ENTIRE set of relevance>=0.5 positive labels maps to a
//     SINGLE coarse class — OpenMIC clips are often genuinely polyphonic/multi-label (e.g.
//     positive for both "guitar" and "voice"); including those would blend two different
//     instruments' timbre into both prototypes. This is real data, not a workaround: many
//     OpenMIC clips get skipped this way, which is itself an honest signal about how much of
//     real music isn't single-source — separate from prototype quality.
//   - Outputs mean +/- 1 standard deviation for centroid (feeds the existing Gaussian
//     centroid-scoring formula's center/half-width directly) and flatness (mean + 1 SD as the
//     "typical ceiling" for the linear flatness taper), and the mean 10-coefficient MFCC
//     vector, ready to paste into `InstrumentEngine.swift`.
//
// Usage: swift run -c release PrototypeTrainer

import Foundation
import AudioIntelligence
import AudioIntelligenceCore

let coarseClasses = ["Piano/Keyboard", "Bass (Acoustic/Electric)", "Brass/Trumpet", "Vocals/Chorus", "Drums/Percussion", "Strings/Synth"]

let openmicToSingleCoarse: [String: String] = [
    "accordion": "Piano/Keyboard",
    "banjo": "Strings/Synth",
    "bass": "Bass (Acoustic/Electric)",
    "cello": "Strings/Synth",
    "cymbals": "Drums/Percussion",
    "drums": "Drums/Percussion",
    "guitar": "Strings/Synth",
    "mandolin": "Strings/Synth",
    "organ": "Piano/Keyboard",
    "piano": "Piano/Keyboard",
    "saxophone": "Brass/Trumpet",
    "trombone": "Brass/Trumpet",
    "trumpet": "Brass/Trumpet",
    "ukulele": "Strings/Synth",
    "violin": "Strings/Synth",
    "voice": "Vocals/Chorus",
]

struct Accumulator {
    var count = 0
    var centroidSum: Double = 0, centroidSqSum: Double = 0
    var flatnessSum: Double = 0, flatnessSqSum: Double = 0
    var mfccSum = [Double](repeating: 0, count: 10)
}

func stddev(sum: Double, sqSum: Double, n: Int) -> Double {
    guard n > 1 else { return 0 }
    let mean = sum / Double(n)
    let variance = max(0, sqSum / Double(n) - mean * mean)
    return variance.squareRoot()
}

@main
struct PrototypeTrainer {
    static func main() async {
        let base = URL(fileURLWithPath: "Tests/Resources/OpenMIC").resolvingSymlinksInPath()
        let csvURL = base.appendingPathComponent("openmic-2018-aggregated-labels.csv")
        let trainURL = base.appendingPathComponent("partitions/split01_train.csv")

        guard let csv = try? String(contentsOf: csvURL, encoding: .utf8) else {
            print("ERROR: could not read \(csvURL.path)"); return
        }
        guard let trainList = try? String(contentsOf: trainURL, encoding: .utf8) else {
            print("ERROR: could not read \(trainURL.path)"); return
        }
        let trainKeys = Set(trainList.split(separator: "\n").map(String.init))
        print("🔎 PrototypeTrainer — \(trainKeys.count) train-partition keys loaded")

        var positives: [String: Set<String>] = [:]
        for line in csv.split(separator: "\n").dropFirst() {
            let cols = line.split(separator: ",")
            guard cols.count >= 3, let relevance = Double(cols[2]) else { continue }
            if relevance >= 0.5 {
                positives[String(cols[0]), default: []].insert(String(cols[1]))
            }
        }

        var accumulators: [String: Accumulator] = [:]
        for cls in coarseClasses { accumulators[cls] = Accumulator() }

        var processed = 0, skippedAmbiguous = 0, skippedMissing = 0, skippedLoadFailed = 0

        for key in trainKeys.sorted() {
            guard let fine = positives[key] else { continue }
            let mappedCoarse = Set(fine.compactMap { openmicToSingleCoarse[$0] })
            guard mappedCoarse.count == 1, let coarse = mappedCoarse.first else {
                skippedAmbiguous += 1
                continue
            }

            let prefix = String(key.prefix(3))
            let audioURL = base.appendingPathComponent("audio/\(prefix)/\(key).ogg")
            guard FileManager.default.fileExists(atPath: audioURL.path) else {
                skippedMissing += 1
                continue
            }
            guard let buf = try? await AudioLoader.load(url: audioURL, targetSampleRate: 22050) else {
                skippedLoadFailed += 1
                continue
            }

            let stftEngine = STFTEngine(nFFT: 2048, hopLength: 512, sampleRate: 22050)
            let stft = await stftEngine.analyze(buf.samples)
            let specRaw = SpectralEngine(sampleRate: 22050).analyze(stft: stft, samples: buf.samples)
            let mel = MelSpectrogramEngine(stftEngine: stftEngine, nMels: 128)
            let mfccEngine = MFCCEngine(melEngine: mel, nMFCC: 20)
            let mfcc = await mfccEngine.createMFCC(from: buf.samples)
            let mfccVec = Array(mfcc.mfcc.prefix(10))

            var acc = accumulators[coarse]!
            acc.count += 1
            acc.centroidSum += Double(specRaw.centroidHz)
            acc.centroidSqSum += Double(specRaw.centroidHz) * Double(specRaw.centroidHz)
            acc.flatnessSum += Double(specRaw.flatness)
            acc.flatnessSqSum += Double(specRaw.flatness) * Double(specRaw.flatness)
            for i in 0..<min(10, mfccVec.count) {
                acc.mfccSum[i] += Double(mfccVec[i])
            }
            accumulators[coarse] = acc

            processed += 1
            if processed % 500 == 0 {
                print("... \(processed) processed (skipped: \(skippedAmbiguous) ambiguous, \(skippedMissing) missing, \(skippedLoadFailed) load-failed)")
            }
        }

        print("\n=== Training complete: \(processed) processed, \(skippedAmbiguous) skipped (ambiguous/multi-label), \(skippedMissing) skipped (missing file), \(skippedLoadFailed) skipped (load failed) ===\n")

        for cls in coarseClasses {
            let a = accumulators[cls]!
            guard a.count > 0 else { print("// \(cls): NO SAMPLES\n"); continue }
            let n = Double(a.count)
            let meanCentroid = a.centroidSum / n
            let sdCentroid = stddev(sum: a.centroidSum, sqSum: a.centroidSqSum, n: a.count)
            let meanFlatness = a.flatnessSum / n
            let sdFlatness = stddev(sum: a.flatnessSum, sqSum: a.flatnessSqSum, n: a.count)
            let meanMfcc = a.mfccSum.map { $0 / n }

            print("// \(cls): n=\(a.count)")
            print(String(format: "//   centroid: mean=%.1f sd=%.1f", meanCentroid, sdCentroid))
            print(String(format: "//   flatness: mean=%.4f sd=%.4f", meanFlatness, sdFlatness))

            let lo = max(0.0, meanCentroid - sdCentroid)
            let hi = meanCentroid + sdCentroid
            let flatMax = min(1.0, meanFlatness + sdFlatness)
            let mfccStr = meanMfcc.map { String(format: "%.4f", $0) }.joined(separator: ", ")
            print(String(format: "centroidRange: %.1f...%.1f,", lo, hi))
            print(String(format: "flatnessMax: %.4f,", flatMax))
            print("mfccPattern: [\(mfccStr)],")
            print("")
        }
    }
}
