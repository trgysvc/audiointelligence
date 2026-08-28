import Foundation

// =============================================================================
// AudioReport — the canonical, typed product of an analysis.
//
// This is THE deliverable. A markdown/JSON/PDF document is just one *rendering*
// of this value. The library produces data; the consuming application decides
// how to present or persist it.
//
// Design rules:
//   • Two clearly separated layers: `measurements` (certifiable, `Measured<T>`)
//     and `estimations` (statistical, `Estimated<T>`).
//   • `features` carries the heavy low-level series; always present in memory,
//     optionally excluded from serialization for a lean export.
//   • `schemaVersion` lets the schema grow additively (e.g. the upcoming
//     instrument/genre layer) without breaking existing consumers.
//   • Fully `Codable` → free JSON and binary-plist transport.
// =============================================================================

public struct AudioReport: Codable, Sendable, Identifiable {
    /// Semantic version of the report schema itself (not the library).
    public static let currentSchemaVersion = "1.0.0"

    public let id: UUID
    public let schemaVersion: String
    public let libraryVersion: String
    public let analyzedAt: Date

    public let metadata: ReportMetadata
    public let measurements: Measurements
    public let estimations: Estimations
    /// Heavy low-level feature series (chromagram, MFCC, spectrogram, …).
    /// Always populated in memory; may be dropped from serialized output.
    public let features: LowLevelFeatures?

    public init(id: UUID = UUID(),
                schemaVersion: String = AudioReport.currentSchemaVersion,
                libraryVersion: String,
                analyzedAt: Date = Date(),
                metadata: ReportMetadata,
                measurements: Measurements,
                estimations: Estimations,
                features: LowLevelFeatures?) {
        self.id = id
        self.schemaVersion = schemaVersion
        self.libraryVersion = libraryVersion
        self.analyzedAt = analyzedAt
        self.metadata = metadata
        self.measurements = measurements
        self.estimations = estimations
        self.features = features
    }
}

// MARK: - Metadata

public struct ReportMetadata: Codable, Sendable {
    public let fileName: String
    public let sourceURL: String?
    public let durationSeconds: Double
    public let sampleRate: Double
    public let channelCount: Int
    /// Codec / encoder reported by the container, when available.
    public let encoder: String?

    public init(fileName: String, sourceURL: String?, durationSeconds: Double,
                sampleRate: Double, channelCount: Int, encoder: String?) {
        self.fileName = fileName
        self.sourceURL = sourceURL
        self.durationSeconds = durationSeconds
        self.sampleRate = sampleRate
        self.channelCount = channelCount
        self.encoder = encoder
    }
}

// MARK: - Measurement layer (certifiable)

public struct Measurements: Codable, Sendable {
    public let loudness: LoudnessMeasurements
    public let fidelity: FidelityMeasurements
    public let stereo: StereoMeasurements
    public let forensic: ForensicMeasurements
    public let spectral: SpectralMeasurements
    public let separation: SeparationMeasurements

    public init(loudness: LoudnessMeasurements, fidelity: FidelityMeasurements,
                stereo: StereoMeasurements, forensic: ForensicMeasurements,
                spectral: SpectralMeasurements, separation: SeparationMeasurements) {
        self.loudness = loudness
        self.fidelity = fidelity
        self.stereo = stereo
        self.forensic = forensic
        self.spectral = spectral
        self.separation = separation
    }
}

/// Loudness per EBU R128 / ITU-R BS.1770.
public struct LoudnessMeasurements: Codable, Sendable {
    public let integrated: Measured<Double>      // LUFS, EBU R128
    public let shortTermMax: Measured<Double>    // LUFS
    public let momentaryMax: Measured<Double>    // LUFS
    public let range: Measured<Double>           // LU, EBU Tech 3342
    public let truePeak: Measured<Double>        // dBTP, ITU-R BS.1770

    public init(integrated: Measured<Double>, shortTermMax: Measured<Double>,
                momentaryMax: Measured<Double>, range: Measured<Double>,
                truePeak: Measured<Double>) {
        self.integrated = integrated
        self.shortTermMax = shortTermMax
        self.momentaryMax = momentaryMax
        self.range = range
        self.truePeak = truePeak
    }
}

/// Distortion & noise figures (AES17 / SMPTE / ITU-R 468).
public struct FidelityMeasurements: Codable, Sendable {
    public let thdPlusN: Measured<Double>        // %, AES17
    public let imd: Measured<Double>             // %, SMPTE
    public let snr: Measured<Double>             // dB
    public let noiseFloor468: Measured<Double>   // dB, ITU-R 468

    public init(thdPlusN: Measured<Double>, imd: Measured<Double>,
                snr: Measured<Double>, noiseFloor468: Measured<Double>) {
        self.thdPlusN = thdPlusN
        self.imd = imd
        self.snr = snr
        self.noiseFloor468 = noiseFloor468
    }
}

public struct StereoMeasurements: Codable, Sendable {
    public let phaseCorrelation: Measured<Double>  // -1…1
    public let width: Measured<Double>             // ratio
    public let sideEnergyPercent: Measured<Double> // %
    public let midSideBalance: Measured<Double>
    public let balanceLR: Measured<Double>         // -1 (L) … +1 (R)

    public init(phaseCorrelation: Measured<Double>, width: Measured<Double>,
                sideEnergyPercent: Measured<Double>, midSideBalance: Measured<Double>,
                balanceLR: Measured<Double>) {
        self.phaseCorrelation = phaseCorrelation
        self.width = width
        self.sideEnergyPercent = sideEnergyPercent
        self.midSideBalance = midSideBalance
        self.balanceLR = balanceLR
    }
}

public struct ForensicMeasurements: Codable, Sendable {
    public let sourceBitDepth: Measured<Int>     // header-read, deterministic
    public let effectiveBits: Measured<Int>      // entropy-derived
    public let isUpsampled: Bool                  // forensic determination
    public let codecCutoff: Measured<Double>     // Hz
    public let clippingEvents: Measured<Int>     // count
    public let entropyScore: Measured<Double>

    public init(sourceBitDepth: Measured<Int>, effectiveBits: Measured<Int>,
                isUpsampled: Bool, codecCutoff: Measured<Double>,
                clippingEvents: Measured<Int>, entropyScore: Measured<Double>) {
        self.sourceBitDepth = sourceBitDepth
        self.effectiveBits = effectiveBits
        self.isUpsampled = isUpsampled
        self.codecCutoff = codecCutoff
        self.clippingEvents = clippingEvents
        self.entropyScore = entropyScore
    }
}

/// Spectral descriptors. No formal standard, but validated for `librosa` parity.
public struct SpectralMeasurements: Codable, Sendable {
    public let centroid: Measured<Double>    // Hz
    public let rolloff: Measured<Double>     // Hz
    public let bandwidth: Measured<Double>   // Hz
    public let flatness: Measured<Double>    // ratio
    public let flux: Measured<Double>
    public let zeroCrossingRate: Measured<Double>
    public let rmsMean: Measured<Double>
    public let rmsMax: Measured<Double>

    public init(centroid: Measured<Double>, rolloff: Measured<Double>,
                bandwidth: Measured<Double>, flatness: Measured<Double>,
                flux: Measured<Double>, zeroCrossingRate: Measured<Double>,
                rmsMean: Measured<Double>, rmsMax: Measured<Double>) {
        self.centroid = centroid
        self.rolloff = rolloff
        self.bandwidth = bandwidth
        self.flatness = flatness
        self.flux = flux
        self.zeroCrossingRate = zeroCrossingRate
        self.rmsMean = rmsMean
        self.rmsMax = rmsMax
    }
}

/// Harmonic/percussive source separation energy ratios (deterministic).
public struct SeparationMeasurements: Codable, Sendable {
    public let harmonicRatio: Measured<Double>    // ratio
    public let percussiveRatio: Measured<Double>  // ratio

    public init(harmonicRatio: Measured<Double>, percussiveRatio: Measured<Double>) {
        self.harmonicRatio = harmonicRatio
        self.percussiveRatio = percussiveRatio
    }
}

// MARK: - Estimation layer (statistical)

public struct Estimations: Codable, Sendable {
    public let tempo: Estimated<Double>          // BPM
    public let key: Estimated<String>            // e.g. "A minor"
    public let timeSignature: Estimated<String>  // e.g. "4/4"
    public let pitch: PitchMetrics               // f0 statistics
    public let structure: [MusicSegment]
    /// Per-instrument predictions (the upcoming estimation layer); `nil` until
    /// that layer ships, so the schema grows additively.
    public let instruments: [Estimated<String>]?
    public let musicology: MusicologyReport

    public init(tempo: Estimated<Double>, key: Estimated<String>,
                timeSignature: Estimated<String>, pitch: PitchMetrics,
                structure: [MusicSegment], instruments: [Estimated<String>]?,
                musicology: MusicologyReport) {
        self.tempo = tempo
        self.key = key
        self.timeSignature = timeSignature
        self.pitch = pitch
        self.structure = structure
        self.instruments = instruments
        self.musicology = musicology
    }
}

/// Interpretive musicology — the most speculative layer. Reuses the existing
/// neutral leaf types (chords, cadences, …); only the marketing-laden container
/// is gone.
public struct MusicologyReport: Codable, Sendable {
    public let fundamentalNote: String
    public let meter: MeterDNA
    public let chords: [VerticalChord]
    public let cadences: [CadenceEvent]
    public let modulations: [ModulationDNA]
    public let motifs: [MotifDNA]
    public let counterpointSpecies: String

    public init(fundamentalNote: String, meter: MeterDNA, chords: [VerticalChord],
                cadences: [CadenceEvent], modulations: [ModulationDNA],
                motifs: [MotifDNA], counterpointSpecies: String) {
        self.fundamentalNote = fundamentalNote
        self.meter = meter
        self.chords = chords
        self.cadences = cadences
        self.modulations = modulations
        self.motifs = motifs
        self.counterpointSpecies = counterpointSpecies
    }
}

// MARK: - Low-level feature series (heavy)

public struct LowLevelFeatures: Codable, Sendable {
    public let chromaProfile: [Float]        // 12 semitone means
    public let mfcc: [Float]                  // 20 coefficient means
    public let spectralContrast: [Float]      // 6 bands (was mislabeled 7 — see SpectralFeatureEngine's fixed off-by-one)
    public let tonnetz: [Float]               // 6 dimensions
    public let tempogramCyclic: [Float]
    public let nmfComponentEnergy: [Float]
    public let viterbiPitchPath: [Int]
    public let waveformPeaks: [Float]
    /// Full magnitude spectrogram `[freqBin][frame]` — the heaviest payload.
    public let magnitudeSpectrogram: [[Float]]

    public init(chromaProfile: [Float], mfcc: [Float], spectralContrast: [Float],
                tonnetz: [Float], tempogramCyclic: [Float], nmfComponentEnergy: [Float],
                viterbiPitchPath: [Int], waveformPeaks: [Float],
                magnitudeSpectrogram: [[Float]]) {
        self.chromaProfile = chromaProfile
        self.mfcc = mfcc
        self.spectralContrast = spectralContrast
        self.tonnetz = tonnetz
        self.tempogramCyclic = tempogramCyclic
        self.nmfComponentEnergy = nmfComponentEnergy
        self.viterbiPitchPath = viterbiPitchPath
        self.waveformPeaks = waveformPeaks
        self.magnitudeSpectrogram = magnitudeSpectrogram
    }
}

// MARK: - Serialization

extension AudioReport {
    /// Returns a copy with `features` removed — for a lean serialized export.
    public func strippingFeatures() -> AudioReport {
        AudioReport(id: id, schemaVersion: schemaVersion, libraryVersion: libraryVersion,
                    analyzedAt: analyzedAt, metadata: metadata, measurements: measurements,
                    estimations: estimations, features: nil)
    }

    /// Evrensel JSON. `includingFeatures: false` ile yalın (hafif) çıktı.
    public func jsonData(includingFeatures: Bool = true,
                         prettyPrinted: Bool = false) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = prettyPrinted ? [.prettyPrinted, .sortedKeys] : [.sortedKeys]
        let target = includingFeatures ? self : strippingFeatures()
        return try encoder.encode(target)
    }

    /// Apple-native binary property list. Kompakt ve hızlı; Apple↔Apple için ideal.
    public func plistData(includingFeatures: Bool = true) throws -> Data {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        let target = includingFeatures ? self : strippingFeatures()
        return try encoder.encode(target)
    }

    /// Decode a report previously produced by ``plistData(includingFeatures:)``.
    public static func decoded(fromPlist data: Data) throws -> AudioReport {
        try PropertyListDecoder().decode(AudioReport.self, from: data)
    }

    /// Decode a report previously produced by ``jsonData(includingFeatures:prettyPrinted:)``.
    public static func decoded(fromJSON data: Data) throws -> AudioReport {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(AudioReport.self, from: data)
    }
}
