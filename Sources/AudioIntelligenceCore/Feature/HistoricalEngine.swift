import Foundation

/// Historical & Contextual Analysis Engine (Tarihsel ve Bağlamsal Analiz).
/// Infers composition period, artistic movements, and global implications.
/// Cross-references timbre and structural findings with musicological patterns.
///
/// **Deliberately NOT wired into the public `AudioReport`** (`AudioReportMapping.swift`'s
/// `MusicologyReport` construction omits this engine's output entirely) -- found and documented
/// 2026-09-03 during a repo-wide audit. Same reasoning as the mood/genre/danceability exclusion
/// (Yapilacaklar.md's "BİLİNÇLİ KAPSAM DIŞI" section): this engine infers subjective, uncalibrated
/// claims ("Romantic/Classical Era", "Jazz Age") from generic signal features (loudness threshold,
/// instrument-label substring match, tempo), stamped with confidence values that were never fit
/// against any ground truth -- exactly what this library's "measured, not claimed" identity rules
/// out for a public field. This class and `inferContext` still run on every `analyze()` call
/// (their result is computed and stored on the internal `MusicDNAAnalysis`, just never mapped
/// through) -- wasted work, not a correctness risk, and a separate low-priority cleanup item.
/// Do not add a mapping from this to `AudioReport` without revisiting that decision first.
public final class HistoricalEngine: Sendable {
    
    public init() {}
    
    /// Provides an educated guess on the context of the audio material.
    public func inferContext(analysis: MusicDNAAnalysis) -> HistoricalContext {
        let (period, movement, global, confidence) = Self.inferPeriod(
            lufs: analysis.mastering.integratedLUFS,
            bpm: analysis.rhythm.bpm,
            instruments: analysis.instruments.primaryLabel,
            entropy: analysis.forensic.entropyScore,
            harmonicStability: analysis.tonality.harmonicStability
        )

        return HistoricalContext(
            suggestedPeriod: period,
            artisticMovement: movement,
            globalContext: global,
            composerContext: "Inferred from tonal stability (\(analysis.tonality.tendency)) and spectral entropy (\(analysis.forensic.entropyScore)).",
            confidence: confidence
        )
    }

    /// Pure period-inference logic, extracted from `inferContext` so it's directly testable
    /// without constructing a full `MusicDNAAnalysis` (a large, deeply-nested struct).
    static func inferPeriod(lufs: Float, bpm: Float, instruments: String, entropy: Float, harmonicStability: Float) -> (period: String, movement: String, global: String, confidence: Float) {
        var period = "Modern/Unclassified"
        var movement = "Contemporary"
        var global = "Global Digital Era"
        var confidence: Float = 0.5

        // --- 1. Period Inference ---
        // Logic: Low volume (-20 LUFS) + Acoustic instruments + Low entropy -> likely pre-loudness war or earlier.
        // `&&` binds tighter than `||` in Swift, so the missing parens meant this was actually
        // `(lufs < -18 && Piano) || Strings` — any track whose primaryLabel merely contains
        // "Strings" was classified "Romantic/Classical Era" regardless of loudness, e.g. a loud
        // modern pop track with a synth-strings patch.
        if lufs < -18 && (instruments.contains("Piano") || instruments.contains("Strings")) {
            period = "Romantic / Classical Era"
            movement = "Classicism/Romanticism"
            global = "Traditional Acoustic Paradigm"
            confidence = 0.7
        } else if lufs > -10 && entropy > 0.8 {
            period = "Digital Era (21st Century)"
            movement = "Post-Modernism / Electronic"
            global = "Post-Loudness War Globalization"
            confidence = 0.82
        } else if instruments.contains("Brass") && bpm > 140 {
            period = "Jazz Age / Mid-20th Century"
            movement = "Bebop / Hard Bop"
            global = "Urban Modernization & Syncopation"
            confidence = 0.75
        }

        // --- 2. Tonal Stability Refinement ---
        // High stability + Specific instrumentation typically points to structural perfection of the era.
        if harmonicStability > 0.8 && instruments.contains("Piano") {
            confidence += 0.05
        }

        return (period, movement, global, min(0.92, confidence))
    }
}
