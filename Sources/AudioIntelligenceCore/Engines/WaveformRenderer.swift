// WaveformRenderer.swift
// Elite Music DNA Engine — Phase 3
// Live console ASCII waveform + progress reporting

import Foundation

public enum WaveformRenderer {

    // MARK: ASCII Waveform

    /// Samples → ASCII waveform satırı. Unicode block characters.
    /// Çıktı: "0:30  ▁▂▃▅▆▇▇▆▅▄▃▂▁░░░░░░░░░░░░░"
    public static func renderLine(
        samples: [Float],
        startSec: Double,
        width: Int = 48
    ) -> String {
        let blocks = "░▁▂▃▄▅▆▇█"
        let n = samples.count
        let stride = max(1, n / width)

        var chars: [Character] = []
        for i in 0..<width {
            let lo = i * stride
            let hi = min(lo + stride, n)
            guard lo < n else { chars.append("░"); continue }

            let chunk = samples[lo..<hi]
            let rms = sqrt(chunk.map { $0 * $0 }.reduce(0, +) / Float(chunk.count))
            let level = min(8, Int(rms * 40))  // scale to 0..8
            chars.append(blocks[blocks.index(blocks.startIndex, offsetBy: level)])
        }

        let timeStr = formatTime(startSec)
        return "\(timeStr)  \(String(chars))"
    }

    /// Tüm parçanın waveform özeti (8 satır)
    public static func renderFull(samples: [Float], sampleRate: Double, lines: Int = 8) -> String {
        let totalSec = Double(samples.count) / sampleRate
        let duration = totalSec / Double(lines)
        var output: [String] = []

        for i in 0..<lines {
            let startSec = Double(i) * duration
            let startSample = Int(startSec * sampleRate)
            let endSample = min(Int((startSec + duration) * sampleRate), samples.count)
            guard startSample < endSample else { break }
            let chunk = Array(samples[startSample..<endSample])
            output.append(renderLine(samples: chunk, startSec: startSec))
        }

        return output.joined(separator: "\n")
    }

    // MARK: Progress Bar

    /// "[████████████████████░░░░] 80% — Spectral analiz..."
    public static func progressBar(percent: Double, message: String, width: Int = 24) -> String {
        let filled = Int(percent / 100.0 * Double(width))
        let empty = width - filled
        let bar = String(repeating: "█", count: max(0, filled)) +
                  String(repeating: "░", count: max(0, empty))
        let pctStr = String(format: "%3.0f%%", percent)
        return "[\(bar)] \(pctStr) — \(message)"
    }

    // MARK: Header Banner

    public static func header(filename: String) -> String {
        """
        ╔══════════════════════════════════════════════════════════════╗
        ║  🎵 EliteAgent — Music DNA Engine                            ║
        ║  Analyzing: \(filename.padding(toLength: 49, withPad: " ", startingAt: 0))║
        ╚══════════════════════════════════════════════════════════════╝
        """
    }

    // MARK: Final DNA Report

    public static func finalReport(
        filename: String,
        duration: Double,
        rhythm: (bpm: Float, gridStd: Double),
        key: String,
        spectral: (centroid: Float, rolloff: Float, bandwidth: Float, flatness: Float, zcr: Float),
        dynamics: (rmsMean: Float, rmsMax: Float, dynamicRangeDb: Float),
        hpss: (harmonic: Float, percussive: Float, characterization: String),
        chroma: [Float],
        mfcc: [Float],
        structure: [(id: Int, start: Double, end: Double, label: String)],
        outputMd: String?
    ) -> String {

        let noteNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]

        // Chroma histogram
        let maxChroma = chroma.max() ?? 1.0
        let chromaLines = (0..<12).sorted(by: { chroma[$0] > chroma[$1] }).prefix(8).map { i -> String in
            let bar = String(repeating: "█", count: Int(chroma[i] / maxChroma * 40))
            return "  \(noteNames[i].padding(toLength: 3, withPad: " ", startingAt: 0))  \(bar.padding(toLength: 42, withPad: " ", startingAt: 0)) \(String(format: "%.3f", chroma[i]))"
        }

        // Segment table
        let segLines = structure.map { seg -> String in
            let start = formatTime(seg.start)
            let end = formatTime(seg.end)
            return "  [\(start)-\(end)] Bölüm \(seg.id) — \(seg.label)"
        }

        let mfccStr = mfcc.prefix(8).map { String(format: "%.1f", $0) }.joined(separator: ", ")
        let charStr = hpss.characterization
        let harmPct = String(format: "%.0f%%", hpss.harmonic * 100)
        let percPct = String(format: "%.0f%%", hpss.percussive * 100)

        var lines: [String] = [
            "┌──────────────────────────────────────────────────────────────────┐",
            "│  🧬 MUSIC DNA REPORT                  \(filename.prefix(26).padding(toLength: 26, withPad: " ", startingAt: 0))│",
            "├──────────────────────────────────────────────────────────────────┤",
            "│  SÜRE: \(formatTime(duration))   SR: 22050 Hz                               │",
            "├──────────────────────────────────────────────────────────────────┤",
            "│  RİTİM                                                           │",
            "│  BPM: \(String(format: "%-8.1f", rhythm.bpm))  Beat Tutarlılığı: ±\(String(format: "%.3f", rhythm.gridStd))s               │",
            "├──────────────────────────────────────────────────────────────────┤",
            "│  TONALİTE → \(key.padding(toLength: 54, withPad: " ", startingAt: 0))│",
            "│  CHROMA PROFİLİ                                                  │",
        ] + chromaLines.map { "│ \($0.padding(toLength: 67, withPad: " ", startingAt: 0))│" } + [
            "├──────────────────────────────────────────────────────────────────┤",
            "│  SPEKTRAL ÖZELLİKLER                                             │",
            "│  Centroid: \(String(format: "%-6.0f", spectral.centroid)) Hz  Rolloff: \(String(format: "%-6.0f", spectral.rolloff)) Hz  Flatness: \(String(format: "%.3f", spectral.flatness))  │",
            "│  Bandwidth: \(String(format: "%-5.0f", spectral.bandwidth)) Hz  ZCR: \(String(format: "%.3f", spectral.zcr))                           │",
            "│  MFCC: [\(mfccStr.prefix(52))...]  │",
            "├──────────────────────────────────────────────────────────────────┤",
            "│  DİNAMİK                                                         │",
            "│  RMS: \(String(format: "%.3f", dynamics.rmsMean)) (peak: \(String(format: "%.3f", dynamics.rmsMax)))  Dinamik Aralık: \(String(format: "%.1f", dynamics.dynamicRangeDb)) dB          │",
            "├──────────────────────────────────────────────────────────────────┤",
            "│  HPSS — \(charStr.padding(toLength: 57, withPad: " ", startingAt: 0))│",
            "│  Harmonik: \(harmPct.padding(toLength: 4, withPad: " ", startingAt: 0))  Perküsif: \(percPct.padding(toLength: 4, withPad: " ", startingAt: 0))                              │",
            "├──────────────────────────────────────────────────────────────────┤",
            "│  YAPI — \(structure.count) BÖLÜM                                               │",
        ] + segLines.map { "│ \($0.padding(toLength: 67, withPad: " ", startingAt: 0))│" } + [
            "├──────────────────────────────────────────────────────────────────┤",
        ]

        if let md = outputMd {
            lines.append("│  📄 \(md.prefix(63).padding(toLength: 63, withPad: " ", startingAt: 0))│")
        }

        lines.append("└──────────────────────────────────────────────────────────────────┘")
        return lines.joined(separator: "\n")
    }

    // MARK: Helpers

    private static func formatTime(_ sec: Double) -> String {
        let m = Int(sec) / 60
        let s = Int(sec) % 60
        return String(format: "%d:%02d", m, s)
    }
}
