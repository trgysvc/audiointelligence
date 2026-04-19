import Foundation

/// Cadence Analysis Engine (Kadans Analizi).
/// Identifies structural resting points and harmonic conclusions.
public final class CadenceEngine: @unchecked Sendable {
    
    public init() {}
    
    /// Detects cadences at the boundaries of structural segments.
    public func detect(verticalChords: [VerticalChord], segments: [MusicSegment], key: String) -> [CadenceEvent] {
        var cadences = [CadenceEvent]()
        
        let chordMap = verticalChords.reduce(into: [Int: VerticalChord]()) { $0[$1.frame] = $1 }
        let frames = verticalChords.map { $0.frame }.sorted()
        
        for segment in segments {
            // Find the chord at the end of the segment
            let segmentEndFrame = findNearestFrame(target: segment.end, frames: frames)
            let segmentStartFrame = findNearestFrame(target: segment.start, frames: frames)
            
            // Check for concluding chord (I) vs dominant (V)
            guard let conclusionChord = chordMap[segmentEndFrame] else { continue }
            
            // Look back for the penultimate chord
            let penultimateIdx = frames.firstIndex(of: segmentEndFrame) ?? 0
            guard penultimateIdx > 0 else { continue }
            let penultimateFrame = frames[penultimateIdx - 1]
            guard let preparationChord = chordMap[penultimateFrame] else { continue }
            
            if let cadence = classify(prep: preparationChord, conc: conclusionChord, key: key) {
                cadences.append(CadenceEvent(
                    frame: segmentEndFrame,
                    type: cadence.type,
                    description: cadence.description
                ))
            }
        }
        
        return cadences
    }
    
    private func findNearestFrame(target: Double, frames: [Int]) -> Int {
        // Simple search (assuming frame rate)
        return frames.min(by: { abs(Double($0) - target * 43) < abs(Double($1) - target * 43) }) ?? 0
    }
    
    private func classify(prep: VerticalChord, conc: VerticalChord, key: String) -> (type: String, description: String)? {
        let pFunc = prep.function
        let cFunc = conc.function
        
        // Perfect Authentic Cadence (V-I)
        if pFunc.contains("Dominant (V)") && cFunc.contains("Tonic (I)") {
            return ("Tam Kadans (PAC)", "Armonik gerilimin merkez tona çözüldüğü, güçlü bir bitiş noktası.")
        }
        
        // Half Cadence (I/IV-V)
        if cFunc.contains("Dominant (V)") {
            return ("Yarım Kadans", "Parçanın henüz tamamlanmadığını hissettiren, dominant üzerinde asılı kalan durak.")
        }
        
        // Plagal Cadence (IV-I)
        if pFunc.contains("Subdominant (IV)") && cFunc.contains("Tonic (I)") {
            return ("Plagal Kadans", "Geleneksel 'Amin' bitişi olarak bilinen, yumuşak bir çözülme.")
        }
        
        // Deceptive Cadence (V-vi)
        if pFunc.contains("Dominant (V)") && cFunc.contains("Submediant (vi)") {
            return ("Aldatıcı Kadans", "Beklenen tonik yerine 6. dereceye giderek dinleyiciyi şaşırtan geçiş.")
        }
        
        return nil
    }
}
