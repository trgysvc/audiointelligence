import XCTest
import AVFoundation
@testable import AudioIntelligence
@testable import AudioIntelligenceCore

/// `DNAReportBuilder` computes HPSS on EVERY 45s chunk but used to only ever store the FIRST
/// chunk's result (`if idx == 0 { allHPSS[0] = hpss }`) — so the public `harmonicRatio`/
/// `percussiveRatio` report fields for any track longer than 45s silently reflected only its
/// first 45 seconds, no matter how long the rest of the track was. Fixed to store every chunk
/// (`allHPSS[idx] = hpss`), matching the same pattern already used for `StructureEngine`.
///
/// Verified with a real >45s file (EBU SQAM glockenspiel, 59s — genuinely spans 2 chunks): the
/// full-file result must differ from a truncated-to-45s copy's result. Before the fix, both
/// would have been identical by construction (only chunk 0 was ever used either way).
final class DNAReportBuilderHPSSTests: XCTestCase {

    /// Writes a copy of `sourceURL` truncated to `seconds`, as a 16-bit PCM WAV, to `destURL`.
    private func writeTruncatedCopy(of sourceURL: URL, seconds: Double, to destURL: URL) async throws {
        let buffer = try await AudioLoader.load(url: sourceURL, targetSampleRate: 44100)
        let sampleCount = min(buffer.samples.count, Int(seconds * 44100))

        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 44100, channels: 1, interleaved: false)!
        let outFile = try AVAudioFile(forWriting: destURL, settings: format.settings)
        let pcmBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(sampleCount))!
        pcmBuffer.frameLength = AVAudioFrameCount(sampleCount)
        let channelData = pcmBuffer.floatChannelData![0]
        for i in 0..<sampleCount { channelData[i] = buffer.samples[i] }
        try outFile.write(from: pcmBuffer)
    }

    func testFullTrackHPSS_differsFromFirstChunkOnly() async throws {
        let sourcePath = "Tests/Resources/SQAM/gspi35_1.wav" // 59s — spans 2 of the 45s chunks
        guard FileManager.default.fileExists(atPath: sourcePath) else {
            throw XCTSkip("SQAM gspi35_1.wav not present locally")
        }
        let sourceURL = URL(fileURLWithPath: sourcePath)

        let tmpDir = FileManager.default.temporaryDirectory
        let truncatedURL = tmpDir.appendingPathComponent("gspi35_1_truncated_44s.wav")
        try? FileManager.default.removeItem(at: truncatedURL)
        try await writeTruncatedCopy(of: sourceURL, seconds: 44.0, to: truncatedURL) // safely under the 45s chunk boundary
        defer { try? FileManager.default.removeItem(at: truncatedURL) }

        let fullReport = try await AudioIntelligence().analyzeRawAggregate(url: sourceURL)
        let truncatedReport = try await AudioIntelligence().analyzeRawAggregate(url: truncatedURL)

        let fullRatio = fullReport.hpss.harmonicRatio
        let truncatedRatio = truncatedReport.hpss.harmonicRatio
        print("🔬 HPSS harmonicRatio: full(59s)=\(fullRatio) truncated(44s, chunk-0-only)=\(truncatedRatio)")

        XCTAssertGreaterThan(abs(fullRatio - truncatedRatio), 0.001,
                              "the full 59s file's HPSS ratio must reflect its second chunk too — before the fix this was identical to the 44s (chunk-0-only) result by construction")
    }
}
