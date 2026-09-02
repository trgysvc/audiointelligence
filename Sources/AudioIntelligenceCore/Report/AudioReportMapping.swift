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
public let audioIntelligenceLibraryVersion = "8.2.3"

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

        // History (DEVLOG Phase 41 & 43 / Yapilacaklar madde 8/9/11), kept because this field's
        // source has genuinely moved twice and a future reader deserves the why, not just the
        // current state: `a.tonality.key` used to be `ReductionEngine.fundamentalNote` (a
        // per-segment loudest-chroma-bin majority vote, no mode) -- found wrong-labeled here as
        // "Krumhansl-Schmuckler" while building item 8's production-vs-isolated parity test
        // (Phase 41), and retracted (label corrected, README ⚠️'d). Measuring both candidates
        // side by side on real GiantSteps (Phase 42) found tonic accuracy statistically tied
        // (p=1.0, N=43) but `detectKey`'s free major/minor signal real (86% mode accuracy, 95%
        // when its own tonic call is right) where `ReductionEngine` can never provide one, and
        // git history showed the original wiring was an oversight (`ReductionEngine` was the
        // only mechanism that existed when it was wired; `detectKey` was added ~2 months later
        // for an unrelated need and this field was never revisited) -- not a deliberate choice
        // this change overrides. `a.tonality.key` is now `ModulationEngine.detectKey`'s output
        // (DNAReportBuilder.swift ~509-511, Phase 43), so this `method` string is accurate again.
        // `confidence` moved WITH it (`detectKeyWithConfidence`'s own correlation strength, not
        // `reduction.stabilityScore` -- a value from one algorithm must not carry a confidence
        // describing a different one, the exact bug class this whole arc started from). It is
        // RAW, not calibrated like `instruments` (see `detectKeyWithConfidence`'s doc comment,
        // and `Estimated.confidence`'s default-vs-`instruments`-exception framing in
        // `MetricWrappers.swift`) -- not fit against ground-truth accuracy, so treat it as a
        // within-algorithm relative score, not "confidence == likelihood of being correct."
        let key = Estimated(a.tonality.key,
                            confidence: Double(a.tonality.keyConfidence),
                            method: "Krumhansl-Schmuckler correlation on high-res STFT chroma")

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

        // `a.musicology.context` (`HistoricalContext` -- suggested period/artistic movement) is
        // DELIBERATELY not mapped here. Same "measured, not claimed" reasoning as the
        // mood/genre/danceability exclusion (Yapilacaklar.md) -- see `HistoricalEngine`'s own doc
        // comment. Do not add it without revisiting that decision.
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
