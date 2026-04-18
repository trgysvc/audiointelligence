import Foundation

/// Enterprise-grade error registry for AudioIntelligence.
/// Categorizes failures into IO, DSP, GPU, Neural, and Domain-specific MIR errors.
public enum AudioIntelligenceError: LocalizedError, Sendable {
    
    // MARK: - Categories
    
    case io(IOError)
    case dsp(DSPError)
    case gpu(GPUError)
    case neural(NeuralError)
    case forensic(ForensicError)
    case logic(LogicError)
    case caching(CacheError)
    
    // MARK: - Enums
    
    public enum IOError: Sendable {
        case fileNotFound(URL)
        case permissionDenied(URL)
        case decodeFailed(URL)
        case formatNotSupported(String)
        case streamInterrupted
    }
    
    public enum DSPError: Sendable {
        case fftSetupFailed
        case dimensionMismatch(expected: String, actual: String)
        case invalidWindowSize(Int)
        case calculationOverflow
        case sampleRateMismatch(expected: Double, actual: Double)
    }
    
    public enum GPUError: Sendable {
        case deviceNotFound
        case commandQueueCreationFailed
        case kernelExecutionFailed(String)
        case shaderCompilationFailed(String)
    }
    
    public enum NeuralError: Sendable {
        case modelNotFound(String)
        case inferenceFailed(String)
        case hardwareUnsupported
    }
    
    public enum ForensicError: Sendable {
        case entropyCalculationFailed
        case codecSignatureMismatch
        case bitDepthResolutionFailure
    }
    
    public enum LogicError: Sendable {
        case invalidParameter(String)
        case stateViolation(String)
        case featureNotLicensed(String)
    }
    
    public enum CacheError: Sendable {
        case writeFailed(String)
        case readFailed(String)
        case corruptData
        case storageLimitExceeded
    }
    
    // MARK: - LocalizedError
    
    public var errorDescription: String? {
        switch self {
        case .io(let error):
            switch error {
            case .fileNotFound(let url): return "File not found: \(url.lastPathComponent)"
            case .permissionDenied(let url): return "Permission denied: \(url.path)"
            case .decodeFailed(let url): return "Failed to decode audio: \(url.lastPathComponent)"
            case .formatNotSupported(let ext): return "Audio format '\(ext)' not supported by native engine"
            case .streamInterrupted: return "Audio stream was interrupted during processing"
            }
        case .dsp(let error):
            switch error {
            case .fftSetupFailed: return "vDSP FFT Setup failed (Accelerate Architecture)"
            case .dimensionMismatch(let exp, let act): return "DSP Dimension Mismatch: Expected \(exp), got \(act)"
            case .invalidWindowSize(let size): return "Invalid window size for FFT: \(size)"
            case .calculationOverflow: return "DSP Calculation overflow or NaN detected"
            case .sampleRateMismatch(let exp, let act): return "Sample rate mismatch: SDK expected \(exp), signal is \(act)"
            }
        case .gpu(let error):
            switch error {
            case .deviceNotFound: return "Metal-compatible GPU not found for hardware acceleration"
            case .commandQueueCreationFailed: return "Metal Command Queue creation failed"
            case .kernelExecutionFailed(let msg): return "Metal Kernel execution failed: \(msg)"
            case .shaderCompilationFailed(let msg): return "Metal Shader compilation failed: \(msg)"
            }
        case .neural(let error):
            switch error {
            case .modelNotFound(let name): return "CoreML model not found: \(name)"
            case .inferenceFailed(let msg): return "CoreML ANE inference error: \(msg)"
            case .hardwareUnsupported: return "Apple Neural Engine (ANE) not available on this device"
            }
        case .forensic(let error):
            switch error {
            case .entropyCalculationFailed: return "Failed to calculate Shannon Entropy for bit-depth validation"
            case .codecSignatureMismatch: return "Signal spectral signature does not match reported codec"
            case .bitDepthResolutionFailure: return "Failure to resolve native bit-depth resolution"
            }
        case .logic(let error):
            switch error {
            case .invalidParameter(let msg): return "Invalid Parameter: \(msg)"
            case .stateViolation(let msg): return "Engine State Violation: \(msg)"
            case .featureNotLicensed(let feature): return "Feature '\(feature)' requires a valid license manifest"
            }
        case .caching(let error):
            switch error {
            case .writeFailed(let msg): return "Cache write failed: \(msg)"
            case .readFailed(let msg): return "Cache read failed: \(msg)"
            case .corruptData: return "Cache data corruption detected (Checksum Mismatch)"
            case .storageLimitExceeded: return "Infinty Cache disk limit (4GB) exceeded"
            }
        }
    }
}
