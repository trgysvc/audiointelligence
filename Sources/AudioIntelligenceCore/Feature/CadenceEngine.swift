import Foundation

/// Cadence Analysis Engine (Kadans Analizi).
/// Identifies structural resting points and harmonic conclusions.
public final class CadenceEngine: @unchecked Sendable {
    
    public init() {}
    
    /// Detects cadences at the boundaries of structural segments (Async Forensic Path).
    public func detect(verticalChords: [VerticalChord], segments: [MusicSegment], key: String, sr: Double) async -> [CadenceEvent] {
        var cadences = [CadenceEvent]()
        
        let chordMap = verticalChords.reduce(into: [Int: VerticalChord]()) { $0[$1.frame] = $1 }
        let frames = verticalChords.map { $0.frame }.sorted()
        let hop = 512
        
        for (idx, segment) in segments.enumerated() {
            if idx % 100 == 0 { await Task.yield() }
            
            // Find the chord at the end of the segment using binary search for speed
            let segmentEndFrame = findNearestFrame(target: segment.end, frames: frames, sr: sr, hop: hop)
            
            // Check for concluding chord (I) vs dominant (V)
            guard let conclusionChord = chordMap[segmentEndFrame] else { continue }
            
            // Look back for the penultimate chord
            let penultimateIdx = frames.firstIndex(of: segmentEndFrame) ?? 0
            guard penultimateIdx > 0 else { continue }
            let penultimateFrame = frames[penultimateIdx - 1]
            guard let preparationChord = chordMap[penultimateFrame] else { continue }
            
            if let cadence = classify(prep: preparationChord, conc: conclusionChord, key: key) {
                let inversionStatus = identifyInversion(chord: conclusionChord)
                cadences.append(CadenceEvent(
                    frame: segmentEndFrame,
                    type: cadence.type,
                    description: "\(cadence.description) (Chord Inversion: \(inversionStatus))"
                ))
            }
        }
        
        return cadences
    }
    
    private func findNearestFrame(target: Double, frames: [Int], sr: Double, hop: Int) -> Int {
        guard !frames.isEmpty else { return 0 }
        let frameRate = sr / Double(hop)
        let targetFrame = Int(target * frameRate)
        
        // v7.9 Optimization: Binary Search instead of Linear min(by:)
        var low = 0
        var high = frames.count - 1
        
        while low <= high {
            let mid = (low + high) / 2
            if frames[mid] == targetFrame { return frames[mid] }
            if frames[mid] < targetFrame { low = mid + 1 }
            else { high = mid - 1 }
        }
        
        // Return nearest neighbor from binary search convergence
        let idx = Swift.min(Swift.max(0, low), frames.count - 1)
        return frames[idx]
    }
    
    private func classify(prep: VerticalChord, conc: VerticalChord, key: String) -> (type: String, description: String)? {
        let pFunc = prep.function
        let cFunc = conc.function
        
        // Perfect Authentic Cadence (V-I)
        if pFunc.contains("Dominant (V)") && cFunc.contains("Tonic (I)") {
            return ("Perfect Authentic Cadence (PAC)", "A strong point of rest where harmonic tension resolves to the tonic.")
        }
        
        // Half Cadence (I/IV-V)
        if cFunc.contains("Dominant (V)") {
            return ("Half Cadence", "A temporary pause on the dominant that leaves the musical phrase feeling incomplete.")
        }
        
        // Plagal Cadence (IV-I)
        if pFunc.contains("Subdominant (IV)") && cFunc.contains("Tonic (I)") {
            return ("Plagal Cadence", "Often known as the 'Amen' cadence, providing a soft and meditative resolution.")
        }
        
        // Deceptive Cadence (V-vi)
        if pFunc.contains("Dominant (V)") && cFunc.contains("Submediant (vi)") {
            return ("Deceptive Cadence", "Surprises the listener by moving to the submediant (vi) instead of the expected tonic.")
        }
        
        return nil
    }
    
    /// Determines a chord's inversion from its symbol (e.g. "G/B", "c°/Eb", "C"). Was
    /// hardcoded to only recognize a root of "C" — every other root (11 of 12 possible chord
    /// roots) fell through to a generic, untranslated-Turkish "Çevrimli Pozisyon (bass Bassa)"
    /// label. Now parses the actual root/quality/bass from `TraditionalTheoryEngine.
    /// formatSymbol`'s real output convention (case = quality, optional "°"/"+"/"?" suffix,
    /// optional "/<bass>" suffix) and computes the true inversion for any of the 12 roots.
    // `internal` (not `private`) for direct unit testing.
    func identifyInversion(chord: VerticalChord) -> String {
        let parts = chord.symbol.components(separatedBy: "/")
        guard let rootPart = parts.first, !rootPart.isEmpty else { return "Root Position (5/3)" }
        guard parts.count == 2 else { return "Root Position (5/3)" }
        let bassName = parts[1]

        // `formatSymbol`'s convention: uppercase root = major (or "+" = augmented), lowercase
        // root = minor (or "°" = diminished), trailing "?" = unclassified.
        var rootToken = rootPart
        let isAugmented = rootToken.hasSuffix("+")
        let isDiminished = rootToken.hasSuffix("°")
        let isUnclassified = rootToken.hasSuffix("?")
        if isAugmented || isUnclassified { rootToken.removeLast() }
        if isDiminished { rootToken.removeLast() } // "°" is a single Character, one removeLast() is correct

        let isMinorCase = rootToken.first.map { $0.isLowercase } ?? false
        let rootNameNormalized = rootToken.uppercased()

        guard let rootPC = ChromaResult.noteNames.firstIndex(of: rootNameNormalized),
              let bassPC = ChromaResult.noteNames.firstIndex(of: bassName.uppercased()) else {
            return "Root Position (5/3)"
        }

        if rootPC == bassPC { return "Root Position (5/3)" }

        let thirdInterval: Int
        let fifthInterval: Int
        if isAugmented { thirdInterval = 4; fifthInterval = 8 }
        else if isDiminished { thirdInterval = 3; fifthInterval = 6 }
        else if isUnclassified { thirdInterval = 4; fifthInterval = 7 } // best-effort default
        else if isMinorCase { thirdInterval = 3; fifthInterval = 7 }
        else { thirdInterval = 4; fifthInterval = 7 } // major

        let bassInterval = (bassPC - rootPC + 12) % 12
        switch bassInterval {
        case thirdInterval: return "First Inversion (6/3)"
        case fifthInterval: return "Second Inversion (6/4)"
        default: return "Inverted Position (\(bassName) in the bass)"
        }
    }
}
