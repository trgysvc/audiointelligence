import Foundation
import Accelerate

/// v52.1: Scientific Auditor
/// A specialized internal engine for performing critical diagnostic sweeps.
/// This tool acts as the "Internal Internal" verification layer.
public final class ScientificAuditor: Sendable {
    
    private let sampleRate: Double = 48000.0
    
    public init() {}
    
    public struct AuditReport: Sendable {
        public let scenarioName: String
        public let expectedValue: Float
        public let measuredValue: Float
        public let errorDb: Float
        public let passed: Bool
    }
    
    /// Scenario A: EBU Tech 3341 - 2.1 (Reference Sine)
    public func runScenarioA() -> AuditReport {
        let n = Int(sampleRate * 5.0)
        // -23 dBFS *RMS* sine (peak = RMS·√2). LUFS is RMS-based, so a peak-calibrated
        // sine would read ~3 dB low — the spurious "calibration drift". K-weighting ≈ 0 dB
        // at 1 kHz, so a -23 dBFS RMS sine must read ≈ -23 LUFS.
        let amp = powf(10.0, -23.0 / 20.0) * sqrtf(2.0)

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
        // -20 dBFS RMS signal (peak = RMS·√2) followed by digital silence; the gate must
        // reject the silent half and report the -20 LUFS of the active half.
        let amp = powf(10.0, -20.0 / 20.0) * sqrtf(2.0)

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
        // SNR needs an active half and a silent (noise-only) half. A −20 dBFS RMS tone over
        // a ≈−70 dBFS noise floor gives ≈50 dB SNR, with both halves on the right side of
        // the engine's −40 dBFS active/noise window split.
        let half = 24000
        let n = half * 2
        let ampStim = powf(10.0, -20.0 / 20.0) * sqrtf(2.0) // -20 dBFS RMS
        let ampNoise = powf(10.0, -70.0 / 20.0) * sqrtf(3.0) // ~-70 dBFS RMS uniform noise

        var samples = [Float](repeating: 0, count: n)
        for i in 0..<n {
            let noise = Float.random(in: -ampNoise...ampNoise)
            if i < half {
                samples[i] = ampStim * sinf(2.0 * Float.pi * 997.0 * Float(i) / Float(sampleRate)) + noise
            } else {
                samples[i] = noise // silent half: noise floor only
            }
        }
        
        let engine = AudioScienceEngine(sampleRate: sampleRate)
        let result = engine.analyze(samples: samples)

        // AES17 dynamic range: a −60 dBFS stimulus over a −110 dBFS noise floor implies a
        // signal-to-noise ratio of ≈50 dB. The meaningful quantity is SNR, not LRA (a
        // steady tone has ~0 LRA), so this scenario measures SNR.
        let measured = result.snr

        return AuditReport(
            scenarioName: "AES17 - Dynamic Range (SNR)",
            expectedValue: 50.0,
            measuredValue: measured,
            errorDb: measured - 50.0,
            passed: measured > 35.0
        )
    }
}
