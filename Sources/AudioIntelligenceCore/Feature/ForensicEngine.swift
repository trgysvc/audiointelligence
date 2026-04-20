import Foundation
import Accelerate

/// High-Trust Forensic Integrity Engine.
/// Detects upsampling, codec artifacts, and bit-depth forgery via Shannon Entropy analysis.
public final class ForensicEngine: @unchecked Sendable {
    
    public struct ForensicResult: Codable, Sendable {
        public let trueBitDepth: Int
        public let codecCutoffHz: Float
        public let clippingEvents: Int
        public let entropyScore: Float       // 0.0 - 1.0 (Higher = more unique data)
        public let isUpsampled: Bool
    }
    
    public init() {}
    
    public func analyze(samples: [Float], magnitude: [Float], nFrames: Int, nFFT: Int, sampleRate: Double) -> ForensicResult {
        let bitDepth = detectTrueBitDepth(samples: samples)
        let cutoff = detectCodecCutoff(magnitude: magnitude, nFrames: nFrames, nFFT: nFFT, sampleRate: sampleRate)
        let clipping = countClippingEvents(samples: samples)
        
        let entropy = calculateEntropy(samples: samples)
        
        // Logical check: If bit depth is reported as 24 but entropy is low, it's likely upsampled
        let upsampled = (bitDepth > 16 && entropy < 0.7)
        
        return ForensicResult(
            trueBitDepth: bitDepth,
            codecCutoffHz: cutoff,
            clippingEvents: clipping,
            entropyScore: entropy,
            isUpsampled: upsampled
        )
    }
    
    private func detectTrueBitDepth(samples: [Float]) -> Int {
        // Statistical approach: Measure the minimum step size between unique values
        let uniqueSamples = Array(Set(samples.prefix(10000))).sorted()
        if uniqueSamples.count < 2 { return 0 }
        
        var minDiff: Float = 1.0
        for i in 1..<uniqueSamples.count {
            let diff = uniqueSamples[i] - uniqueSamples[i-1]
            if diff > 0 && diff < minDiff {
                minDiff = diff
            }
        }
        
        // 16-bit step is 1/32768 (~3e-5)
        // 24-bit step is 1/8388608 (~1e-7)
        if minDiff < 2e-7 { return 24 }
        if minDiff < 5e-5 { return 16 }
        return 8
    }
    
    private func detectCodecCutoff(magnitude: [Float], nFrames: Int, nFFT: Int, sampleRate: Double) -> Float {
        let nBins = nFFT / 2 + 1
        let binFreq = Float(sampleRate) / Float(nFFT)
        
        // 1. Calculate average spectrum across all frames (Mean Pooling)
        var meanMag = [Float](repeating: 0, count: nBins)
        for f in 0..<nBins {
            var sum: Float = 0
            for t in 0..<nFrames {
                sum += magnitude[t * nBins + f]
            }
            meanMag[f] = sum / Float(nFrames)
        }
        
        // 2. Search for the "Cliff": Point where HF energy drops > 10dB relative to lower band
        // Typical MP3 cutoffs: 16kHz, 18kHz, 20kHz
        let searchStartBin = Int(Float(nBins) * 0.4) // Start above 4k for speed
        var cutoffBin = nBins - 1
        
        for f in stride(from: nBins - 2, through: searchStartBin, by: -1) {
            let high = meanMag[f+1] + 1e-12
            let low  = meanMag[f]   + 1e-12
            
            // If energy drops by 10x (10dB) between adjacent bins, we found a codec edge
            if low / high > 10.0 {
                cutoffBin = f
                break
            }
            
            // Also detection via floor: If avg magnitude is below -80dB relative to peak
            let maxMag = meanMag.max() ?? 1.0
            if meanMag[f] < maxMag * 0.0001 {
                cutoffBin = f
            }
        }
        
        return Float(cutoffBin) * binFreq
    }
    
    private func countClippingEvents(samples: [Float]) -> Int {
        var count = 0
        let threshold: Float = 0.9999
        
        var i = 0
        while i < samples.count - 1 {
            if abs(samples[i]) >= threshold && abs(samples[i+1]) >= threshold {
                count += 1
                // Skip consecutive clipped samples to count as one "event"
                while i < samples.count && abs(samples[i]) >= threshold {
                    i += 1
                }
            } else {
                i += 1
            }
        }
        return count
    }
    
    private func calculateEntropy(samples: [Float]) -> Float {
        // Simplified Shannon Entropy on sample values
        let bucketCount = 256
        var buckets = [Int](repeating: 0, count: bucketCount)
        
        for s in samples {
            let normalized = (s + 1.0) / 2.0 // 0.0 to 1.0
            let bucketIdx = min(bucketCount - 1, max(0, Int(normalized * Float(bucketCount))))
            buckets[bucketIdx] += 1
        }
        
        var h: Double = 0
        let total = Double(samples.count)
        for count in buckets {
            if count > 0 {
                let p = Double(count) / total
                h -= p * log2(p)
            }
        }
        
        // Max entropy for 256 buckets is log2(256) = 8
        return Float(h / 8.0)
    }
}
