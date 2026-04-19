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
        
        // Sampling rate for vertical analysis (e.g., every 0.5s to avoid noise)
        let step = max(1, nFrames / 20) 
        
        for t in stride(from: 0, to: nFrames, by: step) {
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
        // Standard Triad Profiles
        let profiles: [(type: TriadType, offsets: [Int])] = [
            (.major, [0, 4, 7]),
            (.minor, [0, 3, 7]),
            (.diminished, [0, 3, 6]),
            (.augmented, [0, 4, 8])
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
        let suffix: String
        switch type {
        case .major: suffix = ""
        case .minor: suffix = "m"
        case .diminished: suffix = "dim"
        case .augmented: suffix = "aug"
        case .unclassified: suffix = "?"
        }
        
        let chordName = "\(rootName)\(suffix)"
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
            return (names[idx], "Bu akor, \(key) tonunun \(names[idx]) derecesidir ve yapısal bir kolon görevi görür.")
        } else {
            // Functional Accidents
            if intervalFromKey == 6 { // Tritone
                return ("Secondary Dominant (V/V)", "Bu arıza (\(ChromaResult.noteNames[root])), Dominant tona yeden nota işlevi görerek armonik gerilimi artırmaktadır.")
            }
            if intervalFromKey == 1 { // Neapolitan / Phrygian II
                return ("Neapolitan (bII)", "Bu kromatik geçiş, tonun dikey dengesini bozarak hüzünlü veya dramatik bir etki yaratmaktadır.")
            }
            return ("Chromatic Color", "Bu akor ton dışı olmasına rağmen tonal zenginlik katan bir armonik süsleme işlevi görmektedir.")
        }
    }
}
