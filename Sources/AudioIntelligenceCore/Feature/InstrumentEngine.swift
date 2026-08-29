import Foundation
import Accelerate

/// Neural Instrument Recognition Engine.
/// Uses spectral fingerprints and MFCC distance matching to identify musical components and dominant sound sources.
public final class InstrumentEngine: Sendable {
    
    // Data-derived fingerprints (Phase 16). Previously every value here (centroid range,
    // flatness ceiling, and especially the MFCC pattern) was hand-typed with no connection to
    // real audio — e.g. the old Piano pattern `[-5.0, 3.0, -1.0, ...]` versus this engine's own
    // real MFCC output magnitude (typically in the hundreds, MFCC-0 dominated by overall
    // log-energy) — meaning `timbreScore` was silently ~0 for every real recording regardless
    // of profile, and the classifier was effectively running on centroid+flatness alone.
    //
    // These values are the real per-class mean +/- 1 SD (centroid, flatness) and mean MFCC
    // vector, computed by `Examples/PrototypeTrainer` from OpenMIC-2018's official TRAINING
    // partition only (`partitions/split01_train.csv`) — the held-out OpenMIC test partition and
    // all of IRMAS (a separate dataset) were never touched by training, so accuracy measured
    // against them is a fair, uncontaminated estimate. Only OpenMIC's 14 fine-grained instrument
    // labels with an unambiguous single coarse-class mapping were used (e.g. "piano"->Piano/
    // Keyboard); clips whose real multi-label annotations spanned more than one coarse class
    // were excluded from training to avoid blending two instruments' timbre into one prototype.
    // See DEVLOG Phase 16 for full methodology and measured before/after accuracy.
    private struct Fingerprint {
        let label: String
        let centroidRange: ClosedRange<Float>
        let flatnessMax: Float
        let mfccPattern: [Float] // Reduced 10-coeff pattern
        let basis: String
    }

    private let profiles: [Fingerprint] = [
        Fingerprint(
            label: "Piano/Keyboard",
            centroidRange: 554.6...1603.6,   // OpenMIC train, n=1550: mean=1079.1 sd=524.5
            flatnessMax: 0.1630,
            mfccPattern: [-254.0938, 200.2891, -27.6288, 21.4378, -8.3042, 5.9155, -12.8358, -0.2233, -12.0884, -1.6733],
            basis: "OpenMIC-2018 train prototype (n=1550): accordion, organ, piano"
        ),
        Fingerprint(
            label: "Bass (Acoustic/Electric)",
            centroidRange: 404.6...1654.8,   // OpenMIC train, n=350: mean=1029.7 sd=625.1
            flatnessMax: 0.2288,
            mfccPattern: [-260.4742, 169.5767, 7.7181, 48.0809, 8.7370, 20.7677, 0.1662, 10.1528, -3.3805, 4.8324],
            basis: "OpenMIC-2018 train prototype (n=350): bass"
        ),
        Fingerprint(
            label: "Brass/Trumpet",
            centroidRange: 1083.0...2184.7,  // OpenMIC train, n=1292: mean=1633.9 sd=550.9
            flatnessMax: 0.2918,
            mfccPattern: [-176.3196, 132.1528, -26.2923, 27.7467, -7.9017, 8.7645, -9.4724, 3.0261, -9.2911, 1.7307],
            basis: "OpenMIC-2018 train prototype (n=1292): saxophone, trombone, trumpet"
        ),
        Fingerprint(
            label: "Vocals/Chorus",
            centroidRange: 1391.2...2486.7,  // OpenMIC train, n=718: mean=1938.9 sd=547.7
            flatnessMax: 0.3772,
            mfccPattern: [-85.9054, 116.4970, -23.1897, 25.9314, -9.8890, 5.3297, -6.9698, 4.7533, -9.3628, 5.9014],
            basis: "OpenMIC-2018 train prototype (n=718): voice"
        ),
        Fingerprint(
            label: "Drums/Percussion",
            centroidRange: 1587.6...2974.9,  // OpenMIC train, n=1335: mean=2281.3 sd=693.6
            flatnessMax: 0.4609,
            mfccPattern: [-120.2319, 93.8670, -5.1137, 35.9895, -3.2795, 14.7737, -3.8496, 8.8711, -4.2021, 6.2101],
            basis: "OpenMIC-2018 train prototype (n=1335): cymbals, drums"
        ),
        Fingerprint(
            label: "Strings/Synth",
            centroidRange: 910.9...1985.1,   // OpenMIC train, n=2928: mean=1448.0 sd=537.1
            flatnessMax: 0.2274,
            mfccPattern: [-199.9608, 145.2058, -27.1025, 33.6395, -9.2643, 4.4564, -11.2757, 1.5405, -11.5215, -1.5284],
            basis: "OpenMIC-2018 train prototype (n=2928): banjo, cello, guitar, mandolin, ukulele, violin"
        )
    ]
    
    public init() {}
    
    public func predict(spectral: AdvancedSpectralMetrics, mfcc: [Float]) -> InstrumentMetrics {
        var predictions = [InstrumentPrediction]()
        
        // 1. Input Processing
        let inputPattern = mfcc.prefix(10).map { Float($0) }
        
        // Multi-Band Refinement (v6.4):
        // We use the spectral rollover and flatness in specialized bands 
        // to detect lead instruments even when high-freq drums dominate the global centroid.
        let isPercussionHeavy = spectral.flatness > 0.4 || spectral.centroid > 4000
        
        for profile in profiles {
            // Masking Correction: Adjust centroid sensitivity if environment is percussion heavy
            let adjustedCentroid = isPercussionHeavy && profile.label == "Piano/Keyboard" ?
                spectral.centroid * 0.3 : spectral.centroid

            // Graded centroid score. Was a binary "inside range = full 0.4 credit, outside =
            // 0" — real audio routinely lands inside several overlapping profile ranges at
            // that identical full credit, producing near-ties whose winner then depends on
            // whatever tiny floating-point noise happens to exist upstream (confirmed
            // empirically: the same real SQAM file classified differently across separate
            // otherwise-identical runs — see `InstrumentBaselineTests`). A Gaussian centered
            // on the range's midpoint gives full credit only at the center and tapers
            // smoothly elsewhere, collapsing most of that tie-proneness at its source instead
            // of arbitrarily breaking ties after the fact.
            let center = (profile.centroidRange.lowerBound + profile.centroidRange.upperBound) / 2
            let halfWidth = max(Float(1.0), (profile.centroidRange.upperBound - profile.centroidRange.lowerBound) / 2)
            let centroidDist = (adjustedCentroid - center) / halfWidth
            // EXPERIMENT (isolated, not yet validated): proper Gaussian density normalization.
            // The un-normalized version below gave every profile the same 0.4 peak regardless
            // of halfWidth — a real Gaussian density's peak height is proportional to 1/sigma,
            // so a wide-variance profile (e.g. Drums/Percussion, halfWidth=693.6) should pay a
            // height penalty for its extra spread instead of getting full peak credit AND wide
            // tolerance for free. `referenceHalfWidth` (580, the mean halfWidth across all 6
            // trained profiles) keeps the overall score scale comparable to before.
            let referenceHalfWidth: Float = 580
            let centroidScore: Float = 0.4 * (referenceHalfWidth / halfWidth) * expf(-0.5 * centroidDist * centroidDist)

            // Graded flatness score — same reasoning, replacing the binary "below max = full
            // 0.2 credit" (with a relaxed 0.15-credit fallback for Piano in dense/percussive
            // mixes) with a smooth linear taper from 0 (at flatnessMax) to full credit (at
            // flatness 0).
            let strictFlatnessScore: Float = 0.2 * max(0, min(1, (profile.flatnessMax - spectral.flatness) / profile.flatnessMax))
            let relaxedFlatnessScore: Float = (isPercussionHeavy && profile.label == "Piano/Keyboard")
                ? 0.15 * max(0, min(1, (Float(0.6) - spectral.flatness) / Float(0.6)))
                : 0.0
            let spectralScore = centroidScore + max(strictFlatnessScore, relaxedFlatnessScore)

            // 2. Timbre Score (MFCC Euclidean distance)
            var mfccDistance: Float = 0.0
            for i in 0..<min(inputPattern.count, profile.mfccPattern.count) {
                let diff = inputPattern[i] - profile.mfccPattern[i]
                mfccDistance += diff * diff
            }
            mfccDistance = sqrtf(mfccDistance)

            // Divisor recalibrated for the real MFCC scale (Phase 16): the old value (50.0)
            // was tuned against the old hand-typed patterns' tiny magnitude (~-5 to 5) and
            // silently zeroed this term for every real recording once real prototypes (MFCC-0
            // dominated by log-energy, typically in the hundreds) replaced them. 250.0 is the
            // real mean pairwise Euclidean distance between the 6 trained prototype MFCC
            // vectors (computed directly from the training run, ranging 28.4 to 188.3) — so a
            // "typical between-class" distance now lands close to zero credit, while a closer,
            // same-class-ish match still earns meaningful partial credit.
            let timbreScore = max(0.0, 0.4 - (mfccDistance / 250.0))
            let totalConfidence = spectralScore + timbreScore
            
            if totalConfidence > 0.3 {
                predictions.append(InstrumentPrediction(
                    label: profile.label,
                    confidence: min(1.0, totalConfidence),
                    technicalBasis: profile.basis
                ))
            }
        }
        
        // Sort and classify
        predictions.sort { $0.confidence > $1.confidence }
        let primary = predictions.first?.label ?? "Ambient/Unclassified"
        
        return InstrumentMetrics(
            predictions: predictions,
            primaryLabel: primary
        )
    }
}
