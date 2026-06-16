import XCTest
import Foundation
@testable import AudioIntelligenceCore

/// Axis A — standard-compliance validation for the AudioScienceEngine "measurement" metrics.
/// Item 1: AES17 THD+N. We synthesize a 997 Hz tone with a *known* harmonic distortion and
/// check the engine reports that THD% (within tolerance). THD+N is an RMS ratio, so a 1%
/// third-harmonic must read ≈1%, not 0.01%.
final class AES17ValidationTests: XCTestCase {

    let sr = 48000.0
    let fund = 997.0

    private func tone(amp: Float, harmonicRel: Float, harmonic: Int, n: Int) -> [Float] {
        var s = [Float](repeating: 0, count: n)
        for i in 0..<n {
            let t = Float(i)
            s[i] = amp * sinf(2 * .pi * Float(fund) * t / Float(sr))
            if harmonicRel > 0 {
                s[i] += amp * harmonicRel * sinf(2 * .pi * Float(fund) * Float(harmonic) * t / Float(sr))
            }
        }
        return s
    }

    func testTHDPlusN() {
        continueAfterFailure = true
        let table = ValidationTable("AES17 THD+N (known-distortion signals)")
        let n = Int(sr) // 1 s
        let eng = AudioScienceEngine(sampleRate: sr)

        // Pure 997 Hz sine → THD+N ≈ 0 (only quantization / notch residual).
        let pure = eng.analyze(samples: tone(amp: 0.5, harmonicRel: 0, harmonic: 3, n: n)).thdPlusN
        // 1% third harmonic → THD+N ≈ 1.0 %.
        let d1 = eng.analyze(samples: tone(amp: 0.5, harmonicRel: 0.01, harmonic: 3, n: n)).thdPlusN
        // 10% third harmonic → THD+N ≈ 10 %.
        let d10 = eng.analyze(samples: tone(amp: 0.5, harmonicRel: 0.10, harmonic: 3, n: n)).thdPlusN

        print(String(format: "THD+N: pure=%.4f%%  1%%harm=%.4f%%  10%%harm=%.4f%%", pure, d1, d10))

        let p1 = table.check("THD+N pure sine (≈0%)",        expected: 0,  measured: Double(pure), tol: 0.2)
        let p2 = table.check("THD+N 1% 3rd harmonic (≈1%)",  expected: 1,  measured: Double(d1),   tol: 0.3)
        let p3 = table.check("THD+N 10% 3rd harmonic (≈10%)",expected: 10, measured: Double(d10),  tol: 1.5)
        table.printTable()
        XCTAssertTrue(p1); XCTAssertTrue(p2); XCTAssertTrue(p3)
    }

    /// SMPTE/DIN IMD: 60 Hz + 7 kHz (4:1) with explicit sidebands at 7000±60 of a known
    /// relative level. IMD = RMS(sidebands)/carrier, so injecting sidebands for r% must read r%.
    private func imdSignal(carrier: Float, imdPercent: Float, n: Int) -> [Float] {
        let s = carrier * (imdPercent / 100.0) / sqrtf(2.0) // each sideband amplitude
        var out = [Float](repeating: 0, count: n)
        for i in 0..<n {
            let t = Float(i)
            out[i] = 0.6 * sinf(2 * .pi * 60 * t / Float(sr))                    // 60 Hz (4×)
                   + carrier * sinf(2 * .pi * 7000 * t / Float(sr))              // 7 kHz carrier
                   + s * sinf(2 * .pi * 6940 * t / Float(sr))                    // lower sideband
                   + s * sinf(2 * .pi * 7060 * t / Float(sr))                    // upper sideband
        }
        return out
    }

    /// ITU-R 468 weighting: a sine's weighted level vs frequency must follow the standard
    /// curve relative to 1 kHz (0 dB). Distinctive points: 2 kHz = +5.6 dB, 6.3 kHz = +12.2 dB.
    func testITU468Weighting() {
        continueAfterFailure = true
        let table = ValidationTable("ITU-R 468 weighting (relative gain vs 1 kHz)")
        let n = Int(sr)
        let eng = AudioScienceEngine(sampleRate: sr)
        func sine(_ f: Double) -> [Float] {
            (0..<n).map { 0.5 * sinf(2 * .pi * Float(f) * Float($0) / Float(sr)) }
        }
        let lvl1k  = eng.analyze(samples: sine(1000)).noiseFloorWeight468
        let lvl2k  = eng.analyze(samples: sine(2000)).noiseFloorWeight468
        let lvl63k = eng.analyze(samples: sine(6300)).noiseFloorWeight468
        let g2k = Double(lvl2k - lvl1k), g63 = Double(lvl63k - lvl1k)
        print(String(format: "468 gains rel 1kHz: 2kHz=%+.2f dB  6.3kHz=%+.2f dB", g2k, g63))

        let p1 = table.check("468 gain @2kHz (+5.6 dB)",  expected: 5.6,  measured: g2k, tol: 1.2)
        let p2 = table.check("468 gain @6.3kHz (+12.2 dB)",expected: 12.2, measured: g63, tol: 1.5)
        table.printTable()
        XCTAssertTrue(p1); XCTAssertTrue(p2)
    }

    /// BS.1770 true-peak: a full-scale fs/4 sine phased at 45° has samples at ±0.707
    /// (sample peak −3.01 dBFS) but a true inter-sample peak of 0 dBFS. The meter must
    /// recover ≈0 dBFS, not −3. Also checks a plain −6 dBFS tone reads ≈−6.
    func testTruePeakInterSample() {
        continueAfterFailure = true
        let table = ValidationTable("BS.1770 true-peak (inter-sample)")
        let n = 48000
        let eng = TruePeakEngine()

        // Full-scale fs/4 sine, 45° phase → sample peak −3.01 dBFS, true peak 0 dBFS.
        let inter = (0..<n).map { sinf(Float.pi * Float($0) / 2.0 + Float.pi / 4.0) }
        let tpInter = eng.detect(samples: inter)
        let samplePeak = 20 * log10f(inter.map { abs($0) }.max() ?? 1e-9)

        // −6 dBFS tone whose samples hit the peak → true peak ≈ −6 dBFS.
        let amp: Float = 0.5
        let low = (0..<n).map { amp * sinf(2 * .pi * 997 * Float($0) / 48000.0) }
        let tpLow = eng.detect(samples: low)

        print(String(format: "TruePeak: inter-sample TP=%.2f dBFS (sample peak %.2f)  −6dB tone TP=%.2f", tpInter, samplePeak, tpLow))

        let p1 = table.check("Inter-sample TP recovers 0 dBFS", expected: 0,  measured: Double(tpInter), tol: 0.6)
        let p2 = table.check("Sample peak was indeed −3 dBFS",  expected: -3.01, measured: Double(samplePeak), tol: 0.3)
        let p3 = table.check("−6 dBFS tone TP ≈ −6 dBFS",       expected: -6, measured: Double(tpLow), tol: 0.6)
        table.printTable()
        XCTAssertTrue(p1); XCTAssertTrue(p2); XCTAssertTrue(p3)
    }

    func testSMPTEIMD() {
        continueAfterFailure = true
        let table = ValidationTable("SMPTE/DIN IMD (known sidebands)")
        let n = 1 << 15 // 32768 samples, pow2
        let eng = AudioScienceEngine(sampleRate: sr)
        let a: Float = 0.15

        let i0  = eng.analyze(samples: imdSignal(carrier: a, imdPercent: 0,  n: n)).smpteIMD
        let i5  = eng.analyze(samples: imdSignal(carrier: a, imdPercent: 5,  n: n)).smpteIMD
        let i10 = eng.analyze(samples: imdSignal(carrier: a, imdPercent: 10, n: n)).smpteIMD
        print(String(format: "IMD: 0%%=%.4f%%  5%%=%.4f%%  10%%=%.4f%%", i0, i5, i10))

        let p1 = table.check("IMD no sidebands (≈0%)", expected: 0,  measured: Double(i0),  tol: 0.3)
        let p2 = table.check("IMD 5% sidebands (≈5%)", expected: 5,  measured: Double(i5),  tol: 0.5)
        let p3 = table.check("IMD 10% sidebands (≈10%)",expected: 10, measured: Double(i10), tol: 1.0)
        table.printTable()
        XCTAssertTrue(p1); XCTAssertTrue(p2); XCTAssertTrue(p3)
    }
}
