import XCTest
@testable import AudioIntelligenceCore

/// `InstrumentEngine.predict`'s percussion-heavy masking correction compared `profile.label ==
/// "Piano"`, but the actual fingerprint's label is `"Piano/Keyboard"` — that comparison never
/// matched, so the correction (relaxing centroid/flatness sensitivity for piano in dense,
/// percussion-heavy mixes) silently never ran for any input. Fixed to compare against the real
/// label.
final class InstrumentEngineTests: XCTestCase {

    private func spectral(centroid: Float, flatness: Float) -> AdvancedSpectralMetrics {
        AdvancedSpectralMetrics(centroid: centroid, rolloff: 0, flatness: flatness, flux: 0,
                                 skewness: 0, kurtosis: 0, bandwidth: 0, zcr: 0, dynamicRange: 0,
                                 rmsMean: 0, rmsMax: 0, brightnessDescription: "", fullMagnitudes: [])
    }

    // Real per-class mean MFCC vectors, computed by `Examples/PrototypeTrainer` from
    // OpenMIC-2018's training partition (Phase 16) — the same values now baked into
    // `InstrumentEngine`'s own `profiles` array. Used here as realistic-scale test inputs
    // (the old hand-typed patterns were a completely different, wrong magnitude — see
    // `InstrumentEngine.swift`'s `Fingerprint` doc comment).
    private let realPianoMFCC: [Float] = [-254.0938, 200.2891, -27.6288, 21.4378, -8.3042, 5.9155, -12.8358, -0.2233, -12.0884, -1.6733]
    private let realBrassMFCC: [Float] = [-176.3196, 132.1528, -26.2923, 27.7467, -7.9017, 8.7645, -9.4724, 3.0261, -9.2911, 1.7307]

    /// A percussion-heavy mix (centroid > 4000) with a piano-like MFCC timbre: the RAW centroid
    /// (4500Hz) falls well outside Piano/Keyboard's own range (~555-1604Hz) and would score
    /// near-zero on its own, but the masking correction's *adjusted* centroid (4500 * 0.3 =
    /// 1350Hz) lands solidly inside it. With the string-comparison bug, this correction never
    /// applied to any profile (dead code) and a competing profile (matching the raw 4500Hz
    /// directly) would win instead; with the fix, Piano/Keyboard's boosted score should win.
    func testPercussionHeavyMix_pianoMaskingCorrectionApplies() {
        let result = InstrumentEngine().predict(
            spectral: spectral(centroid: 4500, flatness: 0.1),
            mfcc: realPianoMFCC
        )
        XCTAssertEqual(result.primaryLabel, "Piano/Keyboard",
                        "the masking correction must apply for the real 'Piano/Keyboard' label, not a never-matching 'Piano'")
    }

    /// Sanity check that scoring is graded/continuous, not clustered at a small set of fixed
    /// binary sums (0.6, 0.4, etc.) — the mechanism that made the classifier fragile to tiny
    /// upstream numerical noise (see `InstrumentBaselineTests.
    /// testInstrumentClassification_isDeterministicAcrossRepeatedRuns`). Two inputs that are
    /// clearly different distances from a profile's ideal center should score measurably
    /// differently, not identically.
    func testGradedScoring_variesWithDistanceFromProfileCenter() {
        // Brass/Trumpet range is ~1083-2185Hz, center ~1634Hz.
        let nearCenter = InstrumentEngine().predict(spectral: spectral(centroid: 1634, flatness: 0.2), mfcc: realBrassMFCC)
        let nearEdge = InstrumentEngine().predict(spectral: spectral(centroid: 2180, flatness: 0.2), mfcc: realBrassMFCC)

        let confNearCenter = nearCenter.predictions.first(where: { $0.label == "Brass/Trumpet" })?.confidence
        let confNearEdge = nearEdge.predictions.first(where: { $0.label == "Brass/Trumpet" })?.confidence
        XCTAssertNotNil(confNearCenter)
        XCTAssertNotNil(confNearEdge)
        if let a = confNearCenter, let b = confNearEdge {
            XCTAssertGreaterThan(a, b, "a centroid near the profile's center should score higher than one near its edge — not an identical binary credit")
        }
    }
}
