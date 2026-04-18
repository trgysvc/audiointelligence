// MelSpectrogramEngine.swift
// Elite Music DNA Engine — Phase 2
//
// High-performance Mel Spectrogram calculation using Accelerate (vDSP).
// Mirroring industry standard.feature.melspectrogram.

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
    
    /// Industry Standard: feature.melspectrogram()
    public func createMelSpectrogram(from samples: [Float]) async -> MelSpectrogramResult {
        // 1. STFT
        let stft = await stftEngine.analyze(samples)
        let nFrames = stft.nFrames
        
        // 2. Power Spectrogram (S^2)
        let powerSpec = stftEngine.powerSpectrogram(from: stft)
        
        // vDSP Matrix Multiply: (nFrames x nFreqs) * (nFreqs x nMels)^T
        // We need result in (nFrames x nMels).
        // powerSpec: [nFrames x nFreqs]
        // melFilterbank: [nMels x nFreqs] -> We treat as [nFreqs x nMels] by transposing in mmul or re-organizing.
        // Actually, vDSP_mmul computes C = A * B.
        // If A is (nFrames x nFreqs) and B is (nFreqs x nMels), we get (nFrames x nMels).
        
        // Since melFilterbank is stored as [nMels x nFreqs], we can pass it as B and swap dimensions.
        // Or simpler: Result[t, m] = sum_f Power[t, f] * Filter[m, f]
        
        var melData = [Float](repeating: 0, count: nFrames * nMels)
        
        vDSP_mmul(
            powerSpec, 1,
            melFilterbank, 1,
            &melData, 1,
            vDSP_Length(nFrames),
            vDSP_Length(nMels),
            vDSP_Length(nFreqs)
        )
        
        return MelSpectrogramResult(melData: melData, nFrames: nFrames, nMels: nMels)
    }
}
