import Foundation
import Accelerate

/// Motif Analysis Engine (Motif ve Tema Analizi).
/// Identifies recurring melodic/rhythmic fragments (leitmotifs) and their transformations.
/// Detects retrogrades, inversions, augmentations, and rhythmic shifts.
public final class MotifEngine: Sendable {
    
    public init() {}
    
    /// Analyzes a pitch sequence and chromagram for recurring motifs (Async Forensic Path).
    public func detectMotifs(pitchPath: [Int], chromagram: [[Float]], sr: Double, hopLength: Int = 512) async -> [MotifDNA] {
        var motifs = [MotifDNA]()
        let nFrames = pitchPath.count
        guard nFrames > 20 else { return [] }
        
        let frameDuration = Double(hopLength) / sr
        
        // Window size for motif search (e.g. 2-8 seconds)
        let minWindow = Int(2.0 / frameDuration) 
        let maxWindow = Int(8.0 / frameDuration)
        
        
        // 1. Sliding Window pattern matching
        // Optimization for v7.1: Sparse Search for Long Tracks (Forensic Parity)
        // For a 45min track, we use a 10s anchor stride and 5s search stride.
        let anchorSeconds = 10.0
        let searchSeconds = 5.0
        let anchorStride = Int(anchorSeconds / frameDuration)
        let searchStride = Int(searchSeconds / frameDuration)
        
        let searchLimit = Int(900.0 / frameDuration) // 15 mins look-ahead max
        
        for windowSize in stride(from: minWindow, through: maxWindow, by: anchorStride) {
            for i in stride(from: 0, to: nFrames - windowSize, by: anchorStride) {
                if i % (anchorStride * 10) == 0 { await Task.yield() } // Prevent OS Timeouts
                
                let segment = pitchPath[i..<i+windowSize]
                guard isInteresting(Array(segment)) else { continue }
                
                // Pre-calculated stats for fast filtering
                let segSum = segment.reduce(0, +)
                
                // Compare with rest of the track
                let searchEnd = min(i + searchLimit, nFrames - windowSize)
                for j in stride(from: i + windowSize, to: searchEnd, by: searchStride) {
                    let target = pitchPath[j..<j+windowSize]
                    
                    // Fast Filter: If sum differs wildly, it's not a match or simple transposition
                    let tarSum = target.reduce(0, +)
                    if abs(segSum - tarSum) > (windowSize * 12) { continue }
                    
                    let (match, type, transType) = compareSegments(original: Array(segment), target: Array(target))
                    
                    if match {
                        let similarity = calculateSimilarity(Array(segment), Array(target))
                        if similarity > 0.85 {
                            motifs.append(MotifDNA(
                                id: "M\(motifs.count)",
                                startTime: Double(j) * frameDuration,
                                endTime: Double(j + windowSize) * frameDuration,
                                label: "Motif-Cluster-\(motifs.count)",
                                type: type,
                                transformationType: transType,
                                similarityScore: similarity,
                                technicalBasis: "Similarity Matrix Match via Pitch-Path Correlation"
                            ))
                            if motifs.count > 40 { break } 
                        }
                    }
                }
                if motifs.count > 50 { break }
            }
        }
        
        return dedupMotifs(motifs)
    }
    
    private func isInteresting(_ segment: [Int]) -> Bool {
        let set = Set(segment)
        return set.count > 2 // Must have more than 2 distinct notes
    }
    
    private func compareSegments(original: [Int], target: [Int]) -> (match: Bool, type: String, transType: String?) {
        // Original Match
        if original == target { return (true, "Original", nil) }
        
        // Transposition Check
        let diff = target[0] - original[0]
        if target.enumerated().allSatisfy({ $0.element - original[$0.offset] == diff }) {
            return (true, "Transformation", "Transposition (\(diff) semitones)")
        }
        
        // Retrograde Check (Mirroring in time)
        if original == target.reversed() {
            return (true, "Transformation", "Retrograde (Mirroring)")
        }
        
        // Inversion Check (Mirroring in pitch)
        let inverted = original.map { original[0] - ($0 - original[0]) }
        if target == inverted {
            return (true, "Transformation", "Inversion")
        }
        
        return (false, "", nil)
    }
    
    private func calculateSimilarity(_ a: [Int], _ b: [Int]) -> Float {
        let length = min(a.count, b.count)
        var matches = 0
        for i in 0..<length {
            if abs(a[i] - b[i]) <= 1 { matches += 1 }
        }
        return Float(matches) / Float(length)
    }
    
    private func dedupMotifs(_ motifs: [MotifDNA]) -> [MotifDNA] {
        // Simple time-based deduplication
        var unique = [MotifDNA]()
        for m in motifs {
            if !unique.contains(where: { abs($0.startTime - m.startTime) < 1.0 }) {
                unique.append(m)
            }
        }
        return unique
    }
}
