import Foundation

/// Represents various audio features that can be analyzed by the platform.
public enum AudioFeature: String, CaseIterable, Sendable {
    /// Spectral features including centroid, flux, and bandwidth.
    case spectral
    
    /// Rhythm features such as BPM and pulse patterns.
    case rhythm
    
    /// Forensic features like encoder identification and watermark detection.
    case forensic
}
