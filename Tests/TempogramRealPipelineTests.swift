import XCTest
@testable import AudioIntelligence
@testable import AudioIntelligenceCore

/// `TempogramEngine.computeACT` was never actually called from the real pipeline —
/// `cyclicTempoMap` was always a literal `[]`. Wired up using `fullOnsetEnv` (already
/// concatenated across the whole track), averaged per lag bin into a track-wide profile.
final class TempogramRealPipelineTests: XCTestCase {

    func testRealAudio_populatesCyclicTempoMap() async throws {
        let path = "Tests/Resources/SQAM/trpt21_2.wav"
        guard FileManager.default.fileExists(atPath: path) else {
            throw XCTSkip("SQAM trpt21_2.wav not present locally")
        }
        let report = try await AudioIntelligence().analyzeRawAggregate(url: URL(fileURLWithPath: path))

        XCTAssertFalse(report.tempogram.cyclicTempoMap.isEmpty, "cyclicTempoMap must no longer be empty on real audio")
        for v in report.tempogram.cyclicTempoMap {
            XCTAssertTrue(v.isFinite, "every entry must be a finite value")
            XCTAssertGreaterThanOrEqual(v, 0, "L-infinity normalized autocorrelation should be non-negative")
        }
        print("🔬 cyclicTempoMap: \(report.tempogram.cyclicTempoMap.count) lag bins, max=\(report.tempogram.cyclicTempoMap.max() ?? 0)")
    }
}
