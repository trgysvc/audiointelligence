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
        
        let filePath = args[1]
        let url = URL(fileURLWithPath: filePath)
        
        print("🚀 Infinity Audit Başlatılıyor...")
        print("📂 Dosya: \(url.lastPathComponent)")
        print("⚙️ Motor: Titan Native (v4.1)")
        print("------------------------------------------")
        
        let intelligence = AudioIntelligence(device: .current, mode: .ultra)
        
        do {
            let result = try await intelligence.analyze(url: url) { percent, message, _ in
                let barWidth = 30
                let filled = Int(percent * Double(barWidth))
                let bar = String(repeating: "█", count: filled) + String(repeating: "░", count: barWidth - filled)
                print("\r[\(bar)] \(Int(percent * 100))% | \(message)", terminator: "")
                fflush(stdout)
            }
            
            print("\n\n✅ Analiz Tamamlandı!")
            print("------------------------------------------")
            print("📝 Rapor Oluşturuldu: \(result.reportPath)")
            print("📊 Özet: \(result.summary)")
            print("\n--- RAPOR ÖNİZLEME ---\n")
            print(result.reportText)
            
        } catch {
            print("\n❌ Analiz sırasında hata oluştu: \(error.localizedDescription)")
        }
    }
}
