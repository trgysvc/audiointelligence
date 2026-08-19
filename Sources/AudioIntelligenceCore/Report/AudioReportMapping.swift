import Foundation

// =============================================================================
// Mapping: MusicDNAAnalysis (internal engine aggregate) → AudioReport (product).
//
// The validated DSP pipeline keeps producing `MusicDNAAnalysis` exactly as
// before; this is the single place that lifts it into the public, layered
// `AudioReport` schema. Keeping the transform isolated means the engines are
// untouched — only the output representation changes.
// =============================================================================

/// The library's released version, stamped into every report.
public let audioIntelligenceLibraryVersion = "8.2.2"

extension AudioReport {

    /// Context the engine aggregate does not itself carry (file-level facts read
    /// from the container header).
    public struct SourceContext: Sendable {
        public let sourceURL: String?
        public let durationSeconds: Double
        public let sampleRate: Double
        public let channelCount: Int
        public let sourceBitDepth: Int

        public init(sourceURL: String?, durationSeconds: Double, sampleRate: Double,
                    channelCount: Int, sourceBitDepth: Int) {
            self.sourceURL = sourceURL
            self.durationSeconds = durationSeconds
            self.sampleRate = sampleRate
            self.channelCount = channelCount
            self.sourceBitDepth = sourceBitDepth
        }
    }

    public init(from a: MusicDNAAnalysis, context ctx: SourceContext) {
        let metadata = ReportMetadata(
            fileName: a.fileName,
            sourceURL: ctx.sourceURL ?? a.forensic.sourceURL,
            durationSeconds: ctx.durationSeconds,
            sampleRate: ctx.sampleRate,
            channelCount: ctx.channelCount,
            encoder: a.forensic.encoder
        )

        // ---- Measurement layer (certifiable) ---------------------------------
        let loudness = LoudnessMeasurements(
            integrated:   Measured(Double(a.mastering.integratedLUFS), unit: .lufs, standard: .ebuR128, validated: true),
            shortTermMax: Measured(Double(a.mastering.shortTermLUFS),  unit: .lufs, standard: .ebuR128, validated: true),
            momentaryMax: Measured(Double(a.mastering.momentaryLUFS),  unit: .lufs, standard: .ebuR128, validated: true),
            range:        Measured(Double(a.mastering.lraLU),          unit: .lu,   standard: .ebuTech3342, validated: true),
            truePeak:     Measured(Double(a.mastering.truePeak),       unit: .dBTP, standard: .ituBS1770, validated: true)
        )

        let fidelity = FidelityMeasurements(
            // THD+N and IMD are test-tone-only lab measurements. On real music no tone is
            // present, the engine yields 0, and validated reflects that it was not actually
            // measured (rather than claiming a certified 0%).
            thdPlusN:      Measured(Double(a.science.thdPlusN),           unit: .percent, standard: .aes17, validated: a.science.thdPlusN > 0),
            imd:           Measured(Double(a.science.smpteIMD),           unit: .percent, standard: .smpte, validated: a.science.smpteIMD > 0),
            snr:           Measured(Double(a.science.snr),                unit: .dB,      standard: nil,     validated: true),
            noiseFloor468: Measured(Double(a.science.noiseFloorWeight468), unit: .dB,     standard: .itu468, validated: true)
        )

        let stereo = StereoMeasurements(
            phaseCorrelation:  Measured(Double(a.mastering.phaseCorrelation),  unit: .dimensionless, validated: true),
            width:             Measured(Double(a.mastering.stereoWidth),       unit: .ratio,         validated: true),
            sideEnergyPercent: Measured(Double(a.mastering.sideEnergyPercent), unit: .percent,       validated: true),
            midSideBalance:    Measured(Double(a.mastering.msBalance),         unit: .dimensionless, validated: true),
            balanceLR:         Measured(Double(a.mastering.balanceLR),         unit: .dimensionless, validated: true)
        )

        let forensic = ForensicMeasurements(
            sourceBitDepth: Measured(ctx.sourceBitDepth,            unit: .bits,  validated: true),
            effectiveBits:  Measured(a.forensic.effectiveBits,      unit: .bits,  validated: true),
            isUpsampled:    a.forensic.isUpsampled,
            codecCutoff:    Measured(Double(a.forensic.codecCutoffHz), unit: .hertz, validated: true),
            clippingEvents: Measured(a.forensic.clippingEvents,    unit: .count, validated: true),
            entropyScore:   Measured(Double(a.forensic.entropyScore), unit: .dimensionless, validated: true)
        )

        let spectral = SpectralMeasurements(
            centroid:         Measured(Double(a.spectral.centroid),  unit: .hertz, standard: .librosaParity, validated: true),
            rolloff:          Measured(Double(a.spectral.rolloff),   unit: .hertz, standard: .librosaParity, validated: true),
            bandwidth:        Measured(Double(a.spectral.bandwidth), unit: .hertz, standard: .librosaParity, validated: true),
            flatness:         Measured(Double(a.spectral.flatness),  unit: .ratio, standard: .librosaParity, validated: true),
            flux:             Measured(Double(a.spectral.flux),      unit: .dimensionless, standard: .librosaParity, validated: true),
            zeroCrossingRate: Measured(Double(a.spectral.zcr),       unit: .ratio, standard: .librosaParity, validated: true),
            rmsMean:          Measured(Double(a.spectral.rmsMean),   unit: .dimensionless, standard: .librosaParity, validated: true),
            rmsMax:           Measured(Double(a.spectral.rmsMax),    unit: .dimensionless, standard: .librosaParity, validated: true)
        )

        let separation = SeparationMeasurements(
            harmonicRatio:   Measured(Double(a.hpss.harmonicEnergyRatio),   unit: .ratio, validated: true),
            percussiveRatio: Measured(Double(a.hpss.percussiveEnergyRatio), unit: .ratio, validated: true)
        )

        let measurements = Measurements(
            loudness: loudness, fidelity: fidelity, stereo: stereo,
            forensic: forensic, spectral: spectral, separation: separation
        )

        // ---- Estimation layer (statistical) ----------------------------------
        let tempo = Estimated(Double(a.rhythm.bpm),
                              confidence: Double(a.rhythm.bpmConfidence),
                              method: "autocorrelation + log-normal tempo prior")

        let key = Estimated(a.tonality.key,
                            confidence: Double(a.tonality.keyConfidence),
                            method: "Krumhansl-Schmuckler on high-res STFT chroma")

        // beatConsistency is a beat-interval deviation in [0, ∞] where *lower* means more
        // regular. Invert and clamp into a 0…1 confidence (it was passed through raw, yielding
        // values like 3.83 → "383%"). Stable meter → high confidence; erratic → low.
        let timeSignature = Estimated(a.musicology.meter.timeSignature,
                                      confidence: max(0, min(1, 1 - Double(a.rhythm.beatConsistency))),
                                      method: "onset-autocorrelation meter detection")

        let instruments: [Estimated<String>]? = a.instruments.predictions.isEmpty
            ? nil
            : a.instruments.predictions.map {
                Estimated($0.label, confidence: Double($0.confidence), method: $0.technicalBasis)
            }

        let musicology = MusicologyReport(
            fundamentalNote: a.reduction.fundamentalNote,
            meter: a.musicology.meter,
            chords: a.musicology.verticalAnalysis,
            cadences: a.musicology.cadences,
            modulations: a.musicology.modulations,
            motifs: a.musicology.motifs,
            counterpointSpecies: a.musicology.counterpointSpecies
        )

        let estimations = Estimations(
            tempo: tempo, key: key, timeSignature: timeSignature,
            pitch: a.pitch, structure: a.segments,
            instruments: instruments, musicology: musicology
        )

        // ---- Low-level feature series (heavy) --------------------------------
        let features = LowLevelFeatures(
            chromaProfile: a.chromaProfile,
            mfcc: a.timbre.mfcc,
            spectralContrast: a.timbre.spectralContrast,
            tonnetz: a.tonnetz.meanTonnetz,
            tempogramCyclic: a.tempogram.cyclicTempoMap,
            nmfComponentEnergy: a.nmf.componentEnergy,
            viterbiPitchPath: a.viterbi.path,
            waveformPeaks: a.waveformPeaks,
            magnitudeSpectrogram: a.spectral.fullMagnitudes
        )

        self.init(
            libraryVersion: audioIntelligenceLibraryVersion,
            analyzedAt: a.timestamp,
            metadata: metadata,
            measurements: measurements,
            estimations: estimations,
            features: features
        )
    }
}
