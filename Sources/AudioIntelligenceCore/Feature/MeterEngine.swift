import Foundation
import Accelerate

/// Meter Analysis Engine (Ölçü ve Ritim Birimi Analizi).
/// Identifies time signatures (4/4, 9/8, Aksak, etc.) and detects anacrusis / polyrhythms.
public final class MeterEngine: Sendable {
    
    public init() {}
    
    /// Analyzes beat times and onsets to determine the meter (Async Forensic Path).
    public func detectMeter(beatTimes: [Double], onsetStrength: [Float], sr: Double) async -> MeterDNA {
        guard beatTimes.count > 4 else {
            return MeterDNA(timeSignature: "Unknown", meterType: "Simple", isAnacrusis: false, polyrhythmRatio: nil, measures: 0)
        }
        
        await Task.yield()
        
        // 1. Calculate inter-beat intervals (IBI)
        var ibis = [Double]()
        for i in 1..<beatTimes.count {
            ibis.append(beatTimes[i] - beatTimes[i-1])
        }
        
        let avgIBI = ibis.reduce(0, +) / Double(ibis.count)
        
        // 2. Pulse grouping analysis (looking for accents every N beats)
        let groupings = [2, 3, 4, 5, 7, 9]
        var scores = [Int: Float]()
        
        for g in groupings {
            var score: Float = 0
            for i in stride(from: 0, to: beatTimes.count, by: g) {
                let frame = Int(beatTimes[i] * sr / 512.0) // 512 is hopLength
                if frame < onsetStrength.count {
                    score += onsetStrength[frame]
                }
            }
            scores[g] = score / Float(Swift.max(1, beatTimes.count / g))
        }
        
        let maxScore = scores.values.max() ?? 0
        let bestG = maxScore > 0.1 ? (scores.max(by: { $0.value < $1.value })?.key ?? 4) : 0
        
        // 3. Classify Meter Type
        let ts: String
        let type: String
        
        if bestG == 0 {
            ts = "Complex / Poly-meter"
            type = "Irregular"
        } else {
            switch bestG {
            case 2:
                ts = "2/4"
                type = "Simple"
            case 3:
                ts = "3/4"
                type = "Simple"
            case 4:
                ts = "4/4"
                type = "Simple"
            case 9:
                ts = "9/8 (Aksak)"
                type = "Aksak"
            case 7:
                ts = "7/8 (Devr-i Turan)"
                type = "Aksak"
            case 5:
                ts = "5/8"
                type = "Aksak"
            default:
                ts = "\(bestG)/4"
                type = "Complex"
            }
        }
        
        // 4. Anacrusis Detection (Eksik Vuruş)
        let firstSignificantOnset = onsetStrength.enumerated().first(where: { $0.element > 0.5 })?.offset ?? 0
        let firstOnsetTime = Double(firstSignificantOnset) * 512.0 / sr
        let isAnacrusis = (beatTimes[0] - firstOnsetTime) > (avgIBI * 0.3)
        
        // Final Safety: Prevent Division by Zero on complex meters
        let finalG = Swift.max(1, bestG)
        
        let primaryPeriodFrames = avgIBI * sr / 512.0
        return MeterDNA(
            timeSignature: ts,
            meterType: type,
            isAnacrusis: isAnacrusis,
            polyrhythmRatio: detectPolyrhythm(onsetStrength, primaryPeriodFrames: primaryPeriodFrames),
            measures: beatTimes.count / finalG
        )
    }

    /// Looks for a secondary pulse forming a simple integer ratio (3:2, 4:3, 5:4 and their
    /// inversions — the common polyrhythm ratios) against the already-detected primary beat
    /// period, via autocorrelation of the onset envelope. Was a hardcoded `nil` (honestly
    /// marked "Placeholder for v7.2" in-code, but the public `MeterDNA.polyrhythmRatio` field
    /// didn't reflect that it was never actually computed).
    // `internal` (not `private`) for direct unit testing.
    func detectPolyrhythm(_ onsets: [Float], primaryPeriodFrames: Double) -> String? {
        guard onsets.count > 100, primaryPeriodFrames > 1 else { return nil }
        let maxLag = min(onsets.count - 1, Int(primaryPeriodFrames * 3))
        guard maxLag > 4 else { return nil }
        let rawAcorr = DSPHelpers.autocorrelate(onsets, maxSize: maxLag + 1)
        guard let zeroLag = rawAcorr.first, zeroLag > 1e-9 else { return nil }
        // `DSPHelpers.autocorrelate` returns raw Σ signal[j]·signal[j+k] energy, not a
        // normalized correlation coefficient — comparing that directly against a fixed
        // threshold like 0.3 is meaningless (it scales with signal energy/length). Normalize
        // by the zero-lag value (total energy) so every score is a proper [0,1] ratio.
        let acorr = rawAcorr.map { $0 / zeroLag }

        // Candidate secondary-pulse ratios relative to the primary period. Trivial
        // multiples/divisors (1:1, 2:1, 1:2...) are deliberately excluded — those are just the
        // same pulse at a different subdivision, not a genuine cross-rhythm.
        let candidateRatios: [(num: Int, den: Int)] = [(3, 2), (2, 3), (4, 3), (3, 4), (5, 4), (4, 5)]

        var bestRatio: (num: Int, den: Int)?
        var bestScore: Float = 0
        for ratio in candidateRatios {
            let candidateLag = Int((primaryPeriodFrames * Double(ratio.den) / Double(ratio.num)).rounded())
            guard candidateLag > 1, candidateLag < acorr.count - 1 else { continue }
            // Local peak in a small window around the theoretical lag, to tolerate tempo drift.
            let windowStart = max(1, candidateLag - 2)
            let windowEnd = min(acorr.count - 1, candidateLag + 2)
            let peakVal = (windowStart...windowEnd).map { acorr[$0] }.max() ?? 0
            if peakVal > bestScore {
                bestScore = peakVal
                bestRatio = ratio
            }
        }

        // Require a reasonably strong correlation — a weak/noisy secondary peak isn't good
        // evidence of a genuine cross-rhythm.
        guard let ratio = bestRatio, bestScore > 0.3 else { return nil }
        return "\(ratio.num):\(ratio.den)"
    }
}
