// WaveletEngine.swift
// AudioIntelligence — Evolution Phase 1
//
// Industry Parity: librosa.wavelet — Multi-resolution analysis via DWT.

import Accelerate
import Foundation

public enum WaveletType: String, Sendable {
    case haar // db1
    case db2
    case db3
}

/// DWT Decomposition result
public struct WaveletDecomposition: Sendable {
    public let coefficients: [String: [Float]] // "cA": approx, "cD1": detail1, etc.
    public let levels: Int
    public let wavelet: WaveletType
}

/// Wavelet Engine
/// Provides Discrete Wavelet Transform (DWT) using vDSP-accelerated filter banks.
public final class WaveletEngine: Sendable {
    
    public init() {}
    
    /// Discrete Wavelet Transform (Multi-level Decomposition)
    /// - Parameters:
    ///   - samples: Input signal
    ///   - wavelet: Type of wavelet to use
    ///   - levels: Number of decomposition levels
    public func decompose(_ samples: [Float], wavelet: WaveletType = .haar, levels: Int = 3) -> WaveletDecomposition {
        let filters = getFilters(for: wavelet)
        var result: [String: [Float]] = [:]
        
        var currentApprox = samples
        
        for level in 1...levels {
            let (cA, cD) = decompositionStep(currentApprox, lowPass: filters.lowPass, highPass: filters.highPass)
            result["cD\(level)"] = cD
            currentApprox = cA
        }
        
        result["cA"] = currentApprox
        
        return WaveletDecomposition(coefficients: result, levels: levels, wavelet: wavelet)
    }
    
    // MARK: - Filter Definitions
    
    private struct WaveletFilters {
        let lowPass: [Float]
        let highPass: [Float]
    }
    
    private func getFilters(for type: WaveletType) -> WaveletFilters {
        switch type {
        case .haar:
            // Haar / DB1
            let s2 = sqrtf(2.0)
            return WaveletFilters(
                lowPass: [1.0/s2, 1.0/s2],
                highPass: [-1.0/s2, 1.0/s2]
            )
        case .db2:
            // Daubechies 2
            let s3 = sqrtf(3.0)
            let s2 = 4.0 * sqrtf(2.0)
            let low = [
                (1.0 + s3) / s2,
                (3.0 + s3) / s2,
                (3.0 - s3) / s2,
                (1.0 - s3) / s2
            ]
            let high = [
                low[3],
                -low[2],
                low[1],
                -low[0]
            ]
            return WaveletFilters(lowPass: low, highPass: high)
        case .db3:
            // Daubechies 3 (Approximation)
            let low: [Float] = [
                0.03522629188570953,
                0.16315334865413757,
                0.3929962140261304,
                0.446100062066804,
                0.22433623031350616,
                0.022230788094441,
                -0.08635150772390317,
                0.007807719117621245
            ]
            var high = [Float](repeating: 0, count: low.count)
            for i in 0..<low.count {
                high[i] = (i % 2 == 0 ? 1 : -1) * low[low.count - 1 - i]
            }
            return WaveletFilters(lowPass: low, highPass: high)
        }
    }
    
    // MARK: - Internal step logic
    
    private func decompositionStep(_ input: [Float], lowPass: [Float], highPass: [Float]) -> (cA: [Float], cD: [Float]) {
        let n = input.count
        let filterLen = lowPass.count
        
        // Output size for Downsampled convolution: (N + F - 1) / 2 approx
        // For simplicity, we use valid padding or circular for audio.
        // vDSP_conv default is 'valid' style or custom.
        
        var approx = [Float](repeating: 0, count: n)
        var detail = [Float](repeating: 0, count: n)
        
        // Convolution using vDSP
        vDSP_conv(input, 1, lowPass, 1, &approx, 1, vDSP_Length(n), vDSP_Length(filterLen))
        vDSP_conv(input, 1, highPass, 1, &detail, 1, vDSP_Length(n), vDSP_Length(filterLen))
        
        // Downsample by 2
        let nOut = n / 2
        var approxDown = [Float](repeating: 0, count: nOut)
        var detailDown = [Float](repeating: 0, count: nOut)
        
        for i in 0..<nOut {
            approxDown[i] = approx[i * 2]
            detailDown[i] = detail[i * 2]
        }
        
        return (approxDown, detailDown)
    }
}
