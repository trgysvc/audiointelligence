import Foundation

/// Forensic-grade error registry for AudioIntelligence.
/// Categorizes failures into IO, DSP, GPU, Neural, and Logic domains.
public enum AudioIntelligenceError: LocalizedError, Sendable {
    
    // MARK: - Categories
    
    case io(IOError)
    case dsp(DSPError)
    case gpu(GPUError)
    case neural(NeuralError)
    case logic(LogicError)
    case caching(CacheError)
    
    // MARK: - Enums
    
    public enum IOError: Sendable {
        case fileNotFound(URL)
        case permissionDenied(URL)
        case decodeFailed(URL)
        case formatNotSupported
    }
    
    public enum DSPError: Sendable {
        case fftSetupFailed
        case dimensionMismatch(expected: String, actual: String)
        case invalidWindowSize(Int)
        case calculationOverflow
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
    
    public enum LogicError: Sendable {
        case invalidParameter(String)
        case stateViolation(String)
    }
    
    public enum CacheError: Sendable {
        case writeFailed(String)
        case readFailed(String)
        case corruptData
    }
    
    // MARK: - LocalizedError
    
    public var errorDescription: String? {
        switch self {
        case .io(let error):
            switch error {
            case .fileNotFound(let url): return "File not found: \(url.lastPathComponent)"
            case .permissionDenied(let url): return "Permission denied: \(url.path)"
            case .decodeFailed(let url): return "Failed to decode audio: \(url.lastPathComponent)"
            case .formatNotSupported: return "Audio format not supported"
            }
        case .dsp(let error):
            switch error {
            case .fftSetupFailed: return "vDSP FFT Setup failed (Accelerate)"
            case .dimensionMismatch(let exp, let act): return "DSP Dimension Mismatch: Expected \(exp), got \(act)"
            case .invalidWindowSize(let size): return "Invalid window size for FFT: \(size)"
            case .calculationOverflow: return "DSP Calculation overflow/NaN detected"
            }
        case .gpu(let error):
            switch error {
            case .deviceNotFound: return "Metal-compatible GPU not found"
            case .commandQueueCreationFailed: return "Metal Command Queue creation failed"
            case .kernelExecutionFailed(let msg): return "Metal Kernel execution failed: \(msg)"
            case .shaderCompilationFailed(let msg): return "Metal Shader compilation failed: \(msg)"
            }
        case .neural(let error):
            switch error {
            case .modelNotFound(let name): return "CoreML model not found: \(name)"
            case .inferenceFailed(let msg): return "CoreML inference error: \(msg)"
            case .hardwareUnsupported: return "Apple Neural Engine (ANE) not available"
            }
        case .logic(let error):
            switch error {
            case .invalidParameter(let msg): return "Invalid Parameter: \(msg)"
            case .stateViolation(let msg): return "Engine State Violation: \(msg)"
            }
        case .caching(let error):
            switch error {
            case .writeFailed(let msg): return "Cache write failed: \(msg)"
            case .readFailed(let msg): return "Cache read failed: \(msg)"
            case .corruptData: return "Cache data corruption detected"
            }
        }
    }
}
