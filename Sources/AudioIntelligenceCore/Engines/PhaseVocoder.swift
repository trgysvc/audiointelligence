// PhaseVocoder.swift
// Elite Music DNA Engine — Phase 4
//
// Phase Vocoder for time-stretching and pitch-shifting.
// Mirroring librosa.core.phase_vocoder.

import Foundation
import Accelerate

public final class PhaseVocoder: Sendable {
    
    public init() {}
    
    /// Librosa: phase_vocoder()
    /// - Parameters:
    ///   - stft: Original STFT matrix
    ///   - rate: Time-stretch rate (>1.0 faster, <1.0 slower)
    ///   - hopLength: Original hop length
    /// - Returns: Time-stretched STFT matrix
    public func stretch(stft: STFTMatrix, rate: Float) -> STFTMatrix {
        guard rate > 0 else { return stft }
        
        let nFreqs = stft.nFreqs
        let nFramesIn = stft.nFrames
        let nFramesOut = Int(ceil(Float(nFramesIn) / rate))
        
        var newMag = [Float](repeating: 0, count: nFreqs * nFramesOut)
        var newPhase = [Float](repeating: 0, count: nFreqs * nFramesOut)
        
        // Expected phase advance per bin
        var phiAdvance = [Float](repeating: 0, count: nFreqs)
        for f in 0..<nFreqs {
            phiAdvance[f] = 2.0 * .pi * Float(stft.hopLength) * Float(f) / Float(stft.nFFT)
        }
        
        // Phase accumulator
        var phaseAcc = [Float](repeating: 0, count: nFreqs)
        for f in 0..<nFreqs {
            phaseAcc[f] = stft.phase[f * nFramesIn]
        }
        
        for t in 0..<nFramesOut {
            let pos = Float(t) * rate
            let left = Int(floor(pos))
            let right = min(left + 1, nFramesIn - 1)
            let alpha = pos - Float(left)
            
            for f in 0..<nFreqs {
                // 1. Interpolate Magnitude
                let m0 = stft.magnitude[f * nFramesIn + left]
                let m1 = stft.magnitude[f * nFramesIn + right]
                newMag[f * nFramesOut + t] = m0 + alpha * (m1 - m0)
                
                // 2. Interpolate Phase (Phase Locking approximation)
                if t > 0 {
                    let dPhi = stft.phase[f * nFramesIn + right] - stft.phase[f * nFramesIn + left]
                    // Wrap difference
                    let wrappedDPhi = dPhi - phiAdvance[f]
                    let principleDPhi = wrappedDPhi - 2.0 * .pi * round(wrappedDPhi / (2.0 * .pi))
                    
                    phaseAcc[f] += phiAdvance[f] + principleDPhi
                }
                
                newPhase[f * nFramesOut + t] = phaseAcc[f]
            }
        }
        
        return STFTMatrix(
            magnitude: newMag,
            phase: newPhase,
            nFFT: stft.nFFT,
            hopLength: stft.hopLength,
            sampleRate: stft.sampleRate
        )
    }
}
