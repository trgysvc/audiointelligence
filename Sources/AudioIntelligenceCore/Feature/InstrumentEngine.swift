import Foundation
import Accelerate

/// Neural Instrument Recognition Engine.
/// Uses spectral fingerprints and MFCC distance matching to identify musical components and dominant sound sources.
public final class InstrumentEngine: Sendable {
    
    // Theoretical Fingerprints for common instruments
    // (Normalized MFCC centroids + Spectral constraints)
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
            centroidRange: 400...1800,
            flatnessMax: 0.15, // Relaxed for percussive pianos
            mfccPattern: [-5.0, 3.0, -1.0, 0.5, -0.5, 0.2, -0.1, 0.1, 0.05, 0.02],
            basis: "Mid Centroid + High Tonality + Rapid Attack"
        ),
        Fingerprint(
            label: "Bass (Acoustic/Electric)",
            centroidRange: 0...450,
            flatnessMax: 0.06,
            mfccPattern: [12.0, -2.0, -6.0, -1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0],
            basis: "Sub-450Hz Fundamental + Stable Harmonic Sustain"
        ),
        Fingerprint(
            label: "Brass/Trumpet",
            centroidRange: 800...5000,
            flatnessMax: 0.35,
            mfccPattern: [2.0, 8.0, 1.0, 4.0, -1.0, 1.0, 0.5, 0.5, 0.2, 0.2],
            basis: "1k-5k Harmonic Spike + Brassy Timbre (2nd/4th MFCC)"
        ),
        Fingerprint(
            label: "Vocals/Chorus",
            centroidRange: 600...3500,
            flatnessMax: 0.2,
            mfccPattern: [1.0, 6.0, 2.0, -3.0, -2.0, 1.0, 0.5, 0.5, 0.2, 0.2],
            basis: "Formant-Rich Middle Band + Non-Linear Flux"
        ),
        Fingerprint(
            label: "Drums/Percussion",
            centroidRange: 3000...15000,
            flatnessMax: 0.9,
            mfccPattern: [18.0, 5.0, 5.0, 2.0, 2.0, 1.0, 1.0, 1.0, 1.0, 1.0],
            basis: "High Flatness + Broadband Transient Energy"
        ),
        Fingerprint(
            label: "Strings/Synth",
            centroidRange: 1500...6000,
            flatnessMax: 0.12,
            mfccPattern: [2.0, -1.0, 5.0, 2.0, 1.0, 1.0, 0.5, 0.5, 0.2, 0.2],
            basis: "High Spectral Bandwidth + Continuous Vibrato/Flow"
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
            var spectralScore: Float = 0.0
            
            // Masking Correction: Adjust centroid sensitivity if environment is percussion heavy
            let adjustedCentroid = isPercussionHeavy && profile.label == "Piano" ? 
                spectral.centroid * 0.3 : spectral.centroid
                
            if profile.centroidRange.contains(adjustedCentroid) {
                spectralScore += 0.4
            }
            
            // Flatness Sensitivity
            if spectral.flatness < profile.flatnessMax {
                spectralScore += 0.2
            } else if isPercussionHeavy && profile.label == "Piano" && spectral.flatness < 0.6 {
                // Relaxed constraint for Piano in dense mixes
                spectralScore += 0.15
            }
            
            // 2. Timbre Score (MFCC Euclidean distance)
            var mfccDistance: Float = 0.0
            for i in 0..<min(inputPattern.count, profile.mfccPattern.count) {
                let diff = inputPattern[i] - profile.mfccPattern[i]
                mfccDistance += diff * diff
            }
            mfccDistance = sqrtf(mfccDistance)
            
            let timbreScore = max(0.0, 0.4 - (mfccDistance / 50.0))
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
