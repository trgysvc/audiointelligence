import XCTest
import Foundation
@testable import AudioIntelligenceCore

/// Validates loudness against EBU SQAM material (broadcast reference audio, EBU Tech 3253)
/// using authoritative values from the reference ffmpeg/ebur128 implementation
/// (ITU-R BS.1770 / EBU R128). A "100% verified file → result" anchor: the expected
/// numbers come from a standards-grade external tool, not from us.
///
/// Calls LoudnessEngine directly at the native sample rate (not the full 26-engine
/// pipeline) so it runs in seconds and isolates the loudness metric. Tolerances start
/// loose to MEASURE drift, then tighten toward EBU compliance (integrated ±0.5 LU).
final class EBUReferenceValidationTests: XCTestCase {

    struct Ref { let file: String; let lufs: Double; let truePeak: Double; let lra: Double }

    // Tests/Resources/sqam_reference_values.txt (ffmpeg ebur128).
    let references: [Ref] = [
        Ref(file: "gspi35_1.wav", lufs: -21.7, truePeak: -5.3,  lra: 14.4),
        Ref(file: "harp40_1.wav", lufs: -32.0, truePeak: -12.5, lra: 16.0),
        Ref(file: "horn23_2.wav", lufs: -20.5, truePeak: -6.9,  lra: 11.8),
        Ref(file: "quar48_1.wav", lufs: -22.6, truePeak: -6.6,  lra: 9.4),
        Ref(file: "spfe49_1.wav", lufs: -22.5, truePeak: -4.7,  lra: 5.9),
        Ref(file: "trpt21_2.wav", lufs: -22.6, truePeak: -7.6,  lra: 18.0),
    ]
    let sqamDir = "Tests/Resources/SQAM"

    func testSQAMLoudnessParity() async throws {
        continueAfterFailure = true
        let table = ValidationTable("EBU SQAM LOUDNESS (vs ffmpeg ebur128)")

        // EBU R128 compliance-grade tolerances (measured deltas were ≤0.08 LU / ≤0.27 dB).
        let lufsTol = 0.5, tpTol = 0.5, lraTol = 0.5

        for ref in references {
            let url = URL(fileURLWithPath: "\(sqamDir)/\(ref.file)")
            guard FileManager.default.fileExists(atPath: url.path) else {
                table.checkExact("\(ref.file): present", expected: "yes", measured: "MISSING", pass: false); continue
            }
            // Pass the file's ACTUAL channels at native rate (BS.1770 sums channels with
            // G=1.0). Duplicating a mono source into two channels would double the energy
            // and add a spurious +3 dB (10·log10 2) — a test artifact, not engine drift.
            let meta = try AudioLoader.metadata(for: url)
            let channels = try await AudioLoader.loadMulti(url: url, targetSampleRate: meta.sampleRate)
            let r = LoudnessEngine(sampleRate: meta.sampleRate).analyze(channels: channels)

            print(String(format: "  %@  LUFS %.1f (ref %.1f)  TP %.1f (ref %.1f)  LRA %.1f (ref %.1f)",
                         ref.file, r.integratedLUFS, ref.lufs, r.truePeakDb, ref.truePeak, r.loudnessRange, ref.lra))

            let l = table.check("\(ref.file) Integrated LUFS", expected: ref.lufs, measured: Double(r.integratedLUFS), tol: lufsTol)
            let t = table.check("\(ref.file) True Peak dBTP",  expected: ref.truePeak, measured: Double(r.truePeakDb), tol: tpTol)
            let a = table.check("\(ref.file) LRA (LU)",        expected: ref.lra, measured: Double(r.loudnessRange), tol: lraTol)
            XCTAssertTrue(l, "\(ref.file) LUFS \(r.integratedLUFS) vs ref \(ref.lufs)")
            XCTAssertTrue(t, "\(ref.file) TruePeak \(r.truePeakDb) vs ref \(ref.truePeak)")
            XCTAssertTrue(a, "\(ref.file) LRA \(r.loudnessRange) vs ref \(ref.lra)")
        }
        table.printTable()
    }
}
