// MFCCEngine.swift
// Elite Music DNA Engine — Phase 2
//
// High-performance Mel-frequency cepstral coefficients (MFCC).
// Mirroring librosa.feature.mfcc using vDSP_DCT.

import Foundation
import Accelerate

public struct MFCCResult: Sendable {
    public let mfcc: [Float]      // Mean MFCC across frames or representative frame
    public let fullData: [Float]  // nMFCC × nFrames
}

public final class MFCCEngine: @unchecked Sendable {
    
    private let melEngine: MelSpectrogramEngine
    private let nMFCC: Int
    private let nMels: Int
    
    // vDSP DCT setup using DFT type for pointer compatibility
    private let dctSetup: vDSP_DFT_Setup
    
    public init(melEngine: MelSpectrogramEngine, nMFCC: Int = 20) {
        self.melEngine = melEngine
        self.nMFCC = nMFCC
        self.nMels = melEngine.nMels
        
        // vDSP_DCT_CreateSetup returns vDSP_DFT_Setup (they share the same pool in C)
        self.dctSetup = vDSP_DCT_CreateSetup(nil, vDSP_Length(nMels), .II)!
    }
    
    public convenience init(nMFCC: Int = 20, nMels: Int = 128, sampleRate: Double = 22050) {
        let stft = STFTEngine(nFFT: 2048, hopLength: 512, sampleRate: sampleRate)
        let mel = MelSpectrogramEngine(stftEngine: stft, nMels: nMels)
        self.init(melEngine: mel, nMFCC: nMFCC)
    }
    
    deinit {
        vDSP_DFT_DestroySetup(dctSetup)
    }
    
    /// Librosa: feature.mfcc()
    public func createMFCC(from samples: [Float]) -> MFCCResult {
        let mel = melEngine.createMelSpectrogram(from: samples)
        return compute(melSpectrogram: mel.melData, stftEngine: STFTEngine(nFFT: 2048, hopLength: 512, sampleRate: 22050))
    }
    
    public func compute(melSpectrogram: [Float], stftEngine: STFTEngine) -> MFCCResult {
        let nFrames = melSpectrogram.count / nMels
        
        var logMel = [Float](repeating: 0, count: melSpectrogram.count)
        for i in 0..<melSpectrogram.count {
            logMel[i] = 10.0 * log10f(max(melSpectrogram[i], 1e-10))
        }
        
        var mfccs = [Float](repeating: 0, count: nMFCC * nFrames)
        var inputFrame  = [Float](repeating: 0, count: nMels)
        var outputFrame = [Float](repeating: 0, count: nMels)
        
        for t in 0..<nFrames {
            for m in 0..<nMels {
                inputFrame[m] = logMel[m * nFrames + t]
            }
            
            vDSP_DCT_Execute(dctSetup, inputFrame, &outputFrame)
            
            let orthoScale = sqrtf(2.0 / Float(nMels))
            for i in 0..<nMFCC {
                let scale = (i == 0) ? (sqrtf(1.0 / Float(nMels))) : orthoScale
                mfccs[i * nFrames + t] = outputFrame[i] * scale
            }
        }
        
        // Calculate mean MFCCs for the result
        var meanMFCC = [Float](repeating: 0, count: nMFCC)
        for i in 0..<nMFCC {
            var sum: Float = 0
            for t in 0..<nFrames {
                sum += mfccs[i * nFrames + t]
            }
            meanMFCC[i] = sum / Float(nFrames)
        }
        
        return MFCCResult(mfcc: meanMFCC, fullData: mfccs)
    }
}
