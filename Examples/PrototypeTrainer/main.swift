// PrototypeTrainer — computes InstrumentEngine's 6 coarse-class prototype fingerprints
// (centroid, flatness, low-band energy ratio, percussive energy ratio — all as Gaussian
// mean+SD — plus mean MFCC) from real OpenMIC-2018 TRAINING data, replacing the original
// hand-typed placeholder values (which were never fit to any real audio at all). See DEVLOG
// Phase 16.
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
//   - Every one of the 6 coarse classes gets a mean+SD for ALL FOUR spatial/spectral-shape
//     features (centroid, flatness, low-band energy ratio, percussive energy ratio) — not just
//     the classes each feature was originally motivated by (Bass/low-band, Drums/percussive).
//     Feature values are class-independent per-recording measurements; withholding a feature
//     from a class removes exactly the information needed to separate that class from the ones
//     that DO get it (e.g. a low-lowband Piano recording needs Piano's own lowband distribution
//     to be correctly placed away from Bass). Also reports flatness/low-band/percussive skew
//     (third standardized moment) so a badly non-Gaussian distribution is visible before fitting
//     a Gaussian score to it.
//
// Usage: swift run -c release PrototypeTrainer

import Foundation
import AudioIntelligence
import AudioIntelligenceCore
import AudioIntelligenceMetal
import Accelerate

// Shared GPU engine — passed to `HPSSEngine` so its 2D median filter offloads to Metal instead
// of the CPU fallback (real spectrograms here are always above the GPU-dispatch threshold).
let sharedMetalEngine = MetalEngine()

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


/// Running moment accumulator (sum, sum of squares, sum of cubes) for one scalar feature —
/// enough to compute mean, SD, and skewness in one pass without storing every raw value.
struct MomentAccumulator {
    var sum: Double = 0, sqSum: Double = 0, cubeSum: Double = 0
    mutating func add(_ x: Double) { sum += x; sqSum += x * x; cubeSum += x * x * x }
    func mean(_ n: Int) -> Double { n > 0 ? sum / Double(n) : 0 }
    func sd(_ n: Int) -> Double {
        guard n > 1 else { return 0 }
        let m = mean(n)
        return max(0, sqSum / Double(n) - m * m).squareRoot()
    }
    /// Fisher-Pearson standardized skewness: 0 = symmetric, >0 = right-tailed, <0 = left-tailed.
    /// Values roughly in [-0.5, 0.5] are "close to symmetric"; beyond +-1 is notably skewed.
    func skewness(_ n: Int) -> Double {
        guard n > 2 else { return 0 }
        let m = mean(n)
        let variance = max(1e-12, sqSum / Double(n) - m * m)
        let sd = variance.squareRoot()
        let thirdMoment = cubeSum / Double(n) - 3 * m * (sqSum / Double(n)) + 2 * m * m * m
        return thirdMoment / (sd * sd * sd)
    }
}

struct Accumulator {
    var count = 0
    var centroid = MomentAccumulator()
    var flatness = MomentAccumulator()
    var lowBand = MomentAccumulator()
    var percussive = MomentAccumulator()
    var mfccSum = [Double](repeating: 0, count: 10)
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
            let lowBand = DSPHelpers.lowBandEnergyRatio(stft: stft, cutoffHz: 250)
            let hpss = HPSSEngine(winHarm: 31, winPerc: 31, metalEngine: sharedMetalEngine).analyze(stft: stft)

            var acc = accumulators[coarse]!
            acc.count += 1
            acc.centroid.add(Double(specRaw.centroidHz))
            acc.flatness.add(Double(specRaw.flatness))
            acc.lowBand.add(Double(lowBand))
            acc.percussive.add(Double(hpss.percussiveEnergyRatio))
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

        print("=== SKEWNESS CHECK (0 = symmetric; roughly |skew| < 1 is close enough for a Gaussian score) ===")
        for cls in coarseClasses {
            let a = accumulators[cls]!
            guard a.count > 2 else { continue }
            print(String(format: "  %@: flatness skew=%.2f  lowBand skew=%.2f  percussive skew=%.2f",
                          cls, a.flatness.skewness(a.count), a.lowBand.skewness(a.count), a.percussive.skewness(a.count)))
        }
        print("")

        for cls in coarseClasses {
            let a = accumulators[cls]!
            guard a.count > 0 else { print("// \(cls): NO SAMPLES\n"); continue }
            let n = Double(a.count)
            let meanMfcc = a.mfccSum.map { $0 / n }
            let mfccStr = meanMfcc.map { String(format: "%.4f", $0) }.joined(separator: ", ")

            print("// \(cls): n=\(a.count)")
            print(String(format: "//   centroid:   mean=%.1f sd=%.1f", a.centroid.mean(a.count), a.centroid.sd(a.count)))
            print(String(format: "//   flatness:   mean=%.4f sd=%.4f", a.flatness.mean(a.count), a.flatness.sd(a.count)))
            print(String(format: "//   lowBand:    mean=%.4f sd=%.4f", a.lowBand.mean(a.count), a.lowBand.sd(a.count)))
            print(String(format: "//   percussive: mean=%.4f sd=%.4f", a.percussive.mean(a.count), a.percussive.sd(a.count)))
            print(String(format: "centroidMean: %.1f, centroidSD: %.1f,", a.centroid.mean(a.count), a.centroid.sd(a.count)))
            print(String(format: "flatnessMean: %.4f, flatnessSD: %.4f,", a.flatness.mean(a.count), a.flatness.sd(a.count)))
            print(String(format: "lowBandMean: %.4f, lowBandSD: %.4f,", a.lowBand.mean(a.count), a.lowBand.sd(a.count)))
            print(String(format: "percussiveMean: %.4f, percussiveSD: %.4f,", a.percussive.mean(a.count), a.percussive.sd(a.count)))
            print("mfccPattern: [\(mfccStr)],")
            print("")
        }
    }
}
