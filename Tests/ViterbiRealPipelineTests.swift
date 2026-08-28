import XCTest
@testable import AudioIntelligence
@testable import AudioIntelligenceCore

/// Confirms `ViterbiMetrics.path` is genuinely populated by the real end-to-end pipeline
/// (`DNAReportBuilder` -> `AudioReportMapping`) — before this fix, `allViterbi` was always a
/// literal `[]`, so this field was always empty in every real analysis, no matter the input.
final class ViterbiRealPipelineTests: XCTestCase {

    func testRealAudio_populatesViterbiPath() async throws {
        let path = "Tests/Resources/SQAM/trpt21_2.wav"
        guard FileManager.default.fileExists(atPath: path) else {
            throw XCTSkip("SQAM trpt21_2.wav not present locally")
        }
        let report = try await AudioIntelligence().analyzeRawAggregate(url: URL(fileURLWithPath: path))

        XCTAssertFalse(report.viterbi.path.isEmpty, "viterbi.path must no longer be empty on real audio")

        let voiced = report.viterbi.path.filter { $0 != 0 }
        print("🔬 viterbi.path: \(report.viterbi.path.count) frames, \(voiced.count) voiced")
        for midi in voiced {
            XCTAssertTrue((0...127).contains(midi), "every non-silence entry must be a valid MIDI note number")
        }
        XCTAssertFalse(voiced.isEmpty, "a real trumpet recording should have some voiced frames")
    }
}
