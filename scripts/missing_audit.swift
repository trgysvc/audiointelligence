import Foundation
import AudioIntelligenceCore

@main
struct MissingAudit {
    static func main() async {
        let filePath = "/Users/trgysvc/Music/Music/Media.localized/Music/Sebas cuba/Ruben Gonzalez - Mandinga improvisacion/Ruben Gonzalez - Mandinga improvisacion.mp3"
        let url = URL(fileURLWithPath: filePath)
        
        print("🧱 Executing RECOVERY Audit (Unabridged Science)...")
        
        do {
            let buffer = try await AudioLoader.load(url: url)
            let stftEngine = STFTEngine(nFFT: 2048, hopLength: 512, sampleRate: buffer.sampleRate)
            let stft = await stftEngine.analyze(buffer.samples)
            
            // 1. Forensic
            print("⏳ Running Forensic Audit...")
            let forensic = await ForensicEngine().analyze(samples: buffer.samples, magnitude: stft.magnitude, nFrames: stft.nFrames, nFFT: 2048, sampleRate: buffer.sampleRate)
            print("RESULT_FORENSIC: BitDepth=\(forensic.trueBitDepth), Entropy=\(forensic.entropyScore), Clipping=\(forensic.clippingEvents)")

            // 2. Audio Science
            print("⏳ Running Audio Science...")
            let science = await AudioScienceEngine(sampleRate: buffer.sampleRate).analyze(samples: buffer.samples)
            print("RESULT_SCIENCE: SNR=\(science.snr), THD=\(science.thdPlusN), DynRange=\(science.dynamicRangeAES17)")

            // 3. Advanced MIR
            print("⏳ Running Tonnetz & Tempogram...")
            let chroma = await ChromaEngine(nFFT: 2048, sampleRate: buffer.sampleRate).chromagram(stft: stft)
            let tonnetz = await TonnetzEngine().compute(chromagram: chroma)
            let onsetRes = await OnsetEngine(sampleRate: buffer.sampleRate).onsetStrength(buffer.samples)
            let tempogram = await TempogramEngine().computeACT(onsetStrength: onsetRes.envelope)
            print("RESULT_MIR: TonnetzComplete, TempogramComplete")

            // 4. NMF (Run alone to avoid timeout)
            print("⏳ Running NMF (Full 50 Iterations)...")
            let nmf = await NMFEngine(nComponents: 2, maxIter: 50).decompose(stft: stft)
            let nmfEnergy = nmf.H.map { $0.reduce(0, +) / Float($0.count) }
            print("RESULT_NMF: Energy=\(nmfEnergy)")

            print("✅ RECOVERY COMPLETE")
            
        } catch {
            print("❌ Hata: \(error.localizedDescription)")
        }
    }
}
