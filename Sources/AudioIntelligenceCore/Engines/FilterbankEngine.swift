// FilterbankEngine.swift
// Elite Music DNA Engine — Phase 1
//
// Mirroring librosa.filters.mel and librosa.filters.chroma.
// Provides linear transformation matrices for spectral analysis.

import Foundation
import Accelerate

public final class FilterbankEngine: Sendable {
    
    // MARK: - Mel Filterbank
    
    /// Librosa: filters.mel()
    /// - Returns: A [n_mels × (1 + n_fft/2)] flat matrix (Row-Major)
    public static func createMelFilterbank(
        sr: Double,
        nFFT: Int,
        nMels: Int = 128,
        fMin: Float = 0.0,
        fMax: Float? = nil,
        htk: Bool = false,
        norm: String? = "slaney"
    ) -> [Float] {
        let actualFMax = fMax ?? Float(sr / 2.0)
        let nFreqs = nFFT / 2 + 1
        
        // FFT frequencies (Hz)
        let fftFreqs = (0..<nFreqs).map { Float($0) * Float(sr) / Float(nFFT) }
        
        // Mel frequencies (distributed linearly in Mel space)
        let melMin = UtilityEngine.hzToMel(fMin, htk: htk)
        let melMax = UtilityEngine.hzToMel(actualFMax, htk: htk)
        
        let melPoints = (0..<nMels + 2).map { i -> Float in
            let mel = melMin + (melMax - melMin) * Float(i) / Float(nMels + 1)
            return UtilityEngine.melToHz(mel, htk: htk)
        }
        
        var weights = [Float](repeating: 0, count: nMels * nFreqs)
        
        for i in 0..<nMels {
            let left = melPoints[i]
            let center = melPoints[i + 1]
            let right = melPoints[i + 2]
            
            // Triangle calculation
            for f in 0..<nFreqs {
                let freq = fftFreqs[f]
                var weight: Float = 0
                
                if freq >= left && freq <= center {
                    weight = (freq - left) / (center - left)
                } else if freq >= center && freq <= right {
                    weight = (right - freq) / (right - center)
                }
                
                weights[i * nFreqs + f] = weight
            }
            
            // Slaney-style normalization
            if norm == "slaney" {
                let enorm = 2.0 / (right - left)
                for f in 0..<nFreqs {
                    weights[i * nFreqs + f] *= enorm
                }
            }
        }
        
        return weights
    }
    
    // MARK: - Chroma Filterbank
    
    /// Librosa: filters.chroma()
    /// Projects FFT bins onto chroma bins (pitch classes).
    public static func createChromaFilterbank(
        sr: Double,
        nFFT: Int,
        nChroma: Int = 12,
        tuning: Float = 0.0,
        ctroct: Float = 5.0,
        octwidth: Float? = 2.0,
        baseC: Bool = true
    ) -> [Float] {
        let nFreqs = nFFT / 2 + 1
        
        // FFT frequencies, excluding DC
        let fftFreqs = (0..<nFFT).map { Float($0) * Float(sr) / Float(nFFT) }
        
        // Map Hz to octaves
        var frqbins = fftFreqs.map { UtilityEngine.hzToOcts($0, tuning: tuning, binsPerOctave: nChroma) }
        
        // Bin 0 (0Hz) fix: Librosa uses 1.5 octaves below bin 1
        if frqbins.count > 1 {
            frqbins[0] = frqbins[1] - 1.5 * Float(nChroma)
        }
        
        // Calculate bin widths
        var binWidths = [Float](repeating: 1.0, count: nFFT)
        for i in 0..<nFFT-1 {
            binWidths[i] = max(frqbins[i + 1] - frqbins[i], 1.0)
        }
        
        var weights = [Float](repeating: 0, count: nChroma * nFreqs)
        
        for c in 0..<nChroma {
            for f in 0..<nFreqs {
                // Distance in pitch classes
                var d = frqbins[f] - Float(c)
                
                // Wrap around semitones
                let offset = Float(nChroma) / 2.0
                d = (d + offset + 10.0 * Float(nChroma)).truncatingRemainder(dividingBy: Float(nChroma)) - offset
                
                // Gaussian bumps
                var weight = expf(-0.5 * powf(2.0 * d / binWidths[f], 2.0))
                
                // Octave weighting (Gaussian dominant window)
                if let width = octwidth {
                    let octWeight = expf(-0.5 * powf((frqbins[f] / Float(nChroma) - ctroct) / width, 2.0))
                    weight *= octWeight
                }
                
                weights[c * nFreqs + f] = weight
            }
        }
        
        // Normalization (Librosa default: L2)
        for c in 0..<nChroma {
            let rowStart = c * nFreqs
            let rowEnd = rowStart + nFreqs
            let row = Array(weights[rowStart..<rowEnd])
            let normalized = UtilityEngine.normalize(row, norm: 2.0)
            weights.replaceSubrange(rowStart..<rowEnd, with: normalized)
        }
        
        // BaseC shift
        if baseC {
            // Librosa shifts by 3 semitones to start at C if requested (A=0, A#=1, B=2, C=3)
            let shift = 3 * (nChroma / 12)
            var shifted = [Float](repeating: 0, count: nChroma * nFreqs)
            for c in 0..<nChroma {
                let target = (c + shift) % nChroma
                for f in 0..<nFreqs {
                    shifted[target * nFreqs + f] = weights[c * nFreqs + f]
                }
            }
            return shifted
        }
        
        return weights
    }
}
