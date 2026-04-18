// SpectrogramRenderer.swift
// Elite Music DNA Engine — Phase 5
//
// Professional Spectrogram Rendering (specshow equivalent).
// Maps 2D magnitude data to high-contrast color palettes.

import Foundation
import Accelerate

public enum SpectrogramPalette: String, Sendable {
    case magma
    case inferno
    case plasma
    case viridis
    case grayscale
}

public struct SpectrogramImage: Sendable {
    public let width: Int
    public let height: Int
    public let pixels: [UInt32] // RGBA8888
}

public final class SpectrogramRenderer: Sendable {
    
    public init() {}
    
    /// Renders an STFT magnitude matrix to a pixel buffer.
    /// - Parameters:
    ///   - magnitude: [nFreqs × nFrames] matrix
    ///   - palette: Color mapping style
    ///   - dBScale: If true, applies 10*log10 scale (recommended)
    public func render(magnitude: [[Float]], palette: SpectrogramPalette = .magma, dBScale: Bool = true) -> SpectrogramImage {
        guard !magnitude.isEmpty else { return SpectrogramImage(width: 0, height: 0, pixels: []) }
        
        let nFreqs = magnitude.count
        let nFrames = magnitude[0].count
        
        var normalized = [[Float]](repeating: [Float](repeating: 0, count: nFrames), count: nFreqs)
        
        // 1. Scale and Normalize
        for f in 0..<nFreqs {
            if dBScale {
                normalized[f] = magnitude[f].map { 10.0 * log10f(max($0, 1e-10)) }
            } else {
                normalized[f] = magnitude[f]
            }
        }
        
        // Find global min/max for normalization across all bins
        var globalMin: Float = Float.infinity
        var globalMax: Float = -Float.infinity
        
        for f in 0..<nFreqs {
            var fMin: Float = 0, fMax: Float = 0
            vDSP_minv(normalized[f], 1, &fMin, vDSP_Length(nFrames))
            vDSP_maxv(normalized[f], 1, &fMax, vDSP_Length(nFrames))
            globalMin = min(globalMin, fMin)
            globalMax = max(globalMax, fMax)
        }
        
        // 2. Map to Palette
        var pixels = [UInt32](repeating: 0, count: nFreqs * nFrames)
        let range = max(1e-8, globalMax - globalMin)
        
        for f in 0..<nFreqs {
            let row = nFreqs - 1 - f // Flip vertical (Low freqs at bottom)
            for t in 0..<nFrames {
                let val = (normalized[f][t] - globalMin) / range
                pixels[row * nFrames + t] = colorForValue(val, palette: palette)
            }
        }
        
        return SpectrogramImage(width: nFrames, height: nFreqs, pixels: pixels)
    }
    
    private func colorForValue(_ t: Float, palette: SpectrogramPalette) -> UInt32 {
        let val = max(0.0, min(1.0, t))
        
        switch palette {
        case .magma:
            // Simplified Magma-like gradient (Black -> Purple -> Pink -> Orange -> White)
            let r = UInt32(min(255, 255 * (val < 0.25 ? 4 * val * 0.2 : val < 0.5 ? 0.2 + (val-0.25)*2.4 : 0.8 + (val-0.5)*0.4)))
            let g = UInt32(min(255, 255 * (val < 0.5 ? 0 : val < 0.8 ? (val-0.5)*2.5 : 0.75 + (val-0.8)*1.25)))
            let b = UInt32(min(255, 255 * (val < 0.3 ? val * 2 : 0.6 + (val-0.3)*0.5)))
            return (255 << 24) | (b << 16) | (g << 8) | r
            
        case .viridis:
            // Simplified Viridis (Purple -> Blue -> Green -> Yellow)
            let r = UInt32(min(255, 255 * (val < 0.7 ? val * 0.3 : 0.21 + (val-0.7)*2.6)))
            let g = UInt32(min(255, 255 * (val < 0.3 ? val * 0.5 : 0.15 + (val-0.3)*1.2)))
            let b = UInt32(min(255, 255 * (val < 0.5 ? 0.3 + val : 0.8 - (val-0.5)*0.6)))
            return (255 << 24) | (b << 16) | (g << 8) | r
            
        case .grayscale:
            let gray = UInt32(val * 255)
            return (255 << 24) | (gray << 16) | (gray << 8) | gray
            
        default:
            // Placeholder for Inferno/Plasma... let's use a nice orange gradient
            let r = UInt32(min(255, 255 * val))
            let g = UInt32(min(255, 255 * val * 0.6))
            let b = UInt32(min(255, 255 * val * 0.2))
            return (255 << 24) | (b << 16) | (g << 8) | r
        }
    }
}
