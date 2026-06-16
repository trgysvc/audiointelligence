import XCTest
import Foundation
@testable import AudioIntelligence
@testable import AudioIntelligenceCore

/// Confirms the metrics that used to be hardcoded placeholders now carry real,
/// signal-derived values (and aren't equal to the old fake constants).
final class RealizedMetricsTests: XCTestCase {
    func testNoHardcodedPlaceholders() async throws {
        let outDir = "/Users/trgysvc/Documents/AI Works"
        if !FileManager.default.fileExists(atPath: outDir) {
            try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
        }
        let url = URL(fileURLWithPath: "Tests/Resources/SQAM/trpt21_2.wav")
        let a = try await AudioIntelligence().analyzeRawAggregate(url: url)

        print("""
        \n── REALIZED METRICS (trpt21_2) ──
        hpss.harmonicMean   = \(a.hpss.harmonicMean)     (was 50)
        hpss.percussiveMean = \(a.hpss.percussiveMean)   (was 50)
        semantic            = \(a.semantic.dominanceMap) / \(a.semantic.primaryRole) / \(a.semantic.textureType) / presence \(a.semantic.presenceScore)  (was Percussion:0.6/Lead/Complex/0.95)
        tonnetz.stability   = \(a.tonnetz.harmonicStability)  (was 0.92)
        tempogram.period    = \(a.tempogram.dominantPeriod)   (was 120)
        nmf                 = err \(a.nmf.reconstructionError) / energy \(a.nmf.componentEnergy)  (was 0.001/[0.8,0.2])
        piptrack.confidence = \(a.piptrack.trackingConfidence)  (was 0.95)
        viterbi.confidence  = \(a.viterbi.confidence)   (was 0.98)
        """)

        // Guard against the exact old fakes (allow the genuine value to coincidentally match
        // only within tiny epsilon is unlikely; check inequality to the literal constants).
        XCTAssertNotEqual(a.hpss.harmonicMean, 50)
        XCTAssertNotEqual(a.semantic.presenceScore, 0.95)
        XCTAssertNotEqual(a.tonnetz.harmonicStability, 0.92)
        XCTAssertNotEqual(a.piptrack.trackingConfidence, 0.95)
        XCTAssertNotEqual(a.viterbi.confidence, 0.98)
        XCTAssertNotEqual(a.nmf.reconstructionError, 0.001)
    }
}
