import XCTest
import Foundation
import Accelerate
@testable import AudioIntelligenceCore
import AudioIntelligenceMetal

/// Foundational DSP parity (Axis A #5). Dumps a deterministic signal as raw float32 and our
/// engine's features to /tmp/parity, so a Python/librosa script can compare them with matched
/// conventions. Raw-float interchange avoids any WAV/codec quantization difference — both
/// sides process the identical samples.
///
/// Run: `swift test --filter ParityDumpTests` then `/tmp/lrvenv/bin/python /tmp/parity_compare.py`.
final class ParityDumpTests: XCTestCase {

    let dir = "/tmp/parity"
    let sr = 22050.0

    private func writeF32(_ a: [Float], to path: String) {
        var data = Data(capacity: a.count * 4)
        for v in a { withUnsafeBytes(of: v) { data.append(contentsOf: $0) } }
        try? data.write(to: URL(fileURLWithPath: path))
    }

    /// Deterministic STATIONARY multi-tone (non-harmonic freqs). Every frame has the same
    /// spectrum, so the comparison is robust to centering/frame-alignment differences — a
    /// sweep's per-frame frequency made the mean spectrum a frame-alignment artifact.
    private func multiTone(n: Int) -> [Float] {
        let freqs = [440.0, 1320.0, 3010.0, 6050.0]
        var s = [Float](repeating: 0, count: n)
        for i in 0..<n {
            let t = Double(i) / sr
            var v = 0.0
            for f in freqs { v += 0.2 * sin(2.0 * Double.pi * f * t) }
            s[i] = Float(v)
        }
        return s
    }

    /// Standalone vDSP real FFT (no STFTEngine) of a signal with exactly 200 cycles per
    /// 2048-sample window → must peak at bin 200. Isolates whether vDSP usage or STFTEngine
    /// is the source of the half-resolution.
    func testRawVDSPConvention() {
        let nFFT = 2048
        let log2n = vDSP_Length(11)
        let setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))!
        defer { vDSP_destroy_fftsetup(setup) }
        let x = (0..<nFFT).map { Float(sin(2.0 * Double.pi * 200.0 * Double($0) / Double(nFFT))) } // 200 cycles/window
        var realp = [Float](repeating: 0, count: nFFT / 2)
        var imagp = [Float](repeating: 0, count: nFFT / 2)
        realp.withUnsafeMutableBufferPointer { rp in
            imagp.withUnsafeMutableBufferPointer { ip in
                var sc = DSPSplitComplex(realp: rp.baseAddress!, imagp: ip.baseAddress!)
                x.withUnsafeBufferPointer { xb in
                    xb.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: nFFT / 2) { cp in
                        vDSP_ctoz(cp, 1, &sc, 1, vDSP_Length(nFFT / 2))
                    }
                }
                vDSP_fft_zrip(setup, &sc, 1, log2n, FFTDirection(kFFTDirection_Forward))
            }
        }
        var peak = 0; var pv: Float = 0
        for k in 0..<nFFT / 2 { let m = sqrtf(realp[k]*realp[k]+imagp[k]*imagp[k]); if m > pv { pv = m; peak = k } }
        print("🔧 RAW zrip(stride1): 200-cycle peaks at bin \(peak) (correct = 200)")

        // Full complex zip (real signal, imag=0): bin k = index k, unambiguous.
        var zre = x; var zim = [Float](repeating: 0, count: nFFT)
        zre.withUnsafeMutableBufferPointer { rp in
            zim.withUnsafeMutableBufferPointer { ip in
                var sc = DSPSplitComplex(realp: rp.baseAddress!, imagp: ip.baseAddress!)
                vDSP_fft_zip(setup, &sc, 1, log2n, FFTDirection(kFFTDirection_Forward))
            }
        }
        var zp = 0; var zv: Float = 0
        for k in 0..<nFFT / 2 { let m = sqrtf(zre[k]*zre[k]+zim[k]*zim[k]); if m > zv { zv = m; zp = k } }
        print("🔧 zip(full complex): 200-cycle peaks at bin \(zp) (correct = 200)")
    }

    func testDumpFeaturesForParity() async throws {
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let n = Int(4.0 * sr)
        let signal = multiTone(n: n)
        writeF32(signal, to: "\(dir)/signal.f32")

        // STFT magnitude (nFFT 2048, hop 512, Hann, center=true, constant pad).
        let stft = await STFTEngine(nFFT: 2048, hopLength: 512, sampleRate: sr).analyze(signal)
        // header: [nFrames, nFreqs] as float32, then frame-major magnitude.
        var stftOut: [Float] = [Float(stft.nFrames), Float(stft.nFreqs)]
        stftOut.append(contentsOf: stft.magnitude)
        writeF32(stftOut, to: "\(dir)/swift_stft.f32")

        // Direct micro-check: a pure sine at exactly bin-200 frequency (2048-pt FFT).
        let binFreq = 200.0 * sr / 2048.0
        let pure = (0..<n).map { 0.5 * Float(sin(2.0 * Double.pi * binFreq * Double($0) / sr)) }
        let ps = await STFTEngine(nFFT: 2048, hopLength: 512, sampleRate: sr).analyze(pure)
        var pb = 0; var pv: Float = 0
        for b in 0..<ps.nFreqs { let m = ps.magnitude[86 * ps.nFreqs + b]; if m > pv { pv = m; pb = b } }
        print("🔬 pure sine @\(String(format: "%.1f", binFreq))Hz (=bin 200): swift peak bin=\(pb)  [nFFT=\(ps.nFFT) nFreqs=\(ps.nFreqs)]")

        // Swift-side sanity: where does the 440 Hz tone land in a middle frame?
        let f = 86, nF = stft.nFreqs
        var peakBin = 0; var peakVal: Float = 0
        for b in 0..<nF {
            let m = stft.magnitude[f * nF + b]
            if m > peakVal { peakVal = m; peakBin = b }
        }
        let binHz = Double(peakBin) * sr / 2048.0
        // Mel spectrogram (128 mel, Slaney) — feeds MFCC; the classifier's feature base.
        let melEng = MelSpectrogramEngine(stftEngine: STFTEngine(nFFT: 2048, hopLength: 512, sampleRate: sr), nMels: 128)
        let mel = await melEng.createMelSpectrogram(from: signal)
        let melFrames = mel.melData.count / mel.nMels
        var melOut: [Float] = [Float(mel.nMels), Float(melFrames)]
        melOut.append(contentsOf: mel.melData)
        writeF32(melOut, to: "\(dir)/swift_mel.f32")
        print("🎚️ Mel dump: \(mel.nMels)×\(melFrames)")

        // MFCC = DCT of LOG-mel (librosa power_to_db → DCT). The pipeline currently DCTs the
        // linear mel (missing the log) — dump the corrected log-mel version to confirm parity.
        let logMel = mel.melData.map { 10.0 * log10f(max($0, 1e-10)) }
        let mfccRaw = MetalEngine().executeBatchDct(melSpectrogram: logMel, nMfcc: 20, nMels: 128)
        if !mfccRaw.isEmpty {
            var mfccOut: [Float] = [Float(20), Float(mfccRaw.count / 20)]
            mfccOut.append(contentsOf: mfccRaw)
            writeF32(mfccOut, to: "\(dir)/swift_mfcc.f32")
            print("🔢 MFCC dump: 20×\(mfccRaw.count / 20)")
        }

        print("📦 Parity dump: STFT \(stft.nFrames)×\(stft.nFreqs), magnitude.count=\(stft.magnitude.count) (expect \(stft.nFrames * stft.nFreqs))")
        print("   frame 86 peak bin=\(peakBin) → \(String(format: "%.1f", binHz)) Hz (a 440 Hz tone should peak at bin 41)")
        XCTAssertEqual(stft.nFreqs, 1025)
    }
}
