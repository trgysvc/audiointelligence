// ManipulationEngine.swift
// Elite Music DNA Engine — Phase 4
//
// High-level audio manipulation: Time-Stretch and Pitch-Shift.
// Mirroring industry standard.effects.

import Foundation
import Accelerate

/// Audio Manipulation Engine.
/// Provides high-fidelity time-stretching and pitch-shifting capabilities using phase vocoding.
public final class ManipulationEngine: Sendable {
    
    private let stftEngine: STFTEngine
    private let vocoder: PhaseVocoder
    
    public init(sampleRate: Double = 44100, nFFT: Int = 2048, hopLength: Int = 512) {
        self.stftEngine = STFTEngine(nFFT: nFFT, hopLength: hopLength, sampleRate: sampleRate)
        self.vocoder = PhaseVocoder()
    }
    
    /// Industry Standard: effects.time_stretch()
    /// Changes speed without changing pitch.
    public func timeStretch(_ samples: [Float], rate: Float) async -> [Float] {
        let stft = await stftEngine.analyze(samples)
        let stretchedSTFT = vocoder.stretch(stft: stft, rate: rate)
        return stftEngine.synthesize(stretchedSTFT)
    }
    
    /// Industry Standard: effects.pitch_shift()
    /// Changes pitch without changing duration.
    /// - Parameters:
    ///   - steps: Number of semitones to shift (positive for up, negative for down)
    public func pitchShift(_ samples: [Float], steps: Float) async -> [Float] {
        let rate = powf(2.0, steps / 12.0)
        
        // 1. Time-stretch by 1/rate to prepare for resampling
        let stretched = await timeStretch(samples, rate: 1.0 / rate)
        
        // 2. Resample back to original length (or rather, change playback rate)
        // For simplicity and quality, high-quality resampling is needed.
        // We can use Accelerate's SRC or a simple linear interpolation for now.
        return resample(stretched, rate: rate)
    }
    
    /// Optimized resampling using vDSP_vgenp (Vectorized Linear Interpolation)
    private func resample(_ samples: [Float], rate: Float) -> [Float] {
        let nIn = samples.count
        let nOut = Int(Float(nIn) / rate)
        var result = [Float](repeating: 0, count: nOut)
        
        // Control vector for vDSP_vgenp: [0, rate, 2*rate, ...]
        var control = [Float](repeating: 0, count: nOut)
        var start: Float = 0
        var step = rate
        vDSP_vgen(&start, &step, &control, 1, vDSP_Length(nOut))
        
        // Vectorized Interpolation
        vDSP_vgenp(samples, 1, control, 1, &result, 1, vDSP_Length(nOut), vDSP_Length(nIn))
        
        return result
    }
}
