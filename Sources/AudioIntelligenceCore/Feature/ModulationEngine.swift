import Foundation
import Accelerate

/// Modulation Analysis Engine (Modülasyon Analizi).
/// Tracks horizontal tonal shifts and identifies transition techniques (pivot, pedal, passing).
public final class ModulationEngine: Sendable {
    
    public init() {}
    
    /// Detects modulations over time based on chromagram windows (Async Forensic Path).
    /// `secondsPerFrame` = hopLength / sampleRate of the chromagram that produced these
    /// frames; it is the single source of truth for frame→time conversion.
    public func detectModulations(chromagram: [[Float]], initialKey: String, secondsPerFrame: Double) async -> [ModulationDNA] {
        var modulations = [ModulationDNA]()
        let nFrames = chromagram[0].count
        // ~4 second analysis window, derived from the real frame rate (not a magic constant).
        let windowSize = Swift.max(8, Int((4.0 / Swift.max(secondsPerFrame, 1e-6)).rounded()))
        guard nFrames > windowSize else { return [] }

        var currentKey = initialKey

        for t in stride(from: windowSize, to: nFrames, by: windowSize / 2) {
            if t % 1000 == 0 { await Task.yield() }
            
            let windowChroma = (0..<12).map { bin in
                let binCount = chromagram[bin].count
                let start = Swift.max(0, Swift.min(binCount, t - windowSize))
                let end = Swift.max(start, Swift.min(binCount, t))
                
                let slice = Array(chromagram[bin][start..<end])
                var sum: Float = 0
                if !slice.isEmpty {
                    vDSP_sve(slice, 1, &sum, vDSP_Length(slice.count))
                    return sum / Float(slice.count)
                }
                return 0
            }
            
            let detectedKey = identifyKey(windowChroma)
            if detectedKey != currentKey && detectedKey != "Unclassified" {
                let technique = determineTechnique(from: currentKey, to: detectedKey, chroma: windowChroma)
                
                modulations.append(ModulationDNA(
                    timestamp: Double(t) * secondsPerFrame,
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
    
    /// Public key estimate for a single averaged chroma vector (root + mode).
    public func detectKey(_ chroma: [Float]) -> String {
        identifyKey(chroma)
    }

    // Krumhansl-Kessler key profiles, matched with Pearson correlation (the textbook
    // Krumhansl-Schmuckler key finder).
    private static let asMajor: [Float] = [6.35, 2.23, 3.48, 2.33, 4.38, 4.09, 2.52, 5.19, 2.39, 3.66, 2.29, 2.88]
    private static let asMinor: [Float] = [6.33, 2.68, 3.52, 5.38, 2.60, 3.53, 2.54, 4.75, 3.98, 2.69, 3.34, 3.17]

    private func identifyKey(_ chroma: [Float]) -> String {
        // Cosine correlation against rotated Krumhansl-Kessler profiles. (Empirically this
        // beat mean-centered Pearson and the Albrecht-Shanahan profiles on the GiantSteps
        // golden set — the remaining errors are chroma-quality limited, not profile/metric.)
        var bestMatch = ""
        var maxCorr: Float = -2.0
        for root in 0..<12 {
            let major = correlate(chroma, rotate(ModulationEngine.asMajor, by: root))
            if major > maxCorr { maxCorr = major; bestMatch = "\(ChromaResult.noteNames[root]) Major" }
            let minor = correlate(chroma, rotate(ModulationEngine.asMinor, by: root))
            if minor > maxCorr { maxCorr = minor; bestMatch = "\(ChromaResult.noteNames[root]) Minor" }
        }
        // Classify whenever there is any tonal correlation; "Unclassified" only for
        // essentially atonal/empty chroma. (A high threshold previously discarded valid keys.)
        return maxCorr > 0.05 ? bestMatch : "Unclassified"
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
    
    /// Returns the diatonic pitch classes shared between the two keys — the actual common
    /// tones a pivot-chord modulation exploits (was a hardcoded `["Common Tones"]` placeholder
    /// string for every single modulation event, parameters unused).
    // `internal` (not `private`) so it's directly unit-testable without needing to construct
    // a chromagram that coincidentally triggers a detected modulation.
    func identifyPivotNotes(from: String, to: String) -> [String] {
        guard let fromPCs = Self.diatonicPitchClasses(for: from),
              let toPCs = Self.diatonicPitchClasses(for: to) else {
            return []
        }
        return fromPCs.intersection(toPCs).sorted().map { ChromaResult.noteNames[$0] }
    }

    /// Parses a "<Root> Major"/"<Root> Minor" key string (`identifyKey`'s own output format)
    /// into its 7 diatonic pitch classes (0-11), using the standard major / natural-minor
    /// interval patterns. Returns nil for anything that doesn't parse (e.g. "Unclassified").
    private static func diatonicPitchClasses(for key: String) -> Set<Int>? {
        let parts = key.components(separatedBy: " ")
        guard parts.count == 2, let rootIdx = ChromaResult.noteNames.firstIndex(of: parts[0]) else {
            return nil
        }
        let intervals = parts[1].lowercased().hasPrefix("min")
            ? [0, 2, 3, 5, 7, 8, 10]  // natural minor
            : [0, 2, 4, 5, 7, 9, 11]  // major
        return Set(intervals.map { (rootIdx + $0) % 12 })
    }
    
    private func rotate(_ profile: [Float], by: Int) -> [Float] {
        var rotated = profile
        for i in 0..<12 {
            rotated[(i + by) % 12] = profile[i]
        }
        return rotated
    }
    
    /// Cosine similarity in [-1, 1]. Normalization makes the 0.7 acceptance threshold
    /// meaningful regardless of overall chroma magnitude (an unnormalized dot product
    /// scaled with loudness, so the threshold was previously arbitrary).
    private func correlate(_ a: [Float], _ b: [Float]) -> Float {
        var dot: Float = 0, na: Float = 0, nb: Float = 0
        for i in 0..<12 { dot += a[i] * b[i]; na += a[i] * a[i]; nb += b[i] * b[i] }
        let denom = sqrtf(na * nb)
        return denom > 1e-12 ? dot / denom : 0
    }
}
