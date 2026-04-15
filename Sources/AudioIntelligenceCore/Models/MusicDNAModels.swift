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
    public let spectral: AdvancedSpectralMetrics
    public let hpss: HPSSMetrics
    public let timbre: TimbreMetrics
    
    // Mastering & Forensic
    public let mastering: MasteringMetrics
    public let forensic: ForensicMetrics
    
    // Visualization Data
    public let waveformPeaks: [Float]
    public let chromaProfile: [Float] // 12 semitones
    public let segments: [MusicSegment]
    
    // Metadata / Paths
    public var reportPath: String?
    
    public init(id: UUID = UUID(), 
                timestamp: Date = Date(), 
                fileName: String,
                rhythm: RhythmMetrics,
                tonality: TonalMetrics,
                spectral: AdvancedSpectralMetrics,
                hpss: HPSSMetrics,
                timbre: TimbreMetrics,
                mastering: MasteringMetrics,
                forensic: ForensicMetrics,
                waveformPeaks: [Float],
                chromaProfile: [Float],
                segments: [MusicSegment]) {
        self.id = id
        self.timestamp = timestamp
        self.fileName = fileName
        self.rhythm = rhythm
        self.tonality = tonality
        self.spectral = spectral
        self.hpss = hpss
        self.timbre = timbre
        self.mastering = mastering
        self.forensic = forensic
        self.waveformPeaks = waveformPeaks
        self.chromaProfile = chromaProfile
        self.segments = segments
    }
}

public struct RhythmMetrics: Codable, Sendable {
    public let bpm: Float
    public let beatConsistency: Float
    public let onsetMean: Float
    public let onsetPeak: Float
    public let characterize: String
}

public struct TonalMetrics: Codable, Sendable {
    public let key: String
    public let strength: Float
    public let keySignature: [Float] // 12 semitone key weights
    public let tendency: String
}

public struct AdvancedSpectralMetrics: Codable, Sendable {
    public let centroid: Float
    public let rolloff: Float
    public let flatness: Float
    public let flux: Float
    public let bandwidth: Float
    public let zcr: Float
    public let dynamicRange: Float
    public let rmsMean: Float
    public let rmsMax: Float
    public let brightnessDescription: String
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
}

public struct ForensicMetrics: Codable, Sendable {
    public let sourceURL: String?
    public let encoder: String?
    public let isVerified: Bool
    public let effectiveBits: Int // Forensic entropy check
    public let isUpsampled: Bool
    public let techSpecs: [String: String]
}

public struct MusicSegment: Codable, Sendable, Identifiable {
    public let id: Int
    public let start: Double
    public let end: Double
    public let label: String
}
