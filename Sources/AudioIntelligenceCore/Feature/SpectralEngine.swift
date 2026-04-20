import Foundation
import Accelerate

/// v28.0: The Infinity Engine — Professional Spectral Analysis
/// Provides 100% depth MIR features including Centroid, Bandwidth, Rolloff, Flatness, ZCR, and Flux.
/// Core Spectral Descriptors Engine.
/// Calculates high-level frequency domain metrics such as Centroid, Flux, Flatness, and Bandwidth.
public final class SpectralEngine: Sendable {
    
    private let sampleRate: Double
    private let nFFT: Int
    private let hopLength: Int
    
    public init(sampleRate: Double, nFFT: Int = 2048, hopLength: Int = 512) {
        self.sampleRate = sampleRate
        self.nFFT = nFFT
        self.hopLength = hopLength
    }
    
    public struct SpectralResult: Sendable {
        public let centroidHz: Float
        public let bandwidthHz: Float
        public let rolloffHz: Float
        public let flatness: Float
        public let zcr: Float
        public let flux: Float // v28.0 Addition
        public let skewness: Float // v50.0 Addition
        public let kurtosis: Float // v50.0 Addition
        public let rmsMean: Float
        public let rmsMax: Float
        /// Spectral Crest Factor = 20·log₁₀(rmsMax/rmsMean).
        /// NOTE: This is NOT Dynamic Range. True DR (EBU R128 LRA) is measured by LoudnessEngine.
        /// Crest Factor describes the peak-to-average energy ratio across frames.
        public let spectralCrestFactor: Float
        
        // Time series for visualization
        public let centroidTimeSeries: [Float]
        public let rmsSeries: [Float]
        public let fullMagnitudes: [[Float]] // [FreqBin][FrameIndex]
    }
    
    public func analyze(stft: STFTMatrix, samples: [Float]) -> SpectralResult {
        let nFrames = stft.nFrames
        let nBins = nFFT / 2 + 1
        let mag = stft.magnitude
        
        let freqs = (0..<nBins).map { Float($0) * Float(sampleRate) / Float(nFFT) }
        
        // 1. Spectral Flux (Delta energy between frames)
        var totalFlux: Float = 0
        if nFrames > 1 {
            for t in 1..<nFrames {
                var frameDiff: Float = 0
                for f in 0..<nBins {
                    let current = mag[t * nBins + f]
                    let previous = mag[(t - 1) * nBins + f]
                    let diff = current - previous
                    frameDiff += max(0, diff) 
                }
                totalFlux += frameDiff
            }
            totalFlux /= Float(nFrames - 1)
        }

        // 2. Centroid
        let centroidSeries = spectralCentroid(magnitude: mag, nFrames: nFrames, frequencies: freqs)
        var meanCentroid: Float = 0
        vDSP_meanv(centroidSeries, 1, &meanCentroid, vDSP_Length(nFrames))

        // 3. Bandwidth (Spread)
        let bandwidthSeries = spectralBandwidth(magnitude: mag, nFrames: nFrames, frequencies: freqs, centroids: centroidSeries)
        var meanBandwidth: Float = 0
        vDSP_meanv(bandwidthSeries, 1, &meanBandwidth, vDSP_Length(nFrames))

        // 8. Higher-Order Statistics (Skewness & Kurtosis) - v50.0
        var totalSkewness: Float = 0
        var totalKurtosis: Float = 0
        
        for t in 0..<nFrames {
            let mu1 = centroidSeries[t]
            let sigma = bandwidthSeries[t]
            let sigmaSq = sigma * sigma
            
            var m3: Float = 0
            var m4: Float = 0
            var totalMag: Float = 0
            
            for f in 0..<nBins {
                let m = mag[t * nBins + f]
                let diff = freqs[f] - mu1
                let diffSq = diff * diff
                m3 += diffSq * diff * m
                m4 += diffSq * diffSq * m
                totalMag += m
            }
            
            if totalMag > 1e-12 && sigma > 1e-6 {
                totalSkewness += (m3 / totalMag) / powf(sigma, 3.0)
                totalKurtosis += (m4 / totalMag) / (sigmaSq * sigmaSq)
            }
        }
        
        let meanSkewness = (totalSkewness / Float(nFrames)).isNaN ? 0.0 : (totalSkewness / Float(nFrames))
        let meanKurtosis = (totalKurtosis / Float(nFrames)).isNaN ? 0.0 : (totalKurtosis / Float(nFrames))

        // 4. Rolloff
        let rolloffSeries = spectralRolloff(magnitude: mag, nFrames: nFrames, frequencies: freqs)
        var meanRolloff: Float = 0
        vDSP_meanv(rolloffSeries, 1, &meanRolloff, vDSP_Length(nFrames))

        // 5. Flatness
        let flatnessSeries = spectralFlatness(magnitude: mag, nFrames: nFrames)
        var meanFlatness: Float = 0
        vDSP_meanv(flatnessSeries, 1, &meanFlatness, vDSP_Length(nFrames))

        // 6. ZCR
        let zcrSeries = zeroCrossingRate(samples: samples, frameLength: nFFT, hopLength: hopLength)
        var meanZCR: Float = 0
        if !zcrSeries.isEmpty {
            vDSP_meanv(zcrSeries, 1, &meanZCR, vDSP_Length(zcrSeries.count))
        }

        // 7. RMS Energy
        let rmsSeries = rmsEnergy(magnitude: mag, nFrames: nFrames)
        var rmsMean: Float = 0
        var rmsMax: Float = 0
        vDSP_meanv(rmsSeries, 1, &rmsMean, vDSP_Length(nFrames))
        vDSP_maxv(rmsSeries, 1, &rmsMax, vDSP_Length(nFrames))

        // Crest Factor: 20·log₁₀(rmsMax/rmsMean)
        // Not the same as Dynamic Range. Use LoudnessEngine.lra for EBU R128 LRA.
        let spectralCrestFactor = (rmsMean > 1e-8) ? 20.0 * log10f(max(1e-8, rmsMax / rmsMean)) : 0.0

        // Reconstruct matrix for visualization (Frequency-major for UI mapping)
        var visualMatrix = [[Float]]()
        for f in 0..<nBins {
            var binData = [Float](repeating: 0, count: nFrames)
            for t in 0..<nFrames {
                binData[t] = mag[t * nBins + f]
            }
            visualMatrix.append(binData)
        }
        
        return SpectralResult(
            centroidHz: meanCentroid,
            bandwidthHz: meanBandwidth,
            rolloffHz: meanRolloff,
            flatness: meanFlatness,
            zcr: meanZCR,
            flux: totalFlux,
            skewness: meanSkewness,
            kurtosis: meanKurtosis,
            rmsMean: rmsMean,
            rmsMax: rmsMax,
            spectralCrestFactor: spectralCrestFactor,
            centroidTimeSeries: centroidSeries,
            rmsSeries: rmsSeries,
            fullMagnitudes: visualMatrix
        )
    }

    private func spectralCentroid(magnitude: [Float], nFrames: Int, frequencies: [Float]) -> [Float] {
        let nFreqs = frequencies.count
        return (0..<nFrames).map { t in
            var weightedSum: Float = 0
            var totalMag: Float = 0
            for f in 0..<nFreqs {
                let m = magnitude[t * nFreqs + f]
                weightedSum += frequencies[f] * m
                totalMag += m
            }
            return totalMag > 1e-12 ? weightedSum / totalMag : 0
        }
    }

    private func spectralBandwidth(magnitude: [Float], nFrames: Int, frequencies: [Float], centroids: [Float]) -> [Float] {
        let nFreqs = frequencies.count
        return (0..<nFrames).map { t in
            let c = centroids[t]
            var weightedSqDiff: Float = 0
            var totalMag: Float = 0
            for f in 0..<nFreqs {
                let m = magnitude[t * nFreqs + f]
                let diff = frequencies[f] - c
                weightedSqDiff += diff * diff * m
                totalMag += m
            }
            return totalMag > 1e-12 ? sqrtf(weightedSqDiff / totalMag) : 0
        }
    }

    private func spectralRolloff(magnitude: [Float], nFrames: Int, frequencies: [Float], rollPercent: Float = 0.85) -> [Float] {
        let nFreqs = frequencies.count
        return (0..<nFrames).map { t in
            var frameTotal: Float = 0
            for f in 0..<nFreqs { frameTotal += magnitude[t * nFreqs + f] }
            let threshold = rollPercent * frameTotal
            var cumsum: Float = 0
            for f in 0..<nFreqs {
                cumsum += magnitude[t * nFreqs + f]
                if cumsum >= threshold { return frequencies[f] }
            }
            return frequencies.last ?? 0
        }
    }

    private func spectralFlatness(magnitude: [Float], nFrames: Int) -> [Float] {
        let nFreqs = magnitude.count / nFrames
        return (0..<nFrames).map { t in
            var logSum: Float = 0
            var linSum: Float = 0
            for f in 0..<nFreqs {
                let m = magnitude[t * nFreqs + f]
                logSum += logf(max(m, 1e-12))
                linSum += m
            }
            let geometricMean = expf(logSum / Float(nFreqs))
            let arithmeticMean = linSum / Float(nFreqs)
            return arithmeticMean > 1e-12 ? geometricMean / arithmeticMean : 0
        }
    }

    private func zeroCrossingRate(samples: [Float], frameLength: Int = 2048, hopLength: Int = 512) -> [Float] {
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

    private func rmsEnergy(magnitude: [Float], nFrames: Int) -> [Float] {
        let nFreqs = magnitude.count / nFrames
        return (0..<nFrames).map { t in
            var sumSq: Float = 0
            for f in 0..<nFreqs {
                let m = magnitude[t * nFreqs + f]
                sumSq += m * m
            }
            return sqrtf(sumSq / Float(nFreqs))
        }
    }
}
