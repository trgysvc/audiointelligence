import XCTest
@testable import AudioIntelligenceCore

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
    private let realBassMFCC: [Float] = [-260.4742, 169.5767, 7.7181, 48.0809, 8.7370, 20.7677, 0.1662, 10.1528, -3.3805, 4.8324]
    private let realDrumsMFCC: [Float] = [-120.2319, 93.8670, -5.1137, 35.9895, -3.2795, 14.7737, -3.8496, 8.8711, -4.2021, 6.2101]

    /// Guards against the underlying scoring mechanism collapsing to a small set of fixed binary
    /// sums (0.6, 0.4, etc.) — the specific fragility to tiny upstream numerical noise this
    /// class's own graded-scoring rewrite (Phase 15) fixed (see `InstrumentBaselineTests.
    /// testInstrumentClassification_isDeterministicAcrossRepeatedRuns`).
    ///
    /// **What this test verifies changed with calibration, and the doc comment now says so
    /// directly rather than as a patch note** -- before DEVLOG item 3/Phase 38-39 wired per-class
    /// ISOTONIC calibration into `predict()`'s public `confidence`, that field was the raw graded
    /// score itself, so "closer to center scores higher" held for ANY two distinct distances,
    /// continuously. Isotonic calibration is a step function BY DESIGN (that is what makes it
    /// isotonic) -- within one block it is now correctly, deliberately FLAT, so "any two distinct
    /// distances differ" is no longer a true universal claim, and asserting it against two
    /// arbitrary points is asserting something calibration doesn't promise. What the test
    /// verifies now, precisely: **calibration has not collapsed to a single constant regardless
    /// of input** -- a center point and a point far enough away to land in a different isotonic
    /// block still produce different confidence. That's a real, narrower invariant (it would catch
    /// a genuine calibration-collapse bug -- e.g. a bad re-fit degenerating to one block covering
    /// the whole range) that survives calibration's plateaus rather than contradicting them.
    ///
    /// `edge` was originally 1 SD out (2185Hz, chosen when `.confidence` was still continuous);
    /// both it and `center` (1634Hz) landed in calibration's same top saturation block (found via
    /// a repo-wide audit, 2026-09-03, both calibrating to exactly 1.0) -- correct isotonic
    /// behavior, not an `InstrumentEngine` regression, just a test written for a property
    /// calibration no longer has everywhere. Moved `edge` to 4000Hz (~4.3 SD out): measured
    /// directly (not guessed) that raw scores for centroids anywhere in [3185, 5685]Hz all
    /// calibrate to the SAME value (0.629, a wide plateau, not a boundary edge) -- comfortably a
    /// different plateau from center's, and far enough from the 1.0-saturation cutoff
    /// (~2685-3185Hz) to stay robust to the small run-to-run calibration drift Phase 39 already
    /// documented as expected (isotonic blocks are a snapshot of one fit, not a value future
    /// re-fits reproduce exactly).
    // Renamed 2026-09-03 from `testGradedScoring_variesWithDistanceFromProfileCenter` (DEVLOG
    // Phase 46) to match what it verifies post-calibration -- see the doc comment above.
    func testCalibratedConfidence_differsAcrossDistinctIsotonicPlateaus() {
        // Brass/Trumpet range is centered ~1634Hz (sd 550.9); its own lowBand/percussive means.
        let nearCenter = InstrumentEngine().predict(spectral: spectral(centroid: 1634, flatness: 0.1886), mfcc: realBrassMFCC, lowBandEnergyRatio: 0.3495, percussiveEnergyRatio: 0.3654)
        let farEdge = InstrumentEngine().predict(spectral: spectral(centroid: 4000, flatness: 0.1886), mfcc: realBrassMFCC, lowBandEnergyRatio: 0.3495, percussiveEnergyRatio: 0.3654)

        let confNearCenter = nearCenter.predictions.first(where: { $0.label == "Brass/Trumpet" })?.confidence
        let confFarEdge = farEdge.predictions.first(where: { $0.label == "Brass/Trumpet" })?.confidence
        XCTAssertNotNil(confNearCenter)
        XCTAssertNotNil(confFarEdge)
        if let a = confNearCenter, let b = confFarEdge {
            XCTAssertGreaterThan(a, b, "calibrated confidence collapsed to the same value for a near-center and a far-edge input -- calibration should not degenerate to a single constant across a range this wide")
        }
    }

    /// Bass (Phase 16): centroid alone doesn't separate Bass from the rest in real mixed
    /// recordings (0% real-world precision before this fix) — `lowBandEnergyRatio` (measured
    /// Cohen's d = 1.50 vs. all other classes on real OpenMIC audio) does. A clip with Bass's
    /// own real mean low-band ratio (0.7491) and Bass's own real MFCC prototype should be
    /// classified Bass even with an ambiguous mid-range centroid.
    func testLowBandEnergyRatio_identifiesBassOnRealMeanValues() {
        let result = InstrumentEngine().predict(
            spectral: spectral(centroid: 1029.7, flatness: 0.1263),
            mfcc: realBassMFCC, lowBandEnergyRatio: 0.7491, percussiveEnergyRatio: 0.3314
        )
        XCTAssertEqual(result.primaryLabel, "Bass (Acoustic/Electric)")
    }

    /// Drums/Percussion (Phase 16): same story — `percussiveEnergyRatio` (HPSS-derived, Cohen's
    /// d = 1.80 vs. all other classes) replaces centroid as the real discriminator. A clip with
    /// Drums' own real mean percussive ratio and MFCC prototype should be classified Drums.
    func testPercussiveEnergyRatio_identifiesDrumsOnRealMeanValues() {
        let result = InstrumentEngine().predict(
            spectral: spectral(centroid: 2281.3, flatness: 0.3447),
            mfcc: realDrumsMFCC, lowBandEnergyRatio: 0.5924, percussiveEnergyRatio: 0.4959
        )
        XCTAssertEqual(result.primaryLabel, "Drums/Percussion")
    }

    /// A tonal, non-percussive, non-bass-heavy input (Piano's own real mean values on every
    /// axis) must not be pulled toward Bass/Drums just because those two classes exist in the
    /// profile list — the low-band/percussive scores should be low for Piano-typical values.
    func testTonalInput_doesNotFalsePositiveAsPercussiveOrBass() {
        let result = InstrumentEngine().predict(
            spectral: spectral(centroid: 1079.1, flatness: 0.0797),
            mfcc: realPianoMFCC, lowBandEnergyRatio: 0.2697, percussiveEnergyRatio: 0.2455
        )
        XCTAssertEqual(result.primaryLabel, "Piano/Keyboard")
    }
}
