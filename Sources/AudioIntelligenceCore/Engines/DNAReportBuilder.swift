import Foundation

public final class DNAReportBuilder: @unchecked Sendable {

    public static func analyze(
        url: URL,
        progress: @Sendable @escaping (Double, String, String?) -> Void
    ) async throws -> (analysis: MusicDNAAnalysis, reportText: String, mdPath: String) {

        let filename = url.lastPathComponent
        progress(5, "Ses dosyası yükleniyor...", nil)
        let buffer = try AudioLoader.load(url: url)

        let waveform = WaveformRenderer.renderFull(samples: buffer.samples, sampleRate: buffer.sampleRate, lines: 6)
        progress(12, "Waveform oluşturuldu", waveform)

        let stftEngine = STFTEngine(nFFT: 2048, hopLength: 512, sampleRate: buffer.sampleRate)
        let stft = stftEngine.analyze(buffer.samples)

        let melBank = MelFilterBank(nMels: 128, nFFT: 2048, sampleRate: buffer.sampleRate)
        let melSpec = melBank.apply(magnitude: stft.magnitude, nFrames: stft.nFrames)

        let onsetEngine = OnsetEngine(sampleRate: buffer.sampleRate)
        let onsetResult = onsetEngine.onsetStrength(buffer.samples)

        let rhythmEngine = RhythmEngine(sampleRate: buffer.sampleRate)
        let rhythm = await rhythmEngine.analyze(onsetResult: onsetResult)

        let chromaEngine = ChromaEngine(nFFT: 2048, sampleRate: buffer.sampleRate)
        let chroma = chromaEngine.chromagram(stft: stft)
        let chromaResult = chromaEngine.detectKey(chromagram: chroma)

        let spectralEngine = SpectralEngine(sampleRate: buffer.sampleRate, nFFT: 2048, hopLength: 512)
        let spectral = spectralEngine.analyze(stft: stft, samples: buffer.samples)

        let mfccEngine = MFCCEngine(nMFCC: 20, nMels: 128)
        let mfccResult = mfccEngine.compute(melSpectrogram: melSpec.flatMap { $0 }, stftEngine: stftEngine)

        let hpssEngine = HPSSEngine(winHarm: 31, winPerc: 31)
        let hpss = hpssEngine.analyze(stft: stft)

        let structureEngine = StructureEngine(hopLength: 512, sampleRate: buffer.sampleRate)
        let structure = structureEngine.analyze(chromagram: chroma, nSegments: 7)
        
        let forensicEngine = ForensicDNAEngine()
        let forensicResult = await forensicEngine.scan(at: url, samples: buffer.samples)
        let bitDepthResult = forensicEngine.analyzeBitDepthIntegrity(samples: buffer.samples)

        let loudnessEngine = LoudnessEngine(sampleRate: buffer.sampleRate)
        let loudness = loudnessEngine.analyze(samples: buffer.samples)
        
        let stereoEngine = StereoEngine()
        let stereo = stereoEngine.analyze(left: buffer.samples, right: buffer.samples)

        progress(93, "Raporlar yazılıyor...", nil)

        let home = FileManager.default.homeDirectoryForCurrentUser
        let aiWorksDir = home.appendingPathComponent("Documents/AI Works", isDirectory: true)
        try? FileManager.default.createDirectory(at: aiWorksDir, withIntermediateDirectories: true)

        let baseName = url.deletingPathExtension().lastPathComponent
        let mdPath = aiWorksDir.appendingPathComponent("\(baseName).dna.md").path

        // Build the Professional Analysis Model
        let analysis = MusicDNAAnalysis(
            fileName: filename,
            rhythm: RhythmMetrics(
                bpm: Float(rhythm.bpm),
                beatConsistency: Float(rhythm.gridStdSec),
                onsetMean: Float(rhythm.onsetMean),
                onsetPeak: Float(rhythm.onsetPeak),
                characterize: rhythm.gridStdSec < 0.02 ? "Hassas Grid" : "İnsan Hissi"
            ),
            tonality: TonalMetrics(
                key: chromaResult.key,
                strength: Float(chromaResult.keyStrength),
                keySignature: chromaResult.meanChroma,
                tendency: chromaResult.isMinor ? "Minör Eğilimli" : "Majör Eğilimli"
            ),
            spectral: AdvancedSpectralMetrics(
                centroid: spectral.centroidHz,
                rolloff: spectral.rolloffHz,
                flatness: spectral.flatness,
                flux: spectral.flux,
                bandwidth: spectral.bandwidthHz,
                zcr: spectral.zcr,
                dynamicRange: spectral.dynamicRangeDb,
                rmsMean: spectral.rmsMean,
                rmsMax: spectral.rmsMax,
                brightnessDescription: spectral.centroidHz > 2500 ? "Parlak" : "Ilık"
            ),
            hpss: HPSSMetrics(
                harmonicRatio: hpss.harmonicEnergyRatio,
                percussiveRatio: hpss.percussiveEnergyRatio,
                harmonicMean: hpss.harmonicEnergyRatio * 100.0,
                percussiveMean: hpss.percussiveEnergyRatio * 100.0,
                characterization: hpss.characterization
            ),
            timbre: TimbreMetrics(
                mfcc: mfccResult.mfcc,
                spectralContrast: [0, 0, 0, 0, 0, 0, 0]
            ),
            mastering: MasteringMetrics(
                integratedLUFS: loudness.integratedLUFS,
                momentaryLUFS: loudness.momentaryLUFsMax,
                shortTermLUFS: loudness.shortTermLUFsMax,
                truePeak: loudness.truePeakDb,
                phaseCorrelation: stereo.correlation,
                monoCompatibility: stereo.monoCompatibility,
                balanceLR: stereo.balance
            ),
            forensic: ForensicMetrics(
                sourceURL: forensicResult.whereFroms.first,
                encoder: forensicResult.encoder,
                isVerified: forensicResult.signatureFound,
                effectiveBits: bitDepthResult.effectiveBits,
                isUpsampled: bitDepthResult.isLikelyUpsampled,
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

        let reportText = MusicDNAReporter.generateReport(analysis: analysis)
        try reportText.write(toFile: mdPath, atomically: true, encoding: .utf8)

        progress(100, "Analiz tamamlandı!", nil)

        var finalAnalysis = analysis
        finalAnalysis.reportPath = mdPath

        return (finalAnalysis, reportText, mdPath)
    }
}
