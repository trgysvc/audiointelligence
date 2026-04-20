import Accelerate
import Foundation

/// Vertical Analysis Engine (Dikey Analiz).
/// Identifies chords, inversions, and musical functions using triadic harmony principles.
public final class TraditionalTheoryEngine: @unchecked Sendable {
    
    public init() {}
    
    /// Analyzes the vertical harmonic content frame-by-frame.
    public func analyzeVertical(chromagram: [[Float]], cqtMatrix: [[Float]], key: String) -> [VerticalChord] {
        let nFrames = chromagram[0].count
        var verticalChords = [VerticalChord]()
        
        // v7.1 Fix: Use fixed 500ms step instead of totalFrames/20
        // Industry Standard: 512 hop at 44.1kHz results in 44100/512 = ~86 fps.
        let step = max(1, Int(0.5 / (512.0 / 44100.0))) 
        
        for t in stride(from: 0, to: nFrames, by: step) {
            // Forensic Safety: Ensure across all 12 bins that the frame 't' exists
            var isSafe = true
            for c in 0..<12 {
                if t >= chromagram[c].count { isSafe = false; break }
            }
            guard isSafe else { continue }
            
            let frameChroma = (0..<12).map { chromagram[$0][t] }
            let (root, type) = identifyTriad(frameChroma)
            
            if type != .unclassified {
                let bassNoteBin = detectBassNote(cqtMatrix: cqtMatrix, frameIndex: t)
                let symbol = formatSymbol(root: root, type: type, bass: bassNoteBin)
                
                let (function, reasoning) = determineFunction(root: root, type: type, key: key)
                
                verticalChords.append(VerticalChord(
                    frame: t,
                    symbol: symbol,
                    function: function,
                    reasoning: reasoning
                ))
            }
        }
        
        return verticalChords
    }
    
    // MARK: - Internal Logic
    
    private enum TriadType {
        case major, minor, diminished, augmented, unclassified
    }
    
    private func identifyTriad(_ chroma: [Float]) -> (root: Int, type: TriadType) {
        // Standard Triad & Jazz Extension Profiles
        let profiles: [(type: TriadType, offsets: [Int])] = [
            (.major, [0, 4, 7]),
            (.minor, [0, 3, 7]),
            (.diminished, [0, 3, 6]),
            (.augmented, [0, 4, 8]),
            // Jazz / v7.0 Additions
            (.major, [0, 4, 7, 11]), // Maj7
            (.major, [0, 4, 7, 10]), // Dominant 7th
            (.minor, [0, 3, 7, 10]), // m7
            (.diminished, [0, 3, 6, 10]), // m7b5
            (.minor, [0, 3, 7, 9])  // m6 (Dorian hint)
        ]
        
        var bestScore: Float = 0
        var bestRoot = 0
        var bestType: TriadType = .unclassified
        
        for root in 0..<12 {
            for profile in profiles {
                var score: Float = 0
                for offset in profile.offsets {
                    score += chroma[(root + offset) % 12]
                }
                
                if score > bestScore && score > 1.5 { // Threshold for triad presence
                    bestScore = score
                    bestRoot = root
                    bestType = profile.type
                }
            }
        }
        
        return (bestRoot, bestType)
    }
    
    private func detectBassNote(cqtMatrix: [[Float]], frameIndex: Int) -> Int {
        // Look at the lowest 2 octaves (bins 0 to 24)
        var maxEnergy: Float = 0
        var dominantBin = 0
        
        for bin in 0..<24 {
            if bin < cqtMatrix.count && frameIndex < cqtMatrix[bin].count {
                let energy = cqtMatrix[bin][frameIndex]
                if energy > maxEnergy {
                    maxEnergy = energy
                    dominantBin = bin
                }
            }
        }
        
        return dominantBin % 12
    }
    
    private func formatSymbol(root: Int, type: TriadType, bass: Int) -> String {
        let rootName = ChromaResult.noteNames[root]
        var chordName = rootName
        
        switch type {
        case .major: chordName += ""
        case .minor: chordName = rootName.lowercased() // Musicology Standard
        case .diminished: chordName = "\(rootName.lowercased())°"
        case .augmented: chordName += "+"
        case .unclassified: chordName += "?"
        }
        
        if root == bass {
            return chordName
        } else {
            return "\(chordName)/\(ChromaResult.noteNames[bass])"
        }
    }
    
    private func determineFunction(root: Int, type: TriadType, key: String) -> (function: String, reasoning: String) {
        // Simplified Functional Logic (v6.5)
        let keyParts = key.components(separatedBy: " ")
        guard keyParts.count >= 2 else { return ("Tonic", "Dominant behavior in current context") }
        
        let keyRootName = keyParts[0]
        _ = keyParts[1].lowercased() == "minor"
        let keyRootBin = ChromaResult.noteNames.firstIndex(of: keyRootName) ?? 0
        
        let intervalFromKey = (root - keyRootBin + 12) % 12
        
        // Diatonic vs Chromatic
        let majorDiatonic = [0, 2, 4, 5, 7, 9, 11]
        let isDiatonic = majorDiatonic.contains(intervalFromKey)
        
        if isDiatonic {
            let names = ["Tonic (I)", "Supertonic (ii)", "Mediant (iii)", "Subdominant (IV)", "Dominant (V)", "Submediant (vi)", "Leading Tone (vii)"]
            let idx = majorDiatonic.firstIndex(of: intervalFromKey) ?? 0
            return (names[idx], "This chord is the \(names[idx]) degree of the \(key) key and serves as a structural pillar.")
        } else {
            // Functional Accidents
            if intervalFromKey == 6 { // Tritone
                return ("Secondary Dominant (V/V)", "This accidental (\(ChromaResult.noteNames[root])) acts as a leading tone to the Dominant key, increasing harmonic tension.")
            }
            if intervalFromKey == 1 { // Neapolitan / Phrygian II
                return ("Neapolitan (bII)", "This chromatic shift destabilizes the vertical balance of the key, creating a melancholic or dramatic effect.")
            }
            return ("Chromatic Color", "Although non-diatonic, this chord functions as a harmonic ornament providing tonal richness.")
        }
    }
}
