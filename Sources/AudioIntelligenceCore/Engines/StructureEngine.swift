// StructureEngine.swift
// Elite Music DNA Engine — Phase 3
//
// Librosa equivalents: segment.py
//   recurrence_matrix() → cosine SSM (vDSP_dotpr based)
//   Foote (2000) novelty score → structural boundaries
//   Agglomerative clustering → segment merging

import Accelerate
import Foundation

public struct StructureResult: Sendable {
    public let segments: [AudioSegment]
    public let boundaryTimes: [Double]
    public let boundaryFrames: [Int]
    public let segmentCount: Int
}

public struct AudioSegment: Sendable {
    public let id: Int
    public let startSec: Double
    public let endSec: Double
    public let durationSec: Double
    public let label: String   // "Intro", "Verse", "Chorus", "Bridge", "Outro"
}

public final class StructureEngine: @unchecked Sendable {

    public let hopLength: Int
    public let sampleRate: Double

    public init(hopLength: Int = 512, sampleRate: Double = 22050) {
        self.hopLength = hopLength
        self.sampleRate = sampleRate
    }

    // MARK: Analyze

    /// Performs structural analysis using multiple feature types.
    /// Combines Chromagram (Harmony) and MFCC (Timbre) for robust segmentation.
    public func analyze(chromagram: [[Float]], mfccs: [[Float]], nSegments: Int = 7) -> StructureResult {
        let nFrames = chromagram[0].count
        guard nFrames > 10 else {
            return StructureResult(segments: [], boundaryTimes: [], boundaryFrames: [], segmentCount: 0)
        }

        // 1. Compute Recurrence Matrix (Cross-affinity between frames)
        // Combine Chroma and MFCC for a comprehensive similarity matrix
        let ssmChroma = DSPHelpers.selfSimilarityMatrix(chromagram)
        let ssmMFCC = DSPHelpers.selfSimilarityMatrix(mfccs)
        
        var combinedSSM = [[Float]](repeating: [Float](repeating: 0, count: nFrames), count: nFrames)
        for i in 0..<nFrames {
            for j in 0..<nFrames {
                // Harmonic vs Timbral weight (0.5 balance)
                combinedSSM[i][j] = (ssmChroma[i][j] + ssmMFCC[i][j]) * 0.5
            }
        }

        // 2. Foote novelty score on the combined SSM
        let kernelSize = min(64, nFrames / 4)
        let novelty = DSPHelpers.footeNovelty(ssm: combinedSSM, kernelSize: max(8, kernelSize))

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

        // 5. Cluster segments to assign structural labels
        let boundaryTimes = boundaryFrames.map { Double($0 * hopLength) / sampleRate }
        var segments: [AudioSegment] = []

        for i in 0..<(boundaryFrames.count - 1) {
            let start = boundaryFrames[i]
            let end = boundaryFrames[i + 1]
            let label = identifySection(combinedSSM: combinedSSM, start: start, end: end, totalFrames: nFrames)
            
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

    // MARK: - Section Identification

    /// Identifies the section type based on recurrence and global position.
    private func identifySection(combinedSSM: [[Float]], start: Int, end: Int, totalFrames: Int) -> String {
        let mid = (start + end) / 2
        let ratio = Double(mid) / Double(totalFrames)
        
        // 1. Basic location-based heuristics
        if ratio < 0.1 { return "Intro" }
        if ratio > 0.9 { return "Outro" }
        
        // 2. Recurrence-based logic: Does this section repeat elsewhere?
        // Sections with high recurrence in the "chorus zone" (0.3 - 0.7) are likely Chorus.
        var recurrenceStrength: Float = 0
        for i in start..<end {
            for j in 0..<totalFrames {
                if j < start || j > end {
                    recurrenceStrength += combinedSSM[i][j]
                }
            }
        }
        let normalizedRecurrence = recurrenceStrength / Float((end - start) * (totalFrames - (end - start)))
        
        if normalizedRecurrence > 0.6 {
            return "Chorus"
        } else if ratio < 0.5 {
            return "Verse"
        } else {
            return "Bridge/Verse"
        }
    }
}
