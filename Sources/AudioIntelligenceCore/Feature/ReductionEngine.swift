import Foundation

/// Tonal Reduction Engine (İndirgeme Analizi).
/// Identifies the skeletal harmonic structure (Urlinie/Ursatz) of a musical work.
public final class ReductionEngine: @unchecked Sendable {
    
    public init() {}
    
    /// Performs tonal reduction based on structural segments and chromagram data.
    public func reduce(chromagram: [[Float]], segments: [MusicSegment]) async -> ReductionMetrics {
        guard !chromagram.isEmpty, !segments.isEmpty else {
            return ReductionMetrics(fundamentalNote: "Unknown", structuralPillars: [], stabilityScore: 0, theoryBasis: "Insufficient data")
        }
        
        let nFrames = chromagram[0].count
        var pillars = [String]()
        var pillarBins = [Int]()
        // 1. Analyze each segment for its "Structural Tonic"
        let totalDuration = Double(nFrames) * (512.0 / 44100.0) // Precise Forensic Duration
        
        Swift.print("🔍 [TRACE] Reduction Audit Started: \(segments.count) segments | \(totalDuration)s real track duration.")
        
        for (idx, segment) in segments.enumerated() {
            Swift.print("   [TRACE] Reduction: Processing Segment \(idx+1)/\(segments.count) (@\(segment.start)s)")
            if idx % 50 == 0 { 
                await Task.yield() 
            }
            
            // Forensic Safety: Bulletproof Frame Mapping
            let safeStartSec = Swift.max(0, Swift.min(totalDuration, segment.start))
            let safeEndSec = Swift.max(safeStartSec, Swift.min(totalDuration, segment.end))
            
            let sRatio = safeStartSec / totalDuration
            let eRatio = safeEndSec / totalDuration
            
            let sFrame = Int(Swift.max(0, Swift.min(Double(nFrames - 1), (sRatio * Double(nFrames)).rounded())))
            let eFrame = Int(Swift.max(Double(sFrame), Swift.min(Double(nFrames), (eRatio * Double(nFrames)).rounded())))
            
            let segmentTonic = findSegmentTonic(chromagram: chromagram, start: sFrame, end: eFrame)
            pillars.append(ChromaResult.noteNames[segmentTonic])
            pillarBins.append(segmentTonic)
        }
        
        // 2. Identify the Global Fundamental (Ur-Note)
        Swift.print("   [TRACE] Reduction: Finding Fundamental across \(pillarBins.count) pillars...")
        let fundamentalBin = findFundamental(pillarBins: pillarBins)
        let fundamentalNote = ChromaResult.noteNames[fundamentalBin]
        Swift.print("   [TRACE] Reduction: Fundamental found: \(fundamentalNote)")
        
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
        var meanChroma = [Float](repeating: 0, count: 12)
        
        for c in 0..<12 {
            let binData = chromagram[c]
            let binCount = binData.count
            
            let safeStart = Swift.max(0, Swift.min(binCount, start))
            let safeEnd = Swift.max(safeStart, Swift.min(binCount, end))
            
            guard safeEnd > safeStart else { continue }
            
            // Forensic Fix: Use Native Swift Loops instead of vDSP to prevent SIGTRAP 133 on large tracks
            var sum: Float = 0
            let sliceStart = safeStart
            let sliceEnd = safeEnd
            
            for i in sliceStart..<sliceEnd {
                sum += binData[i]
            }
            meanChroma[c] = sum / Float(sliceEnd - sliceStart)
        }
        
        let maxChroma = meanChroma.max() ?? 0
        return maxChroma > 0.1 ? (meanChroma.enumerated().max(by: { $0.element < $1.element })?.offset ?? 0) : 0
    }
    
    private func findFundamental(pillarBins: [Int]) -> Int {
        var counts = [Int: Int]()
        for bin in pillarBins {
            counts[bin, default: 0] += 1
        }
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
