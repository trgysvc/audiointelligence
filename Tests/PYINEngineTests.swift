import XCTest
@testable import AudioIntelligenceCore

/// Closing-evidence comparison for the pYIN implementation: YIN vs. pYIN side-by-side on real
/// MDB-stem-synth stems (synthesis-derived ground truth f0 — the strongest kind available, not
/// a human/algorithmic estimate). Not just Raw Pitch Accuracy (<50 cents) — also voicing-decision
/// accuracy and Gross Pitch Error (GPE), since pYIN's real advantage over YIN is usually in
/// voicing/octave-error robustness, not fine cent-accuracy.
///
/// This test caught a real, severe bug before it shipped: the first `PYINDecoder` observation
/// model followed the Mauch & Dixon (2014) paper's eq. 6 literally (`0.5*p*_m` voiced /
/// `0.5*(1-Sigma p*_k)` unvoiced, the SAME value repeated across all 480 unvoiced bins) and
/// collapsed to near-total "unvoiced" on real audio (RPA 2.0% vs. YIN's 50.6%, only 4353/207887
/// true-voiced frames ever both-voiced) — invisible on a clean synthetic sine-tone sanity check,
/// only caught here against real, harmonically messier audio. Root-caused against librosa's
/// reference `pyin` source (the de facto standard implementation): no 0.5 prior factor, and
/// unvoiced mass divided across all bins (`(1-voicedProb)/nBins`), not repeated — see
/// `PYINDecoder.observation(for:)`'s doc comment for the full account. Verified fix: RPA 61.6%,
/// voicing accuracy 85.3%, both beating YIN (50.6%/77.8%) — GPE rose slightly (3.9% vs. 2.1%,
/// consistent with recovering more true-voiced frames at a small cost in gross-error rate among
/// them, not hidden). See DEVLOG Phase 27.
final class PYINEngineTests: XCTestCase {
    private struct Metrics {
        var rpaCorrect = 0       // true-voiced frames, estimate within 50 cents
        var trueVoicedTotal = 0  // true-voiced frames total
        var gpeCount = 0         // true-voiced AND est-voiced frames, |error| > 20%
        var bothVoicedTotal = 0  // true-voiced AND est-voiced frames total
        var voicingCorrect = 0   // frames where (true voiced) == (est voiced), any true/false state
        var voicingTotal = 0
    }

    func testYINvsPYIN_onMDBStemSynth() async throws {
        let audioDir = URL(fileURLWithPath: "Tests/Resources/MDBStemSynth/audio_stems")
        let annotDir = URL(fileURLWithPath: "Tests/Resources/MDBStemSynth/annotation_stems")
        guard let files = try? FileManager.default.contentsOfDirectory(at: audioDir, includingPropertiesForKeys: nil)
            .filter({ $0.pathExtension.lowercased() == "wav" }) else {
            throw XCTSkip("MDB-stem-synth not available")
        }

        let sr = 44100.0, hop = 512
        let gtHopSeconds = 128.0 / 44100.0
        let stems = files.sorted { $0.path < $1.path }
        let limit = 20
        let selected = stride(from: 0, to: stems.count, by: max(1, stems.count / limit)).map { stems[$0] }.prefix(limit)

        var yin = Metrics()
        var pyin = Metrics()
        let decoder = PYINDecoder()

        for f in selected {
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

            let yinEngine = YINEngine(sampleRate: sr, hopLength: hop)
            let yinPitch = yinEngine.analyze(samples: buf.samples)

            let pyinCandidates = yinEngine.analyzePYINCandidates(samples: buf.samples)
            let pyinPath = decoder.decode(candidatesPerFrame: pyinCandidates)

            func score(_ estimates: [Float], into m: inout Metrics) {
                for (i, est) in estimates.enumerated() {
                    let t = Double(i * hop) / sr
                    let gtIdx = Int((t / gtHopSeconds).rounded())
                    guard gtIdx >= 0, gtIdx < gtF0.count else { continue }
                    let trueF0 = gtF0[gtIdx]
                    let trueVoiced = trueF0 > 0
                    let estVoiced = est.isFinite && est > 0

                    m.voicingTotal += 1
                    if trueVoiced == estVoiced { m.voicingCorrect += 1 }

                    if trueVoiced {
                        m.trueVoicedTotal += 1
                        if estVoiced {
                            m.bothVoicedTotal += 1
                            let cents = abs(1200.0 * log2f(est / trueF0))
                            if cents < 50 { m.rpaCorrect += 1 }
                            let relErr = abs(est - trueF0) / trueF0
                            if relErr > 0.2 { m.gpeCount += 1 }
                        }
                    }
                }
            }

            score(yinPitch.f0Series, into: &yin)
            score(pyinPath, into: &pyin)
        }

        func rpaOf(_ m: Metrics) -> Double { m.trueVoicedTotal > 0 ? Double(m.rpaCorrect) / Double(m.trueVoicedTotal) * 100 : 0 }
        func gpeOf(_ m: Metrics) -> Double { m.bothVoicedTotal > 0 ? Double(m.gpeCount) / Double(m.bothVoicedTotal) * 100 : 0 }
        func voicingAccOf(_ m: Metrics) -> Double { m.voicingTotal > 0 ? Double(m.voicingCorrect) / Double(m.voicingTotal) * 100 : 0 }
        func report(_ name: String, _ m: Metrics) {
            print("\(name): RPA<50cents=\(String(format: "%.1f", rpaOf(m)))% (n=\(m.trueVoicedTotal))  " +
                  "GPE(>20%%)=\(String(format: "%.1f", gpeOf(m)))% (n=\(m.bothVoicedTotal))  " +
                  "voicingAcc=\(String(format: "%.1f", voicingAccOf(m)))% (n=\(m.voicingTotal))")
        }

        print("\n=== YIN vs pYIN on MDB-stem-synth (\(selected.count) stems) ===")
        report("YIN ", yin)
        report("pYIN", pyin)

        // Regression guards: pYIN must keep beating YIN on the two metrics it's actually meant
        // to improve (a future change to PYINDecoder that silently regresses back toward the
        // near-total-unvoiced collapse this test caught once must fail loudly, not print quietly).
        XCTAssertGreaterThan(rpaOf(pyin), rpaOf(yin), "pYIN's Raw Pitch Accuracy should beat YIN's")
        XCTAssertGreaterThan(voicingAccOf(pyin), voicingAccOf(yin), "pYIN's voicing-decision accuracy should beat YIN's")
        XCTAssertGreaterThan(rpaOf(pyin), 55.0, "pYIN RPA dropped well below its last-verified 61.6% -- check for the emission-formula regression this test was built to catch")
    }
}
