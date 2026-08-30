import XCTest
@testable import AudioIntelligenceCore

/// Diagnostic (train-partition only). Investigates WHY excluding MFCC-0 from the timbre distance
/// helps Bass/Drums/Strings but hurts Vocals/Brass. Two questions:
///  1. Does each class's OWN real MFCC-0 value cluster tightly around its own profile mean, or is
///     it broadly scattered? (If Vocals' real MFCC-0 is a clean, reliable signal and the others'
///     isn't, that's a principled reason to treat them differently, not an arbitrary tuning knob.)
///  2. For clips where excluding MFCC-0 causes a NEW misclassification (a real regression), who
///     steals the spot, and was MFCC-0 the specific term that used to correctly hold them off?
final class ZZVocalsRegressionDiagnosticTests: XCTestCase {
    private let mfccProfiles: [(label: String, pattern: [Float])] = [
        ("Piano/Keyboard", [-254.0938, 200.2891, -27.6288, 21.4378, -8.3042, 5.9155, -12.8358, -0.2233, -12.0884, -1.6733]),
        ("Bass (Acoustic/Electric)", [-260.4742, 169.5767, 7.7181, 48.0809, 8.7370, 20.7677, 0.1662, 10.1528, -3.3805, 4.8324]),
        ("Brass/Trumpet", [-176.3196, 132.1528, -26.2923, 27.7467, -7.9017, 8.7645, -9.4724, 3.0261, -9.2911, 1.7307]),
        ("Vocals/Chorus", [-85.9054, 116.4970, -23.1897, 25.9314, -9.8890, 5.3297, -6.9698, 4.7533, -9.3628, 5.9014]),
        ("Drums/Percussion", [-120.2319, 93.8670, -5.1137, 35.9895, -3.2795, 14.7737, -3.8496, 8.8711, -4.2021, 6.2101]),
        ("Strings/Synth", [-199.9608, 145.2058, -27.1025, 33.6395, -9.2643, 4.4564, -11.2757, 1.5405, -11.5215, -1.5284]),
    ]
    private let openmicToSingleCoarse: [String: String] = [
        "accordion": "Piano/Keyboard", "organ": "Piano/Keyboard", "piano": "Piano/Keyboard",
        "bass": "Bass (Acoustic/Electric)",
        "saxophone": "Brass/Trumpet", "trombone": "Brass/Trumpet", "trumpet": "Brass/Trumpet",
        "voice": "Vocals/Chorus",
        "cymbals": "Drums/Percussion", "drums": "Drums/Percussion",
        "banjo": "Strings/Synth", "cello": "Strings/Synth", "guitar": "Strings/Synth",
        "mandolin": "Strings/Synth", "ukulele": "Strings/Synth", "violin": "Strings/Synth",
    ]

    private func timbreScoreExcluding(_ excluded: Set<Int>, input: [Float], pattern: [Float]) -> Float {
        var dist: Float = 0
        for i in 0..<min(input.count, pattern.count) where !excluded.contains(i) {
            let d = input[i] - pattern[i]
            dist += d * d
        }
        return max(0, 0.4 - sqrtf(dist) / 250.0)
    }

    func testWhyVocalsAndBrassRegress() async throws {
        let base = URL(fileURLWithPath: "Tests/Resources/OpenMIC").resolvingSymlinksInPath()
        let csvURL = base.appendingPathComponent("openmic-2018-aggregated-labels.csv")
        let trainURL = base.appendingPathComponent("partitions/split01_train.csv")
        guard let csv = try? String(contentsOf: csvURL, encoding: .utf8),
              let trainList = try? String(contentsOf: trainURL, encoding: .utf8) else {
            throw XCTSkip("OpenMIC dataset not available")
        }
        let trainKeys = Set(trainList.split(separator: "\n").map(String.init))

        var positives: [String: Set<String>] = [:]
        for line in csv.split(separator: "\n").dropFirst() {
            let cols = line.split(separator: ",")
            guard cols.count >= 3, let relevance = Double(cols[2]) else { continue }
            if relevance >= 0.5 { positives[String(cols[0]), default: []].insert(String(cols[1])) }
        }

        var perClassKeys: [String: [String]] = [:]
        for key in trainKeys.sorted() {
            guard let fine = positives[key] else { continue }
            let mapped = Set(fine.compactMap { openmicToSingleCoarse[$0] })
            guard mapped.count == 1, let coarse = mapped.first else { continue }
            perClassKeys[coarse, default: []].append(key)
        }
        for k in perClassKeys.keys { perClassKeys[k] = Array(perClassKeys[k]!.prefix(30)) }

        // Question 1: per-class raw MFCC-0 clustering (mean/SD of the REAL input, not the profile).
        var rawMFCC0ByClass: [String: [Float]] = [:]
        // Question 2: regression cases for Vocals/Brass specifically.
        var regressionDetails: [String] = []

        for (trueLabel, keys) in perClassKeys {
            for key in keys {
                let prefix = String(key.prefix(3))
                let audioURL = base.appendingPathComponent("audio/\(prefix)/\(key).ogg")
                guard FileManager.default.fileExists(atPath: audioURL.path),
                      let buf = try? await AudioLoader.load(url: audioURL, targetSampleRate: 22050) else { continue }

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
                let hpss = HPSSEngine(winHarm: 31, winPerc: 31).analyze(stft: stft)
                let inputPattern = Array(mfcc.mfcc.prefix(10))
                rawMFCC0ByClass[trueLabel, default: []].append(inputPattern[0])

                guard trueLabel == "Vocals/Chorus" || trueLabel == "Brass/Trumpet" else { continue }

                let breakdown = InstrumentEngine().predictWithBreakdown(
                    spectral: spectral, mfcc: inputPattern,
                    lowBandEnergyRatio: lowBand, percussiveEnergyRatio: hpss.percussiveEnergyRatio)
                guard let oldWinner = breakdown.max(by: { $0.total < $1.total }) else { continue }

                var bestLabel = "", bestTotal: Float = -1
                for (label, pattern) in mfccProfiles {
                    guard let b = breakdown.first(where: { $0.label == label }) else { continue }
                    let newTimbre = timbreScoreExcluding([0], input: inputPattern, pattern: pattern)
                    let newTotal = b.centroidScore + b.flatnessScore + b.lowBandScore + b.percussiveScore + newTimbre
                    if newTotal > bestTotal { bestTotal = newTotal; bestLabel = label }
                }

                let wasCorrectBefore = oldWinner.label == trueLabel
                let isCorrectAfter = bestLabel == trueLabel
                if wasCorrectBefore && !isCorrectAfter {
                    let truePattern = mfccProfiles.first { $0.label == trueLabel }!.pattern
                    let newPattern = mfccProfiles.first { $0.label == bestLabel }!.pattern
                    let coeff0DistTrue = abs(inputPattern[0] - truePattern[0])
                    let coeff0DistNew = abs(inputPattern[0] - newPattern[0])
                    regressionDetails.append(
                        "key=\(key) true=\(trueLabel) input.mfcc0=\(inputPattern[0]) -> now wins: \(bestLabel) " +
                        "[coeff0: |input-true|=\(coeff0DistTrue) |input-newWinner|=\(coeff0DistNew)]")
                }
            }
        }

        print("\n=== Q1: per-class REAL input MFCC-0 clustering (mean ± SD) ===")
        for label in rawMFCC0ByClass.keys.sorted() {
            let vals = rawMFCC0ByClass[label]!
            let mean = vals.reduce(0,+) / Float(vals.count)
            let sd = sqrtf(vals.map { ($0-mean)*($0-mean) }.reduce(0,+) / Float(vals.count))
            let profileMean = mfccProfiles.first { $0.label == label }!.pattern[0]
            print(String(format: "%@: real mean=%.1f sd=%.1f  (profile/training mean was %.1f, diff=%.1f)",
                          label, mean, sd, profileMean, abs(mean - profileMean)))
        }

        print("\n=== Q2: Vocals/Brass regression cases (correct before, wrong after excluding MFCC-0) ===")
        regressionDetails.forEach { print($0) }
        print("regression count: \(regressionDetails.count)")
        XCTAssertTrue(true)
    }
}
