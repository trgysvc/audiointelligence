import Accelerate
import Foundation

/// Tonal Reduction Engine (İndirgeme Analizi).
/// Identifies the skeletal harmonic structure (Urlinie/Ursatz) of a musical work.
public final class ReductionEngine: @unchecked Sendable {
    
    public init() {}
    
    /// Performs tonal reduction based on structural segments and chromagram data.
    public func reduce(chromagram: [[Float]], segments: [MusicSegment]) -> ReductionMetrics {
        guard !chromagram.isEmpty, !segments.isEmpty else {
            return ReductionMetrics(fundamentalNote: "Unknown", structuralPillars: [], stabilityScore: 0, theoryBasis: "Insufficient data")
        }
        
        let nFrames = chromagram[0].count
        var pillars = [String]()
        var pillarBins = [Int]()
        
        // 1. Analyze each segment for its "Structural Tonic"
        for segment in segments {
            _ = Int(segment.start * (Double(nFrames) / segment.end)) // Rough mapping if end is total
            // Better frame mapping:
            let totalDuration = segments.last?.end ?? 1.0
            let sFrame = Int((segment.start / totalDuration) * Double(nFrames))
            let eFrame = Int((segment.end / totalDuration) * Double(nFrames))
            
            let segmentTonic = findSegmentTonic(chromagram: chromagram, start: sFrame, end: eFrame)
            pillars.append(ChromaResult.noteNames[segmentTonic])
            pillarBins.append(segmentTonic)
        }
        
        // 2. Identify the Global Fundamental (Ur-Note)
        // Rule: The most recurrent structural tonic that appears at start/end or high-energy sections.
        let fundamentalBin = findFundamental(pillarBins: pillarBins)
        let fundamentalNote = ChromaResult.noteNames[fundamentalBin]
        
        // 3. Logic Explanation
        let basis = "The fundamental tonal center was identified as \(fundamentalNote) through structural reduction. The analysis identified \(pillars.count) skeletal anchors, with \(fundamentalNote) serving as the primary harmonic axis across thematic segments."
        
        return ReductionMetrics(
            fundamentalNote: fundamentalNote,
            structuralPillars: pillars,
            stabilityScore: calculateStability(pillarBins: pillarBins, fundamental: fundamentalBin),
            theoryBasis: basis
        )
    }
    
    private func findSegmentTonic(chromagram: [[Float]], start: Int, end: Int) -> Int {
        let safeStart = max(0, start)
        let safeEnd = min(chromagram[0].count, end)
        guard safeEnd > safeStart else { return 0 }
        
        var meanChroma = [Float](repeating: 0, count: 12)
        let count = Float(safeEnd - safeStart)
        
        for c in 0..<12 {
            var sum: Float = 0
            vDSP_sve(Array(chromagram[c][safeStart..<safeEnd]), 1, &sum, vDSP_Length(safeEnd - safeStart))
            meanChroma[c] = sum / count
        }
        
        return meanChroma.enumerated().max(by: { $0.element < $1.element })?.offset ?? 0
    }
    
    private func findFundamental(pillarBins: [Int]) -> Int {
        var counts = [Int: Int]()
        for bin in pillarBins {
            counts[bin, default: 0] += 1
        }
        
        // Favor start and end pillars (Schenkerian focus on boundaries)
        if let first = pillarBins.first { counts[first, default: 0] += 1 }
        if let last = pillarBins.last { counts[last, default: 0] += 1 }
        
        return counts.max(by: { $0.value < $1.value })?.key ?? pillarBins.first ?? 0
    }
    
    private func calculateStability(pillarBins: [Int], fundamental: Int) -> Float {
        guard !pillarBins.isEmpty else { return 0 }
        let matches = pillarBins.filter { $0 == fundamental }.count
        return Float(matches) / Float(pillarBins.count)
    }
}
