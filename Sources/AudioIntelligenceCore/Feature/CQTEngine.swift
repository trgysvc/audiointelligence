// CQTEngine.swift
// Elite Music DNA Engine — Phase 3
//
// Constant-Q Transform (CQT) for musical pitch analysis.
// Corrected: kernel is now properly FFT'd and multiplied with signal spectrum.
// Matches Librosa's cqt/__cqt_response pattern (Schörkhuber & Klapuri 2010).

import Foundation
import Accelerate

/// Constant-Q Transform (CQT) Engine.
/// Provides logarithmically-spaced frequency analysis for high-fidelity musical pitch accuracy.
/// Based on Brown (1991) and Schörkhuber & Klapuri (2010).
///
/// ⚠️ KNOWN LIMITATION: this engine does not yet produce a usable chromagram. Several
/// real bugs were fixed (real→complex FFT, effective post-decimation rate, kernel L1
/// normalization), but the output chroma is still bass-dominated and low-contrast — likely
/// the crude 2-tap decimation aliasing the heavily-decimated low octaves, plus correlation
/// indexing. A methodical reimplementation against librosa's `cqt` is the proper fix.
/// For key/tonal analysis the pipeline uses a high-resolution STFT chromagram (nFFT 8192),
/// which already reaches librosa-level accuracy — do NOT route tonal analysis through CQT.
public final class CQTEngine: @unchecked Sendable {

    public let nBins: Int
    public let binsPerOctave: Int
    public let fMin: Float
    public let sampleRate: Double

    private let Q: Float
    private let hopLength: Int

    public init(
        nBins: Int = 84,          // 7 octaves × 12 bins
        binsPerOctave: Int = 12,
        fMin: Float = 32.7,       // C1
        sampleRate: Double = 22050,
        hopLength: Int = 512
    ) {
        self.nBins = nBins
        self.binsPerOctave = binsPerOctave
        self.fMin = fMin
        self.sampleRate = sampleRate
        self.hopLength = hopLength
        // Q factor: Schörkhuber & Klapuri (2010), Eq. 4
        self.Q = 1.0 / (powf(2.0, 1.0 / Float(binsPerOctave)) - 1.0)
    }

    /// Computes the Constant-Q Transform using recursive decimation and frequency-domain kernels.
    /// Returns [[Float]] where result[bin] contains magnitude per frame.
    public func transform(_ samples: [Float]) -> [[Float]] {
        guard !samples.isEmpty else { return [] }

        let nOctaves = Int(ceil(Float(nBins) / Float(binsPerOctave)))
        var currentSamples = samples
        var result = [[Float]]()

        // Process from highest to lowest octave; decimate signal for each lower octave.
        // The decimated signal's effective sample rate halves each step, so the analysis
        // kernels must use that effective rate (using the original rate analysed every
        // octave at the wrong frequency — the cause of garbage CQT output).
        for octave in (0..<nOctaves).reversed() {
            let decimations = nOctaves - 1 - octave
            let effectiveSR = sampleRate / pow(2.0, Double(decimations))
            let octaveFreq = fMin * powf(2.0, Float(octave))
            let octaveResult = processOctave(currentSamples, centerFreq: octaveFreq, effectiveSR: effectiveSR)
            result.append(contentsOf: octaveResult)

            if octave > 0 {
                currentSamples = decimateByTwo(currentSamples)
            }
        }

        return result.reversed() // Low→High frequency order
    }

    // MARK: - Internal Processing

    private func processOctave(_ samples: [Float], centerFreq: Float, effectiveSR: Double) -> [[Float]] {
        let n = samples.count
        // Power-of-2 FFT size ≥ n
        let nFFT = max(512, Int(pow(2.0, ceil(log2(Double(n + 1))))))
        let log2n = vDSP_Length(log2(Double(nFFT)))
        guard let setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else {
            return [[Float]](repeating: [], count: binsPerOctave)
        }
        defer { vDSP_destroy_fftsetup(setup) }

        // --- 1. FULL complex FFT of the real signal (imag = 0) ---
        // The convolution of the signal with a complex CQT kernel is NOT Hermitian-
        // symmetric, so the packed real FFT (vDSP_fft_zrip) cannot represent it — that was
        // the bug that produced garbage CQT output. A full complex FFT (vDSP_fft_zip) is
        // required throughout.
        var sigRe = samples + [Float](repeating: 0, count: nFFT - n)
        var sigIm = [Float](repeating: 0, count: nFFT)
        complexFFT(&sigRe, &sigIm, setup: setup, log2n: log2n, direction: FFTDirection(FFT_FORWARD))

        let nFrames = max(1, 1 + (n - 1) / hopLength)
        var bins = [[Float]](repeating: [Float](repeating: 0, count: nFrames), count: binsPerOctave)
        let invN: Float = 1.0 / Float(nFFT)

        for i in 0..<binsPerOctave {
            let freq = centerFreq * powf(2.0, Float(i) / Float(binsPerOctave))
            let kernelLen = max(3, min(Int(Float(effectiveSR) * Q / freq), nFFT))

            // --- 2. Hann-windowed complex exponential kernel, FFT'd (full complex) ---
            let kernel = createComplexKernel(len: kernelLen, freq: freq, sr: Float(effectiveSR))
            var kerRe = kernel.real + [Float](repeating: 0, count: nFFT - kernelLen)
            var kerIm = kernel.imag + [Float](repeating: 0, count: nFFT - kernelLen)
            complexFFT(&kerRe, &kerIm, setup: setup, log2n: log2n, direction: FFTDirection(FFT_FORWARD))

            // --- 3. Correlation in the frequency domain: P = S · conj(K) ---
            var pRe = [Float](repeating: 0, count: nFFT)
            var pIm = [Float](repeating: 0, count: nFFT)
            sigRe.withUnsafeMutableBufferPointer { srp in
              sigIm.withUnsafeMutableBufferPointer { sip in
                kerRe.withUnsafeMutableBufferPointer { krp in
                  kerIm.withUnsafeMutableBufferPointer { kip in
                    pRe.withUnsafeMutableBufferPointer { prp in
                      pIm.withUnsafeMutableBufferPointer { pip in
                        var sc = DSPSplitComplex(realp: srp.baseAddress!, imagp: sip.baseAddress!)
                        var kc = DSPSplitComplex(realp: krp.baseAddress!, imagp: kip.baseAddress!)
                        var pc = DSPSplitComplex(realp: prp.baseAddress!, imagp: pip.baseAddress!)
                        // Conjugate flag -1 → C = A · conj(B) (correlation, not convolution).
                        vDSP_zvmul(&sc, 1, &kc, 1, &pc, 1, vDSP_Length(nFFT), -1)
                      }
                    }
                  }
                }
              }
            }

            // --- 4. Inverse full complex FFT → time-domain analytic response ---
            complexFFT(&pRe, &pIm, setup: setup, log2n: log2n, direction: FFTDirection(FFT_INVERSE))

            // --- 5. Magnitude at hop positions (1/nFFT for the unscaled inverse) ---
            for frame in 0..<nFrames {
                let idx = min(frame * hopLength, nFFT - 1)
                let re = pRe[idx] * invN
                let im = pIm[idx] * invN
                bins[i][frame] = sqrtf(re * re + im * im)
            }
        }

        return bins
    }

    /// In-place full complex FFT (vDSP_fft_zip) on separate real/imag buffers.
    private func complexFFT(_ re: inout [Float], _ im: inout [Float],
                            setup: FFTSetup, log2n: vDSP_Length, direction: FFTDirection) {
        re.withUnsafeMutableBufferPointer { rp in
            im.withUnsafeMutableBufferPointer { ip in
                var sc = DSPSplitComplex(realp: rp.baseAddress!, imagp: ip.baseAddress!)
                vDSP_fft_zip(setup, &sc, 1, log2n, direction)
            }
        }
    }

    /// Creates a Hann-windowed complex exponential kernel for frequency `freq`.
    /// Matches Librosa's `filters.wavelet` basis construction.
    private func createComplexKernel(len: Int, freq: Float, sr: Float) -> (real: [Float], imag: [Float]) {
        var kernelRe = [Float](repeating: 0, count: len)
        var kernelIm = [Float](repeating: 0, count: len)

        let lenF = Float(max(len - 1, 1))
        var windowSum: Float = 0
        for i in 0..<len {
            let t = Float(i)
            // Hann window
            let window = 0.5 * (1.0 - cosf(2.0 * .pi * t / lenF))
            windowSum += window
            // Complex exponential at the signal's *effective* rate (post-decimation).
            let angle   = 2.0 * .pi * freq * t / sr
            kernelRe[i]  = window *  cosf(angle)
            kernelIm[i]  = window * -sinf(angle)
        }
        // L1-normalize by the window sum so every bin responds with comparable amplitude.
        // Without this, low bins (long kernels) accumulate far more energy and the chroma
        // reflects kernel length rather than pitch content.
        if windowSum > 1e-9 {
            let inv = 1.0 / windowSum
            for i in 0..<len { kernelRe[i] *= inv; kernelIm[i] *= inv }
        }
        return (kernelRe, kernelIm)
    }

    /// Low-pass anti-aliasing decimation by factor 2.
    private func decimateByTwo(_ samples: [Float]) -> [Float] {
        let n = samples.count
        let outputLen = n / 2
        guard outputLen > 0 else { return [] }
        var output = [Float](repeating: 0, count: outputLen)
        let filter = [Float](repeating: 0.5, count: 2)
        vDSP_desamp(samples, 2, filter, &output, vDSP_Length(outputLen), 2)
        return output
    }
}

// MARK: - Comparable extension for clamped
private extension Int {
    func clamped(to range: Range<Int>) -> Int {
        return Swift.max(range.lowerBound, Swift.min(self, range.upperBound - 1))
    }
}
