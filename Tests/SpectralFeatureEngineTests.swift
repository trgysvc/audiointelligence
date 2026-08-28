import XCTest
@testable import AudioIntelligenceCore

/// `SpectralFeatureEngine.spectralContrast` allocated `nBands + 1` rows (matching
/// `bandEdges`'s size, which legitimately needs nBands+1 edges to define nBands bands) but the
/// fill loop only ever wrote `b in 0..<nBands` — so the last row was permanently zero and fed a
/// spurious always-0 "7th band" into every downstream mean/aggregate.
final class SpectralFeatureEngineTests: XCTestCase {

    func testReturnsExactlyNBandsRows_noSpuriousZeroRow() async {
        let sr = 44100.0
        let nFFT = 2048
        let n = Int(sr * 1.0)
        // Broadband-ish signal (several tones spanning low to high) so every band has real content.
        let freqs: [Double] = [300, 600, 1200, 2400, 4800, 9600]
        var samples = [Float](repeating: 0, count: n)
        for i in 0..<n {
            let t = Double(i) / sr
            var v = 0.0
            for f in freqs { v += 0.1 * sin(2.0 * Double.pi * f * t) }
            samples[i] = Float(v)
        }

        let stft = await STFTEngine(nFFT: nFFT, hopLength: 512, sampleRate: sr).analyze(samples)
        let nBands = 6
        let contrast = SpectralFeatureEngine.spectralContrast(from: stft, nBands: nBands)

        XCTAssertEqual(contrast.count, nBands, "must return exactly nBands rows, not nBands+1")
        for (i, row) in contrast.enumerated() {
            let mean = row.isEmpty ? 0 : row.reduce(0, +) / Float(row.count)
            XCTAssertGreaterThan(mean, 0, "band \(i) should have real (non-zero) contrast for a broadband signal covering it")
        }
    }
}
