// SpectralFeatureEngine.swift
// Elite Music DNA Engine — Phase 2
//
// High-performance spectral feature extraction using Accelerate (vDSP).
// Mirroring industry standard.feature.spectral_centroid, spectral_rolloff, etc.

import Foundation
import Accelerate

/// Advanced Spectral Feature Engine.
/// Provides specialized MIR features such as Spectral Contrast and Band Mapping.
public enum SpectralFeatureEngine {
    
    // MARK: - Spectral Centroid
    
    /// Industry Standard: feature.spectral_centroid()
    /// Calculates the "center of mass" of the spectrum.
    public static func spectralCentroid(from stft: STFTMatrix) -> [Float] {
        let nFreqs = stft.nFreqs
        let nFrames = stft.nFrames
        var centroids = [Float](repeating: 0, count: nFrames)
        
        let freqs = stft.frequencies()
        
        for t in 0..<nFrames {
            var sumMagnitude: Float = 0
            var weightedSum: Float = 0
            
            // Extract frame (contiguous in Frame-major)
            for f in 0..<nFreqs {
                let mag = stft.magnitude[t * nFreqs + f]
                sumMagnitude += mag
                weightedSum += mag * freqs[f]
            }
            
            centroids[t] = sumMagnitude > 1e-10 ? (weightedSum / sumMagnitude) : 0
        }
        
        return centroids
    }
    
    // MARK: - Spectral Rolloff
    
    /// Industry Standard: feature.spectral_rolloff()
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
            // Calculate total energy for this frame (Contiguous access)
            var totalEnergy: Float = 0
            for f in 0..<nFreqs {
                totalEnergy += stft.magnitude[t * nFreqs + f]
            }
            
            let threshold = totalEnergy * rollPercent
            var cumulative: Float = 0
            
            for f in 0..<nFreqs {
                cumulative += stft.magnitude[t * nFreqs + f]
                if cumulative >= threshold {
                    rolloffs[t] = freqs[f]
                    break
                }
            }
        }
        
        return rolloffs
    }
    
    // MARK: - Spectral Flatness
    
    /// Industry Standard: feature.spectral_flatness()
    /// Measure of tonality vs. noise (0 to 1).
    public static func spectralFlatness(from stft: STFTMatrix) -> [Float] {
        let nFreqs = stft.nFreqs
        let nFrames = stft.nFrames
        var flatness = [Float](repeating: 0, count: nFrames)
        
        for t in 0..<nFrames {
            var logSum: Float = 0
            var arithmeticSum: Float = 0
            
            for f in 0..<nFreqs {
                let mag = max(stft.magnitude[t * nFreqs + f], 1e-10)
                logSum += logf(mag)
                arithmeticSum += mag
            }
            
            let gmean = expf(logSum / Float(nFreqs))
            let amean = arithmeticSum / Float(nFreqs)
            
            flatness[t] = amean > 1e-10 ? (gmean / amean) : 0
        }
        
        return flatness
    }
    
    // MARK: - Spectral Contrast
    
    /// Industry Standard: feature.spectral_contrast()
    /// Computes the intensity difference between peaks and valleys in spectral bands.
    public static func spectralContrast(
        from stft: STFTMatrix, 
        nBands: Int = 6, 
        fMin: Float = 200.0
    ) -> [[Float]] {
        let nFreqs = stft.nFreqs
        let nFrames = stft.nFrames
        let freqs = stft.frequencies()
        
        // Octopus-style bands (logarithmic separation)
        var bandEdges = [Int](repeating: 0, count: nBands + 1)
        for i in 0...nBands {
            let f = fMin * powf(2.0, Float(i))
            var idx = 0
            for (j, freq) in freqs.enumerated() {
                if freq >= f { idx = j; break }
            }
            bandEdges[i] = idx
        }
        bandEdges[nBands] = nFreqs - 1
        
        var contrast = [[Float]](repeating: [Float](repeating: 0, count: nFrames), count: nBands + 1)
        
        for t in 0..<nFrames {
            for b in 0..<nBands {
                let start = bandEdges[b]
                let end = bandEdges[b+1]
                guard end > start else { continue }
                
                var bandMags: [Float] = []
                for f in start...end {
                    bandMags.append(stft.magnitude[t * nFreqs + f])
                }
                
                let sorted = bandMags.sorted()
                guard !sorted.isEmpty else { continue }
                
                let valley = sorted[Int(Float(sorted.count) * 0.02)] // 2nd percentile (Industry Standard)
                let peak   = sorted[Int(Float(sorted.count) * 0.98)] // 98th percentile (Industry Standard)
                
                contrast[b][t] = log10f(max(1e-10, peak) / max(1e-10, valley))
            }
        }
        
        return contrast
    }
}
