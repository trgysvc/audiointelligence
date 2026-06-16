import Foundation
import AudioIntelligence

@main
struct InfinityAudit {
    static func main() async {
        let args = ProcessInfo.processInfo.arguments
        guard args.count > 1 else {
            print("❌ Hata: Lütfen bir ses dosyası yolu belirtin.")
            print("Kullanım: swift run -c release InfinityAudit \"/yol/dosya.mp3\"")
            return
        }
        
        var filePath = args[1]
        var selectedFeatures = Set(AudioFeature.allCases)
        
        if args.contains("--features") {
            if let index = args.firstIndex(of: "--features"), index + 1 < args.count {
                let featureNames = args[index + 1].lowercased().split(separator: ",")
                selectedFeatures = []
                for name in featureNames {
                    if let feat = AudioFeature(rawValue: String(name)) {
                        selectedFeatures.insert(feat)
                    }
                }
                // File path is usually the last or first non-flag arg
                if index == 1 { filePath = args[args.count - 1] }
            }
        }
        
        let url = URL(fileURLWithPath: filePath)
        
        print("🚀 Infinity Audit \(selectedFeatures.count == AudioFeature.allCases.count ? "Full" : "Modular") Audit Başlatılıyor...")
        print("📂 Dosya: \(url.lastPathComponent)")
        print("⚙️ Motor: Titan Native (v4.1)")
        print("🎯 Kapsam: \(selectedFeatures.map { $0.rawValue }.joined(separator: ", "))")
        print("------------------------------------------")
        
        let intelligence = AudioIntelligence(device: .automatic, mode: .performance)
        
        do {
            let result = try await intelligence.analyze(url: url, features: selectedFeatures) { percent, message, _ in
                let barWidth = 30
                let filled = max(0, min(barWidth, Int((percent / 100.0) * Double(barWidth))))
                let empty = max(0, barWidth - filled)
                let bar = String(repeating: "█", count: filled) + String(repeating: "░", count: empty)
                print("\r[\(bar)] \(Int(percent))% | \(message)", terminator: "")
                fflush(stdout)
            }
            
            print("\n\n✅ Analiz Tamamlandı!")
            print("------------------------------------------")
            
            // Hardware Telemetry
            let stats = await intelligence.getHardwareStats()
            print("🔥 Donanım Telemetrisi:")
            print("   - İvmelendirme: \(stats.acceleration)")
            print("   - Aktif Çekirdekler: \(stats.activeThreads) Thread")
            print("   - Önbellek Kullanımı: \(stats.cacheUsageMB) MB")
            
            print("------------------------------------------")

            // The library returns *data*; the caller renders & persists.
            let markdown = MarkdownRenderer.render(result)
            let outURL = url.deletingPathExtension().appendingPathExtension("md")
            try markdown.write(to: outURL, atomically: true, encoding: .utf8)
            // Machine-readable export (binary plist) alongside the markdown.
            let plistURL = url.deletingPathExtension().appendingPathExtension("plist")
            try result.plistData(includingFeatures: false).write(to: plistURL)

            print("📝 Markdown raporu yazıldı: \(outURL.path)")
            print("📦 Binary plist (özet) yazıldı: \(plistURL.path)")
            print("\n--- RAPOR ÖNİZLEME ---\n")
            print(markdown)
            
        } catch {
            print("\n❌ Analiz sırasında hata oluştu: \(error.localizedDescription)")
        }
    }
}
