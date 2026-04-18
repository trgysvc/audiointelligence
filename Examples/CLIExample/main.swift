import Foundation
import AudioIntelligence

@main
struct CLIExample {
    static func main() async {
        print("🎙️ AudioIntelligence: Initializing Analysis...")
        
        let intelligence = AudioIntelligence(device: .automatic, mode: .balanced)
        
        // Using a mock URL for the "Hello World"
        let mockURL = URL(fileURLWithPath: "/tmp/sample_song.wav")
        
        do {
            let features: Set<AudioFeature> = [.rhythm, .forensic]
            let report = try await intelligence.analyze(
                url: mockURL,
                features: features
            )
            
            print("\n✅ Analysis Complete:")
            print("-------------------------")
            print("Summary: \(report.summary)")
            
            // v28.0 Infinity Access
            print("BPM: \(report.rawAnalysis.rhythm.bpm)")
            print("Encoder: \(report.rawAnalysis.forensic.encoder ?? "Unknown")")
            print("Loudness: \(report.rawAnalysis.mastering.integratedLUFS) LUFS")
            print("-------------------------")
            
        } catch {
            print("❌ Error during analysis: \(error)")
        }
    }
}
