import XCTest
import Foundation
@testable import AudioIntelligence
@testable import AudioIntelligenceCore

/// Faz 0 — Ground-truth validation harness.
///
/// Unlike the existing parity tests (which only assert `> 0`), every check here
/// compares against a mathematically known value with an explicit tolerance, and
/// prints a single red/green table. This is the regression gate every later fix
/// must turn green. On a broken engine these tests are EXPECTED to fail — that
/// failure is the "starting snapshot".
final class GroundTruthValidationTests: XCTestCase {

    // MARK: - Tolerance table plumbing

    struct Row: Sendable {
        let metric: String
        let expected: String
        let measured: String
        let tolerance: String
        let pass: Bool
    }

    /// Lock-protected sink so async tests can record rows under Swift 6 concurrency.
    final class Collector: @unchecked Sendable {
        private let lock = NSLock()
        private var rows: [Row] = []
        func add(_ r: Row) { lock.lock(); rows.append(r); lock.unlock() }
        func drain() -> [Row] { lock.lock(); defer { rows.removeAll(); lock.unlock() }; return rows }
    }
    private static let collector = Collector()

    /// Records a numeric check and asserts it, continuing on failure so the whole
    /// table is produced in one run.
    private func check(_ metric: String, expected: Double, measured: Double, tol: Double) {
        let pass = abs(expected - measured) <= tol
        Self.collector.add(Row(
            metric: metric,
            expected: String(format: "%.3f", expected),
            measured: String(format: "%.3f", measured),
            tolerance: "±\(String(format: "%.3f", tol))",
            pass: pass
        ))
        XCTAssertTrue(pass, "\(metric): expected \(expected) ±\(tol), measured \(measured)")
    }

    /// Records a boolean / categorical check.
    private func checkBool(_ metric: String, expected: String, measured: String, pass: Bool) {
        Self.collector.add(Row(metric: metric, expected: expected, measured: measured, tolerance: "exact", pass: pass))
        XCTAssertTrue(pass, "\(metric): expected \(expected), measured \(measured)")
    }

    // MARK: - Fixtures lifecycle

    private static let sr = 22050
    private var tmpDir: URL!

    override func setUpWithError() throws {
        continueAfterFailure = true // produce the full table even when checks fail
        tmpDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("AI_GroundTruth_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        // The pipeline currently hardcodes its report output dir; make sure it exists
        // so analyze() doesn't throw on write. (Removing that hardcode is a Faz 1 item.)
        let outDir = "/Users/trgysvc/Documents/AI Works"
        if !FileManager.default.fileExists(atPath: outDir) {
            try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
        }
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmpDir)
    }

    override class func tearDown() {
        printTable()
        super.tearDown()
    }

    private static func printTable() {
        let rows = collector.drain()
        guard !rows.isEmpty else { return }
        let mW = max(34, rows.map { $0.metric.count }.max() ?? 0)
        func pad(_ s: String, _ w: Int) -> String { s.count >= w ? s : s + String(repeating: " ", count: w - s.count) }
        print("\n┌─ GROUND-TRUTH VALIDATION ──────────────────────────────────────────────")
        print("│ \(pad("METRIC", mW))  \(pad("EXPECTED", 10))  \(pad("MEASURED", 12))  \(pad("TOL", 9))  RESULT")
        print("├────────────────────────────────────────────────────────────────────────")
        for r in rows {
            let mark = r.pass ? "✅ PASS" : "❌ FAIL"
            print("│ \(pad(r.metric, mW))  \(pad(r.expected, 10))  \(pad(r.measured, 12))  \(pad(r.tolerance, 9))  \(mark)")
        }
        let passed = rows.filter { $0.pass }.count
        print("└─ \(passed)/\(rows.count) PASSED ───────────────────────────────────────────────────────\n")
    }

    private func analyze(_ url: URL) async throws -> MusicDNAAnalysis {
        let intelligence = AudioIntelligence()
        return try await intelligence.analyze(url: url).rawAnalysis
    }

    // MARK: - Tests

    /// 120 BPM click train, 100s (> 45s chunk boundary) at 16-bit.
    /// Validates: tempo aggregation, bit-depth read, and full-track structure coverage.
    func testTempoAndCoverage_120bpm_100s_16bit() async throws {
        let url = tmpDir.appendingPathComponent("click_120bpm_100s_16.wav")
        let click = SyntheticAudio.clickTrack(bpm: 120, durationSec: 100, sampleRate: Self.sr)
        try SyntheticAudio.writeWAV(to: url, channels: [click], sampleRate: Self.sr, bitDepth: 16)

        let a = try await analyze(url)

        check("Tempo (120 BPM click, multi-chunk)", expected: 120, measured: Double(a.rhythm.bpm), tol: 3)
        checkBool("Bit-depth (16-bit source)", expected: "16", measured: "\(a.forensic.effectiveBits)",
                  pass: a.forensic.effectiveBits == 16)
        let lastEnd = a.segments.map { $0.end }.max() ?? 0
        check("Structure coverage end (≈100s file)", expected: 100, measured: lastEnd, tol: 15)
    }

    /// 24-bit pure sine, short single-chunk file. Validates bit-depth read = 24.
    func testBitDepth_24bit_sine() async throws {
        let url = tmpDir.appendingPathComponent("sine_440_24.wav")
        let s = SyntheticAudio.sine(freqHz: 440, durationSec: 6, sampleRate: Self.sr, amplitude: 0.5)
        try SyntheticAudio.writeWAV(to: url, channels: [s], sampleRate: Self.sr, bitDepth: 24)

        let a = try await analyze(url)
        checkBool("Bit-depth (24-bit source)", expected: "24", measured: "\(a.forensic.effectiveBits)",
                  pass: a.forensic.effectiveBits == 24)
    }

    /// Multi-chunk 16-bit file with a silent section — reproduces the real-album
    /// "0-bit" bug, where silent chunks made the statistical min-aggregation collapse to 0.
    func testBitDepth_16bit_multiChunk_withSilence() async throws {
        let url = tmpDir.appendingPathComponent("silence_100s_16.wav")
        let part = SyntheticAudio.sine(freqHz: 330, durationSec: 35, sampleRate: Self.sr, amplitude: 0.5)
        let silence = [Float](repeating: 0, count: 30 * Self.sr) // 30s digital silence
        let full = part + silence + part
        try SyntheticAudio.writeWAV(to: url, channels: [full], sampleRate: Self.sr, bitDepth: 16)

        let a = try await analyze(url)
        checkBool("Bit-depth (16-bit, multi-chunk + silence)", expected: "16",
                  measured: "\(a.forensic.effectiveBits)", pass: a.forensic.effectiveBits == 16)
    }

    /// 100s tonal piece with 4 distinct keys (C maj → G maj → A min → F maj).
    /// Validates: modulation timebase (timestamps must stay within real duration)
    /// and that a clearly modulating piece actually yields modulations (key detection
    /// not collapsing to "Unclassified").
    func testModulationTimebase_tonal_100s() async throws {
        let url = tmpDir.appendingPathComponent("keys_100s.wav")
        let seg = 25.0
        let cMaj = SyntheticAudio.chord(rootMidi: 60, semitones: [0, 4, 7], durationSec: seg, sampleRate: Self.sr)
        let gMaj = SyntheticAudio.chord(rootMidi: 67, semitones: [0, 4, 7], durationSec: seg, sampleRate: Self.sr)
        let aMin = SyntheticAudio.chord(rootMidi: 69, semitones: [0, 3, 7], durationSec: seg, sampleRate: Self.sr)
        let fMaj = SyntheticAudio.chord(rootMidi: 65, semitones: [0, 4, 7], durationSec: seg, sampleRate: Self.sr)
        let full = cMaj + gMaj + aMin + fMaj
        try SyntheticAudio.writeWAV(to: url, channels: [full], sampleRate: Self.sr, bitDepth: 16)
        let realDuration = Double(full.count) / Double(Self.sr)

        let a = try await analyze(url)
        let maxTs = a.musicology.modulations.map { $0.timestamp }.max() ?? 0
        // Correct invariant: a timestamp may never exceed the real duration. The old
        // 0.18s/frame bug inflated this far past the end; it must now land inside [0, dur].
        checkBool("Modulation max timestamp ≤ duration",
                  expected: "≤\(String(format: "%.1f", realDuration))",
                  measured: String(format: "%.1f", maxTs),
                  pass: maxTs > 0 && maxTs <= realDuration * 1.02)
        checkBool("Modulating piece yields modulations", expected: ">0",
                  measured: "\(a.musicology.modulations.count)", pass: !a.musicology.modulations.isEmpty)
    }

    /// Stereo phase coherence: identical L/R must give phase correlation ≈ +1.0,
    /// not the hardcoded 0.94 placeholder.
    func testStereoPhaseCorrelation_mono_identical() async throws {
        let url = tmpDir.appendingPathComponent("stereo_inphase.wav")
        let s = SyntheticAudio.sine(freqHz: 220, durationSec: 6, sampleRate: Self.sr, amplitude: 0.6)
        try SyntheticAudio.writeWAV(to: url, channels: [s, s], sampleRate: Self.sr, bitDepth: 16)

        let a = try await analyze(url)
        // Identical channels → correlation = 1.0. A hardcoded 0.94 will miss the tolerance.
        check("Phase correlation (identical L/R)", expected: 1.0, measured: Double(a.mastering.phaseCorrelation), tol: 0.02)
    }
}
