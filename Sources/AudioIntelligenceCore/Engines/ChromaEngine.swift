// ChromaEngine.swift
// Elite Music DNA Engine — Phase 2
//
// Librosa eşdeğerleri:
//   filters.chroma() — Gaussian chroma filter bank
//   feature.chroma_stft() — chromagram from STFT
//   feature.tonnetz() (optional)
//   Krumhansl-Schmuckler key detection

import Accelerate
import Foundation

// MARK: - Chroma Sonuç

public struct ChromaResult: Sendable {
    public let chromagram: [[Float]]    // [12 × nFrames]
    public let meanChroma: [Float]      // [12] — tüm süre ortalaması
    public let key: String              // "C Major", "A Minor" etc.
    public let keyStrength: Float       // Korelasyon gücü [0..1]
    public let isMinor: Bool

    public static let noteNames = ["C", "C#", "D", "D#", "E", "F",
                                    "F#", "G", "G#", "A", "A#", "B"]
}

// MARK: - Chroma Filter Bank

/// Librosa filters.chroma() — birebir implementasyon
/// n_chroma=12, ctroct=5.0, octwidth=2.0, base_c=True
final class ChromaFilterBank: @unchecked Sendable {

    let weights: [[Float]]   // [12 × nFreqs]
    let nFFT: Int
    let sampleRate: Float

    init(nFFT: Int = 2048, sampleRate: Float = 22050, tuning: Float = 0.0) {
        self.nFFT = nFFT
        self.sampleRate = sampleRate
        self.weights = ChromaFilterBank.buildWeights(nFFT: nFFT, sampleRate: sampleRate, tuning: tuning)
    }

    /// Librosa: filters.chroma() — Gaussian chroma filter bank
    static func buildWeights(nFFT: Int, sampleRate: Float, tuning: Float,
                              nChroma: Int = 12, ctroct: Float = 5.0, octwidth: Float = 2.0) -> [[Float]] {
        let nFreqs = nFFT / 2 + 1

        // FFT frequencies → chroma bins
        // frqbins = n_chroma * hz_to_octs(frequencies, tuning)
        // hz_to_octs: octs = log2(freq / (A440 * 2^(tuning/1200)))
        var frqbins = [Float](repeating: 0, count: nFreqs)
        let a440: Float = 440.0 * powf(2.0, tuning / 1200.0)

        for i in 1..<nFreqs {
            let hz = Float(i) * sampleRate / Float(nFFT)
            if hz > 0 {
                frqbins[i] = Float(nChroma) * log2f(hz / a440) + Float(nChroma) * 5  // +5 octaves offset
            }
        }
        frqbins[0] = frqbins[1] - Float(nChroma)  // DC bin

        var weights = [[Float]](repeating: [Float](repeating: 0, count: nFreqs), count: nChroma)

        for c in 0..<nChroma {
            for j in 0..<nFreqs {
                // Distance from frqbins[j] to chroma bin c (circular, mod nChroma)
                var dist = frqbins[j] - Float(c)
                // Center in [-nChroma/2, nChroma/2]
                dist = dist - Float(nChroma) * roundf(dist / Float(nChroma))
                // Gaussian bump
                let binwidthbins: Float = 1.0  // 1 bin width
                weights[c][j] = expf(-0.5 * (2.0 * dist / binwidthbins) * (2.0 * dist / binwidthbins))
            }
        }

        // Octave weighting: Gaussian centered at ctroct
        // wts *= exp(-0.5 * ((frqbins/nChroma - ctroct) / octwidth)^2)
        for c in 0..<nChroma {
            for j in 0..<nFreqs {
                let octave = frqbins[j] / Float(nChroma)
                let octWeight = expf(-0.5 * ((octave - ctroct) / octwidth) * ((octave - ctroct) / octwidth))
                weights[c][j] *= octWeight
            }
        }

        // base_c=True: roll -3 positions (A-centered → C-centered)
        var rolled = [[Float]](repeating: [Float](repeating: 0, count: nFreqs), count: nChroma)
        let shift = 3  // A → C
        for c in 0..<nChroma {
            rolled[c] = weights[(c + shift) % nChroma]
        }

        return rolled
    }

    /// Chroma filter → power spectrogram
    func apply(magnitude: [[Float]]) -> [[Float]] {
        let nFreqs = magnitude.count
        let nFrames = magnitude[0].count

        var chroma = [[Float]](repeating: [Float](repeating: 0, count: nFrames), count: 12)

        for c in 0..<12 {
            for f in 0..<min(nFreqs, weights[0].count) {
                let w = weights[c][f]
                if w > 0 {
                    var scaled = [Float](repeating: 0, count: nFrames)
                    // power: mag^2
                    let powRow = magnitude[f].map { $0 * $0 }
                    vDSP_vsmul(powRow, 1, [w], &scaled, 1, vDSP_Length(nFrames))
                    vDSP_vadd(chroma[c], 1, scaled, 1, &chroma[c], 1, vDSP_Length(nFrames))
                }
            }
        }

        // L2 normalize each frame's chroma vector
        return normalizeChroma(chroma)
    }

    func apply(magnitude: [Float], nFrames: Int) -> [[Float]] {
        let nFreqs = magnitude.count / nFrames
        var chroma = [[Float]](repeating: [Float](repeating: 0, count: nFrames), count: 12)

        for c in 0..<12 {
            for f in 0..<min(nFreqs, weights[c].count) {
                let w = weights[c][f]
                if w > 0 {
                    let start = f * nFrames
                    let magRow = Array(magnitude[start..<(start + nFrames)])
                    var powRow = [Float](repeating: 0, count: nFrames)
                    vDSP_vsq(magRow, 1, &powRow, 1, vDSP_Length(nFrames))
                    
                    var scaled = [Float](repeating: 0, count: nFrames)
                    vDSP_vsmul(powRow, 1, [w], &scaled, 1, vDSP_Length(nFrames))
                    vDSP_vadd(chroma[c], 1, scaled, 1, &chroma[c], 1, vDSP_Length(nFrames))
                }
            }
        }

        return normalizeChroma(chroma)
    }
    
    private func normalizeChroma(_ chroma: [[Float]]) -> [[Float]] {
        var result = chroma
        let nFrames = chroma[0].count
        for t in 0..<nFrames {
            var vec = (0..<12).map { result[$0][t] }
            vec = DSPHelpers.normalizeL2(vec)
            for c in 0..<12 {
                result[c][t] = vec[c]
            }
        }
        return result
    }
}

// MARK: - Chroma Engine

public final class ChromaEngine: @unchecked Sendable {

    private let filterBank: ChromaFilterBank
    private let sampleRate: Double

    public init(nFFT: Int = 2048, sampleRate: Double = 22050) {
        self.sampleRate = sampleRate
        self.filterBank = ChromaFilterBank(nFFT: nFFT, sampleRate: Float(sampleRate))
    }

    // MARK: Chromagram

    public func chromagram(stft: STFTMatrix) -> [[Float]] {
        filterBank.apply(magnitude: stft.magnitude, nFrames: stft.nFrames)
    }

    /// Librosa: feature.chroma_cens()
    /// Chromagram Energy Normalized Statistics (CENS).
    /// Best for cover song detection.
    public func createCENS(from chroma: [[Float]], windowSize: Int = 41) -> [[Float]] {
        // 1. L1 Normalization (Frame-wise)
        // Chroma is [12 x nFrames]
        let nFrames = chroma[0].count
        var l1Normalized = [[Float]](repeating: [Float](repeating: 0, count: 12), count: nFrames)
        
        for t in 0..<nFrames {
            let frame = (0..<12).map { chroma[$0][t] }
            l1Normalized[t] = DSPHelpers.normalizeL1(frame)
        }
        
        // 2. Transpose to handle pitch bins independently for temporal smoothing
        // Now it's [12 x nFrames]
        var result = DSPHelpers.transpose(l1Normalized)
        
        // 3. Temporal Smoothing (Bin-wise)
        for i in 0..<result.count {
            result[i] = DSPHelpers.applyHannSmoothing(result[i], windowSize: windowSize)
        }
        
        // 4. L2 Normalization (Bin-wise)
        for i in 0..<result.count {
            result[i] = DSPHelpers.normalizeL2(result[i])
        }
        
        // 5. Transpose back to original format [12 x nFrames]
        // result is already [12 x nFrames], no need for final transpose if we want to return the same shape as input
        // Actually, Librosa returns [12 x nFrames]. My result is [12 x nFrames].
        return result
    }

    // MARK: Key Detection (Krumhansl-Schmuckler)

    /// Krumhansl-Schmuckler anahtar profil korelasyonu.
    /// Mean chroma vektörünü 24 profil (12 major + 12 minor) ile karşılaştır.
    public func detectKey(chromagram: [[Float]]) -> ChromaResult {
        let nFrames = chromagram[0].count

        // Mean chroma across all frames
        var mean = [Float](repeating: 0, count: 12)
        for c in 0..<12 {
            var sum: Float = 0
            vDSP_sve(chromagram[c], 1, &sum, vDSP_Length(nFrames))
            mean[c] = sum / Float(nFrames)
        }

        // Krumhansl-Schmuckler key profiles
        let majorProfile: [Float] = [6.35, 2.23, 3.48, 2.33, 4.38, 4.09,
                                      2.52, 5.19, 2.39, 3.66, 2.29, 2.88]
        let minorProfile: [Float] = [6.33, 2.68, 3.52, 5.38, 2.60, 3.53,
                                      2.54, 4.75, 3.98, 2.69, 3.34, 3.17]

        var bestCorr: Float = -Float.infinity
        var bestKey = 0
        var bestMinor = false

        for root in 0..<12 {
            // Major
            let majorCorr = correlation(mean, rotated(majorProfile, by: root))
            if majorCorr > bestCorr {
                bestCorr = majorCorr
                bestKey = root
                bestMinor = false
            }
            // Minor
            let minorCorr = correlation(mean, rotated(minorProfile, by: root))
            if minorCorr > bestCorr {
                bestCorr = minorCorr
                bestKey = root
                bestMinor = true
            }
        }

        let noteName = ChromaResult.noteNames[bestKey]
        let modeStr = bestMinor ? "Minor" : "Major"
        let keyString = "\(noteName) \(modeStr)"

        return ChromaResult(
            chromagram: chromagram,
            meanChroma: mean,
            key: keyString,
            keyStrength: bestCorr,
            isMinor: bestMinor
        )
    }

    // MARK: Private

    private func correlation(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count else { return 0 }
        let n = a.count
        let aMean = a.reduce(0, +) / Float(n)
        let bMean = b.reduce(0, +) / Float(n)
        let aCentered = a.map { $0 - aMean }
        let bCentered = b.map { $0 - bMean }

        var numerator: Float = 0
        vDSP_dotpr(aCentered, 1, bCentered, 1, &numerator, vDSP_Length(n))

        var aSSQ: Float = 0, bSSQ: Float = 0
        vDSP_svesq(aCentered, 1, &aSSQ, vDSP_Length(n))
        vDSP_svesq(bCentered, 1, &bSSQ, vDSP_Length(n))

        let denom = sqrtf(aSSQ * bSSQ)
        return denom > 1e-8 ? numerator / denom : 0
    }

    private func rotated(_ v: [Float], by n: Int) -> [Float] {
        let count = v.count
        let shift = ((count - n) % count + count) % count
        return Array(v[shift...]) + Array(v[..<shift])
    }
}
