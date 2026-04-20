// TempogramEngine.swift
// Elite Music DNA Engine — Phase 4
//
// Tempogram implementation for mapping tempo variations over time.
// Mirroring industry standard.feature.tempogram using Autocorrelation (ACT).
// Standardized: Includes Hann windowing, L∞ normalization, and BPM frequencies.

import Foundation
import Accelerate

public struct TempogramResult: Codable, Sendable {
    /// The tempogram matrix [lagBin × nFrames].
    public let tempogram: [[Float]]
    /// The BPM values corresponding to each lag bin.
    public let bpms: [Float] 
    public let winLength: Int
    public let hopLength: Int
}

/// Cyclic Tempo and Rhythmic Periodicity Engine.
/// Provides a detailed mapping of rhythmic recurrence and dominant tempo periods.
public final class TempogramEngine: Sendable {
    
    private let winLength: Int
    private let sampleRate: Double
    
    public init(winLength: Int = 384, sampleRate: Double = 22050) {
        self.winLength = winLength
        self.sampleRate = sampleRate
    }
    
    /// Computes an Autocorrelation Tempogram from onset strength.
    /// Matches Librosa's tempogram logic: framing → windowing → autocorrelation → normalization.
    /// - Parameters:
    ///   - onsetStrength: Envelope from OnsetEngine (typically sampled at 512/sr intervals)
    ///   - odfHop: The hop length used to create the onsetStrength (default: 512)
    ///   - tempogramHop: Temporal resolution for the tempogram (default: 1 ODF frame)
    public func computeACT(onsetStrength: [Float], odfHop: Int = 512, tempogramHop: Int = 1) -> TempogramResult {
        let n = onsetStrength.count
        let nFrames = max(0, (n - winLength) / tempogramHop + 1)
        
        guard nFrames > 0 else {
            return TempogramResult(tempogram: [], bpms: [], winLength: winLength, hopLength: tempogramHop)
        }
        
        // 1. Prepare Hann window
        var window = [Float](repeating: 0, count: winLength)
        vDSP_hann_window(&window, vDSP_Length(winLength), Int32(vDSP_HANN_NORM))
        
        var tempogram = [[Float]](repeating: [Float](repeating: 0, count: nFrames), count: winLength)
        
        for t in 0..<nFrames {
            let start = t * tempogramHop
            let end = start + winLength
            var frame = Array(onsetStrength[start..<end])
            
            // 2. Apply windowing (Librosa parity)
            vDSP_vmul(frame, 1, window, 1, &frame, 1, vDSP_Length(winLength))
            
            // 3. Autocorrelation
            let acf = DSPHelpers.autocorrelate(frame, maxSize: winLength)
            
            // 4. L∞ Normalization per frame (Librosa norm=inf)
            var maxVal: Float = 0
            vDSP_maxv(acf, 1, &maxVal, vDSP_Length(winLength))
            
            let normFactor = maxVal > 1e-10 ? 1.0 / maxVal : 0
            var normalizedAcf = [Float](repeating: 0, count: winLength)
            var scalar = normFactor
            vDSP_vsmul(acf, 1, &scalar, &normalizedAcf, 1, vDSP_Length(winLength))
            
            // Fill tempogram column
            for lag in 0..<winLength {
                tempogram[lag][t] = normalizedAcf[lag]
            }
        }
        
        // 5. Calculate BPM frequencies for each lag bin
        // Librosa: bpms[k] = 60.0 / (lag[k] * odfHop / sr)
        var bpms = [Float](repeating: 0, count: winLength)
        for k in 0..<winLength {
            if k == 0 {
                bpms[k] = Float.infinity
            } else {
                let periodSeconds = Double(k * odfHop) / sampleRate
                bpms[k] = Float(60.0 / periodSeconds)
            }
        }
        
        return TempogramResult(
            tempogram: tempogram,
            bpms: bpms,
            winLength: winLength,
            hopLength: tempogramHop
        )
    }
}
