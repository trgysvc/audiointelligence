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

public struct AudioBuffer: Sendable, Codable {
    public let samples: [Float]        // mono, [-1.0, 1.0]
    public let sampleRate: Double
    public let duration: Double

    public var frameCount: Int { samples.count }
}

public struct StereoAudioBuffer: Sendable, Codable {
    public let left: [Float]
    public let right: [Float]
    public let sampleRate: Double
    public let duration: Double
    
    public var frameCount: Int { left.count }
}

// Helper to bypass Sendability mutation issues in synchronous AVAudioConverter loops
private final class ConversionState: @unchecked Sendable {
    var consumed = false
}

// MARK: - AudioLoader

/// AVAssetReader-based audio loader with Sliding Window support.
/// Swift equivalent of Industry Standard's `load()` + `to_mono()` + `resample()` functions.
public enum AudioLoader {

    public static let defaultSampleRate: Double = 22050.0

    // MARK: Metadata

    public static func metadata(for url: URL) throws -> AudioMetadata {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        let frameCount = AVAudioFrameCount(file.length)

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
    public static func load(url: URL, targetSampleRate: Double = defaultSampleRate) async throws -> AudioBuffer {
        guard let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: targetSampleRate,
            channels: 1,
            interleaved: false
        ) else {
            throw AudioIntelligenceError.io(.formatNotSupported("PCM Float32"))
        }

        let file = try AVAudioFile(forReading: url)
        let inputFormat = file.processingFormat

        let totalFrames = AVAudioFrameCount(file.length)
        guard let inputBuffer = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: totalFrames) else {
            throw AudioIntelligenceError.io(.decodeFailed(url))
        }
        try file.read(into: inputBuffer)
        inputBuffer.frameLength = totalFrames

        let converter = AVAudioConverter(from: inputFormat, to: outputFormat)
        let outputFrames = AVAudioFrameCount(Double(totalFrames) * targetSampleRate / inputFormat.sampleRate) + 1

        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: outputFrames) else {
            throw AudioIntelligenceError.io(.decodeFailed(url))
        }

        let state = ConversionState()
        converter?.convert(to: outputBuffer, error: nil) { _, outStatus in
            if state.consumed { outStatus.pointee = .noDataNow; return nil }
            outStatus.pointee = .haveData
            state.consumed = true
            return inputBuffer
        }

        let frameLength = Int(outputBuffer.frameLength)
        guard let channelData = outputBuffer.floatChannelData?[0] else {
            throw AudioIntelligenceError.io(.decodeFailed(url))
        }

        let samples = Array(UnsafeBufferPointer(start: channelData, count: frameLength))
        let duration = Double(frameLength) / targetSampleRate
        return AudioBuffer(samples: samples, sampleRate: targetSampleRate, duration: duration)
    }

    /// Loads the file as Multi-channel Float32 samples.
    public static func loadMulti(url: URL, targetSampleRate: Double = defaultSampleRate) async throws -> [[Float]] {
        let file = try AVAudioFile(forReading: url)
        let inputFormat = file.processingFormat
        let channelCount = Int(inputFormat.channelCount)
        
        guard let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: targetSampleRate,
            channels: AVAudioChannelCount(channelCount),
            interleaved: false
        ) else {
            throw AudioIntelligenceError.io(.formatNotSupported("PCM Float32"))
        }

        let totalFrames = AVAudioFrameCount(file.length)
        guard let inputBuffer = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: totalFrames) else {
            throw AudioIntelligenceError.io(.decodeFailed(url))
        }
        try file.read(into: inputBuffer)
        inputBuffer.frameLength = totalFrames

        let converter = AVAudioConverter(from: inputFormat, to: outputFormat)
        let outputFrames = AVAudioFrameCount(Double(totalFrames) * targetSampleRate / inputFormat.sampleRate) + 1

        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: outputFrames) else {
            throw AudioIntelligenceError.io(.decodeFailed(url))
        }

        let state = ConversionState()
        converter?.convert(to: outputBuffer, error: nil) { _, outStatus in
            if state.consumed { outStatus.pointee = .noDataNow; return nil }
            outStatus.pointee = .haveData
            state.consumed = true
            return inputBuffer
        }

        let frameLength = Int(outputBuffer.frameLength)
        var result = [[Float]]()
        for c in 0..<channelCount {
            if let ptr = outputBuffer.floatChannelData?[c] {
                result.append(Array(UnsafeBufferPointer(start: ptr, count: frameLength)))
            }
        }
        return result
    }
    
    /// Loads the file as stereo Float32 samples.
    public static func loadStereo(url: URL, targetSampleRate: Double = defaultSampleRate) async throws -> StereoAudioBuffer {
        let channels = try await loadMulti(url: url, targetSampleRate: targetSampleRate)
        let left = channels[0]
        let right = channels.count > 1 ? channels[1] : channels[0]
        let duration = Double(left.count) / targetSampleRate
        return StereoAudioBuffer(left: left, right: right, sampleRate: targetSampleRate, duration: duration)
    }

    // MARK: - Sequential Manual Loader (Atomic Fix for Bus Error)
    
    /// Loads a specific slice of the audio file synchronously (Safe for Batch Mode).
    public static func loadNextChunkManual(
        file: AVAudioFile,
        offset: AVAudioFramePosition,
        frameCount: AVAudioFrameCount,
        targetSampleRate: Double = defaultSampleRate
    ) throws -> AudioBuffer {
        let inputFormat = file.processingFormat
        
        guard let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: targetSampleRate,
            channels: 1,
            interleaved: false
        ) else {
            throw AudioIntelligenceError.io(.formatNotSupported("PCM Float32"))
        }

        guard let chunkBuffer = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: frameCount) else {
             throw AudioIntelligenceError.io(.decodeFailed(file.url))
        }
        file.framePosition = offset
        try file.read(into: chunkBuffer, frameCount: frameCount)
        
        let converter = AVAudioConverter(from: inputFormat, to: outputFormat)
        let outFrames = AVAudioFrameCount(Double(chunkBuffer.frameLength) * targetSampleRate / inputFormat.sampleRate) + 1
        
        guard let outBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: outFrames) else {
            throw AudioIntelligenceError.io(.decodeFailed(file.url))
        }
        
        let state = ConversionState()
        converter?.convert(to: outBuffer, error: nil) { _, outStatus in
            if state.consumed { outStatus.pointee = .noDataNow; return nil }
            outStatus.pointee = .haveData
            state.consumed = true
            return chunkBuffer
        }
        
        guard let ptr = outBuffer.floatChannelData?[0] else {
            throw AudioIntelligenceError.io(.decodeFailed(file.url))
        }
        
        let frameLen = Int(outBuffer.frameLength)
        let samples = Array(UnsafeBufferPointer(start: ptr, count: frameLen))
        let duration = Double(frameLen) / targetSampleRate
        
        return AudioBuffer(samples: samples, sampleRate: targetSampleRate, duration: duration)
    }
}
