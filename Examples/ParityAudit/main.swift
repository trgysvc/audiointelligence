import Foundation
import AudioIntelligence
import AudioIntelligenceCore

@main
struct ParityAudit {
    static func main() async {
        let args = ProcessInfo.processInfo.arguments
        guard args.count > 2 else {
            print("❌ Hata: Lütfen sonuç dosyasını ve referans dosyasını belirtin.")
            print("Kullanım: swift run ParityAudit result.json reference_librosa.json")
            return
        }
        
        let resultPath = args[1]
        let referencePath = args[2]
        
        do {
            let resultData = try Data(contentsOf: URL(fileURLWithPath: resultPath))
            let referenceData = try Data(contentsOf: URL(fileURLWithPath: referencePath))
            
            let decoder = JSONDecoder()
            let result = try decoder.decode(MusicDNAAnalysis.self, from: resultData)
            // Note: In a real scenario, we'd decode reference into a common structure.
            // For now, let's assume the user provides a simplified reference JSON.
            let refDict = try JSONSerialization.jsonObject(with: referenceData) as? [String: Any]
            
            print("📊 Starting Scientific Parity Audit...")
            print("------------------------------------------")
            
            // 1. BPM Accuracy
            if let refBPM = refDict?["bpm"] as? Double {
                let diff = abs(Double(result.rhythm.bpm) - refBPM)
                let accuracy = max(0, 100 - (diff / refBPM) * 100)
                print("🥁 Tempo (BPM): Result: \(result.rhythm.bpm) | Ref: \(refBPM)")
                print("   Accuracy: \(accuracy.formatted(.number.precision(.fractionLength(2))))% [MAE: \(diff.formatted())]")
            }
            
            // 2. Pitch Mean Accuracy
            if let refPitch = refDict?["mean_f0"] as? Double {
                let diff = abs(Double(result.pitch.meanF0) - refPitch)
                let accuracy = max(0, 100 - (diff / refPitch) * 100)
                print("🎙️ Pitch (Hz): Result: \(result.pitch.meanF0) | Ref: \(refPitch)")
                print("   Accuracy: \(accuracy.formatted(.number.precision(.fractionLength(2))))% [MAE: \(diff.formatted())]")
            }
            
            // 3. Spectral Centroid
            if let refCentroid = refDict?["centroid"] as? Double {
                let diff = abs(Double(result.spectral.centroid) - refCentroid)
                print("🧪 Spectral Centroid: Result: \(result.spectral.centroid) | Ref: \(refCentroid)")
                print("   MAE: \(diff.formatted()) Hz")
            }
            
            print("------------------------------------------")
            print("✅ Parity Audit Complete.")
            
        } catch {
            print("❌ Hata: \(error.localizedDescription)")
        }
    }
}
