import Foundation
import Accelerate

/// Neural Instrument Recognition Engine.
/// Uses spectral fingerprints and MFCC distance matching to identify musical components and dominant sound sources.
public final class InstrumentEngine: Sendable {

    // Data-derived fingerprints (Phase 16). Every value here (spectral-shape statistics and the
    // MFCC pattern) is fit from real audio via `Examples/PrototypeTrainer`, using OpenMIC-2018's
    // official TRAINING partition only (`partitions/split01_train.csv`) — the held-out OpenMIC
    // test partition and all of IRMAS (a separate dataset) were never touched by training, so
    // accuracy measured against them is a fair, uncontaminated estimate. Only OpenMIC's 14
    // fine-grained instrument labels with an unambiguous single coarse-class mapping were used
    // (e.g. "piano"->Piano/Keyboard); clips whose real multi-label annotations spanned more than
    // one coarse class were excluded from training to avoid blending two instruments' timbre
    // into one prototype.
    //
    // Four independent spectral-shape features (centroid, flatness, low-band-energy ratio,
    // percussive-energy ratio) are each scored via the same Gaussian-density formula (mean/SD
    // per class, feeding a shared 1/sigma-normalized scoring function) — a wide-variance class
    // pays a real height penalty for its extra spread instead of getting full peak credit AND
    // wide tolerance for free. Every feature is computed for and scored against every class:
    // withholding a feature from a class (e.g. only checking low-band energy for Bass) would
    // remove exactly the information other classes need to be correctly placed AWAY from it,
    // and would make cross-class confidence totals incomparable (different classes summing a
    // different number of terms). Low-band-energy-ratio (Bass) and percussive-energy-ratio
    // (Drums/Percussion) were added after `centroid`+`flatness` alone left both classes at 0%
    // real-world precision — centroid position doesn't meaningfully separate either from the
    // rest (Bass's true signature is *low-frequency energy concentration*, Drums' is *noise-like
    // spectral flatness plus percussive/transient character*, neither of which centroid alone
    // captures) — each candidate feature's discriminating power was measured (Cohen's d) against
    // real OpenMIC audio before being added: low-band-energy d=1.50 (Bass vs. rest), percussive-
    // energy-ratio d=1.80 (Drums vs. rest, replacing an initially-tried onset-density feature
    // that only reached d=0.49). See DEVLOG Phase 16 for full methodology, the diagnostic
    // process that led here (confusion matrix, per-feature score-breakdown, distribution
    // skewness checks), and measured before/after accuracy.
    private struct Fingerprint {
        let label: String
        let centroidMean: Float, centroidSD: Float
        let flatnessMean: Float, flatnessSD: Float
        let lowBandMean: Float, lowBandSD: Float
        let percussiveMean: Float, percussiveSD: Float
        let mfccPattern: [Float] // Reduced 10-coeff pattern
        // MFCC coefficient indices excluded from the timbre-distance calculation (default: none).
        // Coefficient 0 is log-energy, not spectral shape — for Bass/Drums/Strings it measures
        // recording-condition loudness (DI vs. mic'd, mix level, dynamic range) rather than real
        // timbre, and is pure noise there: verified case-by-case on real OpenMIC train clips,
        // excluding it flips 15 clips wrong->correct across the three classes with ZERO clips
        // flipping correct->wrong (0/15 net loss). For Vocals/Brass the opposite holds — their
        // real-world energy level is a genuinely reliable, class-characteristic signal (vocals are
        // consistently mixed forward, sustained wind tone has a stable energy envelope); excluding
        // it there loses 6 and 4 case-by-case-verified clips respectively with only partial offsetting
        // gains, a net loss. Piano showed neither gain nor loss (26.7% either way) — left unchanged,
        // since branching the architecture where there's no measured difference just adds complexity
        // for no benefit. See DEVLOG Phase 26 for the full investigation.
        let mfccExcludedCoefficients: Set<Int>
        let basis: String
    }

    private let profiles: [Fingerprint] = [
        Fingerprint(
            label: "Piano/Keyboard",
            centroidMean: 1079.1, centroidSD: 524.5,
            flatnessMean: 0.0797, flatnessSD: 0.0833,
            lowBandMean: 0.2697, lowBandSD: 0.2210,
            percussiveMean: 0.2455, percussiveSD: 0.0948,
            mfccPattern: [-254.0938, 200.2891, -27.6288, 21.4378, -8.3042, 5.9155, -12.8358, -0.2233, -12.0884, -1.6733],
            mfccExcludedCoefficients: [],
            basis: "OpenMIC-2018 train prototype (n=1550): accordion, organ, piano"
        ),
        Fingerprint(
            label: "Bass (Acoustic/Electric)",
            centroidMean: 1029.7, centroidSD: 625.1,
            flatnessMean: 0.1263, flatnessSD: 0.1025,
            lowBandMean: 0.7491, lowBandSD: 0.2008,
            percussiveMean: 0.3314, percussiveSD: 0.1223,
            mfccPattern: [-260.4742, 169.5767, 7.7181, 48.0809, 8.7370, 20.7677, 0.1662, 10.1528, -3.3805, 4.8324],
            mfccExcludedCoefficients: [0],
            basis: "OpenMIC-2018 train prototype (n=350): bass"
        ),
        Fingerprint(
            label: "Brass/Trumpet",
            centroidMean: 1633.9, centroidSD: 550.9,
            flatnessMean: 0.1886, flatnessSD: 0.1032,
            lowBandMean: 0.3495, lowBandSD: 0.2502,
            percussiveMean: 0.3654, percussiveSD: 0.1098,
            mfccPattern: [-176.3196, 132.1528, -26.2923, 27.7467, -7.9017, 8.7645, -9.4724, 3.0261, -9.2911, 1.7307],
            mfccExcludedCoefficients: [],
            basis: "OpenMIC-2018 train prototype (n=1292): saxophone, trombone, trumpet"
        ),
        Fingerprint(
            label: "Vocals/Chorus",
            centroidMean: 1938.9, centroidSD: 547.7,
            flatnessMean: 0.2637, flatnessSD: 0.1135,
            lowBandMean: 0.3444, lowBandSD: 0.2429,
            percussiveMean: 0.4064, percussiveSD: 0.0800,
            mfccPattern: [-85.9054, 116.4970, -23.1897, 25.9314, -9.8890, 5.3297, -6.9698, 4.7533, -9.3628, 5.9014],
            mfccExcludedCoefficients: [],
            basis: "OpenMIC-2018 train prototype (n=718): voice"
        ),
        Fingerprint(
            label: "Drums/Percussion",
            centroidMean: 2281.3, centroidSD: 693.6,
            flatnessMean: 0.3447, flatnessSD: 0.1162,
            lowBandMean: 0.5924, lowBandSD: 0.2355,
            percussiveMean: 0.4959, percussiveSD: 0.0845,
            mfccPattern: [-120.2319, 93.8670, -5.1137, 35.9895, -3.2795, 14.7737, -3.8496, 8.8711, -4.2021, 6.2101],
            mfccExcludedCoefficients: [0],
            basis: "OpenMIC-2018 train prototype (n=1335): cymbals, drums"
        ),
        Fingerprint(
            label: "Strings/Synth",
            centroidMean: 1448.0, centroidSD: 537.1,
            flatnessMean: 0.1400, flatnessSD: 0.0874,
            lowBandMean: 0.3308, lowBandSD: 0.2599,
            percussiveMean: 0.3214, percussiveSD: 0.1109,
            mfccPattern: [-199.9608, 145.2058, -27.1025, 33.6395, -9.2643, 4.4564, -11.2757, 1.5405, -11.5215, -1.5284],
            mfccExcludedCoefficients: [0],
            basis: "OpenMIC-2018 train prototype (n=2928): banjo, cello, guitar, mandolin, ukulele, violin"
        )
    ]

    // Mean SD for each feature across all 6 trained profiles — the reference scale each
    // profile's own 1/sigma normalization is measured against (see `gaussianScore` below).
    private static let referenceCentroidSD: Float = 579.8
    private static let referenceFlatnessSD: Float = 0.101
    private static let referenceLowBandSD: Float = 0.235
    private static let referencePercussiveSD: Float = 0.1004

    public init() {}

    /// - Parameters:
    ///   - lowBandEnergyRatio: fraction of total STFT energy below 250Hz (Bass-discriminating).
    ///   - percussiveEnergyRatio: `HPSSEngine`'s percussive/total energy ratio for the same
    ///     signal (Drums/Percussion-discriminating).
    public func predict(spectral: AdvancedSpectralMetrics, mfcc: [Float], lowBandEnergyRatio: Float, percussiveEnergyRatio: Float) -> InstrumentMetrics {
        var scored = [(label: String, basis: String, rawConfidence: Float)]()
        let inputPattern = mfcc.prefix(10).map { Float($0) }

        for profile in profiles {
            let s = Self.scoreComponents(profile: profile, spectral: spectral, inputPattern: inputPattern,
                                          lowBandEnergyRatio: lowBandEnergyRatio, percussiveEnergyRatio: percussiveEnergyRatio)
            let totalConfidence = s.centroid + s.flatness + s.lowBand + s.percussive + s.timbre

            if totalConfidence > 0.3 {
                scored.append((label: profile.label, basis: profile.basis, rawConfidence: totalConfidence))
            }
        }

        // Sort/primaryLabel by RAW confidence -- deliberately unaffected by calibration below.
        // Cross-class calibration corrects what the confidence NUMBER means; it was not designed
        // or validated as a re-ranking signal, and primaryLabel's extensive existing validation
        // (Phase 35 production-parity agreement, item 4's Brass/Trumpet recall numbers, etc.) was
        // all measured against raw-score ordering -- changing what determines primaryLabel would
        // silently invalidate that evidence. Only the REPORTED confidence is calibrated (Phase
        // 38); which label wins and which labels are included are both untouched.
        scored.sort { $0.rawConfidence > $1.rawConfidence }
        let primary = scored.first?.label ?? "Ambient/Unclassified"

        // Confidence calibration (DEVLOG item 3 / Phase 38): the UNCLAMPED raw score is what the
        // offline fit used (`ScoreBreakdown.total`, no `min(1.0, ...)`) -- passing anything else
        // here would evaluate the fitted curve outside the domain it was measured on.
        let predictions = scored.map { s in
            InstrumentPrediction(
                label: s.label,
                confidence: Float(InstrumentCalibration.calibrate(label: s.label, rawScore: Double(s.rawConfidence))),
                technicalBasis: s.basis
            )
        }

        return InstrumentMetrics(
            predictions: predictions,
            primaryLabel: primary
        )
    }

    /// Diagnostic-only breakdown of each profile's raw score components (Phase 16 calibration
    /// work) — not part of the normal public API surface consumers need, but real
    /// infrastructure for isolating which scoring term drives a given classification decision
    /// (used by `Examples/ReliabilityAudit`'s confusion-matrix diagnostics). Returns one entry
    /// per profile, unsorted (profile declaration order), every component visible individually.
    public struct ScoreBreakdown: Sendable {
        public let label: String
        public let centroidScore: Float
        public let flatnessScore: Float
        public let lowBandScore: Float
        public let percussiveScore: Float
        public let timbreScore: Float
        public let mfccDistance: Float
        public var total: Float { centroidScore + flatnessScore + lowBandScore + percussiveScore + timbreScore }
    }

    public func predictWithBreakdown(spectral: AdvancedSpectralMetrics, mfcc: [Float], lowBandEnergyRatio: Float, percussiveEnergyRatio: Float) -> [ScoreBreakdown] {
        let inputPattern = mfcc.prefix(10).map { Float($0) }
        return profiles.map { profile in
            let s = Self.scoreComponents(profile: profile, spectral: spectral, inputPattern: inputPattern,
                                          lowBandEnergyRatio: lowBandEnergyRatio, percussiveEnergyRatio: percussiveEnergyRatio)
            return ScoreBreakdown(label: profile.label, centroidScore: s.centroid, flatnessScore: s.flatness,
                                   lowBandScore: s.lowBand, percussiveScore: s.percussive, timbreScore: s.timbre, mfccDistance: s.mfccDistance)
        }
    }

    /// Shared Gaussian scoring: `weight * (referenceSD / sd) * exp(-0.5 * ((value-mean)/sd)^2)`.
    /// Peak credit (`weight`) only at the class's own mean; a wide-SD class pays a height
    /// penalty proportional to how much wider than the cross-class average its spread is,
    /// instead of getting full peak credit AND wide tolerance "for free" (the un-normalized
    /// version of this formula was the mechanism that let Bass/Drums — the two widest-spread
    /// classes on plain centroid — dominate almost every real classification regardless of true
    /// fit; see DEVLOG Phase 16's confusion-matrix diagnosis).
    private static func gaussianScore(value: Float, mean: Float, sd: Float, referenceSD: Float, weight: Float) -> Float {
        let safeSD = max(Float(0.001), sd)
        let dist = (value - mean) / safeSD
        return weight * (referenceSD / safeSD) * expf(-0.5 * dist * dist)
    }

    private static func scoreComponents(profile: Fingerprint, spectral: AdvancedSpectralMetrics, inputPattern: [Float],
                                         lowBandEnergyRatio: Float, percussiveEnergyRatio: Float) -> (centroid: Float, flatness: Float, lowBand: Float, percussive: Float, timbre: Float, mfccDistance: Float) {
        // Four independent spectral-shape features, each Gaussian-scored the same way, each
        // sharing a 0.6 total weight budget evenly (0.15 apiece) — timbre keeps the remaining
        // 0.4, unchanged from before.
        let centroidScore = gaussianScore(value: spectral.centroid, mean: profile.centroidMean, sd: profile.centroidSD,
                                           referenceSD: referenceCentroidSD, weight: 0.15)
        let flatnessScore = gaussianScore(value: spectral.flatness, mean: profile.flatnessMean, sd: profile.flatnessSD,
                                           referenceSD: referenceFlatnessSD, weight: 0.15)
        let lowBandScore = gaussianScore(value: lowBandEnergyRatio, mean: profile.lowBandMean, sd: profile.lowBandSD,
                                          referenceSD: referenceLowBandSD, weight: 0.15)
        let percussiveScore = gaussianScore(value: percussiveEnergyRatio, mean: profile.percussiveMean, sd: profile.percussiveSD,
                                             referenceSD: referencePercussiveSD, weight: 0.15)

        // Timbre Score (MFCC Euclidean distance) — Phase 16 recalibration, plus Phase 26's
        // per-class MFCC-0 exclusion (see `Fingerprint.mfccExcludedCoefficients`'s doc comment).
        var mfccDistance: Float = 0.0
        for i in 0..<min(inputPattern.count, profile.mfccPattern.count) where !profile.mfccExcludedCoefficients.contains(i) {
            let diff = inputPattern[i] - profile.mfccPattern[i]
            mfccDistance += diff * diff
        }
        mfccDistance = sqrtf(mfccDistance)
        let timbreScore = max(0.0, 0.4 - (mfccDistance / 250.0))

        return (centroidScore, flatnessScore, lowBandScore, percussiveScore, timbreScore, mfccDistance)
    }
}
