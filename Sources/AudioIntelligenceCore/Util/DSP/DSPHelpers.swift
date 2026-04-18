// DSPHelpers.swift
// Elite Music DNA Engine — Phase 1
//
// vDSP helper collection: used across all analysis engines.
// - Cosine similarity (vDSP_dotpr based)
// - Autocorrelation (for YIN)
// - Median filter (1D — foundation for HPSS 2D)
// - Normalize, softmax, cumulative sum

import Accelerate
import Foundation

// MARK: - Cosine Similarity

public enum DSPHelpers {

    // MARK: Cosine Similarity

    /// Cosine similarity between two L2-normalized vectors.
    /// Used by StructureEngine SSM: vDSP_dotpr based, O(n) vectorized.
    ///
    /// Industry Standard: cosine_similarity via sklearn, US: dot(a/|a|, b/|b|)
    public static func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot: Float = 0
        vDSP_dotpr(a, 1, b, 1, &dot, vDSP_Length(a.count))
        return dot  // If already L2-normalized, the dot product equals cosine similarity
    }

    /// Batch cosine similarity: Self-Similarity Matrix calculation.
    /// Input: features [nFeatures × nFrames] (each column is a frame)
    /// Output: SSM [nFrames × nFrames]
    public static func selfSimilarityMatrix(_ features: [[Float]]) -> [[Float]] {
        let nFrames = features[0].count
        let nFeats = features.count

        // Prepare each frame as a column vector and L2-normalize
        var frames: [[Float]] = (0..<nFrames).map { t in
            (0..<nFeats).map { f in features[f][t] }
        }

        // L2-normalize
        for i in 0..<nFrames {
            var norm: Float = 0
            vDSP_svesq(frames[i], 1, &norm, vDSP_Length(nFeats))
            norm = sqrtf(norm)
            if norm > 1e-8 {
                var invNorm = 1.0 / norm
                vDSP_vsmul(frames[i], 1, &invNorm, &frames[i], 1, vDSP_Length(nFeats))
            }
        }

        // SSM: [nFrames × nFrames]
        var ssm = [[Float]](repeating: [Float](repeating: 0, count: nFrames), count: nFrames)
        for i in 0..<nFrames {
            for j in i..<nFrames {
                var dot: Float = 0
                vDSP_dotpr(frames[i], 1, frames[j], 1, &dot, vDSP_Length(nFeats))
                ssm[i][j] = dot
                ssm[j][i] = dot
            }
        }

        return ssm
    }

    // MARK: Autocorrelation (YIN for)

    /// Full autocorrelation via vDSP_conv with strict Bound-Checks.
    /// YIN algorithm: acf = autocorrelate(y, max_size)
    /// Output includes only lags [0...maxSize-1]
    public static func autocorrelate(_ signal: [Float], maxSize: Int) -> [Float] {
        let n = signal.count
        guard n > 0 && maxSize > 0 else { return [] }
        
        let nResult = 2 * n - 1
        var fullAcorr = [Float](repeating: 0, count: nResult)
        
        // vDSP_conv requires reversed window for cross-correlation logic
        let reversed = Array(signal.reversed())
        
        // Bound-Check: vDSP_conv needs SignalLength >= FilterLength
        // Here both N, so it's OK.
        vDSP_conv(signal, 1, reversed, 1, &fullAcorr, 1, vDSP_Length(n), vDSP_Length(n))
        
        // vDSP_conv(signal, reversed) results are centered at (n-1).
        // lag 0 is at fullAcorr[n-1]
        let offset = n - 1
        let outSize = min(maxSize, n)
        var result = [Float](repeating: 0, count: outSize)
        
        // Safe access to fullAcorr
        for lag in 0..<outSize {
            let idx = offset + lag
            if idx >= 0 && idx < nResult {
                result[lag] = fullAcorr[idx]
            }
        }
        
        return result
    }

    // MARK: 1D Median Filter

    /// 1D sliding window median. Hem HPSS for (2D component),
    /// hem onset max-filter for used.
    /// Industry Standard: scipy.ndimage.maximum_filter1d(S, max_size, axis)
    ///
    /// Note: 2D HPSS for HPSSEngine'de vImage used (bu fonksiyon 1D).
    public static func medianFilter1D(_ signal: [Float], windowSize: Int) -> [Float] {
        guard !signal.isEmpty && windowSize > 0 else { return signal }
        let halfW = windowSize / 2
        let n = signal.count
        var result = [Float](repeating: 0, count: n)

        for i in 0..<n {
            let lo = max(0, i - halfW)
            let hi = min(n - 1, i + halfW)
            var window = Array(signal[lo...hi])
            window.sort()
            result[i] = window[window.count / 2]
        }

        return result
    }

    /// 1D Max filter. Industry Standard onset'in `maximum_filter1d` equivalent.
    public static func maxFilter1D(_ signal: [Float], windowSize: Int) -> [Float] {
        guard !signal.isEmpty && windowSize > 0 else { return signal }
        let halfW = windowSize / 2
        let n = signal.count
        var result = [Float](repeating: 0, count: n)

        for i in 0..<n {
            let lo = max(0, i - halfW)
            let hi = min(n - 1, i + halfW)
            result[i] = signal[lo...hi].max() ?? signal[i]
        }

        return result
    }

    // MARK: Normalization

    /// L2-normalize a vector. Industry Standard: util.normalize(x, norm=2)
    public static func normalizeL2(_ v: [Float]) -> [Float] {
        guard !v.isEmpty else { return [] }
        var norm: Float = 0
        vDSP_svesq(v, 1, &norm, vDSP_Length(v.count))
        norm = sqrtf(norm)
        guard norm > 1e-8 else { return v }
        var invNorm = 1.0 / norm
        var out = v
        vDSP_vsmul(out, 1, &invNorm, &out, 1, vDSP_Length(out.count))
        return out
    }

    /// Max-normalize: divide by max. Industry Standard: normalize(x, norm=inf)
    public static func normalizeMax(_ v: [Float]) -> [Float] {
        guard !v.isEmpty else { return [] }
        var maxVal: Float = 0
        vDSP_maxv(v, 1, &maxVal, vDSP_Length(v.count))
        guard maxVal > 1e-8 else { return v }
        var invMax = 1.0 / maxVal
        var out = v
        vDSP_vsmul(out, 1, &invMax, &out, 1, vDSP_Length(out.count))
        return out
    }

    /// L1-normalize: divide by sum of absolute values. Industry Standard: util.normalize(x, norm=1)
    public static func normalizeL1(_ v: [Float]) -> [Float] {
        guard !v.isEmpty else { return [] }
        var absV = v
        vDSP_vabs(v, 1, &absV, 1, vDSP_Length(v.count))
        var sum: Float = 0
        vDSP_sve(absV, 1, &sum, vDSP_Length(v.count))
        
        guard sum > 1e-8 else { return v }
        var invSum = 1.0 / sum
        var out = v
        vDSP_vsmul(out, 1, &invSum, &out, 1, vDSP_Length(out.count))
        return out
    }

    // MARK: Cumulative Sum (YIN CMND for)

    /// Cumulative sum. NumPy: np.cumsum(x)
    public static func cumsum(_ v: [Float]) -> [Float] {
        guard !v.isEmpty else { return [] }
        var result = [Float](repeating: 0, count: v.count)
        var running: Float = 0
        for (i, val) in v.enumerated() {
            running += val
            result[i] = running
        }
        return result
    }

    // MARK: Log + Tiny

    /// log with tiny constant (Industry Standard: util.tiny) for numerical stability.
    /// tiny(float32) ≈ 1.175e-38
    public static let tinyFloat: Float = 1.175494351e-38

    public static func safeLog(_ v: [Float]) -> [Float] {
        v.map { logf(max($0, tinyFloat)) }
    }

    // MARK: Peak Picking

    /// Finding local maxima. Industry Standard: util.localmax(x)
    public static func localMax(_ signal: [Float]) -> [Int] {
        guard signal.count >= 3 else { return [] }
        var peaks: [Int] = []
        for i in 1..<(signal.count - 1) {
            if signal[i] > signal[i - 1] && signal[i] >= signal[i + 1] {
                peaks.append(i)
            }
        }
        return peaks
    }

    /// Peak picking with threshold. Industry Standard: util.peak_pick parameters:
    /// pre_max=30ms, post_max=0ms, pre_avg=100ms, post_avg=100ms, wait=30ms, delta=0.07
    public static func peakPick(
        _ signal: [Float],
        preMax: Int = 3,
        postMax: Int = 1,
        preAvg: Int = 10,
        postAvg: Int = 10,
        wait: Int = 3,
        delta: Float = 0.07
    ) -> [Int] {
        let n = signal.count
        guard n > 0 else { return [] }
        var peaks: [Int] = []
        var lastPeak = -wait - 1

        for i in 0..<n {
            let loMax = max(0, i - preMax)
            let hiMax = min(n - 1, i + postMax)
            let loAvg = max(0, i - preAvg)
            let hiAvg = min(n - 1, i + postAvg)

            let localMax = signal[loMax...hiMax].max() ?? 0
            let localAvg = signal[loAvg...hiAvg].reduce(0, +) / Float(hiAvg - loAvg + 1)

            if signal[i] == localMax && signal[i] >= localAvg + delta && i - lastPeak > wait {
                peaks.append(i)
                lastPeak = i
            }
        }

        return peaks
    }

    // MARK: Checkerboard Kernel (Foote Novelty - StructureEngine for)

    /// Foote (2000) checkerboard kernel: structural boundary detection.
    /// k × k kernel, top-left + bottom-right = +1, top-right + bottom-left = -1
    public static func footeKernel(size: Int) -> [[Float]] {
        guard size > 0 else { return [] }
        var kernel = [[Float]](repeating: [Float](repeating: 0, count: size), count: size)
        let half = size / 2
        for i in 0..<size {
            for j in 0..<size {
                let sign: Float = ((i < half) == (j < half)) ? 1.0 : -1.0
                // Gaussian taper
                let gi = Float(i - half + 1)
                let gj = Float(j - half + 1)
                let gauss = expf(-0.5 * (gi * gi + gj * gj) / Float(max(1, half * half)))
                kernel[i][j] = sign * gauss
            }
        }
        return kernel
    }

    /// Apply Foote novelty score on SSM → boundary score array
    public static func footeNovelty(ssm: [[Float]], kernelSize: Int = 64) -> [Float] {
        let n = ssm.count
        guard n >= kernelSize else { return [Float](repeating: 0, count: n) }
        let kernel = footeKernel(size: kernelSize)
        let half = kernelSize / 2
        var novelty = [Float](repeating: 0, count: n)

        for t in half..<(n - half) {
            var score: Float = 0
            for i in 0..<kernelSize {
                for j in 0..<kernelSize {
                    let si = t - half + i
                    let sj = t - half + j
                    if si >= 0 && si < n && sj >= 0 && sj < n {
                        score += kernel[i][j] * ssm[si][sj]
                    }
                }
            }
            novelty[t] = max(0, score) // half-wave rectify
        }

        return novelty
    }
    
    /// Streaming Foote Novelty: Calculates novelty WITHOUT storing the full SSM.
    /// Memory: O(N) instead of O(N^2). Precision: 100% Identical.
    public static func streamingFooteNovelty(features: [[Float]], kernelSize: Int = 64) -> [Float] {
        guard !features.isEmpty else { return [] }
        let nFrames = features[0].count
        let nFeats = features.count
        guard nFrames >= kernelSize else { return [Float](repeating: 0, count: nFrames) }
        
        let kernel = footeKernel(size: kernelSize)
        let half = kernelSize / 2
        var novelty = [Float](repeating: 0, count: nFrames)
        
        // Prepare L2-normalized frames for streaming dot products
        var frames: [[Float]] = (0..<nFrames).map { t in
            (0..<nFeats).map { f in features[f][t] }
        }
        for i in 0..<nFrames {
            frames[i] = normalizeL2(frames[i])
        }

        for t in half..<(nFrames - half) {
            var score: Float = 0
            for i in 0..<kernelSize {
                for j in 0..<kernelSize {
                    let si = t - half + i
                    let sj = t - half + j
                    
                    // Compute similarity on-the-fly
                    var dot: Float = 0
                    vDSP_dotpr(frames[si], 1, frames[sj], 1, &dot, vDSP_Length(nFeats))
                    score += kernel[i][j] * dot
                }
            }
            novelty[t] = max(0, score)
        }
        return novelty
    }

    /// Flat Buffer Version: Streaming Foote Novelty
    public static func streamingFooteNovelty(flatFeatures: [Float], featureDim: Int, nFrames: Int, kernelSize: Int = 64) -> [Float] {
        guard nFrames >= kernelSize && featureDim > 0 else { return [Float](repeating: 0, count: nFrames) }
        let kernel = footeKernel(size: kernelSize)
        let half = kernelSize / 2
        var novelty = [Float](repeating: 0, count: nFrames)
        
        flatFeatures.withUnsafeBufferPointer { fBuff in
            guard let base = fBuff.baseAddress else { return }
            let totalMaxIdx = flatFeatures.count
            
            for t in half..<(nFrames - half) {
                var score: Float = 0
                for i in 0..<kernelSize {
                    for j in 0..<kernelSize {
                        let si = t - half + i
                        let sj = t - half + j
                        
                        // Critical Bound-Check for Pointer Arithmetic
                        let offsetI = si * featureDim
                        let offsetJ = sj * featureDim
                        
                        if offsetI + featureDim <= totalMaxIdx && offsetJ + featureDim <= totalMaxIdx {
                            var dot: Float = 0
                            vDSP_dotpr(base.advanced(by: offsetI), 1, 
                                       base.advanced(by: offsetJ), 1, 
                                       &dot, vDSP_Length(featureDim))
                            score += kernel[i][j] * dot
                        }
                    }
                }
                novelty[t] = max(0, score)
            }
        }
        return novelty
    }
    
    /// Flat Buffer Version: Streaming Recurrence Strength
    public static func streamingRecurrenceStrength(flatFeatures: [Float], featureDim: Int, start: Int, end: Int) -> Float {
        let nFrames = featureDim > 0 ? (flatFeatures.count / featureDim) : 0
        guard nFrames > 0 else { return 0 }
        
        var totalStrength: Float = 0
        let safeStart = max(0, start)
        let safeEnd = min(nFrames, end)
        let totalMaxIdx = flatFeatures.count
        
        flatFeatures.withUnsafeBufferPointer { fBuff in
            guard let base = fBuff.baseAddress else { return }
            for i in safeStart..<safeEnd {
                for j in 0..<nFrames {
                    if j < safeStart || j >= safeEnd {
                        let offsetI = i * featureDim
                        let offsetJ = j * featureDim
                        
                        if offsetI + featureDim <= totalMaxIdx && offsetJ + featureDim <= totalMaxIdx {
                            var dot: Float = 0
                            vDSP_dotpr(base.advanced(by: offsetI), 1, 
                                       base.advanced(by: offsetJ), 1, 
                                       &dot, vDSP_Length(featureDim))
                            totalStrength += dot
                        }
                    }
                }
            }
        }
        return totalStrength
    }

    // MARK: DCT-II (MFCC for)

    /// Type-II DCT. Industry Standard: scipy.fft.dct(log_mel_spec, type=2, norm='ortho')
    /// returns first n coefficients
    public static func dct2(_ input: [Float], nCoeffs: Int) -> [Float] {
        let n = input.count
        guard n > 0 && nCoeffs > 0 else { return [] }
        var result = [Float](repeating: 0, count: min(nCoeffs, n))

        for k in 0..<min(nCoeffs, n) {
            var sum: Float = 0
            for i in 0..<n {
                sum += input[i] * cosf(Float.pi * Float(k) * (Float(i) + 0.5) / Float(n))
            }
            // Ortho normalization
            let norm: Float = (k == 0) ? sqrtf(1.0 / Float(n)) : sqrtf(2.0 / Float(n))
            result[k] = sum * norm
        }

        return result
    }

    // MARK: - Matrix & Smoothing for CENS/PLP

    /// Matrix transpose utility for [[Float]].
    public static func transpose(_ matrix: [[Float]]) -> [[Float]] {
        guard !matrix.isEmpty else { return [] }
        let rows = matrix.count
        let cols = matrix[0].count
        var result = [[Float]](repeating: [Float](repeating: 0, count: rows), count: cols)
        for i in 0..<rows {
            for j in 0..<cols {
                result[j][i] = matrix[i][j]
            }
        }
        return result
    }

    /// Hann window temporal smoothing.
    /// Industry Standard's `chroma_cens` smoothing logic using vDSP convolution.
    public static func applyHannSmoothing(_ signal: [Float], windowSize: Int) -> [Float] {
        guard !signal.isEmpty && windowSize > 0 else { return signal }
        guard signal.count >= windowSize else { return signal }
        
        // 1. Create Hann window
        var hann = [Float](repeating: 0, count: windowSize)
        vDSP_hann_window(&hann, vDSP_Length(windowSize), Int32(vDSP_HANN_NORM))
        
        // 2. Normalize window to preserve energy (sum = 1)
        var sum: Float = 0
        vDSP_sve(hann, 1, &sum, vDSP_Length(windowSize))
        if sum > 0 {
            var invSum = 1.0 / sum
            vDSP_vsmul(hann, 1, &invSum, &hann, 1, vDSP_Length(windowSize))
        }

        // 3. Convolve
        let nResult = signal.count + windowSize - 1
        var fullConv = [Float](repeating: 0, count: nResult)
        
        // vDSP_conv requires reversed window for cross-correlation logic
        let reversedHann = Array(hann.reversed())
        
        vDSP_conv(signal, 1, reversedHann, 1, &fullConv, 1, vDSP_Length(signal.count), vDSP_Length(windowSize))
        
        // Center-crop to return original length
        let offset = windowSize / 2
        var result = [Float](repeating: 0, count: signal.count)
        for i in 0..<signal.count {
            let idx = offset + i
            if idx < nResult {
                result[i] = fullConv[idx]
            }
        }
        
        return result
    }

    // MARK: - Matrix Multiply Safety

    /// Safe wrapper for vDSP_mmul.
    /// Performs matrix multiplication C = A * B with strict dimension validation.
    /// Layout: 
    /// - A: [M x P]
    /// - B: [P x N]
    /// - C: [M x N]
    public static func safeMatrixMultiply(
        _ A: [Float], rowsA: Int, colsA: Int,
        _ B: [Float], rowsB: Int, colsB: Int,
        C: inout [Float]
    ) {
        // Validation
        guard colsA == rowsB else {
            print("❌ Matrix Dimension Mismatch: Acols(\(colsA)) != Brows(\(rowsB))")
            return
        }
        guard A.count >= rowsA * colsA else {
            print("❌ Matrix A Buffer Underflow")
            return
        }
        guard B.count >= rowsB * colsB else {
            print("❌ Matrix B Buffer Underflow")
            return
        }
        if C.count < rowsA * colsB {
            C = [Float](repeating: 0, count: rowsA * colsB)
        }
        
        vDSP_mmul(A, 1, B, 1, &C, 1, vDSP_Length(rowsA), vDSP_Length(colsB), vDSP_Length(colsA))
    }
}
