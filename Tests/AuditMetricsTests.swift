import XCTest
@testable import AudioIntelligence
@testable import AudioIntelligenceCore

/// `AuditMetrics` was entirely hardcoded — identical literal values on every single analysis
/// regardless of what actually ran — and directly reachable via the public
/// `AudioIntelligence.analyzeRawAggregate` API (not just internal). Now `engineCoverage`
/// reflects real per-analysis data, `cqtStatus` honestly reports no consumer, and
/// `melSpectrogramResolution` uses the real frame count.
final class AuditMetricsTests: XCTestCase {

    func testRealAudio_auditMetricsReflectRealData() async throws {
        let path = "Tests/Resources/SQAM/trpt21_2.wav"
        guard FileManager.default.fileExists(atPath: path) else {
            throw XCTSkip("SQAM trpt21_2.wav not present locally")
        }
        let analysis = try await AudioIntelligence().analyzeRawAggregate(url: URL(fileURLWithPath: path))
        let audit = analysis.audit

        print("🔬 audit: coverage=\(audit.engineCoverage) cqtStatus=\(audit.cqtStatus) melRes=\(audit.melSpectrogramResolution)")

        XCTAssertEqual(audit.cqtStatus, "Not Used (no downstream consumer in this pipeline)",
                        "must honestly report CQT's real status, not a hardcoded \"OK\"")

        for engine in ["Structure", "HPSS", "Rhythm", "Contrast", "Chroma"] {
            XCTAssertEqual(audit.engineCoverage[engine], true, "\(engine) genuinely ran on this real audio and should report true")
        }

        XCTAssertTrue(audit.melSpectrogramResolution.hasPrefix("128x"), "must use the real nMels=128")
        let frameCountStr = audit.melSpectrogramResolution.replacingOccurrences(of: "128x", with: "")
        let frameCount = Int(frameCountStr) ?? 0
        XCTAssertGreaterThan(frameCount, 0, "must report a real, non-zero frame count, not the old hardcoded \"800\"")
    }
}
