import Foundation

/// Represents the modular feature domains available in the AudioIntelligence Infinity Engine.
/// For a granular list of all 26 analysis engines, see `InfinityEngine`.
public enum AudioFeature: String, CaseIterable, Sendable {
    /// Spectral analysis including STFT, Mel-scale, and MFCC.
    case spectral
    
    /// Rhythmic analysis including BPM, pulse energy, and beat tracking.
    case rhythm
    
    /// Melodic and harmonic analysis including Chroma and Tonnetz.
    case harmonic
    
    /// Fundamental frequency and pitch sequence tracking (YIN/Viterbi).
    case pitch
    
    /// Source separation including HPSS and Neural isolation (ANE).
    case separation
    
    /// High-level semantic descriptors and instrument identification.
    case semantic
    
    /// Forensic auditing including bit-depth entropy and codec signatures.
    case forensic
    
    /// Professional mastering metrics (EBU R128, AES17, True Peak).
    case mastering
}
