import Foundation

/// The main entry point for the AudioIntelligence analysis platform.
public actor AudioIntelligence {
    
    /// Supported devices for analysis.
    public enum Device: Sendable {
        /// Automatically detect and use the best hardware available (M4, M1, Intel).
        case current
        /// Explicit Apple Silicon (Neural Engine/AMX).
        case appleSilicon
        /// Standard CPU-based analysis.
        case cpu
    }
    
    /// Operating modes for the engine.
    public enum Mode: Sendable {
        /// Optimized for power efficiency.
        case eco
        /// Standard balance between speed and quality.
        case balanced
        /// High-precision mode maximizing all available cores.
        case ultra
    }
    
    private let device: Device
    private let mode: Mode
    
    /// Initializes a new analysis engine with specified device and mode.
    public init(device: Device = .current, mode: Mode = .balanced) {
        self.device = device
        self.mode = mode
    }
    
    /// Analyzes an audio file from a URL.
    /// - Parameters:
    ///   - url: The resource URL to analyze.
    ///   - features: A set of features to pull from the audio.
    ///   - explain: Whether to include natural language insights in the report.
    /// - Returns: A complete `AudioReport` with requested features.
    public func analyze(
        url: URL,
        features: Set<AudioFeature> = [.spectral, .rhythm],
        explain: Bool = true
    ) async throws -> AudioReport {
        // Internal logic coordination with AudioIntelligenceCore
        // Mocking the behavior for the initial skeleton:
        
        let bpm = 124.0 // Mocked value
        let report = AudioReport(
            summary: explain ? "This track is \(Int(bpm)) BPM and has high energy." : "",
            rhythm: features.contains(.rhythm) ? .init(bpm: bpm, confidence: 0.98) : nil,
            forensic: features.contains(.forensic) ? .init(encoderName: "LAME 3.100", isAuthentic: true) : nil
        )
        
        return report
    }
    
    /// Compares two audio files for similarity.
    public func compare(_ urlA: URL, and urlB: URL) async -> (score: Double, type: String) {
        // Mock comparison implementation
        return (92.5, "Remix")
    }
}
