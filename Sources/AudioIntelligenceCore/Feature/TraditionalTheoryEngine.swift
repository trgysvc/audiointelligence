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
            // Bass note computed BEFORE root/type selection (not just for inversion labeling
            // afterward) so `identifyTriad` can use it to break chroma-identical ties -- see its
            // own doc comment (DEVLOG Phase 29's bass-note-wiring follow-up).
            let bassNoteBin = detectBassNote(cqtMatrix: cqtMatrix, frameIndex: t)
            let (root, type) = identifyTriad(frameChroma, bassNote: bassNoteBin)

            if type != .unclassified {
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
    
    // `internal` (not `private`) — needed as a parameter type on `determineFunction`, which
    // is itself `internal` for direct unit testing.
    enum TriadType {
        case major, minor, diminished, augmented, unclassified
    }
    
    // `internal` (not `private`) — needed for direct unit testing of the (root, profile)
    // scoring/tie-breaking logic itself, independent of `formatSymbol`'s string output.
    //
    // `bassNote`: real chord-tone sets can be chroma-identical at more than one (root, type) —
    // e.g. C6 and Am7 share the exact same pitch classes, as do all 3 rotations of an augmented
    // triad a major third apart. Chroma alone can't break those ties; the real bass note (already
    // computed from CQT for inversion labeling, see `detectBassNote`) usually can, since the
    // intended root is conventionally the one actually sounding in the bass. Default `nil`
    // preserves the original chroma-only behavior exactly (`ChordScoringAmbiguityTests` relies on
    // this for its own baseline numbers).
    func identifyTriad(_ chroma: [Float], bassNote: Int? = nil) -> (root: Int, type: TriadType) {
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
        // Floating-point tolerance for "effectively tied" scores -- idealized chroma inputs
        // produce EXACTLY equal scores for chroma-identical (root, type) pairs, but real audio
        // won't be bit-identical, so a strict `==` would miss real-world near-ties.
        let tieEpsilon: Float = 0.001

        for root in 0..<12 {
            for profile in profiles {
                var rawScore: Float = 0
                for offset in profile.offsets {
                    rawScore += chroma[(root + offset) % 12]
                }
                // Normalize by profile length (mean chroma energy per chord tone), not the raw
                // sum: an unnormalized sum systematically favors longer (4-note) jazz-extension
                // profiles over plain 3-note triads whenever 3 of the 4 notes happen to match
                // elsewhere — a scoring-scale artifact with no music-theoretic basis, found to
                // misidentify 46/108 canonical (root, quality) combinations even on idealized,
                // noise-free chroma. Normalizing puts every profile on the same 0...1 scale
                // regardless of length.
                //
                // Threshold: chroma here is L2-normalized per frame (`ChromaEngine.
                // normalizeChroma`), so real (non-idealized) audio never reaches the naive
                // "1.5/3-note-triad" equivalent of 0.5 — measured on a real SQAM string-quartet
                // recording, the per-frame best normalized score topped out at 0.465 across the
                // whole file (0 frames ever exceeded 0.5), regressing `identifyTriad` to detect
                // zero chords anywhere. 0.4 was chosen empirically, not guessed: on that same
                // recording it reproduces the exact same fraction of classified frames (41.54%)
                // as the original raw threshold (1.5) did pre-fix — real-world detection
                // sensitivity preserved, while the normalization still fixes which root/type wins.
                let score = rawScore / Float(profile.offsets.count)
                guard score > 0.4 else { continue } // Threshold for triad presence -- unmodified,
                // raw score only, so real-world detection sensitivity (frame classified at all)
                // stays exactly as empirically calibrated above; only WHICH candidate wins among
                // already-qualifying ones is affected by the penalty below.

                // Explained-energy penalty (madde 1 / DEVLOG Phase 45, option B): a smaller
                // profile's note set can numerically outscore a larger profile that fully
                // contains it on real (non-idealized) audio, because real per-tone chroma
                // magnitudes are never perfectly equal (DEVLOG Phase 40) -- e.g. a 3-note "E
                // diminished" beating the true "C dominant 7" it's a subset of. Rather than
                // detect that specific subset relationship, penalize any candidate for chroma
                // energy it leaves unexplained: `chroma` is L2-normalized per frame (sum of
                // squares over all 12 bins = 1), so `matchedEnergy` is the fraction of that unit
                // budget the candidate's own notes account for, and `1 - matchedEnergy` is what's
                // left over in bins the candidate says nothing about. A candidate that explains
                // more of the real energy is rewarded; one that ignores a still-strong bin (like
                // "E diminished" ignoring C's own real energy) is penalized for it.
                var matchedEnergy: Float = 0
                for offset in profile.offsets {
                    let c = chroma[(root + offset) % 12]
                    matchedEnergy += c * c
                }
                let unmatchedEnergy = max(0, 1 - matchedEnergy)
                // λ=0.15: smallest round value with margin over the minimum (~0.053) that flips
                // the measured C7-vs-E-diminished case (DEVLOG Phase 40's own numbers) -- chosen
                // before re-running the closing-evidence tests, not fit to their outcome.
                let energyPenaltyWeight: Float = 0.15
                let adjustedScore = score - energyPenaltyWeight * unmatchedEnergy

                if adjustedScore > bestScore + tieEpsilon {
                    bestScore = adjustedScore
                    bestRoot = root
                    bestType = profile.type
                } else if let bass = bassNote, abs(adjustedScore - bestScore) <= tieEpsilon, root == bass, bestRoot != bass {
                    // Effectively tied with the current best, but THIS candidate's root matches
                    // the real bass note and the current best's doesn't -- prefer it. Doesn't
                    // touch `bestScore` (stays the same, since these ARE the same score) so a
                    // later, non-bass-matching candidate at the same score can't un-do this.
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
    
    // `internal` (not `private`) for direct unit testing of the key-parsing fallback.
    func determineFunction(root: Int, type: TriadType, key: String) -> (function: String, reasoning: String) {
        // Simplified Functional Logic (v6.5)
        let keyParts = key.components(separatedBy: " ")
        // Every other branch below returns a "<Name> (<RomanNumeral>)"-formatted function
        // string (e.g. "Tonic (I)"), which `CadenceEngine.classify` matches via `.contains(
        // "Tonic (I)")`/`.contains("Dominant (V)")` etc. This fallback (no parseable key, e.g.
        // key == "Unclassified") returned a bare "Tonic" — never matching that format, so
        // every cadence in a passage with no detected key silently went unclassified.
        guard keyParts.count >= 2 else { return ("Tonic (I)", "No reliable key context was available; defaulting to the tonic function.") }
        
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
