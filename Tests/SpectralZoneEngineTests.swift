import XCTest
@testable import AudioIntelligenceCore

/// `SpectralZoneEngine.analyze` computed each zone's bin range independently (`floor` for the
/// start, `ceil` for the end of that zone's own frequency range), so the bin(s) straddling a
/// shared boundary between two adjacent zones were counted in BOTH zones' energy sums. Fixed
/// by mapping each boundary frequency to exactly one bin index and using half-open
/// `[start, end)` ranges, so no bin is ever double-counted.
final class SpectralZoneEngineTests: XCTestCase {

    /// nFFT/sampleRate chosen so binFreq = 5Hz exactly and the Sub/Bass|Mid/Body boundary
    /// (250Hz) lands exactly on bin 50 — the precise integer-edge case where the old
    /// floor/ceil-per-zone logic double-counted (`ceil(250/5)=50` for Sub/Bass's end,
    /// `floor(250/5)=50` for Mid/Body's start — both included bin 50).
    func testBoundaryBin_isNotDoubleCounted() {
        let sampleRate = 44100.0
        let nFFT = 8820 // binFreq = 44100/8820 = 5.0 Hz exactly
        let nFreqs = nFFT / 2 + 1
        let nFrames = 4

        // All energy concentrated in bin 50 (exactly 250Hz) — every other bin silent.
        var magnitude = [Float](repeating: 0, count: nFreqs * nFrames)
        for t in 0..<nFrames { magnitude[t * nFreqs + 50] = 1.0 }
        let stft = STFTMatrix(magnitude: magnitude, phase: [Float](repeating: 0, count: nFreqs * nFrames), nFFT: nFFT, hopLength: 512, sampleRate: sampleRate)

        let result = SpectralZoneEngine(sampleRate: sampleRate).analyze(stft: stft)

        let subBass = result.dominanceMap["Sub/Bass"] ?? -1
        let midBody = result.dominanceMap["Mid/Body"] ?? -1
        print("🔬 boundary-bin test: Sub/Bass=\(subBass)% Mid/Body=\(midBody)%")

        // With no double-counting, all the energy (concentrated in one bin) must land
        // entirely in exactly one zone — not split ~50/50 across both, which is what
        // double-counting the shared boundary bin would produce.
        XCTAssertEqual(subBass + midBody, 100.0, accuracy: 0.01, "the two adjacent zones should still account for all the energy between them")
        XCTAssertTrue(subBass > 99.0 || midBody > 99.0, "all energy is in a single bin — it must be attributed to exactly one zone, not split across both (Sub/Bass=\(subBass)%, Mid/Body=\(midBody)%)")
    }

    /// Sanity check that total energy conservation holds across all 4 zones for a broadband
    /// signal too — percentages must sum to 100%.
    func testDominanceMapPercentages_sumToOneHundred() {
        let sampleRate = 44100.0
        let nFFT = 2048
        let nFreqs = nFFT / 2 + 1
        let nFrames = 4
        var magnitude = [Float](repeating: 0, count: nFreqs * nFrames)
        for t in 0..<nFrames {
            for f in 0..<nFreqs { magnitude[t * nFreqs + f] = Float.random(in: 0...1) }
        }
        let stft = STFTMatrix(magnitude: magnitude, phase: [Float](repeating: 0, count: nFreqs * nFrames), nFFT: nFFT, hopLength: 512, sampleRate: sampleRate)

        let result = SpectralZoneEngine(sampleRate: sampleRate).analyze(stft: stft)
        let total = result.dominanceMap.values.reduce(0, +)
        XCTAssertEqual(total, 100.0, accuracy: 0.01)
    }
}
