import Foundation
import AudioIntelligenceCore

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
    
    /// Analyzes an audio file and returns a professional report.
    /// This connects the public API to the v25.0 core engines.
    public func analyze(
        url: URL,
        progress: @Sendable @escaping (Double, String, String?) -> Void = { _, _, _ in }
    ) async throws -> AudioReport {
        
        let result = try await DNAReportBuilder.analyze(url: url, progress: progress)
        
        return AudioReport(
            summary: "Analysis complete for \(url.lastPathComponent). BPM: \(result.analysis.rhythm.bpm)",
            rawAnalysis: result.analysis,
            reportText: result.reportText,
            reportPath: result.mdPath
        )
    }
}
