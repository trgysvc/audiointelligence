import XCTest
@testable import AudioIntelligenceCore

/// Diagnostic (train-partition only). Checks whether excluding MFCC-0 (log-energy, not spectral
/// shape) from InstrumentEngine's timbre distance — a real, principled fix candidate found while
/// investigating Bass's weak recall — helps or hurts EACH of the 6 classes, not just Bass. A fix
/// that helps Bass at the cost of breaking others is not a net improvement.
final class ZZAllClassMFCC0DiagnosticTests: XCTestCase {
    private let mfccProfiles: [(label: String, pattern: [Float])] = [
        ("Piano/Keyboard", [-254.0938, 200.2891, -27.6288, 21.4378, -8.3042, 5.9155, -12.8358, -0.2233, -12.0884, -1.6733]),
        ("Bass (Acoustic/Electric)", [-260.4742, 169.5767, 7.7181, 48.0809, 8.7370, 20.7677, 0.1662, 10.1528, -3.3805, 4.8324]),
        ("Brass/Trumpet", [-176.3196, 132.1528, -26.2923, 27.7467, -7.9017, 8.7645, -9.4724, 3.0261, -9.2911, 1.7307]),
        ("Vocals/Chorus", [-85.9054, 116.4970, -23.1897, 25.9314, -9.8890, 5.3297, -6.9698, 4.7533, -9.3628, 5.9014]),
        ("Drums/Percussion", [-120.2319, 93.8670, -5.1137, 35.9895, -3.2795, 14.7737, -3.8496, 8.8711, -4.2021, 6.2101]),
        ("Strings/Synth", [-199.9608, 145.2058, -27.1025, 33.6395, -9.2643, 4.4564, -11.2757, 1.5405, -11.5215, -1.5284]),
    ]
    // OpenMIC fine labels mapping unambiguously to ONE coarse class (mirrors PrototypeTrainer).
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
        dist = sqrtf(dist)
        return max(0, 0.4 - dist / 250.0)
    }

    func testAllClasses_currentVsMFCC0Excluded() async throws {
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

        // Per coarse class: unambiguous single-fine-label train clips, capped at 30 each for time.
        var perClassKeys: [String: [String]] = [:]
        for key in trainKeys.sorted() {
            guard let fine = positives[key] else { continue }
            let mapped = Set(fine.compactMap { openmicToSingleCoarse[$0] })
            guard mapped.count == 1, let coarse = mapped.first else { continue }
            perClassKeys[coarse, default: []].append(key)
        }
        for k in perClassKeys.keys { perClassKeys[k] = Array(perClassKeys[k]!.prefix(30)) }

        var currentHits: [String: Int] = [:], newHits: [String: Int] = [:], counts: [String: Int] = [:]

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

                let breakdown = InstrumentEngine().predictWithBreakdown(
                    spectral: spectral, mfcc: Array(mfcc.mfcc.prefix(10)),
                    lowBandEnergyRatio: lowBand, percussiveEnergyRatio: hpss.percussiveEnergyRatio)
                guard let currentWinner = breakdown.max(by: { $0.total < $1.total }) else { continue }

                let inputPattern = Array(mfcc.mfcc.prefix(10))
                var bestLabel = "", bestTotal: Float = -1
                for (label, pattern) in mfccProfiles {
                    guard let b = breakdown.first(where: { $0.label == label }) else { continue }
                    let newTimbre = timbreScoreExcluding([0], input: inputPattern, pattern: pattern)
                    let newTotal = b.centroidScore + b.flatnessScore + b.lowBandScore + b.percussiveScore + newTimbre
                    if newTotal > bestTotal { bestTotal = newTotal; bestLabel = label }
                }

                counts[trueLabel, default: 0] += 1
                if currentWinner.label == trueLabel { currentHits[trueLabel, default: 0] += 1 }
                if bestLabel == trueLabel { newHits[trueLabel, default: 0] += 1 }
            }
        }

        print("\n=== ALL-CLASS MFCC-0-EXCLUSION IMPACT (train partition) ===")
        var totalN = 0, totalCurrent = 0, totalNew = 0
        for label in counts.keys.sorted() {
            let n = counts[label] ?? 0
            let cur = currentHits[label] ?? 0
            let new = newHits[label] ?? 0
            totalN += n; totalCurrent += cur; totalNew += new
            print(String(format: "%@: n=%d current=%d (%.1f%%) mfcc0-excluded=%d (%.1f%%)",
                          label, n, cur, Double(cur)/Double(n)*100, new, Double(new)/Double(n)*100))
        }
        print(String(format: "TOTAL: n=%d current=%d (%.1f%%) mfcc0-excluded=%d (%.1f%%)",
                      totalN, totalCurrent, Double(totalCurrent)/Double(totalN)*100, totalNew, Double(totalNew)/Double(totalN)*100))
        XCTAssertTrue(true)
    }
}
