import Foundation
import AudioIntelligence

@main
struct CLIExample {
    static func main() async {
        print("🎙️ AudioIntelligence: Initializing Analysis...")

        let intelligence = AudioIntelligence(device: .automatic, mode: .balanced)

        let path = CommandLine.arguments.count > 1
            ? CommandLine.arguments[1]
            : "/tmp/sample_song.wav"
        let url = URL(fileURLWithPath: path)

        do {
            // Full feature set → exercises every engine (matches the app path).
            // The library streams progress to the consumer via this closure; the app
            // decides how to surface it (here: a live, single-line percentage bar).
            let report = try await intelligence.analyze(url: url) { percent, message, detail in
                let p = max(0, min(100, percent))
                let filled = Int(p / 5)                       // 20-cell bar
                let bar = String(repeating: "█", count: filled)
                        + String(repeating: "░", count: 20 - filled)
                var line = "\r[\(bar)] \(String(format: "%5.1f", p))%  \(message)"
                if let detail, !detail.isEmpty { line += " — \(detail)" }
                // Pad to clear any longer previous line, stay on the same terminal row.
                FileHandle.standardError.write(Data((line + String(repeating: " ", count: 12)).utf8))
            }
            FileHandle.standardError.write(Data("\n".utf8))   // close the progress line

            print("\n✅ Analysis Complete:")
            print("=========================")
            print("File: \(report.metadata.fileName)")
            print("Duration: \(String(format: "%.1f", report.metadata.durationSeconds))s  •  SR: \(Int(report.metadata.sampleRate)) Hz  •  ch: \(report.metadata.channelCount)")
            print("=========================")

            // ---- Estimations -------------------------------------------------
            let tempo = report.estimations.tempo
            let key   = report.estimations.key
            let ts    = report.estimations.timeSignature
            print("BPM:           \(String(format: "%.1f", tempo.value))  (conf \(pct(tempo.confidence)))")
            print("Key:           \(key.value)  (conf \(pct(key.confidence)))")
            print("Time sig:      \(ts.value)  (conf \(pct(ts.confidence)))   ← Bug 3")

            // ---- Fidelity (lab metrics) -------------------------------------
            let thd = report.measurements.fidelity.thdPlusN
            let imd = report.measurements.fidelity.imd
            print("THD+N:         \(String(format: "%.4f", thd.value))%  validated=\(thd.validated)   ← Bug 2")
            print("IMD:           \(String(format: "%.4f", imd.value))%  validated=\(imd.validated)   ← Bug 2")
            print("  (NaN check)  thd.isNaN=\(thd.value.isNaN)  imd.isNaN=\(imd.value.isNaN)")

            // ---- Waveform peaks ---------------------------------------------
            let peaks = report.features?.waveformPeaks ?? []
            let pk = peaks.max() ?? 0
            print("waveformPeaks: \(peaks.count) points, max=\(String(format: "%.3f", pk))   ← Bug 1")

            // ---- Persist (CONSUMER responsibility, not the library's) -------
            // The library only hands back encoded `Data` via jsonData()/plistData();
            // writing to disk is this example app's job, never the library's.
            let baseName = url.deletingPathExtension().lastPathComponent
            let outDir = url.deletingLastPathComponent()

            let jsonData = try report.jsonData(prettyPrinted: true)
            let jsonURL = outDir.appendingPathComponent("\(baseName).report.json")
            try jsonData.write(to: jsonURL)

            let plistData = try report.plistData()
            let plistURL = outDir.appendingPathComponent("\(baseName).report.plist")
            try plistData.write(to: plistURL)

            print("JSON  → \(jsonURL.path) (\(jsonData.count) bytes)")
            print("plist → \(plistURL.path) (\(plistData.count) bytes)")
            print("(serialization succeeded — no NaN propagation)")
            print("=========================")

        } catch {
            print("❌ Error during analysis: \(error)")
        }
    }

    static func pct(_ x: Double) -> String { "\(Int((x * 100).rounded()))%" }
}
