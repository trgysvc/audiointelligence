import XCTest
@testable import AudioIntelligenceCore
import Accelerate

/// `HPSSEngine`'s CPU-fallback 2D median filter re-sorted a fresh `windowSize`-element window
/// from scratch (`vDSP_vsort`, O(w log w)) at *every single output pixel*, even though adjacent
/// windows share all but one element — a real, measured cost (~5s per ~10s audio clip at the
/// default windowSize=31, discovered while diagnosing an unexpectedly slow batch measurement;
/// see DEVLOG Phase 16). Replaced with an incremental sliding-window median (sort once per row/
/// column, then remove the one outgoing element and binary-search-insert the one incoming
/// element as the window slides) — same algorithm, same result, less redundant work.
///
/// This test proves the replacement is behavior-preserving: a local copy of the ORIGINAL
/// brute-force implementation (not the production code — verifying against a description of
/// itself would prove nothing) is compared element-for-element against the new code's real
/// output, across varied synthetic inputs including edge cases the incremental version's
/// boundary handling could plausibly get wrong (duplicate values, windows wider than the data,
/// single-row/column inputs).
final class HPSSEngineTests: XCTestCase {

    /// Reference implementation: the exact algorithm `HPSSEngine`'s CPU fallback used before
    /// Phase 16 — full re-sort of a freshly-extracted window at every pixel. Deliberately
    /// duplicated here (not `@testable`-imported from production) as the independent ground
    /// truth this test verifies the new incremental version against.
    private func bruteForceMedianFilter(_ data: [Float], nRows: Int, nCols: Int, windowSize: Int, horizontal: Bool) -> [Float] {
        var result = [Float](repeating: 0, count: data.count)
        let halfWin = windowSize / 2
        if horizontal {
            for r in 0..<nRows {
                let rowStart = r * nCols
                var window = [Float](repeating: 0, count: windowSize)
                for c in 0..<nCols {
                    for i in 0..<windowSize {
                        let idx = c + i - halfWin
                        window[i] = (idx >= 0 && idx < nCols) ? data[rowStart + idx] : 0
                    }
                    vDSP_vsort(&window, vDSP_Length(windowSize), 1)
                    result[rowStart + c] = window[halfWin]
                }
            }
        } else {
            for c in 0..<nCols {
                var window = [Float](repeating: 0, count: windowSize)
                for r in 0..<nRows {
                    for i in 0..<windowSize {
                        let idx = r + i - halfWin
                        window[i] = (idx >= 0 && idx < nRows) ? data[idx * nCols + c] : 0
                    }
                    vDSP_vsort(&window, vDSP_Length(windowSize), 1)
                    result[r * nCols + c] = window[halfWin]
                }
            }
        }
        return result
    }

    /// Exercises the real (private) implementation the same way `HPSSEngine.separate` does:
    /// through a full `analyze(stft:)` call with `metalEngine: nil` (forces the CPU path), then
    /// independently recomputes the harmonic/percussive magnitude the reference implementation
    /// would produce from the same masking formula, and compares.
    private func runComparison(magnitude: [Float], nFrames: Int, nFreqs: Int, winHarm: Int, winPerc: Int) {
        let stft = STFTMatrix(magnitude: magnitude, phase: [Float](repeating: 0, count: magnitude.count),
                               nFFT: (nFreqs - 1) * 2, hopLength: 512, sampleRate: 22050)
        let result = HPSSEngine(winHarm: winHarm, winPerc: winPerc, metalEngine: nil).analyze(stft: stft)

        let refHarmonicMedian = bruteForceMedianFilter(magnitude, nRows: nFrames, nCols: nFreqs, windowSize: winHarm, horizontal: false)
        let refPercussiveMedian = bruteForceMedianFilter(magnitude, nRows: nFrames, nCols: nFreqs, windowSize: winPerc, horizontal: true)

        var refMaskH = [Float](repeating: 0, count: magnitude.count)
        var refMaskP = [Float](repeating: 0, count: magnitude.count)
        for i in 0..<magnitude.count {
            let h = powf(refHarmonicMedian[i], 2.0)
            let p = powf(refPercussiveMedian[i], 2.0)
            let total = h + p + 1e-10
            refMaskH[i] = h / total
            refMaskP[i] = p / total
        }
        var refMagH = [Float](repeating: 0, count: magnitude.count)
        var refMagP = [Float](repeating: 0, count: magnitude.count)
        vDSP_vmul(magnitude, 1, refMaskH, 1, &refMagH, 1, vDSP_Length(magnitude.count))
        vDSP_vmul(magnitude, 1, refMaskP, 1, &refMagP, 1, vDSP_Length(magnitude.count))

        for i in 0..<magnitude.count {
            XCTAssertEqual(result.harmonic.magnitude[i], refMagH[i], accuracy: 1e-6,
                            "harmonic magnitude mismatch at index \(i) — incremental filter diverged from brute-force reference")
            XCTAssertEqual(result.percussive.magnitude[i], refMagP[i], accuracy: 1e-6,
                            "percussive magnitude mismatch at index \(i)")
        }
    }

    func testIncrementalMedianFilter_matchesBruteForce_randomData() {
        var rng = SystemRandomNumberGenerator()
        let nFrames = 40, nFreqs = 17
        let magnitude = (0..<(nFrames * nFreqs)).map { _ in Float.random(in: 0...1, using: &rng) }
        runComparison(magnitude: magnitude, nFrames: nFrames, nFreqs: nFreqs, winHarm: 31, winPerc: 31)
    }

    /// Real audio-like data has long runs of exact zeros (silence, boundary padding) — a
    /// pathological case for the incremental version's remove/insert-by-value logic if it ever
    /// mishandled duplicate values.
    func testIncrementalMedianFilter_matchesBruteForce_manyDuplicates() {
        let nFrames = 20, nFreqs = 10
        var magnitude = [Float](repeating: 0, count: nFrames * nFreqs)
        for i in stride(from: 0, to: magnitude.count, by: 3) { magnitude[i] = 1.0 } // sparse nonzero pattern, lots of ties
        runComparison(magnitude: magnitude, nFrames: nFrames, nFreqs: nFreqs, winHarm: 5, winPerc: 5)
    }

    /// Window wider than the data in one dimension — boundary zero-padding must still agree.
    func testIncrementalMedianFilter_matchesBruteForce_windowLargerThanData() {
        let nFrames = 3, nFreqs = 25
        var rng = SystemRandomNumberGenerator()
        let magnitude = (0..<(nFrames * nFreqs)).map { _ in Float.random(in: 0...1, using: &rng) }
        runComparison(magnitude: magnitude, nFrames: nFrames, nFreqs: nFreqs, winHarm: 31, winPerc: 31)
    }

    /// A single row/column — degenerate loop bounds (`1..<1` empty ranges).
    func testIncrementalMedianFilter_matchesBruteForce_singleRowAndColumn() {
        var rng = SystemRandomNumberGenerator()
        let magnitude1 = (0..<9).map { _ in Float.random(in: 0...1, using: &rng) }
        runComparison(magnitude: magnitude1, nFrames: 1, nFreqs: 9, winHarm: 5, winPerc: 5)
        let magnitude2 = (0..<9).map { _ in Float.random(in: 0...1, using: &rng) }
        runComparison(magnitude: magnitude2, nFrames: 9, nFreqs: 1, winHarm: 5, winPerc: 5)
    }
}
