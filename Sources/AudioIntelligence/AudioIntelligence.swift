import Foundation
@_exported import AudioIntelligenceCore

/// The central entry point for the AudioIntelligence SDK.
/// Managed as a thread-safe Swift Actor, it provides both "One-Stop" DNA analysis
/// and granular access to specific MIR, Mastering, and Forensic engines.
public actor AudioIntelligence {
    
    /// Hardware execution targets for the DSP pipeline.
    public enum Device: Sendable {
        /// Automatic selection based on task (ANE for neural, AMX for DSP).
        case automatic
        
        /// Force Apple Silicon acceleration (AMX + ANE).
        case appleSilicon
        
        /// Fallback to standard CPU execution.
        case cpu
    }
    
    /// Energy and throughput profiles.
    public enum Mode: Sendable {
        /// Optimized for background processing with minimal thermal impact.
        case efficiency
        
        /// Standard balance of speed and power.
        case balanced
        
        /// Maximum throughput (high AMX utilization).
        case performance
    }
    
    // MARK: - Initialization
    
    public init(device: Device = .automatic, mode: Mode = .balanced) {}
    
    // MARK: - Analysis APIs
    
    /// Professional analysis pipeline.
    /// Performs a deep-dive "DNA" scan of the audio file based on selected features.
    ///
    /// - Parameters:
    ///   - url: The file URL of the audio source.
    ///   - features: A set of feature domains to analyze (default: all).
    ///   - progress: A closure that receives (0.0 to 1.0) progress updates and stage metadata.
    /// - Returns: An `AudioReport` containing human-readable summaries and raw technical data.
    public func analyze(
        url: URL,
        features: Set<AudioFeature> = Set(AudioFeature.allCases),
        progress: @Sendable @escaping (Double, String, String?) -> Void = { _, _, _ in }
    ) async throws -> AudioReport {
        
        // Map public AudioFeature to internal AnalysisLane
        var lanes: Set<AnalysisLane> = []
        for feat in features {
            switch feat {
            case .spectral:   lanes.insert(.spectral); lanes.insert(.timbre)
            case .rhythm:     lanes.insert(.rhythm)
            case .harmonic:   lanes.insert(.tonal); lanes.insert(.advanced)
            case .pitch:      lanes.insert(.semantic)
            case .separation: lanes.insert(.advanced)
            case .semantic:   lanes.insert(.semantic)
            case .forensic:   lanes.insert(.forensic)
            case .mastering:  lanes.insert(.mastering)
            }
        }
        
        let builder = DNAReportBuilder()
        let result = try await builder.analyze(url: url, lanes: lanes, progress: progress)
        
        return AudioReport(
            summary: "Analysis complete for \(url.lastPathComponent). Dynamic Domain breadth: \(features.count) features (\(lanes.count) optimized lanes).",
            rawAnalysis: result.analysis,
            reportText: result.reportText,
            reportPath: result.mdPath
        )
    }
    
    // MARK: - Granular Utility APIs
    
    /// Manually clears the 4GB hybrid disk/RAM cache.
    public func invalidateCache() async {
        await IntelligenceCache.shared.clear()
    }
    
    /// Returns current hardware telemetry.
    public func getHardwareStats() async -> [String: Any] {
        return [
            "acceleration": "AMX/ANE",
            "threads": ProcessInfo.processInfo.activeProcessorCount,
            "cache_usage_bytes": await IntelligenceCache.shared.currentSize()
        ]
    }
}
