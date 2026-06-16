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
}
