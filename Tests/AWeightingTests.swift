import XCTest
import Foundation
@testable import AudioIntelligenceCore

/// `ScientificFilterBuilder.aWeightingCoefficients` was an unimplemented stub that always
/// returned `[]` regardless of sample rate — every caller of A-weighting silently got no
/// filtering at all. Replaced with a real bilinear transform of the analog A-weighting
/// prototype (IEC 61672-1 / ANSI S1.4-1983 zpk), mirroring the already-verified
/// `itu468WeightingCoefficients` approach.
///
/// The exact analog pole locations (a double pole at 20.598997057568145 Hz, a double pole at
/// 12194.21714799801 Hz, single poles at 107.65264864304628 Hz and 737.8622307362899 Hz, and
/// 4 zeros at s=0) are the literal values from the widely cross-referenced open-source
/// `waveform-analysis` project's `ABC_weighting.py` (itself citing ANSI S1.4-1983 §5.2 and IEC
/// 61672-1 as source standards) — fetched and read directly from the raw source, not inferred.
///
/// There is no independent, pre-existing A-weighting curve implementation elsewhere in this
/// codebase to cross-check against (unlike ITU-468, which has `AudioScienceEngine.itu468Response`
/// as a genuinely separate code path). Instead, this test evaluates the SAME analog zpk's
/// magnitude response via a direct closed-form formula — `|H(jw)| = k*w^4 / [(w²+a1²)(w²+a4²)·
/// sqrt(w²+a2²)·sqrt(w²+a3²)]` — a distinct arithmetic path from `ScientificFilterBuilder`'s
/// Complex-struct bilinear-transform + biquad-cascade machinery. This still catches the class of
/// bug that matters here: a wrong bilinear transform, wrong pole pairing/grouping across the 3
/// biquad sections, or a wrong gain distribution — while `0 dB at 1kHz` is verified as a direct,
/// construction-level invariant (the analog gain is normalized at exactly that point).
final class AWeightingTests: XCTestCase {

    private let f1 = 20.598997057568145
    private let f2 = 107.65264864304628
    private let f3 = 737.8622307362899
    private let f4 = 12194.21714799801

    /// Closed-form magnitude of the analog A-weighting prototype at frequency `f` (Hz), gain
    /// normalized so |H(j*2*pi*1000)| = 1 (0dB reference at 1kHz), independent of the
    /// bilinear-transform/biquad-cascade code under test.
    private func referenceAnalogMagnitude(_ f: Double) -> Double {
        func rawMag(_ freq: Double) -> Double {
            let w = 2.0 * Double.pi * freq
            let a1 = 2.0 * Double.pi * f1
            let a2 = 2.0 * Double.pi * f2
            let a3 = 2.0 * Double.pi * f3
            let a4 = 2.0 * Double.pi * f4
            let numerator = pow(w, 4)
            let denominator = (w * w + a1 * a1) * (w * w + a4 * a4) * sqrt(w * w + a2 * a2) * sqrt(w * w + a3 * a3)
            return numerator / denominator
        }
        return rawMag(f) / rawMag(1000.0)
    }

    /// Evaluates a cascade of biquads at digital frequency `f` (Hz) for sample rate `fs`,
    /// returning linear magnitude |H(e^jw)|. Same technique as `ScientificFilterBuilderTests`.
    private func cascadeMagnitude(_ sections: [ScientificFilterBuilder.BiquadCoeffs], frequency f: Double, sampleRate fs: Double) -> Double {
        let w = 2.0 * Double.pi * f / fs
        let zInvRe = cos(w), zInvIm = -sin(w)
        func cMul(_ a: (Double, Double), _ b: (Double, Double)) -> (Double, Double) {
            (a.0 * b.0 - a.1 * b.1, a.0 * b.1 + a.1 * b.0)
        }
        func cAdd(_ a: (Double, Double), _ b: (Double, Double)) -> (Double, Double) { (a.0 + b.0, a.1 + b.1) }
        func cMag(_ a: (Double, Double)) -> Double { sqrt(a.0 * a.0 + a.1 * a.1) }

        var totalMag = 1.0
        let zInv = (zInvRe, zInvIm)
        let zInv2 = cMul(zInv, zInv)
        for s in sections {
            let num = cAdd(cAdd((s.b0, 0), cMul((s.b1, 0), zInv)), cMul((s.b2, 0), zInv2))
            let den = cAdd(cAdd((1, 0), cMul((s.a1, 0), zInv)), cMul((s.a2, 0), zInv2))
            totalMag *= cMag(num) / cMag(den)
        }
        return totalMag
    }

    func testDigitalFilterMatchesAnalyticCurve_acrossSampleRates() {
        let sampleRates: [Double] = [44100, 48000, 96000]
        let checks: [(freq: Double, tolerance: Double)] = [(100, 0.5), (1000, 0.5), (2000, 0.5), (8000, 1.0), (15000, 30.0)]

        for fs in sampleRates {
            let sections = ScientificFilterBuilder.aWeightingCoefficients(sampleRate: fs)
            XCTAssertEqual(sections.count, 3, "expected 3 biquad sections at fs=\(fs)")

            for (f, tolerance) in checks {
                let digitalDb = 20 * log10(max(1e-12, cascadeMagnitude(sections, frequency: f, sampleRate: fs)))
                let analogDb = 20 * log10(max(1e-12, referenceAnalogMagnitude(f)))
                let delta = abs(digitalDb - analogDb)
                print("🔬 A-weighting @ fs=\(Int(fs)) f=\(Int(f))Hz: digital=\(String(format: "%.2f", digitalDb))dB analog=\(String(format: "%.2f", analogDb))dB Δ=\(String(format: "%.2f", delta))dB")
                XCTAssertLessThan(delta, tolerance, "fs=\(fs) f=\(f)Hz: digital filter deviates more than expected from the analytic curve")
            }
        }
    }

    /// 1kHz is the curve's 0dB reference point by construction (the analog gain is normalized
    /// at exactly that frequency) — the digital filter should reproduce that at every sample rate.
    func test1kHzReference_isUnityGainAtEverySampleRate() {
        for fs: Double in [44100, 48000, 88200, 96000, 192000] {
            let sections = ScientificFilterBuilder.aWeightingCoefficients(sampleRate: fs)
            let db = 20 * log10(cascadeMagnitude(sections, frequency: 1000, sampleRate: fs))
            XCTAssertEqual(db, 0.0, accuracy: 1.0, "fs=\(fs): 1kHz should be close to 0dB reference")
        }
    }

    /// A-weighting attenuates strongly below its low-frequency corner and rolls off again at
    /// very high frequency — a basic sanity check that the filter shape is a band-pass-like
    /// weighting curve, not e.g. a flat pass-through (which is what an empty `[]` coefficient
    /// array — the old bug — effectively degenerated to when callers didn't guard against it).
    func testLowAndHighFrequencies_areAttenuatedRelativeTo1kHz() {
        let fs = 48000.0
        let sections = ScientificFilterBuilder.aWeightingCoefficients(sampleRate: fs)
        let db1k = 20 * log10(cascadeMagnitude(sections, frequency: 1000, sampleRate: fs))
        let db31 = 20 * log10(cascadeMagnitude(sections, frequency: 31.5, sampleRate: fs))
        let db16k = 20 * log10(cascadeMagnitude(sections, frequency: 16000, sampleRate: fs))
        XCTAssertLessThan(db31, db1k - 20, "31.5Hz should be strongly attenuated relative to the 1kHz reference")
        XCTAssertLessThan(db16k, db1k, "16kHz should be attenuated relative to the 1kHz reference")
    }
}
