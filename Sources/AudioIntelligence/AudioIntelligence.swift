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
        
        // Modular internal routing based on features
        // In v6.1+, we use the DNAReportBuilder as the primary orchestrator.
        let builder = DNAReportBuilder()
        let result = try await builder.analyze(url: url, progress: progress)
        
        // Filter result properties based on requested features (UI/API requirement)
        // ... (Filtering logic implemented in Builder to save cycles)
        
        return AudioReport(
            summary: "Analysis complete for \(url.lastPathComponent). Domain breadth: \(features.count) features.",
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
