// StructureEngine.swift
// Elite Music DNA Engine — Phase 3
//
// Librosa eşdeğerleri: segment.py
//   recurrence_matrix() → cosine SSM (vDSP_dotpr tabanlı)
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
    public let label: String   // "Giriş", "Verse", "Nakarat", "Köprü", "Outro"
}

public final class StructureEngine: @unchecked Sendable {

    public let hopLength: Int
    public let sampleRate: Double

    public init(hopLength: Int = 512, sampleRate: Double = 22050) {
        self.hopLength = hopLength
        self.sampleRate = sampleRate
    }

    // MARK: Analyze

    public func analyze(chromagram: [[Float]], nSegments: Int = 7) -> StructureResult {
        let nFrames = chromagram[0].count
        guard nFrames > 2 else {
            return StructureResult(segments: [], boundaryTimes: [], boundaryFrames: [], segmentCount: 0)
        }

        // Step 1: Self-Similarity Matrix (cosine, vDSP_dotpr)
        let ssm = DSPHelpers.selfSimilarityMatrix(chromagram)

        // Step 2: Foote novelty score → boundary candidates
        let kernelSize = min(64, nFrames / 4)
        let novelty = DSPHelpers.footeNovelty(ssm: ssm, kernelSize: max(4, kernelSize))

        // Step 3: Peak pick on novelty curve
        let frameRate = sampleRate / Double(hopLength)
        let minWait = Int(frameRate * 8.0)  // Minimum 8 saniye arası

        var boundaryFrames = DSPHelpers.peakPick(
            novelty,
            preMax: kernelSize / 4,
            postMax: kernelSize / 4,
            preAvg: kernelSize / 2,
            postAvg: kernelSize / 2,
            wait: minWait,
            delta: 0.05
        )

        // Always include start (0) and end
        if !boundaryFrames.contains(0) { boundaryFrames.insert(0, at: 0) }
        if !boundaryFrames.contains(nFrames - 1) { boundaryFrames.append(nFrames - 1) }
        boundaryFrames.sort()

        // Step 4: Agglomerative merging if too many segments
        if boundaryFrames.count > nSegments + 1 {
            boundaryFrames = agglomerativeMerge(boundaries: boundaryFrames, targetCount: nSegments + 1)
        }

        // Step 5: Build segments
        let boundaryTimes = boundaryFrames.map { Double($0 * hopLength) / sampleRate }
        var segments: [AudioSegment] = []

        for i in 0..<(boundaryFrames.count - 1) {
            let startSec = boundaryTimes[i]
            let endSec = boundaryTimes[i + 1]
            segments.append(AudioSegment(
                id: i + 1,
                startSec: startSec,
                endSec: endSec,
                durationSec: endSec - startSec,
                label: labelSegment(index: i, total: boundaryFrames.count - 1)
            ))
        }

        return StructureResult(
            segments: segments,
            boundaryTimes: Array(boundaryTimes.dropLast()),
            boundaryFrames: Array(boundaryFrames.dropLast()),
            segmentCount: segments.count
        )
    }

    // MARK: Agglomerative Merging

    /// En kısa ardışık segmentleri birleştirerek hedef segment sayısına indir.
    private func agglomerativeMerge(boundaries: [Int], targetCount: Int) -> [Int] {
        var b = boundaries

        while b.count > targetCount {
            // En kısa segment aralığını bul ve sil (orta sınırı kaldır)
            var minDist = Int.max
            var minIdx = 1
            for i in 1..<(b.count - 1) {
                let dist = b[i + 1] - b[i - 1]  // merge distance
                if dist < minDist {
                    minDist = dist
                    minIdx = i
                }
            }
            b.remove(at: minIdx)
        }

        return b
    }

    // MARK: Segment Labeling

    /// Konum bazlı bölüm isimlendirme (heuristic)
    private func labelSegment(index: Int, total: Int) -> String {
        if total <= 1 { return "Ana Bölüm" }
        let ratio = Double(index) / Double(total)
        switch ratio {
        case 0..<0.12: return "Giriş"
        case 0.12..<0.35: return "Verse"
        case 0.35..<0.55: return "Nakarat"
        case 0.55..<0.75: return "Verse 2"
        case 0.75..<0.9: return "Nakarat 2"
        default: return "Outro"
        }
    }
}
