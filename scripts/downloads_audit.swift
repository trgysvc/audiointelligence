import Foundation
import AudioIntelligenceCore

@main
struct DownloadsAudit {
    static func main() async {
        let filePath = "/Users/trgysvc/Downloads/Ruben Gonzalez - Mandinga improvisacion.mp3"
        let url = URL(fileURLWithPath: filePath)
        
        let builder = DNAReportBuilder()
        
        print("🔭 Starting UNABRIDGED DOWNLOADS AUDIT...")
        print("📂 Source: \(filePath)")
        print("📜 Standards: Scientific Validation v6.3.0")
        print("---------------------------------------------------------")
        
        do {
            let (analysis, report, mdPath) = try await builder.analyze(url: url) { progress, status, _ in
                print("[\(Int(progress))%] \(status)")
            }
            
            print("\n✅ ANALYSIS COMPLETE!")
            print("📄 Report saved to: \(mdPath)")
            print("---------------------------------------------------------")
            print("Loudness: \(analysis.mastering.integratedLUFS) LUFS")
            print("Key: \(analysis.tonality.key)")
            print("Bit Depth: \(analysis.forensic.effectiveBits)-bit")
            print("AES17 SNR: \(analysis.science.snr) dB")
            print("---------------------------------------------------------")
            
        } catch {
            print("❌ Hata: \(error.localizedDescription)")
        }
    }
}
