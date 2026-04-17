import Foundation
@_exported import AudioIntelligenceCore

public actor AudioIntelligence {
    
    public enum Device: Sendable {
        case current
        case appleSilicon
        case cpu
    }
    
    public enum Mode: Sendable {
        case eco
        case balanced
        case ultra
    }
    
    public init(device: Device = .current, mode: Mode = .balanced) {}
    
    /// Professional analysis entry point.
    /// Supports both progress tracking and feature selection for v25.0+.
    public func analyze(
        url: URL,
        features: Set<AudioFeature> = [.spectral, .rhythm],
        explain: Bool = true,
        progress: @Sendable @escaping (Double, String, String?) -> Void = { _, _, _ in }
    ) async throws -> AudioReport {
        
        let builder = DNAReportBuilder()
        let result = try await builder.analyze(url: url, progress: progress)
        
        return AudioReport(
            summary: explain ? "Analysis complete for \(url.lastPathComponent). BPM: \(result.analysis.rhythm.bpm)" : "",
            rawAnalysis: result.analysis,
            reportText: result.reportText,
            reportPath: result.mdPath
        )
    }
}
