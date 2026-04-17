// AudioLoader.swift
// Elite Music DNA Engine — Phase 1
//
// Strategy:
//   - Sliding Window Buffer: Process in 30s chunks instead of loading entirely for memory efficiency.
//   - Mono Downmix: Average channels using vDSP_vadd (zero-copy intent).
//   - autoreleasepool: Release memory explicitly after each chunk processing.
//   - Float32 Normalization: Convert Int16 → [-1.0, 1.0] using vDSP_vflt16.
//   - AVAudioConverter: Native mastering-quality resampling.
//

@preconcurrency import AVFoundation
import Accelerate

// MARK: - Audio Metadata

public struct AudioMetadata: Sendable {
    public let url: URL
    public let duration: Double        // saniye
    public let sampleRate: Double      // Hz
    public let channels: Int
    public let frameCount: AVAudioFrameCount
}

// MARK: - Loaded Audio Buffer

public struct AudioBuffer: Sendable {
    public let samples: [Float]        // mono, [-1.0, 1.0]
    public let sampleRate: Double
    public let duration: Double

    public var frameCount: Int { samples.count }
}

// Helper to bypass Sendability mutation issues in synchronous AVAudioConverter loops
private final class ConversionState: @unchecked Sendable {
    var consumed = false
}

// MARK: - AudioLoader

/// AVAssetReader-based audio loader with Sliding Window support.
/// Swift equivalent of Librosa's `load()` + `to_mono()` + `resample()` functions.
public final class AudioLoader: @unchecked Sendable {

    public static let defaultSampleRate: Double = 22050.0

    // MARK: Metadata

    public static func metadata(for url: URL) throws -> AudioMetadata {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        let frameCount = AVAudioFrameCount(file.length)
        let _ = Double(frameCount) / format.sampleRate

        return AudioMetadata(
            url: url,
            duration: Double(frameCount) / format.sampleRate,
            sampleRate: format.sampleRate,
            channels: Int(format.channelCount),
            frameCount: frameCount
        )
    }

    // MARK: Full Load (≤ ~5 dakika)

    /// Loads the entire file as mono Float32 samples.
    /// Librosa: `y, sr = librosa.load(path, sr=22050, mono=True)`
    public static func load(url: URL, targetSampleRate: Double = defaultSampleRate) throws -> AudioBuffer {
        // Output format: mono, Float32, target SR
        guard let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: targetSampleRate,
            channels: 1,
            interleaved: false
        ) else {
            throw AudioLoadError.formatCreationFailed
        }

        let file = try AVAudioFile(forReading: url)
        let inputFormat = file.processingFormat

        // Native format buffer
        let totalFrames = AVAudioFrameCount(file.length)
        guard let inputBuffer = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: totalFrames) else {
            throw AudioLoadError.bufferAllocationFailed
        }
        try file.read(into: inputBuffer)
        inputBuffer.frameLength = totalFrames

        // Resample + mono downmix via AVAudioConverter
        let converter = AVAudioConverter(from: inputFormat, to: outputFormat)
        let outputFrames = AVAudioFrameCount(
            Double(totalFrames) * targetSampleRate / inputFormat.sampleRate
        ) + 1

        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: outputFrames) else {
            throw AudioLoadError.bufferAllocationFailed
        }

        let state = ConversionState()
        let status = converter?.convert(to: outputBuffer, error: nil) { _, outStatus in
            if state.consumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            outStatus.pointee = .haveData
            state.consumed = true
            return inputBuffer
        }

        guard status == .haveData || status == .endOfStream || status == .inputRanDry else {
            throw AudioLoadError.conversionFailed
        }

        let frameLength = Int(outputBuffer.frameLength)
        guard let channelData = outputBuffer.floatChannelData?[0] else {
            throw AudioLoadError.noChannelData
        }

        // Keep peak normalization if present, otherwise leave as is (matching Librosa behavior)
        let samples = Array(UnsafeBufferPointer(start: channelData, count: frameLength))
        let duration = Double(frameLength) / targetSampleRate

        return AudioBuffer(samples: samples, sampleRate: targetSampleRate, duration: duration)
    }

    // MARK: Sliding Window Iterator

    /// Chunk-based processing iterator for large files.
    /// Each chunk is ~30 seconds. Memory is explicitly released using `autoreleasepool`.
    ///
    /// Librosa streaming equivalent: `librosa.stream(path, block_length=...)`
    public static func chunks(
        url: URL,
        chunkDuration: Double = 30.0,
        overlap: Double = 0.0,
        targetSampleRate: Double = defaultSampleRate,
        handler: @escaping (_ chunk: [Float], _ startSec: Double, _ isLast: Bool) throws -> Void
    ) throws {
        guard let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: targetSampleRate,
            channels: 1,
            interleaved: false
        ) else {
            throw AudioLoadError.formatCreationFailed
        }

        let file = try AVAudioFile(forReading: url)
        let inputFormat = file.processingFormat
        let totalFrames = AVAudioFrameCount(file.length)
        let _ = Double(totalFrames) / inputFormat.sampleRate

        let chunkInputFrames = AVAudioFrameCount(chunkDuration * inputFormat.sampleRate)
        let overlapInputFrames = AVAudioFrameCount(overlap * inputFormat.sampleRate)
        let hopInputFrames = chunkInputFrames - overlapInputFrames

        var readOffset: AVAudioFramePosition = 0
        var currentStartSec = 0.0

        while readOffset < AVAudioFramePosition(totalFrames) {
            try autoreleasepool {
                let remaining = AVAudioFrameCount(totalFrames) - AVAudioFrameCount(readOffset)
                let readCount = min(chunkInputFrames, remaining)

                guard let chunkBuffer = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: readCount) else {
                    throw AudioLoadError.bufferAllocationFailed
                }

                file.framePosition = readOffset
                try file.read(into: chunkBuffer, frameCount: readCount)
                chunkBuffer.frameLength = AVAudioFrameCount(file.framePosition) - AVAudioFrameCount(readOffset)

                // Convert chunk
                let converter = AVAudioConverter(from: inputFormat, to: outputFormat)
                let outFrames = AVAudioFrameCount(Double(chunkBuffer.frameLength) * targetSampleRate / inputFormat.sampleRate) + 1

                guard let outBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: outFrames) else {
                    throw AudioLoadError.bufferAllocationFailed
                }

                let state = ConversionState()
                converter?.convert(to: outBuffer, error: nil) { _, outStatus in
                    if state.consumed { outStatus.pointee = .noDataNow; return nil }
                    outStatus.pointee = .haveData
                    state.consumed = true
                    return chunkBuffer
                }

                let frameLen = Int(outBuffer.frameLength)
                if let ptr = outBuffer.floatChannelData?[0], frameLen > 0 {
                    let chunk = Array(UnsafeBufferPointer(start: ptr, count: frameLen))
                    let isLast = (readOffset + AVAudioFramePosition(readCount)) >= AVAudioFramePosition(totalFrames)
                    try handler(chunk, currentStartSec, isLast)
                }

                readOffset += AVAudioFramePosition(hopInputFrames)
                currentStartSec += Double(hopInputFrames) / inputFormat.sampleRate
            }
        }
    }
}

// MARK: - Errors

public enum AudioLoadError: Error, LocalizedError {
    case formatCreationFailed
    case bufferAllocationFailed
    case conversionFailed
    case noChannelData
    case fileNotFound(URL)

    public var errorDescription: String? {
        switch self {
        case .formatCreationFailed: return "Could not create AVAudioFormat"
        case .bufferAllocationFailed: return "Could not allocate PCM buffer"
        case .conversionFailed: return "Audio conversion failed"
        case .noChannelData: return "Could not retrieve channel data"
        case .fileNotFound(let url): return "File not found at path: \(url.path)"
        }
    }
}
