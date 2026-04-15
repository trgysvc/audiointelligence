// MelFilterBank.swift
// Elite Music DNA Engine — Phase 1
//
// Librosa eşdeğeri: librosa.filters.mel() — filters.py
//
// Tam algoritma (kaynak koddan):
//   1. FFT bin frekansları: fftfreqs = [0, sr/n_fft, ..., sr/2]
//   2. Mel-spaced center freqs: mel_frequencies(n_mels+2, fmin, fmax)
//   3. Triangular filters: lower/upper slopes
//   4. Slaney area normalization: enorm = 2.0 / (mel_f[2:] - mel_f[:n_mels])

import Accelerate
import Foundation

public final class MelFilterBank: @unchecked Sendable {

    // MARK: Properties
    public let nMels: Int         // default: 128
    public let nFFT: Int          // default: 2048
    public let sampleRate: Double
    public let fMin: Float        // default: 0.0
    public let fMax: Float        // default: sr/2

    /// weights: [nMels × nFreqs] — row-major, Slaney normalized
    public let weights: [[Float]]

    // MARK: Init

    public init(nMels: Int = 128, nFFT: Int = 2048, sampleRate: Double = 22050,
                fMin: Float = 0.0, fMax: Float? = nil) {
        self.nMels = nMels
        self.nFFT = nFFT
        self.sampleRate = sampleRate
        self.fMin = fMin
        self.fMax = fMax ?? Float(sampleRate / 2.0)

        self.weights = MelFilterBank.buildWeights(
            nMels: nMels, nFFT: nFFT,
            sampleRate: Float(sampleRate),
            fMin: self.fMin, fMax: self.fMax
        )
    }

    // MARK: Apply

    public func apply(magnitude: [[Float]]) -> [[Float]] {
        let nFreqs = magnitude.count
        let nFrames = magnitude[0].count

        // Power spectrogram: S^2 (column-wise)
        var power = [[Float]](repeating: [Float](repeating: 0, count: nFrames), count: nFreqs)
        for f in 0..<nFreqs {
            vDSP_vsq(magnitude[f], 1, &power[f], 1, vDSP_Length(nFrames))
        }

        return applyMelWeights(to: power)
    }

    public func apply(magnitude: [Float], nFrames: Int) -> [[Float]] {
        let nFreqs = magnitude.count / nFrames
        
        // Power spectrogram: S^2 (flat)
        var power = [Float](repeating: 0, count: magnitude.count)
        vDSP_vsq(magnitude, 1, &power, 1, vDSP_Length(magnitude.count))
        
        // Structure into [[Float]] for current weight logic
        var nestedPower = [[Float]](repeating: [Float](repeating: 0, count: nFrames), count: nFreqs)
        for f in 0..<nFreqs {
            let start = f * nFrames
            nestedPower[f] = Array(power[start..<(start + nFrames)])
        }
        
        return applyMelWeights(to: nestedPower)
    }
    
    private func applyMelWeights(to power: [[Float]]) -> [[Float]] {
        let nFreqs = power.count
        let nFrames = power[0].count
        var melSpec = [[Float]](repeating: [Float](repeating: 0, count: nFrames), count: nMels)

        for m in 0..<nMels {
            for f in 0..<min(nFreqs, weights[m].count) {
                var scaled = [Float](repeating: 0, count: nFrames)
                var w = weights[m][f]
                vDSP_vsmul(power[f], 1, &w, &scaled, 1, vDSP_Length(nFrames))
                vDSP_vadd(melSpec[m], 1, scaled, 1, &melSpec[m], 1, vDSP_Length(nFrames))
            }
        }
        return melSpec
    }

    // MARK: Build Filter Weights

    /// Librosa'nın filters.mel() algoritmasının birebir Swift dönüşümü.
    private static func buildWeights(nMels: Int, nFFT: Int, sampleRate: Float,
                                     fMin: Float, fMax: Float) -> [[Float]] {
        let nFreqs = nFFT / 2 + 1

        // FFT frekans ekseni
        let fftFreqs = (0..<nFreqs).map { Float($0) * sampleRate / Float(nFFT) }

        // Mel-spaced center freqs (n_mels + 2 nokta)
        let melFreqs = melFrequencies(n: nMels + 2, fMin: fMin, fMax: fMax)

        // Triangular filter construction (Librosa kaynak kodu ile bire bir)
        var weights = [[Float]](repeating: [Float](repeating: 0, count: nFreqs), count: nMels)

        for i in 0..<nMels {
            let fLow  = melFreqs[i]
            let fMid  = melFreqs[i + 1]
            let fHigh = melFreqs[i + 2]
            let dLow  = fMid - fLow    // fdiff[i]
            let dHigh = fHigh - fMid   // fdiff[i+1]

            for j in 0..<nFreqs {
                let freq = fftFreqs[j]
                let lower = (freq - fLow) / dLow    // rising slope
                let upper = (fHigh - freq) / dHigh  // falling slope
                weights[i][j] = max(0, min(lower, upper))
            }
        }

        // Slaney area normalization:
        // enorm[i] = 2.0 / (melFreqs[i+2] - melFreqs[i])
        for i in 0..<nMels {
            let enorm = 2.0 / (melFreqs[i + 2] - melFreqs[i])
            for j in 0..<nFreqs {
                weights[i][j] *= enorm
            }
        }

        return weights
    }

    // MARK: Mel Scale Conversion

    /// Hz → Mel (HTK=false, Slaney)
    /// Librosa: librosa.hz_to_mel(freq, htk=False)
    public static func hzToMel(_ hz: Float) -> Float {
        // Slaney formülü (librosa default)
        let fMin: Float = 0.0
        let fSp: Float = 200.0 / 3.0
        let minLogHz: Float = 1000.0
        let minLogMel = (minLogHz - fMin) / fSp
        let logStep = logf(6.4) / 27.0

        if hz >= minLogHz {
            return minLogMel + logf(hz / minLogHz) / logStep
        } else {
            return (hz - fMin) / fSp
        }
    }

    /// Mel → Hz (HTK=false, Slaney)
    public static func melToHz(_ mel: Float) -> Float {
        let fMin: Float = 0.0
        let fSp: Float = 200.0 / 3.0
        let minLogHz: Float = 1000.0
        let minLogMel = (minLogHz - fMin) / fSp
        let logStep = logf(6.4) / 27.0

        if mel >= minLogMel {
            return minLogHz * expf(logStep * (mel - minLogMel))
        } else {
            return fMin + fSp * mel
        }
    }

    /// Mel-spaced frequency array. Librosa: mel_frequencies(n, fmin, fmax)
    public static func melFrequencies(n: Int, fMin: Float, fMax: Float) -> [Float] {
        let melMin = hzToMel(fMin)
        let melMax = hzToMel(fMax)
        return (0..<n).map { i in
            let mel = melMin + Float(i) * (melMax - melMin) / Float(n - 1)
            return melToHz(mel)
        }
    }
}
