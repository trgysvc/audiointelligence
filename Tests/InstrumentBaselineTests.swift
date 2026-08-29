import XCTest
import Foundation
@testable import AudioIntelligence
@testable import AudioIntelligenceCore

/// Baseline accuracy of the (heuristic, 6-class) InstrumentEngine against EBU SQAM solo
/// instruments. There is no librosa reference for instrument classification, so SQAM's
/// documented instrument is the ground truth. Mapping SQAM's specific instruments onto the
/// 6 coarse classes is necessarily loose; "acceptable" lists the reasonable class(es).
final class InstrumentBaselineTests: XCTestCase {

    // file → (human label, acceptable engine classes)
    let cases: [(file: String, label: String, acceptable: [String])] = [
        ("trpt21_2.wav", "Trumpet",      ["Brass/Trumpet"]),
        ("horn23_2.wav", "French Horn",  ["Brass/Trumpet"]),
        ("harp40_1.wav", "Harp",         ["Strings/Synth", "Piano/Keyboard"]),
        ("quar48_1.wav", "Vocal Quartet",["Vocals/Chorus"]),
        ("spfe49_1.wav", "Speech",       ["Vocals/Chorus"]),
        ("gspi35_1.wav", "Glockenspiel", ["Piano/Keyboard", "Drums/Percussion", "Strings/Synth"]),
    ]
    let sqamDir = "Tests/Resources/SQAM"

    func testInstrumentClassificationBaseline() async throws {
        let outDir = "/Users/trgysvc/Documents/AI Works"
        if !FileManager.default.fileExists(atPath: outDir) {
            try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
        }

        var primaryHits = 0, top2Hits = 0, total = 0
        print("\n  file            expected         primary(top-3)")
        for c in cases {
            let url = URL(fileURLWithPath: "\(sqamDir)/\(c.file)")
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            let a = try await AudioIntelligence().analyzeRawAggregate(url: url)
            total += 1
            let preds = a.instruments.predictions
            let primary = a.instruments.primaryLabel
            let top2 = Set(preds.prefix(2).map { $0.label })
            let primaryOK = c.acceptable.contains(primary)
            let top2OK = c.acceptable.contains { top2.contains($0) }
            if primaryOK { primaryHits += 1 }
            if top2OK { top2Hits += 1 }
            let top3 = preds.prefix(3).map { "\($0.label) \(Int($0.confidence*100))%" }.joined(separator: ", ")
            print("  \(c.file)  \(c.label.padding(toLength: 14, withPad: " ", startingAt: 0))  \(primaryOK ? "✓" : "✗") \(primary)  [\(top3)]")
        }
        let n = Double(max(1, total))
        print("📊 Instrument baseline over \(total): primary=\(primaryHits) (\(Int(Double(primaryHits)/n*100))%)  top2=\(top2Hits) (\(Int(Double(top2Hits)/n*100))%)")
        XCTAssertGreaterThan(total, 0)
    }

    /// `InstrumentEngine.predict`'s spectral scoring used binary thresholds (`if centroidRange.
    /// contains(...) { score += 0.4 }`) with wide, overlapping profile ranges — real audio
    /// routinely landed multiple profiles at the *exact same* rounded confidence, and which one
    /// won the tie depended on tiny upstream floating-point noise. Empirically confirmed on
    /// this exact file: two full-pipeline runs on unmodified code classified it as
    /// "Brass/Trumpet" once and "Piano/Keyboard" once. Replaced binary thresholds with graded
    /// (Gaussian centroid / linear flatness) scoring, which — re-verified with 3 consecutive
    /// full-pipeline runs during development, byte-identical confidence percentages every time
    /// — collapses the near-ties at their source. This runs the real pipeline twice in one test
    /// as a permanent regression guard against the same bug recurring.
    func testInstrumentClassification_isDeterministicAcrossRepeatedRuns() async throws {
        let path = "\(sqamDir)/trpt21_2.wav"
        guard FileManager.default.fileExists(atPath: path) else {
            throw XCTSkip("SQAM trpt21_2.wav not present locally")
        }
        let url = URL(fileURLWithPath: path)
        let first = try await AudioIntelligence().analyzeRawAggregate(url: url).instruments
        let second = try await AudioIntelligence().analyzeRawAggregate(url: url).instruments

        XCTAssertEqual(first.primaryLabel, second.primaryLabel,
                        "the same file through the same pipeline must classify identically run-to-run")
        XCTAssertEqual(first.predictions.map(\.label), second.predictions.map(\.label),
                        "the full ranked prediction order must also be stable, not just the winner")
    }
}
