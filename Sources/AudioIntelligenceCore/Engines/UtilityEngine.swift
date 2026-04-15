// UtilityEngine.swift
// Elite Music DNA Engine — Phase 1
//
// Mirroring librosa.core.convert functions.
// Essential for Librosa-exact filterbank generation.

import Foundation

public enum ScalingMode: Sendable {
    case slaney    // Default Librosa behavior
    case htk       // Hidden Markov Model Toolkit style
}

public enum UtilityEngine {
    
    // MARK: - Frequency Conversions (Hz ↔ Mel)
    
    /// Librosa: hz_to_mel()
    public static func hzToMel(_ hz: Float, htk: Bool = false) -> Float {
        if htk {
            return 2595.0 * log10f(1.0 + hz / 700.0)
        }
        
        // Slaney parameters
        let fMin: Float = 0.0
        let fSp: Float = 200.0 / 3.0
        let minLogHz: Float = 1000.0
        let minLogMel: Float = (minLogHz - fMin) / fSp
        let logStep: Float = logf(6.4) / 27.0
        
        if hz < minLogHz {
            return (hz - fMin) / fSp
        } else {
            return minLogMel + logf(hz / minLogHz) / logStep
        }
    }
    
    /// Librosa: mel_to_hz()
    public static func melToHz(_ mel: Float, htk: Bool = false) -> Float {
        if htk {
            return 700.0 * (powf(10.0, mel / 2595.0) - 1.0)
        }
        
        let fMin: Float = 0.0
        let fSp: Float = 200.0 / 3.0
        let minLogHz: Float = 1000.0
        let minLogMel: Float = (minLogHz - fMin) / fSp
        let logStep: Float = logf(6.4) / 27.0
        
        if mel < minLogMel {
            return fMin + fSp * mel
        } else {
            return minLogHz * expf(logStep * (mel - minLogMel))
        }
    }
    
    // MARK: - Octave Conversions
    
    /// Librosa: hz_to_octs()
    /// A0 = 27.5 Hz by default
    public static func hzToOcts(_ hz: Float, tuning: Float = 0.0, binsPerOctave: Int = 12) -> Float {
        let a440: Float = 440.0
        // Librosa: hz_to_octs uses frequency / (a440 * 2.0**(tuning / bins_per_octave - 4.75))
        // Simplified: log2(hz / 440) + 4.75
        let baseOct = log2f(hz / a440) + 4.75
        return baseOct + (tuning / Float(binsPerOctave))
    }
    
    // MARK: - Normalization
    
    /// Librosa: util.normalize()
    /// Supports axis-wise normalization (mode: 1 for L1, 2 for L2, .infinity for Max)
    public static func normalize(_ vector: [Float], norm: Float = 1.0) -> [Float] {
        guard !vector.isEmpty else { return vector }
        
        let magnitude: Float
        if norm == .infinity {
            magnitude = vector.map(abs).max() ?? 1.0
        } else if norm == 1.0 {
            magnitude = vector.reduce(0) { $0 + abs($1) }
        } else if norm == 2.0 {
            let sumSq = vector.reduce(0) { $0 + ($1 * $1) }
            magnitude = sqrtf(sumSq)
        } else {
            magnitude = 1.0 // Fallback
        }
        
        let safeMag = max(magnitude, 1e-10)
        return vector.map { $0 / safeMag }
    }
}
