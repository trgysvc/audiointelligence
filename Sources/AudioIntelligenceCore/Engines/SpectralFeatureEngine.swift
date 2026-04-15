// SpectralFeatureEngine.swift
// Elite Music DNA Engine — Phase 2
//
// High-performance spectral feature extraction using Accelerate (vDSP).
// Mirroring librosa.feature.spectral_centroid, spectral_rolloff, etc.

import Foundation
import Accelerate

public enum SpectralFeatureEngine {
    
    // MARK: - Spectral Centroid
    
    /// Librosa: feature.spectral_centroid()
    /// Calculates the "center of mass" of the spectrum.
    public static func spectralCentroid(from stft: STFTMatrix) -> [Float] {
        let nFreqs = stft.nFreqs
        let nFrames = stft.nFrames
        var centroids = [Float](repeating: 0, count: nFrames)
        
        let freqs = stft.frequencies()
        
        for t in 0..<nFrames {
            var sumMagnitude: Float = 0
            var weightedSum: Float = 0
            
            // Extract frame (column)
            for f in 0..<nFreqs {
                let mag = stft.magnitude[f * nFrames + t]
                sumMagnitude += mag
                weightedSum += mag * freqs[f]
            }
            
            centroids[t] = sumMagnitude > 1e-10 ? (weightedSum / sumMagnitude) : 0
        }
        
        return centroids
    }
    
    // MARK: - Spectral Rolloff
    
    /// Librosa: feature.spectral_rolloff()
    /// Frequency below which a certain percentage (rollPercent) of total energy lies.
    public static func spectralRolloff(
        from stft: STFTMatrix, 
        rollPercent: Float = 0.85
    ) -> [Float] {
        let nFreqs = stft.nFreqs
        let nFrames = stft.nFrames
        var rolloffs = [Float](repeating: 0, count: nFrames)
        
        let freqs = stft.frequencies()
        
        for t in 0..<nFrames {
            // Calculate total energy for this frame
            var totalEnergy: Float = 0
            for f in 0..<nFreqs {
                totalEnergy += stft.magnitude[f * nFrames + t]
            }
            
            let threshold = totalEnergy * rollPercent
            var cumulative: Float = 0
            
            for f in 0..<nFreqs {
                cumulative += stft.magnitude[f * nFrames + t]
                if cumulative >= threshold {
                    rolloffs[t] = freqs[f]
                    break
                }
            }
        }
        
        return rolloffs
    }
    
    // MARK: - Spectral Flatness
    
    /// Librosa: feature.spectral_flatness()
    /// Measure of tonality vs. noise (0 to 1).
    public static func spectralFlatness(from stft: STFTMatrix) -> [Float] {
        let nFreqs = stft.nFreqs
        let nFrames = stft.nFrames
        var flatness = [Float](repeating: 0, count: nFrames)
        
        for t in 0..<nFrames {
            var logSum: Float = 0
            var arithmeticSum: Float = 0
            
            for f in 0..<nFreqs {
                let mag = max(stft.magnitude[f * nFrames + t], 1e-10)
                logSum += logf(mag)
                arithmeticSum += mag
            }
            
            let gmean = expf(logSum / Float(nFreqs))
            let amean = arithmeticSum / Float(nFreqs)
            
            flatness[t] = amean > 1e-10 ? (gmean / amean) : 0
        }
        
        return flatness
    }
}
