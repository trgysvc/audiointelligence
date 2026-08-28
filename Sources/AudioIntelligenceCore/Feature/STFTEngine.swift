// STFTEngine.swift
// Elite Music DNA Engine — Phase 1
//
// Industry Standard functional parity: industry standard.stft() — core/spectrum.py
//

import Accelerate
import Foundation
import AudioIntelligenceMetal
import CryptoKit

// MARK: - Window Type

public enum WindowType: String, Sendable {
    case hann
    case hamming
}

// MARK: - STFT Result Matrix

/// Flat memory layout for high-performance audio analysis.
/// Optimized for cache locality: Frame-major (Time-first).
public struct STFTMatrix: Codable, Sendable {
    /// Contiguous data: magnitude[t * nFreqs + f]
    public let magnitude: [Float]
    /// Contiguous data: phase[t * nFreqs + f]
    public let phase: [Float]
    
    public let nFFT: Int
    public let hopLength: Int
    public let sampleRate: Double
    
    public var nFreqs: Int { nFFT / 2 + 1 }
    public var nFrames: Int { magnitude.count / nFreqs }
    
    public init(magnitude: [Float], phase: [Float], nFFT: Int, hopLength: Int, sampleRate: Double) {
        self.magnitude = magnitude
        self.phase = phase
        self.nFFT = nFFT
        self.hopLength = hopLength
        self.sampleRate = sampleRate
    }

    /// Accessor for a specific frequency bin across all frames (Gather operation)
    public func magnitudeRow(forBin f: Int) -> [Float] {
        var row = [Float](repeating: 0, count: nFrames)
        for t in 0..<nFrames {
            row[t] = magnitude[t * nFreqs + f]
        }
        return row
    }
    
    /// Accessor for a specific frame across all frequencies (Contiguous operation)
    public func magnitudeFrame(forTimeline t: Int) -> ArraySlice<Float> {
        let start = t * nFreqs
        return magnitude[start..<(start + nFreqs)]
    }

    public func frequencies() -> [Float] {
        (0..<nFreqs).map { Float($0) * Float(sampleRate) / Float(nFFT) }
    }

    public func frameToTime(_ frame: Int) -> Double {
        Double(frame * hopLength) / sampleRate
    }
}

// MARK: - STFTEngine

/// Short-Time Fourier Transform (STFT) Engine.
/// The foundational spectral analysis engine for all frequency-domain DSP tasks.
public final class STFTEngine: @unchecked Sendable {
    public static let defaultNFFT = 2048
    public static let defaultHopLength = 512

    public let nFFT: Int
    public let hopLength: Int
    public let sampleRate: Double
    public let windowType: WindowType

    private let nFreqs: Int
    private let window: [Float]
    private let dftSetup: vDSP_DFT_Setup
    private let idftSetup: vDSP_DFT_Setup
    private let metalEngine: MetalEngine?

    /// v7.6 SEALED: M4 Silicon Hardware Acceleration Status
    public var isHardwareAccelerated: Bool {
        return metalEngine != nil
    }

    public init(nFFT: Int = defaultNFFT, 
                hopLength: Int = defaultHopLength, 
                sampleRate: Double = 44100,
                windowType: WindowType = .hann,
                metalEngine: MetalEngine? = nil) {
        self.nFFT = nFFT
        self.hopLength = hopLength
        self.sampleRate = sampleRate
        self.windowType = windowType
        self.metalEngine = metalEngine
        self.nFreqs = nFFT / 2 + 1

        // Use periodic window (Industry Standard default: sym=False)
        self.window = STFTEngine.createPeriodicWindow(type: windowType, length: nFFT)

        // vDSP_DFT real-to-complex setup (Optimal for real audio data)
        self.dftSetup = vDSP_DFT_zrop_CreateSetup(nil, vDSP_Length(nFFT), .FORWARD)!
        self.idftSetup = vDSP_DFT_zrop_CreateSetup(nil, vDSP_Length(nFFT), .INVERSE)!
    }

    deinit {
        vDSP_DFT_DestroySetup(dftSetup)
        vDSP_DFT_DestroySetup(idftSetup)
    }

    // MARK: Periodic Window Creation

    private static func createPeriodicWindow(type: WindowType, length: Int) -> [Float] {
        var w = [Float](repeating: 0, count: length)
        let alpha: Float
        let beta: Float
        
        switch type {
        case .hann:
            alpha = 0.5
            beta = 0.5
        case .hamming:
            alpha = 0.54
            beta = 0.46
        }
        
        for n in 0..<length {
            w[n] = alpha - beta * cosf(2.0 * .pi * Float(n) / Float(length))
        }
        return w
    }

    // MARK: Analyze

    /// Computes STFT with Industry Standard-exact behavior.
    /// - Parameter padMode: 'constant' (zeros) or 'reflect' (Industry Standard default: 'constant')
    public func analyze(_ samples: [Float], center: Bool = true, padMode: String = "constant") async -> STFTMatrix {
        // Cache Check (SHA256 hash of the full signal).
        // Previously hashed only the first 2000 + last 2000 samples (+ sample count) for
        // signals over 4000 samples — two different signals sharing the same head/tail but
        // differing in the middle (e.g. the same lead-in/fade padding around different
        // content, which is common when chunking a track) would collide on the same cache
        // key and one would silently return the other's STFT result. SHA256 over the full
        // buffer is still fast relative to the STFT/HPSS/etc. work this cache is protecting
        // (hardware-accelerated on Apple platforms; a 45s/22kHz chunk is ~1M samples, ~4MB).
        let signature = samples.withUnsafeBufferPointer { Data(buffer: $0) }
        let hash = SHA256.hash(data: signature)
        let sampleHash = hash.compactMap { String(format: "%02x", $0) }.joined()
        
        let cacheKey = await IntelligenceCache.shared.generateKey(for: URL(string: "stft://local")!, parameters: [
            "hash": sampleHash, "nFFT": nFFT, "hop": hopLength, "window": windowType.rawValue, "center": center, "pad": padMode
        ])
        
        // In-memory cache only. A spectrogram is reused within a file (onset/mel/spectral
        // re-request the same chunk's STFT) but never across distinct files, so the old
        // disk cache wrote ~42 MB per chunk that was never read back — bloating to GBs and
        // adding seconds/file on batch runs. A small bounded RAM LRU keeps the intra-file
        // reuse without any disk I/O.
        if let cached = STFTMemoryCache.shared.get(cacheKey) {
            return cached
        }

        let input: [Float]
        if center {
            input = padSignal(samples, pad: nFFT / 2, mode: padMode)
        } else {
            input = samples
        }

        let nSamples = input.count
        let nFrames = 1 + Int(floor(Float(nSamples - nFFT) / Float(hopLength)))
        
        var magnitudes = [Float](repeating: 0, count: nFreqs * nFrames)
        var phases     = [Float](repeating: 0, count: nFreqs * nFrames)

        // Log-based FFT setup for zrip
        let log2n = UInt(round(log2(Double(nFFT))))
        let fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))!
        defer { vDSP_destroy_fftsetup(fftSetup) }
        
        var allReal = [Float](repeating: 0, count: nFrames * nFreqs)
        var allImag = [Float](repeating: 0, count: nFrames * nFreqs)

        // v7.6 GPU Optimization: Batched Windowing
        let preWindowed: [Float]
        if let metal = metalEngine {
            preWindowed = metal.executeBatchWindowing(samples: input, window: window, nFFT: nFFT, hopLength: hopLength)
        } else {
            preWindowed = []
        }

        // Full complex FFT (real signal, imag = 0). The previous packed real FFT (vDSP_fft_zrip
        // with a stride-1 ctoz) placed a frequency at HALF its true bin (index k held bin 2k,
        // dropping the odd bins) — the whole frequency axis was 2× compressed. A full complex
        // FFT (vDSP_fft_zip) maps bin k → index k correctly.
        var fftReal = [Float](repeating: 0, count: nFFT)
        var fftImag = [Float](repeating: 0, count: nFFT)
        for t in 0..<nFrames {
            let start = t * hopLength
            if !preWindowed.isEmpty {
                let frameStart = t * nFFT
                for i in 0..<nFFT { fftReal[i] = preWindowed[frameStart + i]; fftImag[i] = 0 }
            } else {
                input.withUnsafeBufferPointer { iBuff in
                    guard let iBase = iBuff.baseAddress else { return }
                    for i in 0..<nFFT { fftReal[i] = iBase[start + i] * window[i]; fftImag[i] = 0 }
                }
            }
            fftReal.withUnsafeMutableBufferPointer { rp in
                fftImag.withUnsafeMutableBufferPointer { ip in
                    var sc = DSPSplitComplex(realp: rp.baseAddress!, imagp: ip.baseAddress!)
                    vDSP_fft_zip(fftSetup, &sc, 1, log2n, FFTDirection(kFFTDirection_Forward))
                }
            }
            // Positive-frequency bins 0…nFFT/2 (k = bin k).
            for f in 0..<nFreqs {
                allReal[t * nFreqs + f] = fftReal[f]
                allImag[t * nFreqs + f] = fftImag[f]
            }
        }
        
        // v7.5 GPU Optimization: Batch Magnitude/Phase to Metal
        if let metal = metalEngine {
            let res = metal.executeComplexMagnitudePhase(real: allReal, imag: allImag)
            if !res.magnitude.isEmpty {
                magnitudes = res.magnitude
                phases = res.phase
            } else {
                // CPU Fallback
                for i in 0..<allReal.count {
                    let re = allReal[i]; let im = allImag[i]
                    magnitudes[i] = sqrtf(re * re + im * im)
                    phases[i] = atan2f(im, re)
                }
            }
        } else {
            // CPU Pure Accelerate
            for i in 0..<allReal.count {
                let re = allReal[i]; let im = allImag[i]
                magnitudes[i] = sqrtf(re * re + im * im)
                phases[i] = atan2f(im, re)
            }
        }
        
        let matrix = STFTMatrix(magnitude: magnitudes, phase: phases, nFFT: nFFT, hopLength: hopLength, sampleRate: sampleRate)
        STFTMemoryCache.shared.set(cacheKey, matrix)
        return matrix
    }

    // MARK: - Synthesize (ISTFT)

    /// Industry Standard: istft() — core/spectrum.py
    /// Reconstructs time-domain signal from STFT matrix.
    /// - Parameter length: If provided, crops padding to match original signal length (useful when center=true)
    public func synthesize(_ stft: STFTMatrix, length: Int? = nil) -> [Float] {
        let nFrames = stft.nFrames
        let nFreqs = stft.nFreqs
        let nFFT = stft.nFFT
        let hopLength = stft.hopLength
        
        let expectedLength = (nFrames - 1) * hopLength + nFFT
        var signal = [Float](repeating: 0, count: expectedLength)
        var windowSum = [Float](repeating: 0, count: expectedLength)
        
        // Log-based FFT setup for zrip
        let log2n = UInt(round(log2(Double(nFFT))))
        let fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))!
        defer { vDSP_destroy_fftsetup(fftSetup) }
        
        var splitComplex = DSPSplitComplex(
            realp: UnsafeMutablePointer<Float>.allocate(capacity: nFFT / 2),
            imagp: UnsafeMutablePointer<Float>.allocate(capacity: nFFT / 2)
        )
        defer {
            splitComplex.realp.deallocate()
            splitComplex.imagp.deallocate()
        }
        
        var timeDomainOut = [Float](repeating: 0, count: nFFT)
        
        for t in 0..<nFrames {
            // 1. Pack into DSPSplitComplex specialized layout for vDSP_fft_zrip
            // DC in realp[0], Nyquist in imagp[0]
            splitComplex.realp[0] = stft.magnitude[t * nFreqs + 0] * cosf(stft.phase[t * nFreqs + 0])
            splitComplex.imagp[0] = stft.magnitude[t * nFreqs + (nFreqs - 1)] * cosf(stft.phase[t * nFreqs + (nFreqs - 1)])
            
            for f in 1..<nFreqs - 1 {
                let mag = stft.magnitude[t * nFreqs + f]
                let phi = stft.phase[t * nFreqs + f]
                splitComplex.realp[f] = mag * cosf(phi)
                splitComplex.imagp[f] = mag * sinf(phi)
            }
            
            // 2. Inverse FFT
            vDSP_fft_zrip(fftSetup, &splitComplex, 1, log2n, FFTDirection(kFFTDirection_Inverse))
            
            // 3. Unpack and Scale
            // vDSP_fft_zrip Inverse scale: 1/(2N) or just handle it here
            var scale = 0.5 / Float(nFFT) 
            
            timeDomainOut.withUnsafeMutableBufferPointer { buffer in
                guard let baseAddress = buffer.baseAddress else { return }
                baseAddress.withMemoryRebound(to: DSPComplex.self, capacity: nFFT / 2) { complexPtr in
                    vDSP_ztoc(&splitComplex, 1, complexPtr, 1, vDSP_Length(nFFT / 2))
                }
            }
            
            vDSP_vsmul(timeDomainOut, 1, &scale, &timeDomainOut, 1, vDSP_Length(nFFT))
            
            // 4. Overlap-Add
            let start = t * hopLength
            for i in 0..<nFFT {
                let sIdx = start + i
                if sIdx < expectedLength {
                    let win = window[i]
                    signal[sIdx] += timeDomainOut[i] * win
                    windowSum[sIdx] += win * win
                }
            }
        }
        
        // Normalize by window square sum (WOLA)
        for i in 0..<expectedLength {
            if windowSum[i] > 1e-8 {
                signal[i] /= windowSum[i]
            }
        }
        
        // 5. Crop Padding
        if let length = length {
            let startIdx = nFFT / 2
            let endIdx = startIdx + length
            if startIdx < expectedLength {
                let safeEnd = min(endIdx, expectedLength)
                return Array(signal[startIdx..<safeEnd])
            }
        }
        
        return signal
    }

    // MARK: Padding Logic

    private func padSignal(_ samples: [Float], pad: Int, mode: String) -> [Float] {
        if mode == "reflect" {
            // industry standard.util.pad_center(samples, size=n, mode='reflect')
            // Equivalent to np.pad(y, pad, mode='reflect')
            var padded = [Float](repeating: 0, count: samples.count + 2 * pad)
            
            // Center
            padded.replaceSubrange(pad..<(pad + samples.count), with: samples)
            
            // Left Reflection
            for i in 0..<pad {
                padded[pad - 1 - i] = samples[i + 1]
            }
            
            // Right Reflection
            let lastIdx = samples.count - 1
            for i in 0..<pad {
                padded[pad + samples.count + i] = samples[lastIdx - 1 - i]
            }
            
            return padded
        } else {
            // Constant (Zero) padding
            let zeros = [Float](repeating: 0, count: pad)
            return zeros + samples + zeros
        }
    }

    // MARK: Post-Processing

    public func powerSpectrogram(from stft: STFTMatrix) -> [Float] {
        var power = [Float](repeating: 0, count: stft.magnitude.count)
        vDSP_vsq(stft.magnitude, 1, &power, 1, vDSP_Length(stft.magnitude.count))
        return power
    }

    public func amplitudeToDb(_ magnitudes: [Float], ref: Float? = nil) -> [Float] {
        let maxVal = ref ?? (magnitudes.max() ?? 1.0)
        let safeRef = max(maxVal, 1e-10)
        
        return magnitudes.map { 20.0 * log10f(max($0, 1e-10) / safeRef) }
    }
    
    public func powerToDb(_ power: [Float], ref: Float? = nil) -> [Float] {
        let maxVal = ref ?? (power.max() ?? 1.0)
        let safeRef = max(maxVal, 1e-10)
        
        return power.map { 10.0 * log10f(max($0, 1e-10) / safeRef) }
    }
    
    public func powerToDb(_ power: [[Float]], ref: Float? = nil) -> [[Float]] {
        // Flatten to find global max if ref is nil
        let flat = power.flatMap { $0 }
        let maxVal = ref ?? (flat.max() ?? 1.0)
        let safeRef = max(maxVal, 1e-10)
        
        return power.map { row in
            row.map { 10.0 * log10f(max($0, 1e-10) / safeRef) }
        }
    }
}

/// Bounded in-memory LRU for STFT matrices, shared across engine instances so the
/// onset/mel/spectral engines re-use a chunk's spectrogram from RAM instead of recomputing
/// it or round-tripping ~42 MB through disk. Capacity is small because only a couple of
/// distinct spectrograms are live at once; nothing is persisted between files.
final class STFTMemoryCache: @unchecked Sendable {
    static let shared = STFTMemoryCache()
    private let lock = NSLock()
    private var store: [String: STFTMatrix] = [:]
    private var order: [String] = []
    private let capacity = 4

    func get(_ key: String) -> STFTMatrix? {
        lock.lock(); defer { lock.unlock() }
        guard let v = store[key] else { return nil }
        if let i = order.firstIndex(of: key) { order.remove(at: i); order.append(key) }
        return v
    }

    func set(_ key: String, _ value: STFTMatrix) {
        lock.lock(); defer { lock.unlock() }
        if store[key] == nil { order.append(key) }
        store[key] = value
        while order.count > capacity {
            let evicted = order.removeFirst()
            store.removeValue(forKey: evicted)
        }
    }

    /// The cache key (`analyze`'s `sampleHash` + STFT params) has no notion of which
    /// `STFTEngine` instance — or whether its `metalEngine` — produced the cached result, so
    /// two engines analyzing identical samples with identical params collide on the same
    /// entry. Tests that need to force fresh execution (e.g. comparing a CPU-only engine
    /// against a GPU-backed one on the same signal) must clear this, not `IntelligenceCache`
    /// (a separate, disk-backed cache with its own key space).
    func clear() {
        lock.lock(); defer { lock.unlock() }
        store.removeAll()
        order.removeAll()
    }
}
