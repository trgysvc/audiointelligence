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

    /// Performs structural analysis using multiple feature types.
    /// Combines Chromagram (Harmony) and MFCC (Timbre) for robust segmentation.
    public func analyze(chromagram: [[Float]], mfccs: [[Float]], nSegments: Int = 7) -> StructureResult {
        let nFrames = chromagram[0].count
        guard nFrames > 10 else {
            return StructureResult(segments: [], boundaryTimes: [], boundaryFrames: [], segmentCount: 0)
        }

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

        // 3. Robust peak picking
        let frameRate = sampleRate / Double(hopLength)
        let minWait = Int(frameRate * 8.0) // 8 second minimum segment
        
        var boundaryFrames = DSPHelpers.peakPick(
            novelty,
            preMax: 4,
            postMax: 4,
            preAvg: 16,
            postAvg: 16,
            wait: minWait,
            delta: 0.03
        )

        // 4. Force boundaries at start and end
        if !boundaryFrames.contains(0) { boundaryFrames.insert(0, at: 0) }
        let lastFrame = nFrames - 1
        if !boundaryFrames.contains(lastFrame) { boundaryFrames.append(lastFrame) }
        boundaryFrames.sort()

        // 5. Cluster segments using streaming recurrence strength
        let boundaryTimes = boundaryFrames.map { Double($0 * hopLength) / sampleRate }
        var segments: [AudioSegment] = []

        for i in 0..<(boundaryFrames.count - 1) {
            let start = boundaryFrames[i]
            let end = boundaryFrames[i + 1]
            let label = identifySectionStreaming(flatChroma: flatChroma, chromaDim: chromaDim, start: start, end: end, nFrames: nFrames)
            
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

    // MARK: - Section Identification (Streaming)

    private func identifySectionStreaming(flatChroma: [Float], chromaDim: Int, start: Int, end: Int, nFrames: Int) -> String {
        let mid = (start + end) / 2
        let ratio = Double(mid) / Double(nFrames)
        
        if ratio < 0.1 { return "Intro" }
        if ratio > 0.9 { return "Outro" }
        
        let strength = DSPHelpers.streamingRecurrenceStrength(flatFeatures: flatChroma, featureDim: chromaDim, start: start, end: end)
        let normalizedRecurrence = strength / Float((end - start) * (nFrames - (end - start)))
        
        if normalizedRecurrence > 0.6 {
            return "Chorus"
        } else if ratio < 0.5 {
            return "Verse"
        } else {
            return "Bridge/Verse"
        }
    }
}
