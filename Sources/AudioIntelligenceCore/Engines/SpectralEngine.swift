// SpectralEngine.swift
// Elite Music DNA Engine — Phase 2
//
// Librosa eşdeğerleri: feature/spectral.py
//   spectral_centroid, spectral_bandwidth, spectral_rolloff,
//   spectral_flatness, zero_crossing_rate, rms

import Accelerate
import Foundation

public struct SpectralResult: Sendable {
    public let centroidHz: Float          // Spectral centroid (Hz)
    public let bandwidthHz: Float         // Spectral bandwidth (Hz)
    public let rolloffHz: Float           // 85% rolloff frequency (Hz)
    public let flatness: Float            // Geometric/Arithmetic mean ratio [0..1]
    public let zcr: Float                 // Zero-crossing rate (mean per frame)
    public let rmsMean: Float             // Root mean square energy (mean)
    public let rmsMax: Float              // Peak RMS
    public let dynamicRangeDb: Float      // 20*log10(max/mean)
    public let centroidTimeSeries: [Float]  // Per-frame centroid
    public let rmsSeries: [Float]           // Per-frame RMS
}

public final class SpectralEngine: @unchecked Sendable {

    private let sampleRate: Double
    private let nFFT: Int
    private let hopLength: Int

    public init(sampleRate: Double = 22050, nFFT: Int = 2048, hopLength: Int = 512) {
        self.sampleRate = sampleRate
        self.nFFT = nFFT
        self.hopLength = hopLength
    }

    // MARK: Full Spectral Analysis

    public func analyze(stft: STFTMatrix, samples: [Float]) -> SpectralResult {
        let freqs = stft.frequencies()
        let mag = stft.magnitude
        let nFrames = stft.nFrames

        // Per-frame centroid
        let centroidSeries = spectralCentroid(magnitude: mag, nFrames: nFrames, frequencies: freqs)
        // Mean
        var meanCentroid: Float = 0
        vDSP_meanv(centroidSeries, 1, &meanCentroid, vDSP_Length(nFrames))

        // Per-frame bandwidth (around centroid)
        let bandwidthSeries = spectralBandwidth(magnitude: mag, nFrames: nFrames, frequencies: freqs, centroids: centroidSeries)
        var meanBandwidth: Float = 0
        vDSP_meanv(bandwidthSeries, 1, &meanBandwidth, vDSP_Length(nFrames))

        // Mean rolloff
        let rolloffSeries = spectralRolloff(magnitude: mag, nFrames: nFrames, frequencies: freqs, rollPercent: 0.85)
        var meanRolloff: Float = 0
        vDSP_meanv(rolloffSeries, 1, &meanRolloff, vDSP_Length(nFrames))

        // Mean flatness (over all frames)
        let flatnessSeries = spectralFlatness(magnitude: mag, nFrames: nFrames)
        var meanFlatness: Float = 0
        vDSP_meanv(flatnessSeries, 1, &meanFlatness, vDSP_Length(nFrames))

        // ZCR
        let zcrSeries = zeroCrossingRate(samples: samples, frameLength: nFFT, hopLength: hopLength)
        var meanZCR: Float = 0
        if !zcrSeries.isEmpty {
            vDSP_meanv(zcrSeries, 1, &meanZCR, vDSP_Length(zcrSeries.count))
        }

        // RMS per frame
        let rmsSeries = rmsEnergy(magnitude: mag, nFrames: nFrames)
        var rmsMean: Float = 0
        var rmsMax: Float = 0
        vDSP_meanv(rmsSeries, 1, &rmsMean, vDSP_Length(nFrames))
        vDSP_maxv(rmsSeries, 1, &rmsMax, vDSP_Length(nFrames))

        // Dynamic range: 20*log10(rmsMax / rmsMean)
        let dynamicRangeDb = (rmsMean > 1e-8 && rmsMax > 1e-8)
        ? 20.0 * log10f(rmsMax / rmsMean)
        : 0.0

        return SpectralResult(
            centroidHz: meanCentroid,
            bandwidthHz: meanBandwidth,
            rolloffHz: meanRolloff,
            flatness: meanFlatness,
            zcr: meanZCR,
            rmsMean: rmsMean,
            rmsMax: rmsMax,
            dynamicRangeDb: dynamicRangeDb,
            centroidTimeSeries: centroidSeries,
            rmsSeries: rmsSeries
        )
    }

    // MARK: Spectral Centroid

    /// Flat array [f * nFrames + t]
    public func spectralCentroid(magnitude: [Float], nFrames: Int, frequencies: [Float]) -> [Float] {
        let nFreqs = frequencies.count
        return (0..<nFrames).map { t in
            var weightedSum: Float = 0
            var totalMag: Float = 0
            for f in 0..<nFreqs {
                let m = magnitude[f * nFrames + t]
                weightedSum += frequencies[f] * m
                totalMag += m
            }
            return totalMag > DSPHelpers.tinyFloat ? weightedSum / totalMag : 0
        }
    }

    /// Nested array [[Float]]
    public func spectralCentroid(magnitude: [[Float]], frequencies: [Float]) -> [Float] {
        let nFreqs = magnitude.count
        let nFrames = magnitude[0].count
        return (0..<nFrames).map { t in
            var weightedSum: Float = 0
            var totalMag: Float = 0
            for f in 0..<nFreqs {
                let m = magnitude[f][t]
                weightedSum += frequencies[f] * m
                totalMag += m
            }
            return totalMag > DSPHelpers.tinyFloat ? weightedSum / totalMag : 0
        }
    }

    // MARK: Spectral Bandwidth

    public func spectralBandwidth(magnitude: [Float], nFrames: Int, frequencies: [Float], centroids: [Float]) -> [Float] {
        let nFreqs = frequencies.count
        return (0..<nFrames).map { t in
            let c = centroids[t]
            var weightedSqDiff: Float = 0
            var totalMag: Float = 0
            for f in 0..<nFreqs {
                let m = magnitude[f * nFrames + t]
                let diff = frequencies[f] - c
                weightedSqDiff += diff * diff * m
                totalMag += m
            }
            return totalMag > DSPHelpers.tinyFloat ? sqrtf(weightedSqDiff / totalMag) : 0
        }
    }

    public func spectralBandwidth(magnitude: [[Float]], frequencies: [Float], centroids: [Float]) -> [Float] {
        let nFreqs = magnitude.count
        let nFrames = magnitude[0].count
        return (0..<nFrames).map { t in
            let c = centroids[t]
            var weightedSqDiff: Float = 0
            var totalMag: Float = 0
            for f in 0..<nFreqs {
                let m = magnitude[f][t]
                let diff = frequencies[f] - c
                weightedSqDiff += diff * diff * m
                totalMag += m
            }
            return totalMag > DSPHelpers.tinyFloat ? sqrtf(weightedSqDiff / totalMag) : 0
        }
    }

    // MARK: Spectral Rolloff

    public func spectralRolloff(magnitude: [Float], nFrames: Int, frequencies: [Float], rollPercent: Float = 0.85) -> [Float] {
        let nFreqs = frequencies.count
        return (0..<nFrames).map { t in
            var frameTotal: Float = 0
            for f in 0..<nFreqs { frameTotal += magnitude[f * nFrames + t] }
            let threshold = rollPercent * frameTotal
            var cumsum: Float = 0
            for f in 0..<nFreqs {
                cumsum += magnitude[f * nFrames + t]
                if cumsum >= threshold { return frequencies[f] }
            }
            return frequencies.last ?? 0
        }
    }

    public func spectralRolloff(magnitude: [[Float]], frequencies: [Float], rollPercent: Float = 0.85) -> [Float] {
        let nFreqs = magnitude.count
        let nFrames = magnitude[0].count
        return (0..<nFrames).map { t in
            var frameTotal: Float = 0
            for f in 0..<nFreqs { frameTotal += magnitude[f][t] }
            let threshold = rollPercent * frameTotal
            var cumsum: Float = 0
            for f in 0..<nFreqs {
                cumsum += magnitude[f][t]
                if cumsum >= threshold { return frequencies[f] }
            }
            return frequencies.last ?? 0
        }
    }

    // MARK: Spectral Flatness

    public func spectralFlatness(magnitude: [Float], nFrames: Int) -> [Float] {
        let nFreqs = magnitude.count / nFrames
        return (0..<nFrames).map { t in
            var logSum: Float = 0
            var linSum: Float = 0
            for f in 0..<nFreqs {
                let m = magnitude[f * nFrames + t]
                logSum += logf(max(m, DSPHelpers.tinyFloat))
                linSum += m
            }
            let geometricMean = expf(logSum / Float(nFreqs))
            let arithmeticMean = linSum / Float(nFreqs)
            return arithmeticMean > DSPHelpers.tinyFloat ? geometricMean / arithmeticMean : 0
        }
    }

    public func spectralFlatness(magnitude: [[Float]]) -> [Float] {
        let nFreqs = magnitude.count
        let nFrames = magnitude[0].count
        return (0..<nFrames).map { t in
            var logSum: Float = 0
            var linSum: Float = 0
            for f in 0..<nFreqs {
                let m = magnitude[f][t]
                logSum += logf(max(m, DSPHelpers.tinyFloat))
                linSum += m
            }
            let geometricMean = expf(logSum / Float(nFreqs))
            let arithmeticMean = linSum / Float(nFreqs)
            return arithmeticMean > DSPHelpers.tinyFloat ? geometricMean / arithmeticMean : 0
        }
    }

    // MARK: Zero-Crossing Rate

    public func zeroCrossingRate(samples: [Float], frameLength: Int = 2048, hopLength: Int = 512) -> [Float] {
        let n = samples.count
        let nFrames = max(1, 1 + (n - frameLength) / hopLength)
        var zcr = [Float](repeating: 0, count: nFrames)
        for t in 0..<nFrames {
            let start = t * hopLength
            let end = min(start + frameLength, n)
            var crossings = 0
            for i in (start + 1)..<end {
                if (samples[i] >= 0) != (samples[i - 1] >= 0) {
                    crossings += 1
                }
            }
            zcr[t] = Float(crossings) / Float(end - start)
        }
        return zcr
    }

    // MARK: RMS Energy

    public func rmsEnergy(magnitude: [Float], nFrames: Int) -> [Float] {
        let nFreqs = magnitude.count / nFrames
        return (0..<nFrames).map { t in
            var sumSq: Float = 0
            for f in 0..<nFreqs {
                let m = magnitude[f * nFrames + t]
                sumSq += m * m
            }
            return sqrtf(sumSq / Float(nFreqs))
        }
    }

    public func rmsEnergy(magnitude: [[Float]]) -> [Float] {
        let nFreqs = magnitude.count
        let nFrames = magnitude[0].count
        return (0..<nFrames).map { t in
            var sumSq: Float = 0
            for f in 0..<nFreqs {
                let m = magnitude[f][t]
                sumSq += m * m
            }
            return sqrtf(sumSq / Float(nFreqs))
        }
    }
}
