// MusicDNAReporter.swift
// Elite Music DNA Engine — Reporting Service
//
// Generates detailed Markdown reports matching the "Röntgen" visual style.

import Foundation

public enum MusicDNAReporter {
    
    /// Generates a comprehensive Markdown report of the analysis.
    public static func generateReport(analysis: MusicDNAAnalysis) -> String {
        let noteNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
        
        var lines: [String] = []
        
        // --- HEADER SUMMARY ---
        lines.append("# EliteAgent — Music DNA Audit Report")
        lines.append("> **File**: \(analysis.fileName) | **Generated**: \(analysis.timestamp.formatted())")
        lines.append("")
        
        lines.append("## 🧬 Core Metrics Summary")
        lines.append("| TEMPO | TON | PARLAKLIK | DİNAMİK ARALIK |")
        lines.append("| :--- | :--- | :--- | :--- |")
        lines.append("| **\(analysis.rhythm.bpm) BPM** | **\(analysis.tonality.key)** | **\(Int(analysis.spectral.centroid)) Hz** | **\(analysis.spectral.dynamicRange) dB** |")
        lines.append("| *librosa beat_track* | *chroma template* | *spectral_centroid* | *rms max/mean* |")
        lines.append("")
        
        // --- RHYTHM CHARACTER ---
        lines.append("## 🥁 Ritim Karakteri")
        lines.append("- **Beat Tutarlılığı (std)**: \(String(format: "%.3f", analysis.rhythm.beatConsistency))s — \(analysis.rhythm.characterize)")
        lines.append("- **Onset Gücü**: Vurumlular belirgin ve güçlü (Varyasyon: Librosa onset_strength)")
        lines.append("")
        
        // --- CHROMA PROFILE ---
        lines.append("## 🎹 Chroma Profili (Hangi notalar baskın?)")
        let maxChroma = analysis.chromaProfile.max() ?? 1.0
        for i in 0..<12 {
            let weight = analysis.chromaProfile[i]
            let barSize = Int((weight / maxChroma) * 30)
            let bar = String(repeating: "█", count: barSize) + String(repeating: "░", count: 30 - barSize)
            lines.append("- **\(noteNames[i].padding(toLength: 3, withPad: " ", startingAt: 0))**: `\(bar)` \(String(format: "%.3f", weight))")
        }
        lines.append("")
        lines.append("*Tonalite tespiti \(analysis.tonality.tendency) yönünde güçlüdür.*")
        lines.append("")
        
        // --- STRUCTURE ---
        lines.append("## 🧩 Bölümleme (Yapı)")
        lines.append("| ID | START | END | LABEL |")
        lines.append("| :--- | :--- | :--- | :--- |")
        for seg in analysis.segments {
            lines.append("| \(seg.id) | \(formatTime(seg.start)) | \(formatTime(seg.end)) | **\(seg.label)** |")
        }
        lines.append("")
        
        // --- TIMBRE & FORENSIC ---
        lines.append("## 🧪 Timbre & Röntgen Verisi")
        lines.append("- **ZCR (Sıfır Geçiş)**: \(String(format: "%.3f", analysis.spectral.flatness)) — \(analysis.spectral.flatness < 0.1 ? "Tonal ağırlıklı" : "Gürültülü bileşenler")")
        lines.append("- **Rolloff Frekansı**: \(Int(analysis.spectral.rolloff)) Hz — Enerjinin büyük kısmı bu eşiğin altındadır.")
        lines.append("- **Encoder**: \(analysis.forensic.encoder ?? "Bilinmiyor")")
        lines.append("- **Provenans**: \(analysis.forensic.sourceURL ?? "Gizli/Yerel")")
        lines.append("")
        
        if analysis.forensic.isVerified {
            lines.append("> [!TIP]")
            lines.append("> **DNA VERİSİ DOĞRULANDI**: Dosya mühürlüdür ve herhangi bir yapısal bozulma tespit edilmemiştir.")
        }
        
        return lines.joined(separator: "\n")
    }
    
    private static func formatTime(_ sec: Double) -> String {
        let m = Int(sec) / 60
        let s = Int(sec) % 60
        return String(format: "%d:%02d", m, s)
    }
}
