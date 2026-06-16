import XCTest
import Foundation
@testable import AudioIntelligenceCore

/// Wires the ScientificAuditor's EBU Tech 3341/3342 self-calibration scenarios into the
/// test suite — the same internal "SIR" sweep that flagged CALIBRATION DRIFT in the
/// original report. With the loudness path proven EBU-compliant (see EBUReference
/// ValidationTests), these synthetic reference signals must now land in tolerance.
final class ScientificAuditorTests: XCTestCase {
    func testEBUCalibrationScenarios() {
        let auditor = ScientificAuditor()
        let reports = [auditor.runScenarioA(), auditor.runScenarioB(), auditor.runScenarioC(), auditor.runScenarioD()]

        let table = ValidationTable("SCIENTIFIC AUDITOR — EBU 3341/3342 CALIBRATION (SIR)")
        for r in reports {
            table.checkExact(r.scenarioName,
                             expected: String(format: "%.2f", r.expectedValue),
                             measured: String(format: "%.2f (err %+.3f dB)", r.measuredValue, r.errorDb),
                             pass: r.passed)
            XCTAssertTrue(r.passed, "\(r.scenarioName): measured \(r.measuredValue) vs expected \(r.expectedValue) (err \(r.errorDb) dB)")
        }
        table.printTable()
    }
}
