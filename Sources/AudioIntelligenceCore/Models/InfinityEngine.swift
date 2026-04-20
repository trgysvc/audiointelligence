/// Scientific Stability Tiers for AudioIntelligence Engines.
public enum StabilityTier: String, Codable, Sendable {
    /// Mathematically verified against industry standards (EBU, ITU, IEEE).
    case laboratory = "Laboratory Verified (Forensic Grade)"
    
    /// Statistical inference based on high-quality feature sets.
    case probabilistic = "Probabilistic Model (Analytical Grade)"
    
    /// Heuristic or theoretical estimate with lower adli certainty.
    case analytical = "Theoretical Guess (Experimental)"
}

/// A comprehensive registry of all 26 analysis and forensic engines available in the Infinity Suite.
/// This enum provides a central reference for developers to understand the granular DSP capabilities 
/// of the AudioIntelligence SDK.
public enum InfinityEngine: String, CaseIterable, Sendable {
    
    // MARK: - Core Spectral & Foundation
    
    /// The fundamental spectral analyst using vDSP-optimized FFT.
    case stft = "STFTEngine"
    
    /// Raw spectral characterization including Centroid, Flux, and Flatness.
    case spectral = "SpectralEngine"
    
    /// Complex-to-Log Constant-Q Transform for high-fidelity musical pitch mapping.
    case cqt = "CQTEngine"
    
    /// High-resolution Mel-scale spectrogram generation (optimized for neural inputs).
    case melSpectrogram = "MelSpectrogramEngine"
    
    // MARK: - Rhythmic & Temporal
    
    /// Multi-band transient analysis for rhythmic onset detection.
    case onsets = "OnsetEngine"
    
    /// Global tempo and beat consistency estimation using Dynamic Programming.
    case rhythm = "RhythmEngine"
    
    /// Cyclic tempo mapping and dominant period identification via tempograms.
    case tempogram = "TempogramEngine"
    
    /// Predominant Local Pulse tracking for rhythmic "feel" analysis.
    case plp = "PLPTracker"
    
    // MARK: - Harmonic & Tonal
    
    /// 12-bin harmonic energy distribution (Chromagram).
    case chroma = "ChromaEngine"
    
    /// 6-dimensional tonal centroid mapping for advanced harmonic relationships.
    case tonnetz = "TonnetzEngine"
    
    /// Time-domain fundamental frequency (F0) tracking via YIN.
    case yin = "YINEngine"
    
    /// Parabolic interpolation for sub-bin pitch tracking precision.
    case piptrack = "PiptrackEngine"
    
    /// Hidden Markov Model path optimization for pitch sequence modeling.
    case viterbi = "ViterbiEngine"
    
    // MARK: - Timbre & Semantic
    
    /// 20-coefficient Mel-Frequency Cepstral Coefficients for timbral fingerprinting.
    case mfcc = "MFCCEngine"
    
    /// Octopus-style band mapping for spectral contrast analysis.
    case contrast = "SpectralFeatureEngine"
    
    /// Energy distribution analysis across semantic frequency zones.
    case zones = "SpectralZoneEngine"
    
    /// Neural-assisted classification of dominant instruments and sound sources.
    case instruments = "InstrumentEngine"
    
    // MARK: - Forensic & Standards
    
    /// Bit-depth entropy and Shannon randomness auditing for forgery detection.
    case forensic = "ForensicEngine"
    
    /// EBU R128 / ITU-R BS.1770-4 scientifically calibrated loudness metering.
    case loudness = "LoudnessEngine"
    
    /// 511-tap high-precision inter-sample true peak detection.
    case truePeak = "TruePeakEngine"
    
    /// Phase correlation and mono compatibility verification.
    case stereo = "StereoEngine"
    
    /// Laboratory-grade scientific metrics including AES17 DR and SMPTE IMD.
    case audioScience = "AudioScienceEngine"
    
    // MARK: - Structural & Separation
    
    /// Foote Novelty-based structural segmentation (Verse, Chorus, Outro).
    case structure = "StructureEngine"
    
    /// Median-filter based Harmonic-Percussive Source Separation.
    case hpss = "HPSSEngine"
    
    /// Non-negative Matrix Factorization for blind pattern identification.
    case nmf = "NMFEngine"
    
    /// Apple Neural Engine (ANE) optimized stem separation and isolation.
    case neuralSeparation = "NeuralSeparationEngine"
    
    /// High-fidelity time-stretching and pitch-shifting (The 26th Engine).
    case manipulation = "ManipulationEngine"
    
    // MARK: - Traditional Musicology & Theory (v6.5+)
    
    /// Skeletal harmonic structural analysis (Schenkerian Reduction).
    case reduction = "ReductionEngine"
    
    /// Vertical harmonic relationship and chord function analysis.
    case theory = "TraditionalTheoryEngine"
    
    /// Melodic species and parallel interval error detection.
    case counterpoint = "CounterpointEngine"
    
    /// Structural cadential closure identification (PAC, Half, etc.).
    case cadence = "CadenceEngine"
    
    /// Leitmotif tracking and thematic transformation analysis.
    case motif = "MotifEngine"
    
    /// Horizontal tonal shift and transition technique detection.
    case modulation = "ModulationEngine"
    
    /// Time signature and pulse grouping analysis.
    case meter = "MeterEngine"
    
    /// Composition period and artistic movement inference.
    case historical = "HistoricalEngine"

    /// Returns the scientific stability tier for the engine.
    public var tier: StabilityTier {
        switch self {
        case .stft, .loudness, .truePeak, .audioScience, .cqt, .melSpectrogram, .rhythm:
            return .laboratory
        case .spectral, .onsets, .chroma, .tonnetz, .yin, .piptrack, .viterbi, .mfcc, .contrast, .zones, .forensic, .hpss, .nmf:
            return .probabilistic
        case .tempogram, .plp, .instruments, .stereo, .structure, .neuralSeparation, .manipulation, .reduction, .theory, .counterpoint, .cadence, .motif, .modulation, .meter, .historical:
            return .analytical
        }
    }

    /// Returns a localized, professional description of the engine's purpose.
    public var description: String {
        switch self {
        case .stft: return "Fundamental spectral analyst (FFT foundation)."
        case .spectral: return "High-level spectral descriptors (Centroid, Flux, Flatness)."
        case .cqt: return "Constant-Q Transform for musical pitch accuracy."
        case .melSpectrogram: return "Mel-scale spectral representation for machine learning."
        case .onsets: return "Transient and rhythmic onset detection."
        case .rhythm: return "BPM and pulse energy estimation using Dynamic Programming."
        case .tempogram: return "Cyclic tempo and rhythmic recurrence mapping."
        case .plp: return "Predominant Local Pulse tracking for rhythmic feel."
        case .chroma: return "12-bin harmonic energy distribution (Chromagram)."
        case .tonnetz: return "6D tonal centroid mapping for harmonic relationships."
        case .yin: return "Time-domain fundamental frequency (F0) estimation."
        case .piptrack: return "Sub-bin refined pitch tracking via parabolic interpolation."
        case .viterbi: return "HMM sequence modeling for pitch path optimization."
        case .mfcc: return "20-coefficient Mel-Frequency Cepstral Coefficients."
        case .contrast: return "Octopus-style band mapping for spectral contrast."
        case .zones: return "Frequency zone energy distribution analysis."
        case .instruments: return "Neural instrument identification and classification."
        case .forensic: return "Bit-depth entropy and Shannon randomness auditing."
        case .loudness: return "EBU R128 / ITU-R BS.1770-4 calibrated metering."
        case .truePeak: return "High-precision inter-sample peak detection."
        case .stereo: return "Phase correlation and mono compatibility verification."
        case .audioScience: return "Laboratory-grade scientific metrics (AES17, IMD)."
        case .structure: return "Structural segmentation (Verse, Chorus, Outro)."
        case .hpss: return "Harmonic-Percussive Source Separation."
        case .nmf: return "Non-negative Matrix Factorization for pattern detection."
        case .neuralSeparation: return "ANE-accelerated neural stem separation."
        case .reduction: return "Skeletal harmonic structural analysis (Schenkerian Reduction)."
        case .theory: return "Vertical harmonic relationship and chord function analysis."
        case .counterpoint: return "Melodic species and parallel interval error detection."
        case .cadence: return "Structural cadential closure identification (PAC, Half, etc.)."
        case .motif: return "Leitmotif tracking and thematic transformation analysis."
        case .modulation: return "Horizontal tonal shift and transition technique detection."
        case .meter: return "Time signature and pulse grouping analysis."
        case .historical: return "Composition period and artistic movement inference."
        case .manipulation: return "High-fidelity time-stretching and pitch-shifting."
        }
    }
}
