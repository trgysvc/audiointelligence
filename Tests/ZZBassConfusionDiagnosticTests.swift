import XCTest
@testable import AudioIntelligenceCore

/// Diagnostic (train-partition only — test partition stays untouched per the session's train/
/// test separation rule). For real Bass-labeled OpenMIC TRAIN clips, computes the full 6-class
/// score breakdown and, whenever Bass is NOT the top prediction, identifies which class won and
/// on which specific term (centroid/flatness/lowBand/percussive/timbre) it won most decisively —
/// looking for a genuine, fixable pattern rather than guessing.
final class ZZBassConfusionDiagnosticTests: XCTestCase {
    // Hardcoded copy of InstrumentEngine's own mfccPattern table (Sources/.../InstrumentEngine.swift)
    // — needed here only to test a hypothesis (does excluding MFCC-0, pure log-energy/loudness,
    // from the timbre distance improve Bass discrimination) against real data BEFORE touching
    // production code. Not a production-logic duplication, just the literal reference numbers.
    private let mfccProfiles: [(label: String, pattern: [Float])] = [
        ("Piano/Keyboard", [-254.0938, 200.2891, -27.6288, 21.4378, -8.3042, 5.9155, -12.8358, -0.2233, -12.0884, -1.6733]),
        ("Bass (Acoustic/Electric)", [-260.4742, 169.5767, 7.7181, 48.0809, 8.7370, 20.7677, 0.1662, 10.1528, -3.3805, 4.8324]),
        ("Brass/Trumpet", [-176.3196, 132.1528, -26.2923, 27.7467, -7.9017, 8.7645, -9.4724, 3.0261, -9.2911, 1.7307]),
        ("Vocals/Chorus", [-85.9054, 116.4970, -23.1897, 25.9314, -9.8890, 5.3297, -6.9698, 4.7533, -9.3628, 5.9014]),
        ("Drums/Percussion", [-120.2319, 93.8670, -5.1137, 35.9895, -3.2795, 14.7737, -3.8496, 8.8711, -4.2021, 6.2101]),
        ("Strings/Synth", [-199.9608, 145.2058, -27.1025, 33.6395, -9.2643, 4.4564, -11.2757, 1.5405, -11.5215, -1.5284]),
    ]

    /// mfccDistance/timbreScore recomputed with a configurable set of excluded coefficient
    /// indices, to test whether MFCC-0 (log-energy, not spectral shape) is diluting the
    /// discrimination the other 9 shape-carrying coefficients could otherwise provide.
    private func timbreScoreExcluding(_ excluded: Set<Int>, input: [Float], pattern: [Float]) -> Float {
        var dist: Float = 0
        for i in 0..<min(input.count, pattern.count) where !excluded.contains(i) {
            let d = input[i] - pattern[i]
            dist += d * d
        }
        dist = sqrtf(dist)
        return max(0, 0.4 - dist / 250.0)
    }

    func testBassConfusion_onTrainPartition() async throws {
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

        // Unambiguous single-label Bass clips only (matches PrototypeTrainer's own purity rule).
        let bassKeys = trainKeys.filter { positives[$0] == ["bass"] }.sorted().prefix(80)
        XCTAssertFalse(bassKeys.isEmpty, "expected some unambiguous Bass train clips")

        var hitCount = 0
        var winnerCounts: [String: Int] = [:]
        var winningTermCounts: [String: Int] = [:] // which term gave the winner its biggest edge over Bass
        var hitCountNoMFCC0 = 0 // hypothetical: timbre distance excludes coeff 0 (log-energy)

        for key in bassKeys {
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
            guard let bass = breakdown.first(where: { $0.label == "Bass (Acoustic/Electric)" }),
                  let winner = breakdown.max(by: { $0.total < $1.total }) else { continue }

            // Hypothetical: same 4 non-timbre terms (already computed by production code, kept
            // as-is), but timbre recomputed excluding MFCC-0. Does Bass win under this scoring?
            let inputPattern = Array(mfcc.mfcc.prefix(10))
            var bestHypoLabel = ""
            var bestHypoTotal: Float = -1
            for (label, pattern) in mfccProfiles {
                guard let b = breakdown.first(where: { $0.label == label }) else { continue }
                let newTimbre = timbreScoreExcluding([0], input: inputPattern, pattern: pattern)
                let newTotal = b.centroidScore + b.flatnessScore + b.lowBandScore + b.percussiveScore + newTimbre
                if newTotal > bestHypoTotal { bestHypoTotal = newTotal; bestHypoLabel = label }
            }
            if bestHypoLabel == "Bass (Acoustic/Electric)" { hitCountNoMFCC0 += 1 }

            if winner.label == "Bass (Acoustic/Electric)" {
                hitCount += 1
                continue
            }
            winnerCounts[winner.label, default: 0] += 1

            let deltas: [(String, Float)] = [
                ("centroid", winner.centroidScore - bass.centroidScore),
                ("flatness", winner.flatnessScore - bass.flatnessScore),
                ("lowBand", winner.lowBandScore - bass.lowBandScore),
                ("percussive", winner.percussiveScore - bass.percussiveScore),
                ("timbre", winner.timbreScore - bass.timbreScore),
            ]
            let biggestTerm = deltas.max { $0.1 < $1.1 }!.0
            winningTermCounts[biggestTerm, default: 0] += 1

            print("key=\(key) winner=\(winner.label)(\(winner.total)) bass=\(bass.total) biggestEdgeTerm=\(biggestTerm) " +
                  "deltas: centroid=\(deltas[0].1) flatness=\(deltas[1].1) lowBand=\(deltas[2].1) percussive=\(deltas[3].1) timbre=\(deltas[4].1) " +
                  "[bass lowBandScore=\(bass.lowBandScore) winner lowBandScore=\(winner.lowBandScore)]")
        }

        let total = hitCount + winnerCounts.values.reduce(0, +)
        print("\n=== BASS CONFUSION DIAGNOSTIC (train partition, n=\(total)) ===")
        print("hits (current production formula): \(hitCount)/\(total)")
        print("hits (hypothetical: timbre distance excludes MFCC-0): \(hitCountNoMFCC0)/\(total)")
        print("who wins instead of Bass: \(winnerCounts.sorted { $0.value > $1.value })")
        print("which term gives the winner its biggest edge: \(winningTermCounts.sorted { $0.value > $1.value })")
        XCTAssertTrue(true)
    }
}
