// CQTEngine.swift
// Elite Music DNA Engine — Phase 3
//
// Constant-Q Transform (CQT) for musical pitch analysis.
// Mirroring industry standard.cqt behavior.

import Foundation
import Accelerate

public final class CQTEngine: @unchecked Sendable {
    
    public let nBins: Int
    public let binsPerOctave: Int
    public let fMin: Float
    public let sampleRate: Double
    
    private let Q: Float
    
    public init(
        nBins: Int = 84, // 7 octaves
        binsPerOctave: Int = 12, 
        fMin: Float = 32.7, // C1
        sampleRate: Double = 22050
    ) {
        self.nBins = nBins
        self.binsPerOctave = binsPerOctave
        self.fMin = fMin
        self.sampleRate = sampleRate
        self.Q = 1.0 / (powf(2.0, 1.0 / Float(binsPerOctave)) - 1.0)
    }
    
    /// Computes the Constant-Q Transform using recursive decimation and fast frequency-domain kernels.
    /// Implementation based on Brown (1991) and Schörkhuber & Klapuri (2010).
    public func transform(_ samples: [Float]) -> [[Float]] {
        guard !samples.isEmpty else { return [] }
        
        let effectiveSamples = samples
        
        let nOctaves = Int(ceil(Float(nBins) / Float(binsPerOctave)))
        var currentSamples = effectiveSamples
        var result = [[Float]]()
        
        // 1. We process from the highest octave down to fMin
        // Each octave is processed, then the signal is decimated by 2.
        for octave in (0..<nOctaves).reversed() {
            let octaveFreq = fMin * powf(2.0, Float(octave))
            let octaveResult = processOctave(currentSamples, centerFreq: octaveFreq)
            result.append(contentsOf: octaveResult)
            
            // Decimate for the next (lower) octave
            if octave > 0 {
                currentSamples = decimateByTwo(currentSamples)
            }
        }
        
        return result.reversed() // Return from Low to High frequency
    }
    
    // MARK: - Internal Processing
    
    private func processOctave(_ samples: [Float], centerFreq: Float) -> [[Float]] {
        let n = samples.count
        let nFFT = Int(pow(2.0, ceil(log2(Double(n + 1))))) // Next power of 2
        
        let dftSetup = vDSP_DFT_zrop_CreateSetup(nil, vDSP_Length(nFFT), .FORWARD)!
        let complexIDFT = vDSP_DFT_zop_CreateSetup(nil, vDSP_Length(nFFT), .INVERSE)!
        defer {
            vDSP_DFT_DestroySetup(dftSetup)
            vDSP_DFT_DestroySetup(complexIDFT)
        }
        
        // 1. Forward FFT of the signal segment (ONLY ONCE PER OCTAVE)
        var realIn = samples + [Float](repeating: 0, count: nFFT - n)
        var sigSigReal = [Float](repeating: 0, count: nFFT / 2)
        var sigSigImag = [Float](repeating: 0, count: nFFT / 2)
        vDSP_DFT_Execute(dftSetup, realIn, [Float](repeating: 0, count: nFFT / 2), &sigSigReal, &sigSigImag)
        
        // Reconstruct full spectrum for complex multiplication
        var sigReal = [Float](repeating: 0, count: nFFT)
        var sigImag = [Float](repeating: 0, count: nFFT)
        sigReal[0] = sigSigReal[0]
        sigReal[nFFT/2] = sigSigImag[0]
        for f in 1..<nFFT/2 {
            sigReal[f] = sigSigReal[f]; sigImag[f] = sigSigImag[f]
            sigReal[nFFT - f] = sigSigReal[f]; sigImag[nFFT - f] = -sigSigImag[f]
        }
        
        var sigComplex = DSPSplitComplex(realp: &sigReal, imagp: &sigImag)
        var bins = [[Float]]()
        
        for i in 0..<binsPerOctave {
            let freq = centerFreq * powf(2.0, Float(i) / Float(binsPerOctave))
            let kernelLen = Int(Float(sampleRate) * Q / freq)
            let (kernelRe, kernelIm) = createComplexKernel(len: kernelLen, freq: freq)
            
            // 2. Forward FFT of the complex kernel
            var kRealIn = kernelRe + [Float](repeating: 0, count: nFFT - kernelLen)
            var kImagIn = kernelIm + [Float](repeating: 0, count: nFFT - kernelLen)
            var kerReal = [Float](repeating: 0, count: nFFT)
            var kerImag = [Float](repeating: 0, count: nFFT)
            
            let complexDFT = vDSP_DFT_zop_CreateSetup(nil, vDSP_Length(nFFT), .FORWARD)!
            vDSP_DFT_Execute(complexDFT, kRealIn, kImagIn, &kerReal, &kerImag)
            vDSP_DFT_DestroySetup(complexDFT)
            
            // 3. Frequency Domain Multiplication
            var resReal = [Float](repeating: 0, count: nFFT)
            var resImag = [Float](repeating: 0, count: nFFT)
            var kerComplex = DSPSplitComplex(realp: &kerReal, imagp: &kerImag)
            var resComplex = DSPSplitComplex(realp: &resReal, imagp: &resImag)
            
            vDSP_zvmul(&sigComplex, 1, &kerComplex, 1, &resComplex, 1, vDSP_Length(nFFT), 1)
            
            // 4. Inverse FFT
            var timeReal = [Float](repeating: 0, count: nFFT)
            var timeImag = [Float](repeating: 0, count: nFFT)
            vDSP_DFT_Execute(complexIDFT, resReal, resImag, &timeReal, &timeImag)
            
            // Normalize & Abs
            var scale = 1.0 / Float(nFFT)
            vDSP_vsmul(timeReal, 1, &scale, &timeReal, 1, vDSP_Length(nFFT))
            vDSP_vsmul(timeImag, 1, &scale, &timeImag, 1, vDSP_Length(nFFT))
            
            var magnitude = [Float](repeating: 0, count: n)
            var finalComplex = DSPSplitComplex(realp: &timeReal, imagp: &timeImag)
            vDSP_zvabs(&finalComplex, 1, &magnitude, 1, vDSP_Length(n))
            
            bins.append(magnitude)
        }
        return bins
    }
    
    private func createComplexKernel(len: Int, freq: Float) -> (real: [Float], imag: [Float]) {
        var kernelRe = [Float](repeating: 0, count: len)
        var kernelIm = [Float](repeating: 0, count: len)
        for i in 0..<len {
            let window = 0.5 * (1.0 - cosf(2.0 * Float.pi * Float(i) / Float(len - 1)))
            let angle = 2.0 * Float.pi * freq * Float(i) / Float(sampleRate)
            kernelRe[i] = window * cosf(angle)
            kernelIm[i] = window * -sinf(angle)
        }
        return (kernelRe, kernelIm)
    }
    
    private func decimateByTwo(_ samples: [Float]) -> [Float] {
        let n = samples.count
        let outputLen = n / 2
        var output = [Float](repeating: 0, count: outputLen)
        
        // Anti-aliasing low-pass filter
        let decimationFilter = [Float](repeating: 0.5, count: 2)
        vDSP_desamp(samples, 2, decimationFilter, &output, vDSP_Length(outputLen), 2)
        
        return output
    }
}
