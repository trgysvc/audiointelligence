import Foundation

public struct MusicDNAAnalysis: Codable, Sendable, Identifiable {
    public let id: UUID
    public let timestamp: Date
    public let fileName: String
    
    // Core Metrics
    public let rhythm: RhythmMetrics
    public let tonality: TonalMetrics
    public let spectral: SpectralMetrics
    public let forensic: ForensicMetrics
    
    // Visualization
    public let waveformPeaks: [Float] // Downsampled (e.g., 100 points)
    
    // Detailed Data
    public let chromaProfile: [Float] // 12 semitones
    public let segments: [MusicSegment]
    
    // File Paths
    public var reportPath: String? // Path to the generated .md file
    
    public init(id: UUID = UUID(), 
                timestamp: Date = Date(), 
                fileName: String,
                rhythm: RhythmMetrics,
                tonality: TonalMetrics,
                spectral: SpectralMetrics,
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
        self.forensic = forensic
        self.waveformPeaks = waveformPeaks
        self.chromaProfile = chromaProfile
        self.segments = segments
    }
}

public struct RhythmMetrics: Codable, Sendable {
    public let bpm: Float
    public let beatConsistency: Float // std of intervals
    public let characterize: String // e.g., "Rigit Grid", "Human Feeling"
}

public struct TonalMetrics: Codable, Sendable {
    public let key: String // e.g., "G Minor / Bb Major"
    public let tendency: String // e.g., "Minor leaning"
}

public struct SpectralMetrics: Codable, Sendable {
    public let centroid: Float
    public let rolloff: Float
    public let flatness: Float
    public let dynamicRange: Float // dB
    public let brightnessDescription: String // e.g., "Warm-Bright"
}

public struct ForensicMetrics: Codable, Sendable {
    public let sourceURL: String?
    public let encoder: String?
    public let isVerified: Bool
    public let techSpecs: [String: String]
}

public struct MusicSegment: Codable, Sendable, Identifiable {
    public let id: Int
    public let start: Double
    public let end: Double
    public let label: String // e.g., "Intro", "Verse"
}
