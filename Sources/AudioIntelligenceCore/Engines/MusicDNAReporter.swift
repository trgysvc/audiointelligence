import Foundation

public enum MusicDNAReporter {
    
    public static func generateReport(analysis: MusicDNAAnalysis) -> String {
        let noteNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
        var lines: [String] = []
        
        lines.append("# 🧬 Elite Music DNA Audit: \(analysis.fileName)")
        lines.append("> **Generated**: \(analysis.timestamp.formatted()) | **Device**: Apple Silicon Accelerate")
        lines.append("")
        
        // --- 1. MASTERING ENGINEER DASHBOARD ---
        lines.append("## 🎚️ 1. Mastering Engineer Dashboard")
        lines.append("| Metric | Value | Compliance / Status |")
        lines.append("| :--- | :--- | :--- |")
        lines.append("| **Integrated LUFS** | \(String(format: "%.2f", analysis.mastering.integratedLUFS)) LUFS | \(analysis.mastering.integratedLUFS < -14.5 ? "Low" : "High") |")
        lines.append("| **True Peak** | \(String(format: "%.2f", analysis.mastering.truePeak)) dBTP | \(analysis.mastering.truePeak > -0.1 ? "⚠️ Clipping Risk" : "✅ Safe") |")
        lines.append("| **Phase Correlation** | \(String(format: "%.2f", analysis.mastering.phaseCorrelation)) | \(analysis.mastering.phaseCorrelation < 0.7 ? "⚠️ Mono Issues" : "✅ Solid") |")
        lines.append("| **L/R Balance** | \(String(format: "%.2f", analysis.mastering.balanceLR)) | \(abs(analysis.mastering.balanceLR) > 0.05 ? "⚠️ Off-Center" : "✅ Balanced") |")
        lines.append("")
        
        // --- 2. RHYTHM & TEMPO DNA ---
        lines.append("## 🥁 2. Ritim & Tempo DNA")
        lines.append("- **BPM**: \(String(format: "%.2f", analysis.rhythm.bpm))")
        lines.append("- **Beat Consistency**: \(String(format: "%.4f", analysis.rhythm.beatConsistency))s (\(analysis.rhythm.characterize))")
        lines.append("- **Onset Strength**: Mean: \(String(format: "%.3f", analysis.rhythm.onsetMean)) | Peak: \(String(format: "%.3f", analysis.rhythm.onsetPeak))")
        lines.append("")
        
        // --- 3. SPECTRUM & TIMBRE (INFINITY DEPTH) ---
        lines.append("## 🧪 3. Spektrum & Timbre (Infinity Audit)")
        lines.append("### Spectral Suite")
        lines.append("- **Centroid**: \(Int(analysis.spectral.centroid)) Hz (\(analysis.spectral.brightnessDescription))")
        lines.append("- **Spectral Flux**: \(String(format: "%.4f", analysis.spectral.flux)) (Enerji değişim hızı)")
        lines.append("- **Flatness/ZCR**: \(String(format: "%.4f", analysis.spectral.flatness)) / \(String(format: "%.4f", analysis.spectral.zcr))")
        lines.append("- **Dynamic Range**: \(String(format: "%.1f", analysis.spectral.dynamicRange)) dB")
        lines.append("- **RMS Energy**: Mean: \(String(format: "%.4f", analysis.spectral.rmsMean)) | Max: \(String(format: "%.4f", analysis.spectral.rmsMax))")
        lines.append("")
        
        lines.append("### HPSS (Harmonic Percussive Source Separation)")
        let hBar = Int(analysis.hpss.harmonicRatio * 30.0)
        let pBar = Int(analysis.hpss.percussiveRatio * 30.0)
        lines.append("- **Harmonic**: `\(String(repeating: "█", count: max(0, min(30, hBar))))\(String(repeating: "░", count: max(0, 30 - hBar)))` \(String(format: "%.1f%%", analysis.hpss.harmonicRatio * 100))")
        lines.append("- **Percussive**: `\(String(repeating: "█", count: max(0, min(30, pBar))))\(String(repeating: "░", count: max(0, 30 - pBar)))` \(String(format: "%.1f%%", analysis.hpss.percussiveRatio * 100))")
        lines.append("- **Dominance**: \(analysis.hpss.characterization)")
        lines.append("")
        
        lines.append("### Timbre (MFCC 20 Coefficients)")
        lines.append("```")
        lines.append(analysis.timbre.mfcc.map { String(format: "%.2f", $0) }.joined(separator: ", "))
        lines.append("```")
        lines.append("")
        
        // --- 4. TONALITY (CHROMA MAP) ---
        lines.append("## 🎹 4. Tonalite & Chroma Map")
        lines.append("**Key Detection**: \(analysis.tonality.key) (\(analysis.tonality.tendency))")
        lines.append("")
        let maxChroma = analysis.chromaProfile.max() ?? 1.0
        for i in 0..<12 {
            let weight = analysis.chromaProfile[i]
            let bSize = Int((weight / (maxChroma > 0 ? maxChroma : 1.0)) * 25.0)
            let bar = String(repeating: "█", count: max(0, min(25, bSize))) + String(repeating: "░", count: max(0, 25 - bSize))
            lines.append("- **\(noteNames[i].padding(toLength: 3, withPad: " ", startingAt: 0))**: `\(bar)` \(String(format: "%.3f", weight))")
        }
        lines.append("")
        
        // --- 5. FORENSIC DNA (RÖNTGEN) ---
        lines.append("## 🔍 5. Forensic DNA (Röntgen)")
        lines.append("| Feature | Status |")
        lines.append("| :--- | :--- |")
        lines.append("| **Bit-Depth Integrity** | \(analysis.forensic.effectiveBits)-bit (\(analysis.forensic.isUpsampled ? "⚠️ FAKE HI-RES" : "✅ NATIVE")) |")
        lines.append("| **Encoder Signature** | \(analysis.forensic.encoder ?? "Unknown") |")
        lines.append("| **Provenance** | \(analysis.forensic.sourceURL ?? "Local/Untracked") |")
        lines.append("| **Verified Signature** | \(analysis.forensic.isVerified ? "✅ MATCH" : "❓ NO SIGNATURE") |")
        lines.append("")
        
        // --- 6. STRUCTURE ---
        lines.append("## 🧩 6. Yapısal Segmentasyon")
        lines.append("| ID | START | END | LABEL |")
        lines.append("| :-- | :--- | :--- | :--- |")
        for seg in analysis.segments {
            lines.append("| \(seg.id) | \(formatTime(seg.start)) | \(formatTime(seg.end)) | **\(seg.label)** |")
        }
        lines.append("")
        
        return lines.joined(separator: "\n")
    }
    
    private static func formatTime(_ sec: Double) -> String {
        let m = Int(sec) / 60
        let s = Int(sec) % 60
        return String(format: "%d:%02d", m, s)
    }
}
