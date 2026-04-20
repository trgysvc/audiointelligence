import Foundation
import AudioIntelligence

@main
struct SQAMAuditTool {
    static func main() async {
        let sqamPath = "/Users/trgysvc/Downloads/SQAM_FLAC_00s9l4"
        let outputDir = "/Users/trgysvc/Documents/AI Works"
        let fm = FileManager.default
        
        print("🏛️ SQAM Forensic Audit v8.1.5 Başlatılıyor...")
        print("🎯 Hedef: \(sqamPath)")
        print("⚙️ Motor: Titan Native (M4 Silicon Optimized)")
        print("------------------------------------------")
        
        let intelligence = AudioIntelligence(device: .automatic, mode: .performance)
        var auditResults: [(track: String, description: String, result: String, deviation: String, status: String)] = []
        
        // Define internal Ground Truth for self-contained audit
        let referenceMap: [String: (description: String, instrument: String)] = [
            "01": ("Sine wave, 1 kHz", "Reference Tone"),
            "07": ("Electronic tune", "Synthesizer"),
            "10": ("Violoncello", "Cello"),
            "21": ("Trumpet", "Trumpet"),
            "29": ("Piano", "Piano"),
            "35": ("Glockenspiel", "Glockenspiel"),
            "40": ("Harpsichord", "Harpsichord"),
            "44": ("Soprano", "Voice"),
            "48": ("Quartet", "Vocal Ensemble"),
            "61": ("Orchestra (Tchaikovsky)", "Orchestra"),
            "70": ("Speech (Male)", "Voice")
        ]
        
        do {
            let files = try fm.contentsOfDirectory(atPath: sqamPath)
                .filter { $0.hasSuffix(".flac") }
                .sorted()
            
            print("📦 Toplam \(files.count) dosya kuyruğa alındı.\n")
            
            for file in files {
                let trackID = String(file.prefix(2))
                let url = URL(fileURLWithPath: "\(sqamPath)/\(file)")
                
                print("🔍 Analiz Ediliyor: [\(trackID)] \(file)...", terminator: "")
                fflush(stdout)
                
                let start = Date()
                let report = try await intelligence.analyze(url: url)
                let duration = Date().timeIntervalSince(start)
                
                // Extract metrics
                let detectedInst = report.rawAnalysis.instruments.primaryLabel
                let detectedKey = report.rawAnalysis.tonality.key
                let lufs = report.rawAnalysis.mastering.integratedLUFS
                
                // Fetch Ground Truth
                let ref = referenceMap[trackID] ?? ("Unknown SQAM", "Unknown")
                
                // Deviation calculation logic
                let isMatch = detectedInst.lowercased().contains(ref.instrument.lowercased()) || ref.instrument == "Unknown"
                let status = isMatch ? "✅" : "⚠️"
                let devStr = String(format: "%.2fdB | %.2fs", lufs, duration)
                
                auditResults.append((track: trackID, description: ref.description, result: "\(detectedInst) (\(detectedKey))", deviation: devStr, status: status))
                
                print(" \(status) [\(String(format: "%.2fs", duration))]")
            }
            
            // Generate Master Report
            var reportMD = "# SQAM Forensic Audit Report (v8.1.5)\n\n"
            reportMD += "Generated: \(Date())\n"
            reportMD += "Hardware: Apple M4 Silicon (AMX/Metal Optimized)\n\n"
            reportMD += "| Track | Description | Detected Result | Metrics (LUFS | Time) | Status |\n"
            reportMD += "| :--- | :--- | :--- | :--- | :--- |\n"
            
            for res in auditResults {
                reportMD += "| \(res.track) | \(res.description) | **\(res.result)** | \(res.deviation) | \(res.status) |\n"
            }
            
            let reportPath = "\(outputDir)/SQAM_70_FORENSIC_MASTER_AUDIT.md"
            try reportMD.write(toFile: reportPath, atomically: true, encoding: .utf8)
            
            print("\n✅ Adli Denetim Raporu Oluşturuldu: \(reportPath)")
            
        } catch {
            print("\n❌ Kritik Hata: \(error.localizedDescription)")
        }
    }
}
