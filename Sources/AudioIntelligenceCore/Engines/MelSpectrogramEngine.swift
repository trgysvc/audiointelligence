// MelSpectrogramEngine.swift
// Elite Music DNA Engine — Phase 2
//
// High-performance Mel Spectrogram calculation using Accelerate (vDSP).
// Mirroring librosa.feature.melspectrogram.

import Foundation
import Accelerate

public struct MelSpectrogramResult: Sendable {
    /// nMels × nFrames flat matrix (Row-Major)
    public let melData: [Float]
    public let nFrames: Int
    public let nMels: Int
}

public final class MelSpectrogramEngine: @unchecked Sendable {
    
    private let stftEngine: STFTEngine
    private let melFilterbank: [Float]
    public let nMels: Int
    private let nFreqs: Int
    
    public init(stftEngine: STFTEngine, nMels: Int = 128) {
        self.stftEngine = stftEngine
        self.nMels = nMels
        self.nFreqs = stftEngine.nFFT / 2 + 1
        
        // Pre-compute filterbank once
        self.melFilterbank = FilterbankEngine.createMelFilterbank(
            sr: stftEngine.sampleRate,
            nFFT: stftEngine.nFFT,
            nMels: nMels
        )
    }
    
    /// Librosa: feature.melspectrogram()
    public func createMelSpectrogram(from samples: [Float]) -> MelSpectrogramResult {
        // 1. STFT
        let stft = stftEngine.analyze(samples)
        let nFrames = stft.nFrames
        
        // 2. Power Spectrogram (S^2)
        let powerSpec = stftEngine.powerSpectrogram(from: stft)
        
        // 3. Matrix Multiply (nMels x nFreqs) * (nFreqs x nFrames)
        // Librosa: mel_spectrum[m, t] = sum_f mel_filterbank[m, f] * power_spectrum[f, t]
        
        var melData = [Float](repeating: 0, count: nMels * nFrames)
        
        // vDSP Matrix Multiply is Column-Major (Fortran-style). 
        // Our matrices are Row-Major but structured. 
        // melFilterbank[m, f] (nMels rows, nFreqs cols)
        // powerSpec[f, t] (nFreqs rows, nFrames cols)
        
        // For efficiency in vDSP_mmul: 
        // C = A * B -> (M x P) * (P x N)
        // melData = melFilterbank * powerSpec
        
        vDSP_mmul(
            melFilterbank, 1,
            powerSpec, 1,
            &melData, 1,
            vDSP_Length(nMels),
            vDSP_Length(nFrames),
            vDSP_Length(nFreqs)
        )
        
        return MelSpectrogramResult(melData: melData, nFrames: nFrames, nMels: nMels)
    }
}
