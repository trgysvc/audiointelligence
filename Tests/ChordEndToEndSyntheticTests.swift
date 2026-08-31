import XCTest
@testable import AudioIntelligenceCore

/// End-to-end chord-identification accuracy: `TraditionalTheoryEngineTests.swift`'s doc comment
/// and `ChordScoringAmbiguityTests.swift` both measure `identifyTriad` in isolation, fed an
/// idealized chroma vector (1.0 at each chord tone, 0 elsewhere) — that characterizes the
/// scoring algorithm itself, not whether the REAL signal chain (synthesized audio -> STFT ->
/// `ChromaEngine` -> `CQTEngine` -> `TraditionalTheoryEngine.analyzeVertical`) preserves enough
/// fidelity for it to work. Isophonics/Billboard (real recordings with chord annotations) only
/// distribute annotations, not audio, so a real-corpus end-to-end measurement isn't available —
/// this is the next-best ground truth: self-synthesized audio with 100%-exact known chords (see
/// `~/Desktop/AudioIntelligence_Yapilacaklar.md` open item 2).
///
/// Same 108 canonical (12 roots x 9 qualities) chords as `ChordScoringAmbiguityTests`, so this
/// result is directly comparable to that test's idealized-chroma baseline (31/108 mismatches: 8
/// augmented-symmetry + 23 relative-chord-superset, both irreducible-from-chroma-alone or
/// bass-note-resolvable, not scoring bugs — see that file's doc comment).
final class ChordEndToEndSyntheticTests: XCTestCase {

    private static let sr = 22050
    private static let hop = 512

    // Mirrors ChordScoringAmbiguityTests' profile list exactly, for a direct comparison between
    // idealized-chroma accuracy and real-audio-pipeline accuracy on the identical chord set.
    private let profiles: [(name: String, type: TraditionalTheoryEngine.TriadType, offsets: [Int])] = [
        ("major", .major, [0, 4, 7]),
        ("minor", .minor, [0, 3, 7]),
        ("diminished", .diminished, [0, 3, 6]),
        ("augmented", .augmented, [0, 4, 8]),
        ("maj7", .major, [0, 4, 7, 11]),
        ("dom7", .major, [0, 4, 7, 10]),
        ("m7", .minor, [0, 3, 7, 10]),
        ("m7b5", .diminished, [0, 3, 6, 10]),
        ("m6", .minor, [0, 3, 7, 9]),
    ]
    private let noteNames = ["C","C#","D","D#","E","F","F#","G","G#","A","A#","B"]

    /// `formatSymbol`'s root+quality naming (not the bass/inversion suffix) — used to check the
    /// real pipeline's detected symbol's root+quality prefix against what's expected, independent
    /// of bass-note detection accuracy (a separate concern, tracked by open item 3).
    private func expectedNamePrefix(root: Int, type: TraditionalTheoryEngine.TriadType) -> String {
        let rootName = noteNames[root]
        switch type {
        case .major: return rootName
        case .minor: return rootName.lowercased()
        case .diminished: return "\(rootName.lowercased())°"
        case .augmented: return "\(rootName)+"
        case .unclassified: return "\(rootName)?"
        }
    }

    /// Synthesizes one chord's audio, runs the REAL production signal chain (same STFT/Chroma/CQT
    /// parameters `DNAReportBuilder.swift` uses: nFFT=8192 chroma, hop=512, CQT nBins=84/
    /// binsPerOctave=12/fMin=32.7), and returns every chord symbol `analyzeVertical` detected
    /// across the clip.
    private func detectedSymbols(rootMidi: Int, offsets: [Int]) async -> [String] {
        let samples = SyntheticAudio.chord(rootMidi: rootMidi, semitones: offsets, durationSec: 3.0, sampleRate: Self.sr)

        let stft = await STFTEngine(nFFT: 8192, hopLength: Self.hop, sampleRate: Double(Self.sr)).analyze(samples)
        let chroma = ChromaEngine(nFFT: 8192, sampleRate: Double(Self.sr)).chromagram(stft: stft)
        let cqt = CQTEngine(nBins: 84, binsPerOctave: 12, fMin: 32.7, sampleRate: Double(Self.sr), hopLength: Self.hop).transform(samples)

        // `key` only affects `function`/`reasoning`, never the returned chord `symbol` (root +
        // quality + bass) -- irrelevant to this test, which measures identification, not
        // functional-harmony labeling.
        let vertical = TraditionalTheoryEngine().analyzeVertical(chromagram: chroma, cqtMatrix: cqt, key: "C Major")
        return vertical.map { $0.symbol }
    }

    func testChordIdentification_endToEnd_onSynthesizedAudio_acrossAllRootsAndQualities() async {
        var mismatches: [String] = []
        var augmentedSymmetryCount = 0
        var relativeChordSupersetCount = 0
        var noDetectionCount = 0
        var otherCount = 0
        var total = 0

        for root in 0..<12 {
            for p in profiles {
                total += 1
                let symbols = await detectedSymbols(rootMidi: 60 + root, offsets: p.offsets)
                let intendedName = "\(noteNames[root]) \(p.name)"

                guard !symbols.isEmpty else {
                    noDetectionCount += 1
                    mismatches.append("\(intendedName) -> [NO CHORD DETECTED]")
                    continue
                }

                // Majority vote across the clip's detected frames (ignoring the bass/inversion
                // suffix -- see `expectedNamePrefix`'s doc comment): a single mis-tagged transient
                // frame shouldn't fail a chord a real pipeline would report correctly most of the
                // time, matching how a real consumer would read multiple detected frames per chord.
                let expectedPrefix = expectedNamePrefix(root: root, type: p.type)
                let matchCount = symbols.filter { $0.hasPrefix(expectedPrefix) }.count
                let isMajorityMatch = Double(matchCount) / Double(symbols.count) > 0.5

                if !isMajorityMatch {
                    let gotName = symbols.joined(separator: ",")
                    if p.type == .augmented {
                        augmentedSymmetryCount += 1
                        mismatches.append("\(intendedName) -> \(gotName)  [likely AUGMENTED SYMMETRY]")
                    } else {
                        // Not attempting the same fine-grained classification
                        // `ChordScoringAmbiguityTests` does (that requires knowing exactly which
                        // wrong chord was picked) -- just report what real audio actually produced.
                        relativeChordSupersetCount += 1
                        mismatches.append("\(intendedName) -> \(gotName)  [mismatch]")
                    }
                }
            }
        }
        otherCount = mismatches.count - augmentedSymmetryCount - relativeChordSupersetCount - noDetectionCount

        print("=== END-TO-END CHORD ACCURACY (synthesized audio, real STFT/Chroma/CQT pipeline) ===")
        print("Total canonical chords tested: \(total)")
        print("Correctly identified (majority of clip's frames): \(total - mismatches.count)/\(total)")
        print("Total mismatches: \(mismatches.count)/\(total)")
        print("  - no chord ever detected in the clip: \(noDetectionCount)")
        print("  - augmented-symmetry-shaped mismatches: \(augmentedSymmetryCount)")
        print("  - other mismatches: \(relativeChordSupersetCount)")
        print("  - unclassified bucket: \(otherCount)")
        print("\n--- DETAIL ---")
        mismatches.forEach { print($0) }
        print("\nFor comparison, ChordScoringAmbiguityTests' idealized-chroma baseline: 77/108 correct (31 mismatches: 8 augmented-symmetry + 23 relative-chord-superset).")

        // Loose sanity floor, not a tight regression contract: this is the first real-audio
        // end-to-end measurement of this pipeline (item 2 of the project's open-items list) — the
        // purpose is to catch a total collapse (e.g. the real STFT/Chroma chain turns out to
        // corrupt chroma badly enough that almost nothing is recognized), not to lock in today's
        // exact count as a target.
        XCTAssertGreaterThan(total - mismatches.count, total / 2,
                              "fewer than half of all 108 canonical chords were correctly identified end-to-end on synthesized audio -- investigate before assuming the real STFT/Chroma/CQT chain preserves enough fidelity for chord identification")
    }
}
