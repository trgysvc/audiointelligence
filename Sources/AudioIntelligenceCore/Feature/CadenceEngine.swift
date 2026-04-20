import Foundation

/// Cadence Analysis Engine (Kadans Analizi).
/// Identifies structural resting points and harmonic conclusions.
public final class CadenceEngine: @unchecked Sendable {
    
    public init() {}
    
    /// Detects cadences at the boundaries of structural segments.
    public func detect(verticalChords: [VerticalChord], segments: [MusicSegment], key: String, sr: Double) -> [CadenceEvent] {
        var cadences = [CadenceEvent]()
        
        let chordMap = verticalChords.reduce(into: [Int: VerticalChord]()) { $0[$1.frame] = $1 }
        let frames = verticalChords.map { $0.frame }.sorted()
        let hop = 512
        
        for segment in segments {
            // Find the chord at the end of the segment
            let segmentEndFrame = findNearestFrame(target: segment.end, frames: frames, sr: sr, hop: hop)
            _ = findNearestFrame(target: segment.start, frames: frames, sr: sr, hop: hop)
            
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
        let frameRate = sr / Double(hop)
        // Optimization: Use binary search for nearest if frames is large, 
        // but since we only call this a few times per segment, linear is fine if not hanging.
        return frames.min(by: { abs(Double($0) - target * frameRate) < abs(Double($1) - target * frameRate) }) ?? 0
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
    
    private func identifyInversion(chord: VerticalChord) -> String {
        let parts = chord.symbol.components(separatedBy: "/")
        if parts.count == 1 { return "Root Position (5/3)" }
        
        let root = parts[0].uppercased()
        let bass = parts[1]
        
        // Simplified inversion logic
        if root.contains("C") && bass == "E" { return "1. Çevrim (6/3)" }
        if root.contains("C") && bass == "G" { return "2. Çevrim (6/4)" }
        
        return "Çevrimli Pozisyon (\(bass) Bassa)"
    }
}
