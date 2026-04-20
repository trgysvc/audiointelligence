import Accelerate
import Foundation

/// Counterpoint Engine (Kontrpuan Analizi).
/// Identifies melodic species and theoretical errors based on Fuxian principles.
public final class CounterpointEngine: @unchecked Sendable {
    
    public init() {}
    
    /// Analyzes the relationship between Bass and Lead voices.
    public func analyze(pitchPath: [Int], chroma: [[Float]]) -> (species: String, errors: [String]) {
        // 1. Identify "Structural Voices"
        // We'll use the Pitch Path (Viterbi) for Lead and the dominant low chroma for Bass
        let nFrames = pitchPath.count
        guard nFrames > 10 else { return ("Unknown", []) }
        
        var leadNotes = [Int]()
        var bassNotes = [Int]()
        
        for t in 0..<nFrames {
            // Lead from Viterbi path (Midi Note)
            let leadMidi = pitchPath[t]
            if leadMidi > 0 { leadNotes.append(leadMidi) }
            
            // Bass from Chroma (Lowest 12-bin profile)
            // Safety Check: Ensure chroma has the frame index t
            guard chroma.indices.contains(0), chroma[0].indices.contains(t) else { continue }
            
            let frameChroma = (0..<12).map { chroma[$0][t] }
            let bassBin = frameChroma.enumerated().max(by: { $0.element < $1.element })?.offset ?? 0
            // Assume bass is in the 3rd octave for MIDI comparison
            bassNotes.append(bassBin + 36) 
        }
        
        // 2. Species Detection (Rhythm Ratio)
        let species = detectSpecies(lead: leadNotes, bass: bassNotes)
        
        // 3. Error Detection (Parallel Intervals)
        let errors = detectParallelErrors(lead: leadNotes, bass: bassNotes)
        
        return (species, errors)
    }
    
    private func detectSpecies(lead: [Int], bass: [Int]) -> String {
        let ratio = Float(lead.count) / Float(max(1, bass.count))
        
        if ratio > 0.9 && ratio < 1.1 { return "1:1 (One-to-One)" }
        if ratio >= 1.8 && ratio <= 2.2 { return "1:2 (One-to-Two)" }
        if ratio >= 3.5 && ratio <= 4.5 { return "1:4 (One-to-Four)" }
        if ratio > 2.5 && ratio < 3.5 { return "AKSÂK (Irregular/Complex)" }
        
        return "Florid / Free Style"
    }
    
    private func detectParallelErrors(lead: [Int], bass: [Int]) -> [String] {
        var errors = [String]()
        let length = min(lead.count, bass.count)
        guard length > 5 else { return [] }
        
        var lastInterval = -1
        
        for i in 1..<length {
            let interval = abs(lead[i] - bass[i]) % 12
            let leadMove = lead[i] - lead[i-1]
            let bassMove = bass[i] - bass[i-1]
            
            // Parallel 5ths (7 semitones)
            if interval == 7 && lastInterval == 7 && (leadMove != 0 || bassMove != 0) {
                if (leadMove > 0 && bassMove > 0) || (leadMove < 0 && bassMove < 0) {
                    errors.append("ERROR: Parallel Fifths (Voices moving in parallel perfect fifths detected)")
                }
            }
            
            // Parallel Octaves (0 or 12 semitones)
            if (interval == 0 || interval == 12) && (lastInterval == 0 || lastInterval == 12) && (leadMove != 0 || bassMove != 0) {
                if (leadMove > 0 && bassMove > 0) || (leadMove < 0 && bassMove < 0) {
                    errors.append("ERROR: Parallel Octaves (Voices moving in parallel octaves detected)")
                }
            }
            
            lastInterval = interval
        }
        
        // Deduplicate errors to avoid spamming the report
        return Array(Set(errors))
    }
}
