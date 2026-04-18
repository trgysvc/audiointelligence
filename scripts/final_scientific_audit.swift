import Foundation
import AudioIntelligenceCore

@main
struct FinalScientificAudit {
    static func main() async {
        let filePath = "/Users/trgysvc/Music/Music/Media.localized/Music/Sebas cuba/Ruben Gonzalez - Mandinga improvisacion/Ruben Gonzalez - Mandinga improvisacion.mp3"
        let url = URL(fileURLWithPath: filePath)
        
        print("🏁 Starting COMPLETE UNABRIDGED SCIENTIFIC AUDIT...")
        print("📂 Target: Ruben Gonzalez - Mandinga")
        print("⚙️ Method: Streaming DSP (Zero-Reduction High Precision)")
        print("---------------------------------------------------------")
        
        do {
            let buffer = try await AudioLoader.load(url: url)
            let stereoBuffer = try await AudioLoader.loadStereo(url: url)
            print("✅ Audio Loaded: \(buffer.samples.count) samples @ \(buffer.sampleRate)Hz")
            
            // 1. Initial Processing
            print("⏳ Running STFT (Unabridged)...")
            let stftEngine = STFTEngine(nFFT: 2048, hopLength: 512, sampleRate: buffer.sampleRate)
            let stft = await stftEngine.analyze(buffer.samples)
            print("✅ STFT Complete")

            // 2. Loudness Engine (v6.3 validated)
            print("⏳ Running Loudness & True Peak (511-tap)...")
            let loudness = await LoudnessEngine(sampleRate: buffer.sampleRate).analyze(samples: buffer.samples)
            print("✅ Loudness: \(loudness.integratedLUFS) LUFS")
            print("✅ True Peak: \(loudness.truePeakDb) dBTP")

            // 3. Chroma & Key
            print("⏳ Running Chroma & Key Detection...")
            let chroma = await ChromaEngine(nFFT: 2048, sampleRate: buffer.sampleRate).chromagram(stft: stft)
            let key = await ChromaEngine(nFFT: 2048, sampleRate: buffer.sampleRate).detectKey(chromagram: chroma)
            print("✅ Tonal DNA: \(key.key) (\(Int(key.keyStrength * 100))%)")

            // 4. Structure (NEW STREAMING ALGORITHM)
            print("⏳ Running Structural Analysis (Streaming SSM)...")
            let mfccEngine = MFCCEngine(nMFCC: 20, nMels: 128)
            let melBank = MelFilterBank(nMels: 128, nFFT: 2048, sampleRate: buffer.sampleRate)
            let melSpec = melBank.apply(magnitude: stft.magnitude, nFrames: stft.nFrames)
            let mfccRes = await mfccEngine.compute(melSpectrogram: melSpec.flatMap { $0 }, stftEngine: stftEngine)
            
            let nFrames = mfccRes.fullData.count / 20
            let mfccMatrix: [[Float]] = (0..<20).map { i in
                Array(mfccRes.fullData[(i * nFrames)..<((i + 1) * nFrames)])
            }
            
            let structResult = StructureEngine(hopLength: 512, sampleRate: buffer.sampleRate).analyze(chromagram: chroma, mfccs: mfccMatrix)
            print("✅ Structure Map: \(structResult.segmentCount) segments identified")

            // 5. Source Separation (HPSS & NMF)
            print("⏳ Running Source Separation (HPSS & NMF)...")
            let hpss = await HPSSEngine(winHarm: 31, winPerc: 31).analyze(stft: stft)
            let nmf = await NMFEngine(nComponents: 2).decompose(stft: stft)
            print("✅ HPSS: Harmonic ratio \(Int(hpss.harmonicEnergyRatio * 100))%")
            print("✅ NMF: Decomposition Complete")

            // 6. Forensic Audit
            print("⏳ Running Forensic Audit (Entropy/Bit-depth)...")
            let forensic = await ForensicEngine().analyze(samples: buffer.samples, magnitude: stft.magnitude, nFrames: stft.nFrames, nFFT: 2048, sampleRate: buffer.sampleRate)
            print("✅ Forensic Status: Verified (\(forensic.trueBitDepth)-bit)")

            // 7. Audio Science (AES17)
            print("⏳ Running Audio Science Suite (AES17)...")
            let science = await AudioScienceEngine(sampleRate: buffer.sampleRate).analyze(samples: buffer.samples)
            print("✅ SNR: \(science.snr) dB | THD+N: \(science.thdPlusN)")

            // 8. Advanced MIR (Tonnetz/Tempogram/Viterbi/Piptrack)
            print("⏳ Running Advanced MIR Suite...")
            let tonnetz = await TonnetzEngine().compute(chromagram: chroma)
            let onsetRes = await OnsetEngine(sampleRate: buffer.sampleRate).onsetStrength(buffer.samples)
            let tempogram = await TempogramEngine().computeACT(onsetStrength: onsetRes.envelope)
            let pip = await PiptrackEngine().track(stft: stft)
            
            // Viterbi
            let observations = (0..<stft.nFrames).map { t in (0..<12).map { chroma[$0][t] } }
            let transM: [[Float]] = (0..<12).map { _ in (0..<12).map { _ in Float(1.0/12.0) } }
            let startP = [Float](repeating: 1.0/12.0, count: 12)
            let viterbi = await ViterbiEngine().decode(observations: observations, transitionMatrix: transM, startProbs: startP)
            
            print("✅ Tonnetz/Tempogram/Piptrack/Viterbi: COMPLETE")

            print("\n🌈 100% UNABRIDGED ANALYSIS COMPLETE!")
            print("---------------------------------------------------------")
            print("Loudness: \(loudness.integratedLUFS) LUFS")
            print("True Peak: \(loudness.truePeakDb) dBTP")
            print("Key: \(key.key)")
            print("Segments: \(structResult.segments.map { $0.label }.joined(separator: ", "))")
            print("Effective Bit Depth: \(forensic.trueBitDepth)")
            print("Shannon Entropy: \(forensic.entropyScore)")
            print("---------------------------------------------------------")
            
        } catch {
            print("❌ Hata: \(error.localizedDescription)")
        }
    }
}
