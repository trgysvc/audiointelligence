// StructureEngine.swift
// Elite Music DNA Engine — Phase 3
//
// Industry Standard equivalents: segment.py
//   recurrence_matrix() → cosine SSM (vDSP_dotpr based)
//   Foote (2000) novelty score → structural boundaries
//   Agglomerative clustering → segment merging

import Accelerate
import Foundation

public struct StructureResult: Codable, Sendable {
    public let segments: [AudioSegment]
    public let boundaryTimes: [Double]
    public let boundaryFrames: [Int]
    public let segmentCount: Int
}

public struct AudioSegment: Codable, Sendable {
    public let id: Int
    public let startSec: Double
    public let endSec: Double
    public let durationSec: Double
    public let label: String   // "Intro", "Verse", "Chorus", "Bridge", "Outro"
}

/// Boundary peak-picking parameters, calibrated against real SALAMI ground truth
/// (DEVLOG Phase 29). Exposed separately from `analyze()` so a calibration tool can
/// reuse one already-computed novelty curve across many parameter combinations instead
/// of recomputing STFT/chroma/MFCC/Foote-novelty per trial.
///
/// `deltaMultiplier` (not a raw additive `delta`): `StructureEngine.streamingFooteNovelty`'s
/// output is raw, unnormalized Foote-novelty energy -- its absolute scale depends on the
/// feature vectors' dimensionality (chroma dim, MFCC dim) and whether it's computed over a
/// whole track or a single ~45s chunk (`DNAReportBuilder` calls `analyze()` once per chunk).
/// Calibration against real SALAMI audio found the previous hand-set absolute `delta=0.03`
/// was, in that unnormalized scale (measured mean novelty ~668K, max ~46M on real tracks),
/// close to zero -- i.e. it was providing essentially NO effective threshold at all, which is
/// the real root cause behind the severe over-segmentation Phase 28 first measured (predicted
/// boundary counts running 2-3x true counts). Expressing the threshold as a multiplier of the
/// novelty curve's OWN mean (computed at call time in `boundaries(from:config:)`) instead of a
/// fixed absolute constant makes the calibrated value self-scale correctly across different
/// feature dimensionalities and whole-track-vs-chunked calling contexts, rather than being
/// valid only for the exact configuration it was measured under. (Even with that self-scaling,
/// `DNAReportBuilder`'s per-chunk analysis still introduced a chunk-seam novelty artifact that
/// deltaMultiplier alone could not fix -- see DEVLOG Phase 29's chunk-boundary-artifact finding;
/// StructureEngine now runs once on the whole track there instead of once per chunk.)
public struct StructurePeakPickConfig: Sendable {
    public var preMax: Int
    public var postMax: Int
    public var preAvg: Int
    public var postAvg: Int
    public var waitSeconds: Double
    public var deltaMultiplier: Float

    public init(preMax: Int = 4, postMax: Int = 4, preAvg: Int = 24, postAvg: Int = 24, waitSeconds: Double = 12.0, deltaMultiplier: Float = 2.0) {
        self.preMax = preMax
        self.postMax = postMax
        self.preAvg = preAvg
        self.postAvg = postAvg
        self.waitSeconds = waitSeconds
        self.deltaMultiplier = deltaMultiplier
    }

    /// Calibrated against real SALAMI ground truth (38 calibration / 19 held-out track split,
    /// grid-searched over deltaMultiplier/wait/preAvg-postAvg, verified with the real unmodified
    /// `DSPHelpers.peakPick`): calibration F@3.0s 40.2%->44.7%, held-out F@3.0s 39.3%->45.7%. See
    /// DEVLOG Phase 29 and `Examples/StructureCalibration`.
    public static let calibrated = StructurePeakPickConfig()
}

/// Prepared (feature-domain) intermediate output of `StructureEngine.analyze()`, before
/// peak-picking. Computing this once and calling `boundaries(from:config:)` many times lets
/// a calibration sweep vary peak-picking parameters without recomputing the novelty curve.
public struct StructureFeatures: Sendable {
    public let flatChroma: [Float]
    public let chromaDim: Int
    public let novelty: [Float]
    public let nFrames: Int
}

/// Structural Segmentation Engine.
/// Identifies song sections (Verse, Chorus, Outro) using Foote Novelty analysis and Self-Similarity Matrices.
public final class StructureEngine: @unchecked Sendable {

    public let hopLength: Int
    public let sampleRate: Double

    public init(hopLength: Int = 512, sampleRate: Double = 22050) {
        self.hopLength = hopLength
        self.sampleRate = sampleRate
    }

    // MARK: - Academic Parity: librosa.segment.recurrence_matrix()

    /// Computes a Cosine Self-Similarity Matrix (SSM) for structural analysis.
    /// - Parameters:
    ///   - features: Feature matrix where each inner array is a frequency/coefficient bin.
    /// - Returns: A 2D array representing the recurrence of patterns across time.
    public func recurrenceMatrix(features: [[Float]]) -> [[Float]] {
        return DSPHelpers.selfSimilarityMatrix(features)
    }

    // MARK: Analyze

    /// Computes the feature-domain intermediate (flattened chroma + combined Foote novelty
    /// curve) that peak-picking runs over. Split out from `analyze()` so a calibration sweep
    /// can compute this once per track and reuse it across many `boundaries(from:config:)`
    /// calls instead of recomputing the novelty curve per parameter trial.
    public func prepareFeatures(chromagram: [[Float]], mfccs: [[Float]]) -> StructureFeatures? {
        guard !chromagram.isEmpty else { return nil }
        let nFrames = chromagram[0].count
        guard nFrames > 10 else { return nil }

        // 1. Prepare normalized features (Memory Optimized & Safety Guards)
        let chromaDim = chromagram.count
        let mfccDim = mfccs.count

        var flatChroma = [Float](repeating: 0, count: nFrames * chromaDim)
        var flatMFCC   = [Float](repeating: 0, count: nFrames * mfccDim)

        flatChroma.withUnsafeMutableBufferPointer { chromaBuff in
            flatMFCC.withUnsafeMutableBufferPointer { mfccBuff in
                guard let cBase = chromaBuff.baseAddress, let mBase = mfccBuff.baseAddress else { return }

                for t in 0..<nFrames {
                    let offsetC = t * chromaDim
                    let offsetM = t * mfccDim

                    // SAFE COPY: Ensure indices exist before pointer write
                    for f in 0..<chromaDim {
                        if f < chromagram.count && t < chromagram[f].count {
                            cBase[offsetC + f] = chromagram[f][t]
                        }
                    }
                    for f in 0..<mfccDim {
                        if f < mfccs.count && t < mfccs[f].count {
                            mBase[offsetM + f] = mfccs[f][t]
                        }
                    }
                }
            }
        }

        // 2. Foote novelty using streaming dot-products (Memory Optimized)
        let kernelSize = min(64, nFrames / 4)
        let noveltyChroma = DSPHelpers.streamingFooteNovelty(flatFeatures: flatChroma, featureDim: chromaDim, nFrames: nFrames, kernelSize: max(8, kernelSize))
        let noveltyMFCC = DSPHelpers.streamingFooteNovelty(flatFeatures: flatMFCC, featureDim: mfccDim, nFrames: nFrames, kernelSize: max(8, kernelSize))

        var novelty = [Float](repeating: 0, count: nFrames)
        for i in 0..<nFrames {
            novelty[i] = (noveltyChroma[i] + noveltyMFCC[i]) * 0.5
        }

        return StructureFeatures(flatChroma: flatChroma, chromaDim: chromaDim, novelty: novelty, nFrames: nFrames)
    }

    /// Peak-picks boundaries out of an already-computed `StructureFeatures` and clusters the
    /// resulting segments. This is the cheap half of `analyze()` — safe to call repeatedly
    /// with different `config` values against the same features (e.g. a calibration sweep).
    public func boundaries(from features: StructureFeatures, config: StructurePeakPickConfig = .calibrated) -> StructureResult {
        let nFrames = features.nFrames
        let frameRate = sampleRate / Double(hopLength)
        let minWait = Int(frameRate * config.waitSeconds)

        // Absolute delta, scaled to THIS call's own novelty curve (see `deltaMultiplier`'s
        // doc comment on `StructurePeakPickConfig`) -- makes the calibrated multiplier portable
        // across different chroma/MFCC dimensionalities and whole-track-vs-chunked calls.
        let meanNovelty = features.novelty.isEmpty ? 0 : features.novelty.reduce(0, +) / Float(features.novelty.count)
        let delta = config.deltaMultiplier * meanNovelty

        var boundaryFrames = DSPHelpers.peakPick(
            features.novelty,
            preMax: config.preMax,
            postMax: config.postMax,
            preAvg: config.preAvg,
            postAvg: config.postAvg,
            wait: minWait,
            delta: delta
        )

        // Force boundaries at start and end
        if !boundaryFrames.contains(0) { boundaryFrames.insert(0, at: 0) }
        let lastFrame = nFrames - 1
        if !boundaryFrames.contains(lastFrame) { boundaryFrames.append(lastFrame) }
        boundaryFrames.sort()

        // Cluster segments using streaming recurrence strength
        let boundaryTimes = boundaryFrames.map { Double($0 * hopLength) / sampleRate }
        var segments: [AudioSegment] = []

        for i in 0..<(boundaryFrames.count - 1) {
            let start = boundaryFrames[i]
            let end = boundaryFrames[i + 1]
            let label = identifySectionStreaming(flatChroma: features.flatChroma, chromaDim: features.chromaDim, start: start, end: end, nFrames: nFrames)

            segments.append(AudioSegment(
                id: i + 1,
                startSec: Double(start * hopLength) / sampleRate,
                endSec: Double(end * hopLength) / sampleRate,
                durationSec: Double((end - start) * hopLength) / sampleRate,
                label: label
            ))
        }

        return StructureResult(
            segments: segments,
            boundaryTimes: Array(boundaryTimes.dropLast()),
            boundaryFrames: Array(boundaryFrames.dropLast()),
            segmentCount: segments.count
        )
    }

    /// Performs structural analysis using multiple feature types.
    /// Combines Chromagram (Harmony) and MFCC (Timbre) for robust segmentation.
    public func analyze(chromagram: [[Float]], mfccs: [[Float]], nSegments: Int = 7, config: StructurePeakPickConfig = .calibrated) -> StructureResult {
        guard let features = prepareFeatures(chromagram: chromagram, mfccs: mfccs) else {
            return StructureResult(segments: [], boundaryTimes: [], boundaryFrames: [], segmentCount: 0)
        }
        return boundaries(from: features, config: config)
    }

    // MARK: - Section Identification (Streaming)

    private func identifySectionStreaming(flatChroma: [Float], chromaDim: Int, start: Int, end: Int, nFrames: Int) -> String {
        let mid = (start + end) / 2
        let ratio = Double(mid) / Double(nFrames)
        
        // 1. Boundary Labels
        if ratio < 0.08 { return "Intro" }
        if ratio > 0.92 { return "Outro" }
        
        // 2. Content Analysis: Recurrence (Harmony) vs Change (Timbre)
        let strength = DSPHelpers.streamingRecurrenceStrength(flatFeatures: flatChroma, featureDim: chromaDim, start: start, end: end)
        let normalizedRecurrence = strength / Float((end - start) * (nFrames - (end - start)))
        
        // v6.4 Logic: Differentiate between a "hook" (Chorus) and a "solo" (Lead/Thematic)
        // Highly repetitive sections (High SSM recurrence) → Chorus
        if normalizedRecurrence > 0.65 {
            return "Chorus"
        } 
        
        // Low recurrence middle sections → Solo/Thematic vs Verse
        if ratio > 0.3 && ratio < 0.8 {
            // In a 'Descarga', these are the most likely solo sections
            return normalizedRecurrence < 0.4 ? "Solo / Lead Section" : "Thematic Development"
        }
        
        return ratio < 0.5 ? "Verse" : "Bridge"
    }
}
