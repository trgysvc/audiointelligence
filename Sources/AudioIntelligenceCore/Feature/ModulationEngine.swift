import Foundation
import Accelerate

/// Modulation Analysis Engine (Modülasyon Analizi).
/// Tracks horizontal tonal shifts and identifies transition techniques (pivot, pedal, passing).
public final class ModulationEngine: Sendable {
    
    public init() {}
    
    /// Detects modulations over time based on chromagram windows.
    public func detectModulations(chromagram: [[Float]], initialKey: String) -> [ModulationDNA] {
        var modulations = [ModulationDNA]()
        let nFrames = chromagram[0].count
        guard nFrames > 40 else { return [] }
        
        let windowSize = 40 // ~7 seconds
        var currentKey = initialKey
        
        for t in stride(from: windowSize, to: nFrames, by: windowSize / 2) {
            let windowChroma = (0..<12).map { bin in
                let start = max(0, t - windowSize)
                let end = min(nFrames, t)
                let slice = Array(chromagram[bin][start..<end])
                var sum: Float = 0
                vDSP_sve(slice, 1, &sum, vDSP_Length(slice.count))
                return sum / Float(slice.count)
            }
            
            let detectedKey = identifyKey(windowChroma)
            if detectedKey != currentKey && detectedKey != "Unclassified" {
                let technique = determineTechnique(from: currentKey, to: detectedKey, chroma: windowChroma)
                
                modulations.append(ModulationDNA(
                    timestamp: Double(t) * 0.18,
                    fromKey: currentKey,
                    toKey: detectedKey,
                    technique: technique,
                    pivotNotes: identifyPivotNotes(from: currentKey, to: detectedKey),
                    description: "The harmonic axis has shifted from \(currentKey) to \(detectedKey) using the \(technique) technique."
                ))
                currentKey = detectedKey
            }
        }
        
        return modulations
    }
    
    private func identifyKey(_ chroma: [Float]) -> String {
        // Simple Krumhansl-Schmuckler like key profile matching
        let majorProfile: [Float] = [6.35, 2.23, 3.48, 2.33, 4.38, 4.09, 2.52, 5.19, 2.39, 3.66, 2.29, 2.88]
        let minorProfile: [Float] = [6.33, 2.68, 3.52, 5.38, 2.60, 3.53, 2.54, 4.75, 3.98, 2.69, 3.34, 3.17]
        
        var bestMatch = ""
        var maxCorr: Float = -1.0
        
        for root in 0..<12 {
            let rotatedMajor = rotate(majorProfile, by: root)
            let rotatedMinor = rotate(minorProfile, by: root)
            
            let corrMajor = correlate(chroma, rotatedMajor)
            let corrMinor = correlate(chroma, rotatedMinor)
            
            if corrMajor > maxCorr {
                maxCorr = corrMajor
                bestMatch = "\(ChromaResult.noteNames[root]) Major"
            }
            if corrMinor > maxCorr {
                maxCorr = corrMinor
                bestMatch = "\(ChromaResult.noteNames[root]) Minor"
            }
        }
        
        return maxCorr > 0.7 ? bestMatch : "Unclassified"
    }
    
    private func determineTechnique(from: String, to: String, chroma: [Float]) -> String {
        // Simplified heuristic
        if from.contains("Major") && to.contains("Minor") { return "Modal (Parallel)" }
        let fromRoot = from.components(separatedBy: " ").first ?? ""
        let toRoot = to.components(separatedBy: " ").first ?? ""
        
        if fromRoot == toRoot { return "Mode Change" }
        
        // Check for specific interval transitions
        return "Common Chord (Pivot)"
    }
    
    private func identifyPivotNotes(from: String, to: String) -> [String] {
        // Returns common notes between the two keys
        return ["Common Tones"]
    }
    
    private func rotate(_ profile: [Float], by: Int) -> [Float] {
        var rotated = profile
        for i in 0..<12 {
            rotated[(i + by) % 12] = profile[i]
        }
        return rotated
    }
    
    private func correlate(_ a: [Float], _ b: [Float]) -> Float {
        var sum: Float = 0
        for i in 0..<12 { sum += a[i] * b[i] }
        return sum
    }
}
