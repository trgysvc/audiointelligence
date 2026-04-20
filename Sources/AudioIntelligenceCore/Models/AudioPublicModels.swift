import Foundation

/// Defines the high-level analysis domains available to the user.
public enum AudioFeature: String, CaseIterable, Codable, Sendable {
    case spectral
    case rhythm
    case harmonic
    case pitch
    case separation
    case semantic
    case forensic
    case mastering
}

/// The final report returned to the user after an Infinity Analysis.
public struct AudioReport: Codable, Sendable {
    /// A human-readable summary of the analysis results.
    public let summary: String
    
    /// The full, raw technical analysis data (26+ engines).
    public let rawAnalysis: MusicDNAAnalysis
    
    /// The formatted Markdown report string.
    public let reportText: String
    
    /// The local path to the generated .md report file, if saved.
    public let reportPath: String?

    public init(summary: String, rawAnalysis: MusicDNAAnalysis, reportText: String, reportPath: String?) {
        self.summary = summary
        self.rawAnalysis = rawAnalysis
        self.reportText = reportText
        self.reportPath = reportPath
    }
}
