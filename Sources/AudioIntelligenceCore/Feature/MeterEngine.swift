import Foundation
import Accelerate

/// Meter Analysis Engine (Ölçü ve Ritim Birimi Analizi).
/// Identifies time signatures (4/4, 9/8, Aksak, etc.) and detects anacrusis / polyrhythms.
public final class MeterEngine: Sendable {
    
    public init() {}
    
    /// Analyzes beat times and onsets to determine the meter.
    public func detectMeter(beatTimes: [Double], onsetStrength: [Float], sr: Double) -> MeterDNA {
        guard beatTimes.count > 4 else {
            return MeterDNA(timeSignature: "Unknown", meterType: "Simple", isAnacrusis: false, polyrhythmRatio: nil, measures: 0)
        }
        
        // 1. Calculate inter-beat intervals (IBI)
        var ibis = [Double]()
        for i in 1..<beatTimes.count {
            ibis.append(beatTimes[i] - beatTimes[i-1])
        }
        
        let avgIBI = ibis.reduce(0, +) / Double(ibis.count)
        
        // 2. Pulse grouping analysis (looking for accents every N beats)
        // We look for higher onset energy at beat positions
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
            scores[g] = score / Float(beatTimes.count / g)
        }
        
        let bestG = scores.max(by: { $0.value < $1.value })?.key ?? 4
        
        // 3. Classify Meter Type
        let ts: String
        let type: String
        
        switch bestG {
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
        
        // 4. Anacrusis Detection (Eksik Vuruş)
        // If the first beat starts "late" relative to the first significant onset
        let firstSignificantOnset = onsetStrength.enumerated().first(where: { $0.element > 0.5 })?.offset ?? 0
        let firstOnsetTime = Double(firstSignificantOnset) * 512.0 / sr
        let isAnacrusis = (beatTimes[0] - firstOnsetTime) > (avgIBI * 0.3)
        
        return MeterDNA(
            timeSignature: ts,
            meterType: type,
            isAnacrusis: isAnacrusis,
            polyrhythmRatio: detectPolyrhythm(onsetStrength),
            measures: beatTimes.count / bestG
        )
    }
    
    private func detectPolyrhythm(_ onsets: [Float]) -> String? {
        // Simplified check: look for secondary pulse in autocorrelation
        return nil // Placeholder for v7.2
    }
}
