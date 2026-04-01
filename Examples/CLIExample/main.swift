import Foundation
import AudioIntelligence

@main
struct CLIExample {
    static func main() async {
        print("🎙️ AudioIntelligence: Initializing Analysis...")
        
        let intelligence = AudioIntelligence(device: .current, mode: .balanced)
        
        // Using a mock URL for the "Hello World"
        let mockURL = URL(fileURLWithPath: "/tmp/sample_song.wav")
        
        do {
            let report = try await intelligence.analyze(
                url: mockURL,
                features: [.rhythm, .forensic]
            )
            
            print("\n✅ Analysis Complete:")
            print("-------------------------")
            print("Summary: \(report.summary)")
            
            if let bpm = report.rhythm?.bpm {
                print("BPM: \(bpm)")
            }
            
            if let forensic = report.forensic {
                print("Encoder: \(forensic.encoderName)")
            }
            print("-------------------------")
            
        } catch {
            print("❌ Error during analysis: \(error)")
        }
    }
}
