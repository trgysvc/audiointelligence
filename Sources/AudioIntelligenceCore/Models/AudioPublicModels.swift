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
// `AudioReport` — the public analysis product — now lives in
// `Report/AudioReport.swift` with a measurement/estimation-layered schema.
