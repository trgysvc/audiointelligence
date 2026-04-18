// ManipulationEngine.swift
// Elite Music DNA Engine — Phase 4
//
// High-level audio manipulation: Time-Stretch and Pitch-Shift.
// Mirroring librosa.effects.

import Foundation
import Accelerate

public final class ManipulationEngine: Sendable {
    
    private let stftEngine: STFTEngine
    private let vocoder: PhaseVocoder
    
    public init(sampleRate: Double = 44100, nFFT: Int = 2048, hopLength: Int = 512) {
        self.stftEngine = STFTEngine(nFFT: nFFT, hopLength: hopLength, sampleRate: sampleRate)
        self.vocoder = PhaseVocoder()
    }
    
    /// Librosa: effects.time_stretch()
    /// Changes speed without changing pitch.
    public func timeStretch(_ samples: [Float], rate: Float) async -> [Float] {
        let stft = await stftEngine.analyze(samples)
        let stretchedSTFT = vocoder.stretch(stft: stft, rate: rate)
        return stftEngine.synthesize(stretchedSTFT)
    }
    
    /// Librosa: effects.pitch_shift()
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
    
    private func resample(_ samples: [Float], rate: Float) -> [Float] {
        let nIn = samples.count
        let nOut = Int(Float(nIn) / rate)
        var result = [Float](repeating: 0, count: nOut)
        
        for i in 0..<nOut {
            let pos = Float(i) * rate
            let left = Int(floor(pos))
            let right = min(left + 1, nIn - 1)
            let alpha = pos - Float(left)
            
            if left < nIn {
                result[i] = samples[left] * (1.0 - alpha) + samples[right] * alpha
            }
        }
        
        return result
    }
}
