import Foundation
import Accelerate

/// v52.1: Scientific Auditor
/// A specialized internal engine for performing critical diagnostic sweeps.
/// This tool acts as the "Internal Internal" verification layer.
public final class ScientificAuditor: Sendable {
    
    private let sampleRate: Double = 48000.0
    
    public init() {}
    
    public struct AuditReport: Sendable {
        let scenarioName: String
        let expectedValue: Float
        let measuredValue: Float
        let errorDb: Float
        let passed: Bool
    }
    
    /// Scenario A: EBU Tech 3341 - 2.1 (Reference Sine)
    public func runScenarioA() -> AuditReport {
        let n = Int(sampleRate * 5.0)
        let amp = powf(10.0, -23.0 / 20.0) // -23dBFS Peak Sine
        
        var samples = [Float](repeating: 0, count: n)
        for i in 0..<n {
            samples[i] = amp * sinf(2.0 * Float.pi * 1000.0 * Float(i) / Float(sampleRate))
        }
        
        let engine = LoudnessEngine(sampleRate: sampleRate)
        let result = engine.analyze(samples: samples)
        
        let measured = result.integratedLUFS
        let error = measured - (-23.0)
        
        return AuditReport(
            scenarioName: "EBU 3341 - Calibration (Sine)",
            expectedValue: -23.0,
            measuredValue: measured,
            errorDb: error,
            passed: abs(error) < 0.1
        )
    }
    
    /// Scenario B: EBU Tech 3341 - 2.2 (Gate Sensitivity)
    public func runScenarioB() -> AuditReport {
        let nHalf = Int(sampleRate * 5.0)
        // Correct EBU test: -20 LUFS signal followed by "digital zero" or sub-gate noise.
        let amp = powf(10.0, -20.0 / 20.0) 
        
        var samples = [Float](repeating: 0, count: nHalf * 2)
        for i in 0..<nHalf {
            samples[i] = amp * sinf(2.0 * Float.pi * 1000.0 * Float(i) / Float(sampleRate))
        }
        // Silence remains 0.0
        
        let engine = LoudnessEngine(sampleRate: sampleRate)
        let result = engine.analyze(samples: samples)
        
        let measured = result.integratedLUFS
        let error = measured - (-20.0)
        
        return AuditReport(
            scenarioName: "EBU 3341 - Gating Rejection",
            expectedValue: -20.0,
            measuredValue: measured,
            errorDb: error,
            passed: abs(error) < 0.2
        )
    }
    
    /// Scenario C: EBU Tech 3342 (LRA Performance)
    public func runScenarioC() -> AuditReport {
        let nHalf = Int(sampleRate * 10.0)
        let amp1 = powf(10.0, -20.0 / 20.0)
        let amp2 = powf(10.0, -30.0 / 20.0)
        
        var samples = [Float](repeating: 0, count: nHalf * 2)
        for i in 0..<nHalf {
            samples[i] = amp1 * sinf(2.0 * Float.pi * 1000.0 * Float(i) / Float(sampleRate))
            samples[i + nHalf] = amp2 * sinf(2.0 * Float.pi * 1000.0 * Float(i) / Float(sampleRate))
        }
        
        let engine = LoudnessEngine(sampleRate: sampleRate)
        let result = engine.analyze(samples: samples)
        
        let measured = result.loudnessRange
        let error = measured - 10.0
        
        return AuditReport(
            scenarioName: "EBU 3342 - LRA (Dynamic Range)",
            expectedValue: 10.0,
            measuredValue: measured,
            errorDb: error,
            passed: abs(error) < 0.5
        )
    }
    
    /// Scenario D: AES17 Forensic Accuracy
    public func runScenarioD() -> AuditReport {
        let n = 48000
        let ampStim = powf(10.0, -60.0 / 20.0) // -60 dBFS
        let ampNoise = powf(10.0, -110.0 / 20.0) // -110 dBFS Noise Floor
        
        var samples = [Float](repeating: 0, count: n)
        for i in 0..<n {
            let sine = ampStim * sinf(2.0 * Float.pi * 997.0 * Float(i) / Float(sampleRate))
            let noise = Float.random(in: -ampNoise...ampNoise)
            samples[i] = sine + noise
        }
        
        let engine = AudioScienceEngine(sampleRate: sampleRate)
        let result = engine.analyze(samples: samples)
        
        // Final measurement logic based on noise floor relation to stimulus
        let measured = result.dynamicRangeAES17
        
        return AuditReport(
            scenarioName: "AES17 - Forensic Dyn Range",
            expectedValue: 50.0, // Relative to stimulus
            measuredValue: measured,
            errorDb: measured - 50.0,
            passed: measured > 45.0
        )
    }
}
