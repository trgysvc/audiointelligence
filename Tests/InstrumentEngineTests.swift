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

    /// Sanity check that centroid scoring is graded/continuous, not clustered at a small set of
    /// fixed binary sums (0.6, 0.4, etc.) — the mechanism that made the classifier fragile to
    /// tiny upstream numerical noise (see `InstrumentBaselineTests.
    /// testInstrumentClassification_isDeterministicAcrossRepeatedRuns`). Two inputs that are
    /// clearly different distances from a profile's ideal center should score measurably
    /// differently, not identically. Low-band/percussive inputs held at each profile's own mean
    /// (neutral — neither helps nor hurts) to isolate the centroid axis.
    func testGradedScoring_variesWithDistanceFromProfileCenter() {
        // Brass/Trumpet range is centered ~1634Hz (sd 550.9); its own lowBand/percussive means.
        let nearCenter = InstrumentEngine().predict(spectral: spectral(centroid: 1634, flatness: 0.1886), mfcc: realBrassMFCC, lowBandEnergyRatio: 0.3495, percussiveEnergyRatio: 0.3654)
        let nearEdge = InstrumentEngine().predict(spectral: spectral(centroid: 2185, flatness: 0.1886), mfcc: realBrassMFCC, lowBandEnergyRatio: 0.3495, percussiveEnergyRatio: 0.3654)

        let confNearCenter = nearCenter.predictions.first(where: { $0.label == "Brass/Trumpet" })?.confidence
        let confNearEdge = nearEdge.predictions.first(where: { $0.label == "Brass/Trumpet" })?.confidence
        XCTAssertNotNil(confNearCenter)
        XCTAssertNotNil(confNearEdge)
        if let a = confNearCenter, let b = confNearEdge {
            XCTAssertGreaterThan(a, b, "a centroid near the profile's center should score higher than one near its edge — not an identical binary credit")
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
