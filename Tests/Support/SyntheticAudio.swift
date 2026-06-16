import Foundation

/// Deterministic synthetic audio generator for ground-truth validation.
///
/// Every fixture has a mathematically exact "expected" value, so a failing test
/// can only mean the engine is wrong — never the input being ambiguous.
/// Files are written as raw RIFF/PCM WAV so the on-disk bit depth is exact
/// (AVFoundation float buffers would destroy the quantization lattice we need
/// to validate bit-depth detection).
enum SyntheticAudio {

    // MARK: - WAV Writer (RIFF / integer PCM, little-endian)

    /// Writes integer PCM WAV. `channels` is [channel][sample], values in [-1, 1].
    static func writeWAV(
        to url: URL,
        channels: [[Float]],
        sampleRate: Int,
        bitDepth: Int
    ) throws {
        precondition(!channels.isEmpty, "need at least one channel")
        precondition(bitDepth == 16 || bitDepth == 24, "only 16/24-bit supported")
        let channelCount = channels.count
        let frameCount = channels[0].count
        for ch in channels { precondition(ch.count == frameCount, "channel length mismatch") }

        let bytesPerSample = bitDepth / 8
        let blockAlign = channelCount * bytesPerSample
        let byteRate = sampleRate * blockAlign
        let dataSize = frameCount * blockAlign

        var data = Data()

        func appendLE32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }
        func appendLE16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }

        // RIFF header
        data.append(contentsOf: Array("RIFF".utf8))
        appendLE32(UInt32(36 + dataSize))
        data.append(contentsOf: Array("WAVE".utf8))

        // fmt chunk
        data.append(contentsOf: Array("fmt ".utf8))
        appendLE32(16)                       // PCM fmt chunk size
        appendLE16(1)                        // PCM
        appendLE16(UInt16(channelCount))
        appendLE32(UInt32(sampleRate))
        appendLE32(UInt32(byteRate))
        appendLE16(UInt16(blockAlign))
        appendLE16(UInt16(bitDepth))

        // data chunk
        data.append(contentsOf: Array("data".utf8))
        appendLE32(UInt32(dataSize))

        // Interleaved samples, quantized to the exact target bit depth.
        let maxInt16: Float = 32767.0
        let maxInt24: Float = 8388607.0
        for frame in 0..<frameCount {
            for ch in 0..<channelCount {
                let s = max(-1.0, min(1.0, channels[ch][frame]))
                if bitDepth == 16 {
                    let q = Int32((s * maxInt16).rounded())
                    appendLE16(UInt16(bitPattern: Int16(clamping: q)))
                } else {
                    var q = Int32((s * maxInt24).rounded())
                    q = max(-8388608, min(8388607, q))
                    let u = UInt32(bitPattern: q)
                    data.append(UInt8(u & 0xFF))
                    data.append(UInt8((u >> 8) & 0xFF))
                    data.append(UInt8((u >> 16) & 0xFF))
                }
            }
        }

        try data.write(to: url)
    }

    // MARK: - Signal Generators

    /// Periodic click train at an exact BPM. Each click is a short decaying burst,
    /// producing clean onsets for tempo detection. Duration > 45s on demand so it
    /// crosses the pipeline's 45s chunk boundary (where the BPM aggregation bug lives).
    static func clickTrack(bpm: Double, durationSec: Double, sampleRate: Int) -> [Float] {
        let n = Int(durationSec * Double(sampleRate))
        var out = [Float](repeating: 0, count: n)
        let samplesPerBeat = 60.0 / bpm * Double(sampleRate)
        let burstLen = Int(0.01 * Double(sampleRate)) // 10ms click
        var beat = 0.0
        while Int(beat) < n {
            let start = Int(beat)
            for i in 0..<burstLen {
                let idx = start + i
                if idx >= n { break }
                // Decaying 1kHz burst — a sharp, repeatable transient.
                let env = expf(-Float(i) / Float(burstLen) * 5.0)
                out[idx] += env * sinf(2.0 * .pi * 1000.0 * Float(i) / Float(sampleRate)) * 0.8
            }
            beat += samplesPerBeat
        }
        return out
    }

    /// Pure sine of a fixed frequency/amplitude. Used for bit-depth and level tests.
    static func sine(freqHz: Double, durationSec: Double, sampleRate: Int, amplitude: Float = 0.5) -> [Float] {
        let n = Int(durationSec * Double(sampleRate))
        var out = [Float](repeating: 0, count: n)
        for i in 0..<n {
            out[i] = amplitude * sinf(2.0 * .pi * Float(freqHz) * Float(i) / Float(sampleRate))
        }
        return out
    }

    /// A sustained triad in a known key (additive sines on the chord tones).
    /// `rootMidi` is the MIDI note of the root; `semitones` are chord intervals.
    static func chord(rootMidi: Int, semitones: [Int], durationSec: Double, sampleRate: Int) -> [Float] {
        let n = Int(durationSec * Double(sampleRate))
        var out = [Float](repeating: 0, count: n)
        let amp: Float = 0.3 / Float(max(1, semitones.count))
        for st in semitones {
            let midi = rootMidi + st
            let freq = 440.0 * pow(2.0, Double(midi - 69) / 12.0)
            for i in 0..<n {
                out[i] += amp * sinf(2.0 * .pi * Float(freq) * Float(i) / Float(sampleRate))
            }
        }
        return out
    }

    // MARK: - Math helpers

    /// Mix several equal-length buffers.
    static func mix(_ buffers: [[Float]]) -> [Float] {
        guard let first = buffers.first else { return [] }
        var out = [Float](repeating: 0, count: first.count)
        for b in buffers {
            for i in 0..<min(out.count, b.count) { out[i] += b[i] }
        }
        return out
    }
}
