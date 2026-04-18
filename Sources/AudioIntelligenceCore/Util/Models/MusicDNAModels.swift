import Foundation

/// The "Infinity" Analysis model. 
/// Exposes 100% of the AudioIntelligence DSP metrics without data stripping.
public struct MusicDNAAnalysis: Codable, Sendable, Identifiable {
    public let id: UUID
    public let timestamp: Date
    public let fileName: String
    
    // Core MIR Metrics
    public let rhythm: RhythmMetrics
    public let tonality: TonalMetrics
    public let pitch: PitchMetrics
    public let spectral: AdvancedSpectralMetrics
    public let hpss: HPSSMetrics
    public let timbre: TimbreMetrics
    
    // Mastering & Forensic
    public let mastering: MasteringMetrics
    public let semantic: SemanticMetrics // v55.0 Addition
    public let forensic: ForensicMetrics
    public let instruments: InstrumentMetrics // v56.0 Addition
    public let science: ScienceMetrics // v52.0 Addition
    
    // Visualization Data
    public let waveformPeaks: [Float]
    public let chromaProfile: [Float] // 12 semitones
    public let segments: [MusicSegment]
    
    // Audit & Extension Data (v45.0)
    public let audit: AuditMetrics
    
    // v6.1 Infinity Additions (Complete 26 Engine Coverage)
    public let tonnetz: TonnetzMetrics
    public let tempogram: TempogramMetrics
    public let nmf: NMFMetrics
    public let piptrack: PiptrackMetrics
    public let viterbi: ViterbiMetrics // v6.3 Addition: Refined Pitch Sequence
    
    // Metadata / Paths
    public var reportPath: String?
    
    public init(id: UUID = UUID(), 
                 timestamp: Date = Date(), 
                 fileName: String,
                 rhythm: RhythmMetrics,
                 tonality: TonalMetrics,
                 pitch: PitchMetrics,
                 spectral: AdvancedSpectralMetrics,
                 hpss: HPSSMetrics,
                 timbre: TimbreMetrics,
                 mastering: MasteringMetrics,
                 semantic: SemanticMetrics,
                 forensic: ForensicMetrics,
                 instruments: InstrumentMetrics,
                 science: ScienceMetrics,
                 waveformPeaks: [Float],
                 chromaProfile: [Float],
                 segments: [MusicSegment],
                 audit: AuditMetrics,
                 tonnetz: TonnetzMetrics,
                 tempogram: TempogramMetrics,
                 nmf: NMFMetrics,
                 piptrack: PiptrackMetrics,
                 viterbi: ViterbiMetrics) {
        self.id = id
        self.timestamp = timestamp
        self.fileName = fileName
        self.rhythm = rhythm
        self.tonality = tonality
        self.pitch = pitch
        self.spectral = spectral
        self.hpss = hpss
        self.timbre = timbre
        self.mastering = mastering
        self.semantic = semantic
        self.forensic = forensic
        self.instruments = instruments
        self.science = science
        self.waveformPeaks = waveformPeaks
        self.chromaProfile = chromaProfile
        self.segments = segments
        self.audit = audit
        self.tonnetz = tonnetz
        self.tempogram = tempogram
        self.nmf = nmf
        self.piptrack = piptrack
        self.viterbi = viterbi
    }
}

public struct RhythmMetrics: Codable, Sendable {
    public let bpm: Float
    public let bpmConfidence: Float
    public let beatConsistency: Float
    public let onsetMean: Float
    public let onsetPeak: Float
    public let characterize: String
}

public struct TonalMetrics: Codable, Sendable {
    public let key: String
    public let keyConfidence: Float
    public let strength: Float
    public let keySignature: [Float] // 12 semitone key weights
    public let tendency: String
}

public struct PitchMetrics: Codable, Sendable {
    public let meanF0: Float
    public let medianF0: Float
    public let minF0: Float
    public let maxF0: Float
    public let voicedRatio: Float // 0.0 to 1.0
    public let stability: Float   // Consistency of pitch
}

public struct AdvancedSpectralMetrics: Codable, Sendable {
    public let centroid: Float
    public let rolloff: Float
    public let flatness: Float
    public let flux: Float
    public let skewness: Float
    public let kurtosis: Float
    public let bandwidth: Float
    public let zcr: Float
    public let dynamicRange: Float
    public let rmsMean: Float
    public let rmsMax: Float
    public let brightnessDescription: String
    public let fullMagnitudes: [[Float]] // [FreqBin][FrameIndex] for visualization
}

public struct HPSSMetrics: Codable, Sendable {
    public let harmonicRatio: Float
    public let percussiveRatio: Float
    public let harmonicMean: Float
    public let percussiveMean: Float
    public let characterization: String // e.g., "Harmonic Dominant"
}

public struct TimbreMetrics: Codable, Sendable {
    public let mfcc: [Float] // All 20 coefficients
    public let spectralContrast: [Float] // 7 bands
}

public struct MasteringMetrics: Codable, Sendable {
    public let integratedLUFS: Float
    public let momentaryLUFS: Float
    public let shortTermLUFS: Float
    public let truePeak: Float
    public let phaseCorrelation: Float
    public let monoCompatibility: String
    public let balanceLR: Float // -1.0 (Left) to +1.0 (Right)
    public let msBalance: Float // v51.0 Addition
    public let sideEnergyPercent: Float // v55.0 Addition
    public let stereoWidth: Float       // v55.0 Addition
    public let lraLU: Float     // v52.0 Addition: EBU Tech 3342
}

public struct SemanticMetrics: Codable, Sendable {
    public let dominanceMap: [String: Float]
    public let primaryRole: String
    public let textureType: String
    public let presenceScore: Float
}

public struct ForensicMetrics: Codable, Sendable {
    public let sourceURL: String?
    public let encoder: String?
    public let isVerified: Bool
    public let effectiveBits: Int // Forensic entropy check
    public let isUpsampled: Bool
    public let codecCutoffHz: Float // v55.0 Addition
    public let entropyScore: Float  // v55.0 Addition
    public let clippingEvents: Int  // v55.0 Addition
    public let techSpecs: [String: String]
}

public struct InstrumentMetrics: Codable, Sendable {
    public let predictions: [InstrumentPrediction]
    public let primaryLabel: String
}

public struct InstrumentPrediction: Codable, Sendable {
    public let label: String
    public let confidence: Float // 0.0 - 1.0
    public let technicalBasis: String
}

public struct MusicSegment: Codable, Sendable, Identifiable {
    public let id: Int
    public let start: Double
    public let end: Double
    public let label: String
}

public struct ScienceMetrics: Codable, Sendable {
    public let dynamicRangeAES17: Float
    public let thdPlusN: Float
    public let smpteIMD: Float
    public let snr: Float
    public let noiseFloorWeight468: Float // ITU-R 468
    public let status: String // "Verified Compliance"
}
public struct AuditMetrics: Codable, Sendable {
    public let engineCoverage: [String: Bool]
    public let cqtStatus: String
    public let melSpectrogramResolution: String
    public let utilityCheck: String
    public let filterbankStatus: String
}

// MARK: - v6.1 Infinity Extended Metrics

public struct TonnetzMetrics: Codable, Sendable {
    public let meanTonnetz: [Float] // 6 dimensions
    public let harmonicStability: Float
}

public struct TempogramMetrics: Codable, Sendable {
    public let cyclicTempoMap: [Float]
    public let dominantPeriod: Int
}

public struct NMFMetrics: Codable, Sendable {
    public let reconstructionError: Float
    public let componentEnergy: [Float]
}

public struct PiptrackMetrics: Codable, Sendable {
    public let refinedMeanF0: Float
    public let trackingConfidence: Float
}

public struct ViterbiMetrics: Codable, Sendable {
    public let path: [Int]
    public let confidence: Float
}
