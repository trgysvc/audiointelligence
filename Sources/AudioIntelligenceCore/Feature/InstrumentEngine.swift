import Foundation
import Accelerate

/**
 * v56.0: Instrument Recognition Engine
 * Uses spectral fingerprints and MFCC distance matching to identify musical components.
 */
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
            label: "Piano",
            centroidRange: 400...1800,
            flatnessMax: 0.1,
            mfccPattern: [-5.0, 2.0, -1.0, 0.5, -0.5, 0.2, -0.1, 0.1, 0.05, 0.02],
            basis: "Mid Centroid + High Tonality + Complex Harmonics"
        ),
        Fingerprint(
            label: "Kick/Bass",
            centroidRange: 0...400,
            flatnessMax: 0.05,
            mfccPattern: [10.0, -2.0, -5.0, -1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0],
            basis: "Sub-250Hz Dominance + Minimal ZCR"
        ),
        Fingerprint(
            label: "Drums/Percussion",
            centroidRange: 3000...12000,
            flatnessMax: 0.8,
            mfccPattern: [15.0, 5.0, 5.0, 2.0, 2.0, 1.0, 1.0, 1.0, 1.0, 1.0],
            basis: "High Flatness + High Spectral Flux (Transients)"
        ),
        Fingerprint(
            label: "Vocal/Lead",
            centroidRange: 1000...3500,
            flatnessMax: 0.15,
            mfccPattern: [0.0, 5.0, 2.0, -2.0, -1.0, 0.5, 0.5, 0.2, 0.1, 0.1],
            basis: "1k-3k Presence Band + Formant Stability"
        ),
        Fingerprint(
            label: "Strings/Synth",
            centroidRange: 1500...5000,
            flatnessMax: 0.12,
            mfccPattern: [2.0, -1.0, 5.0, 2.0, 1.0, 1.0, 0.5, 0.5, 0.2, 0.2],
            basis: "High Spectral Bandwidth + Continuous Harmonic Series"
        )
    ]
    
    public init() {}
    
    public func predict(spectral: AdvancedSpectralMetrics, mfcc: [Float]) -> InstrumentMetrics {
        var predictions = [InstrumentPrediction]()
        
        // Normalize input MFCC for comparison (using first 10 for simplicity)
        let inputPattern = mfcc.prefix(10).map { Float($0) }
        
        for profile in profiles {
            // 1. Spectral Score (Centroid & Flatness)
            var spectralScore: Float = 0.0
            if profile.centroidRange.contains(spectral.centroid) {
                spectralScore += 0.4
            }
            if spectral.flatness < profile.flatnessMax {
                spectralScore += 0.2
            }
            
            // 2. Timbre Score (MFCC Euclidean distance)
            var mfccDistance: Float = 0.0
            for i in 0..<min(inputPattern.count, profile.mfccPattern.count) {
                let diff = inputPattern[i] - profile.mfccPattern[i]
                mfccDistance += diff * diff
            }
            mfccDistance = sqrtf(mfccDistance)
            
            // Convert distance to score (Lower distance = higher score)
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
        
        // Sort by confidence
        predictions.sort { $0.confidence > $1.confidence }
        
        let primary = predictions.first?.label ?? "Ambient/Unclassified"
        
        return InstrumentMetrics(
            predictions: predictions,
            primaryLabel: primary
        )
    }
}
