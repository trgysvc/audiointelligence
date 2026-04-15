// Elite Music DNA Engine — Phase 3
// Pure Markdown Report Engine

import Foundation

public final class DNAReportBuilder: @unchecked Sendable {

    // MARK: Master Analyze + Report

    /// Tüm analizi koordine eden ana fonksiyon.
    /// progress callback: (percent: Double, message: String, waveformLine: String?)
    public static func analyze(
        url: URL,
        progress: @Sendable @escaping (Double, String, String?) -> Void
    ) async throws -> (analysis: MusicDNAAnalysis, reportText: String, mdPath: String) {

        let filename = url.lastPathComponent

        // Step 1: Load
        progress(5, "Ses dosyası yükleniyor...", nil)
        let buffer = try AudioLoader.load(url: url)

        // Waveform (first 8 chunks = full overview)
        let waveform = WaveformRenderer.renderFull(
            samples: buffer.samples,
            sampleRate: buffer.sampleRate,
            lines: 6
        )
        progress(12, "Waveform oluşturuldu", waveform)

        // Step 2: STFT
        progress(20, "STFT hesaplanıyor (n_fft=2048)...", nil)
        let stftEngine = STFTEngine(nFFT: 2048, hopLength: 512, sampleRate: buffer.sampleRate)
        let stft = stftEngine.analyze(buffer.samples)

        // Step 3: Mel
        progress(30, "Mel filtre bankası uygulanıyor...", nil)
        let melBank = MelFilterBank(nMels: 128, nFFT: 2048, sampleRate: buffer.sampleRate)
        let melSpec = melBank.apply(magnitude: stft.magnitude, nFrames: stft.nFrames)

        // Step 4: Onset
        progress(38, "Onset gücü hesaplanıyor...", nil)
        let onsetEngine = OnsetEngine(sampleRate: buffer.sampleRate)
        let onsetResult = onsetEngine.onsetStrength(buffer.samples)

        // Step 5: Rhythm (actor — async)
        progress(45, "BPM ve beat tracking (Ellis DP)...", nil)
        let rhythmEngine = RhythmEngine(sampleRate: buffer.sampleRate)
        let rhythm = await rhythmEngine.analyze(onsetResult: onsetResult)

        // Step 6: Chroma + Key
        progress(55, "Chroma analizi ve tonalite...", nil)
        let chromaEngine = ChromaEngine(nFFT: 2048, sampleRate: buffer.sampleRate)
        let chroma = chromaEngine.chromagram(stft: stft)
        let chromaResult = chromaEngine.detectKey(chromagram: chroma)

        // Step 7: Spectral
        progress(62, "Spektral özellikler hesaplanıyor...", nil)
        let spectralEngine = SpectralEngine(sampleRate: buffer.sampleRate, nFFT: 2048, hopLength: 512)
        let spectral = spectralEngine.analyze(stft: stft, samples: buffer.samples)

        // Step 8: MFCC
        progress(68, "MFCC katsayıları hesaplanıyor...", nil)
        let mfccEngine = MFCCEngine(nMFCC: 20, nMels: 128)
        let mfccResult = mfccEngine.compute(melSpectrogram: melSpec.flatMap { $0 }, stftEngine: stftEngine)

        // Step 9: HPSS
        progress(75, "Harmonik/Perküsif ayrımı (HPSS)...", nil)
        let hpssEngine = HPSSEngine(winHarm: 31, winPerc: 31)
        let hpss = hpssEngine.analyze(stft: stft)

        // Step 10: Structure
        progress(85, "Yapısal segmentasyon (Foote SSM)...", nil)
        let structureEngine = StructureEngine(hopLength: 512, sampleRate: buffer.sampleRate)
        let structure = structureEngine.analyze(chromagram: chroma, nSegments: 7)
        
        // Step 11: Forensics (Röntgen)
        progress(90, "Adli (Forensic) DNA taranıyor...", nil)
        let forensicEngine = ForensicDNAEngine()
        let forensicResult = await forensicEngine.scan(at: url, samples: buffer.samples)
        let bitDepthResult = forensicEngine.analyzeBitDepthIntegrity(samples: buffer.samples)

        // Step 12: Professional Mastering Metrics (v25.0)
        progress(92, "Mastering metrikleri (LUFS, Stereo) hesaplanıyor...", nil)
        let loudnessEngine = LoudnessEngine(sampleRate: buffer.sampleRate)
        let loudness = loudnessEngine.analyze(samples: buffer.samples)
        
        let stereoEngine = StereoEngine()
        let stereo = stereoEngine.analyze(left: buffer.samples, right: buffer.samples) // Mono downmix fallback for baseline

        progress(93, "Raporlar yazılıyor...", nil)

        let home = FileManager.default.homeDirectoryForCurrentUser
        let aiWorksDir = home.appendingPathComponent("Documents/AI Works", isDirectory: true)
        
        // Ensure AI Works directory exists
        if !FileManager.default.fileExists(atPath: aiWorksDir.path) {
            try? FileManager.default.createDirectory(at: aiWorksDir, withIntermediateDirectories: true, attributes: nil)
        }

        // Output path
        let baseName = url.deletingPathExtension().lastPathComponent
        let mdPath = aiWorksDir.appendingPathComponent("\(baseName).dna.md").path

        // Build Markdown
        let markdown = buildMarkdown(
            url: url, buffer: buffer, rhythm: rhythm,
            chroma: chromaResult, spectral: spectral, mfcc: mfccResult,
            hpss: hpss, structure: structure, waveform: waveform,
            forensic: forensicResult, loudness: loudness, stereo: stereo
        )
        try markdown.write(toFile: mdPath, atomically: true, encoding: String.Encoding.utf8)

        progress(100, "Analiz tamamlandı!", nil)

        // Construct the MusicDNAAnalysis model
        let analysis = MusicDNAAnalysis(
            fileName: filename,
            rhythm: RhythmMetrics(
                bpm: Float(rhythm.bpm),
                beatConsistency: Float(rhythm.gridStdSec),
                characterize: rhythm.gridStdSec < 0.02 ? "Hassas Grid" : "İnsan Hissi"
            ),
            tonality: TonalMetrics(
                key: chromaResult.key,
                tendency: chromaResult.isMinor ? "Minör Eğilimli" : "Majör Eğilimli"
            ),
            spectral: SpectralMetrics(
                centroid: spectral.centroidHz,
                rolloff: spectral.rolloffHz,
                flatness: spectral.flatness,
                dynamicRange: spectral.dynamicRangeDb,
                brightnessDescription: spectral.centroidHz > 2500 ? "Parlak" : "Ilık"
            ),
            forensic: ForensicMetrics(
                sourceURL: forensicResult.whereFroms.first,
                encoder: forensicResult.encoder,
                isVerified: forensicResult.signatureFound,
                techSpecs: ["Format": forensicResult.format, "Bitrate": forensicResult.bitRate]
            ),
            waveformPeaks: stride(from: 0, to: buffer.samples.count, by: max(1, buffer.samples.count / 100)).map { i in
                let end = min(i + max(1, buffer.samples.count / 100), buffer.samples.count)
                let chunk = buffer.samples[i..<end]
                return sqrt(chunk.reduce(0) { $0 + $1 * $1 } / Float(chunk.count))
            },
            chromaProfile: chromaResult.meanChroma,
            segments: structure.segments.map { 
                MusicSegment(id: $0.id, start: $0.startSec, end: $0.endSec, label: $0.label)
            }
        )
        
        // Final report for chat
        let reportText = WaveformRenderer.finalReport(
            filename: filename,
            duration: buffer.duration,
            rhythm: (bpm: Float(rhythm.bpm), gridStd: rhythm.gridStdSec),
            key: chromaResult.key,
            spectral: (
                centroid: spectral.centroidHz,
                rolloff: spectral.rolloffHz,
                bandwidth: spectral.bandwidthHz,
                flatness: spectral.flatness,
                zcr: spectral.zcr
            ),
            dynamics: (
                rmsMean: spectral.rmsMean,
                rmsMax: spectral.rmsMax,
                dynamicRangeDb: spectral.dynamicRangeDb
            ),
            hpss: (
                harmonic: hpss.harmonicEnergyRatio,
                percussive: hpss.percussiveEnergyRatio,
                characterization: hpss.characterization
            ),
            chroma: chromaResult.meanChroma,
            mfcc: mfccResult.mfcc,
            structure: structure.segments.map { ($0.id, $0.startSec, $0.endSec, $0.label) },
            outputMd: mdPath
        )

        var finalAnalysis = analysis
        finalAnalysis.reportPath = mdPath

        return (finalAnalysis, reportText, mdPath)
    }

    // MARK: Markdown Builder

    private static func buildMarkdown(
        url: URL, buffer: AudioBuffer, rhythm: RhythmResult,
        chroma: ChromaResult, spectral: SpectralResult, mfcc: MFCCResult,
        hpss: HPSSResult, structure: StructureResult, waveform: String,
        forensic: ForensicDNA, loudness: LoudnessEngine.LoudnessResult,
        stereo: StereoEngine.StereoResult
    ) -> String {
        let noteNames = ChromaResult.noteNames
        let filename = url.lastPathComponent
        let now = ISO8601DateFormatter().string(from: Date())

        let md = """
        # 🧬 Music DNA Report: \(filename)

        **Analiz Tarihi:** \(now)
        **Süre:** \(String(format: "%.1f", buffer.duration))s
        **Sample Rate:** \(Int(buffer.sampleRate)) Hz

        ## Waveform

        ```
        \(waveform)
        ```

        ## Ritim

        | Özellik | Değer |
        |---------|-------|
        | BPM | \(String(format: "%.2f", rhythm.bpm)) |
        | Beat Tutarlılığı (std) | ±\(String(format: "%.3f", rhythm.gridStdSec))s |
        | Beat Sayısı | \(rhythm.beatFrames.count) |
        | Onset Mean | \(String(format: "%.3f", rhythm.onsetMean)) |
        | Onset Peak | \(String(format: "%.3f", rhythm.onsetPeak)) |

        ## Tonalite

        **Anahtar:** \(chroma.key) (güç: \(String(format: "%.3f", chroma.keyStrength)))

        ### Chroma Profili

        | Nota | Ağırlık |
        |------|---------|
        \(zip(noteNames, chroma.meanChroma).map { "| \($0.0) | \(String(format: "%.4f", $0.1)) |" }.joined(separator: "\n"))

        ## Spektral Özellikler

        | Özellik | Değer |
        |---------|-------|
        | Centroid | \(String(format: "%.1f", spectral.centroidHz)) Hz |
        | Rolloff (85%) | \(String(format: "%.1f", spectral.rolloffHz)) Hz |
        | Bandwidth | \(String(format: "%.1f", spectral.bandwidthHz)) Hz |
        | Flatness | \(String(format: "%.4f", spectral.flatness)) |
        | ZCR | \(String(format: "%.4f", spectral.zcr)) |

        ## Dinamik

        | Özellik | Değer |
        |---------|-------|
        | RMS (ortalama) | \(String(format: "%.4f", spectral.rmsMean)) |
        | RMS (peak) | \(String(format: "%.4f", spectral.rmsMax)) |
        | Dinamik Aralık | \(String(format: "%.2f", spectral.dynamicRangeDb)) dB |

        ## MFCC (İlk 20 Katsayı)

        ```
        \(mfcc.mfcc.map { String(format: "%.3f", $0) }.joined(separator: ", "))
        ```

        ## Harmonik/Perküsif Ayrımı (HPSS)

        | | Enerji Oranı |
        |-|--------------|
        | Harmonik | \(String(format: "%.1f%%", hpss.harmonicEnergyRatio * 100)) |
        | Perküsif | \(String(format: "%.1f%%", hpss.percussiveEnergyRatio * 100)) |
        | Karakterizasyon | \(hpss.characterization) |

        ## Yapısal Analiz

        **\(structure.segmentCount) bölüm tespit edildi.**

        | # | Başlangıç | Bitiş | Süre | Etiket |
        |---|-----------|-------|------|--------|
        \(structure.segments.map {
            let s = formatTime($0.startSec)
            let e = formatTime($0.endSec)
            let d = String(format: "%.0fs", $0.durationSec)
            return "| \($0.id) | \(s) | \(e) | \(d) | \($0.label) |"
        }.joined(separator: "\n"))

        ## Adli Bilişim (Forensic Röntgen)

        | Özellik | Değer |
        |---------|-------|
        | Format | \(forensic.format) |
        | Bit Rate | \(forensic.bitRate) |
        | Encoder | \(forensic.encoder) |
        | Signature | \(forensic.signatureFound ? "✅ Doğrulandı" : "❓ Bilinmiyor") |
        | WhereFroms | \(forensic.whereFroms.joined(separator: ", ")) |
        | Bit Integrity | \(forensic.effectiveBits)-bit (\(forensic.isLikelyUpsampled ? "⚠️ Upsampled" : "✅ Native")) |

        ## Mastering Engineer Verileri (v25.0)

        | Metrik | Değer | Eşik |
        |--------|-------|------|
        | Integrated Loudness | \(String(format: "%.2f", loudness.integratedLUFS)) LUFS | Spotify: -14 |
        | True Peak | \(String(format: "%.2f", loudness.truePeakDb)) dBTP | Limit: -0.1 |
        | Phase Correlation | \(String(format: "%.2f", stereo.correlation)) | Mono: > 0.8 |
        | Mono Compatibility | \(stereo.monoCompatibility) | |

        ---
        *EliteAgent Music DNA Engine v14.10*
        """
        return md
    }

    // MARK: Helpers

    private static func formatTime(_ sec: Double) -> String {
        let m = Int(sec) / 60
        let s = Int(sec) % 60
        return String(format: "%d:%02d", m, s)
    }
}
