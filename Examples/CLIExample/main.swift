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
            print("File: \(report.metadata.fileName)")

            // Estimation (statistical) vs Measurement (validated)
            let tempo = report.estimations.tempo
            print("BPM (estimate, \(Int(tempo.confidence * 100))% conf): \(String(format: "%.1f", tempo.value))")
            print("Encoder: \(report.metadata.encoder ?? "Unknown")")
            let lufs = report.measurements.loudness.integrated
            print("Loudness: \(String(format: "%.1f", lufs.value)) LUFS (\(lufs.standard?.rawValue ?? "—"))")
            print("-------------------------")
            
        } catch {
            print("❌ Error during analysis: \(error)")
        }
    }
}
