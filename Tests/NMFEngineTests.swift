import XCTest
@testable import AudioIntelligenceCore

/// `NMFEngine.decompose`'s multiplicative-update loop guarded `H` against NaN/Infinity after
/// every iteration (self-healing a single bad element back to a small epsilon) but had no
/// equivalent guard on `W` — once a NaN/Infinity entered `W` (e.g. from a degenerate input
/// magnitude bin), it multiplied itself forward every remaining iteration with no recovery,
/// permanently poisoning that (component, frequency) cell.
final class NMFEngineTests: XCTestCase {

    /// A single NaN magnitude bin (a genuinely malformed but not impossible upstream STFT
    /// result — e.g. a divide-by-zero slipping through an unrelated code path) must not leave
    /// `W` or `H` with any non-finite entries after decomposition.
    func testNaNMagnitudeBin_doesNotPoisonWOrH() {
        let nFreqs = 8
        let nFrames = 6
        var magnitude = [Float](repeating: 0.5, count: nFrames * nFreqs)
        magnitude[3] = Float.nan // corrupt one bin in frame 0

        let stft = STFTMatrix(magnitude: magnitude,
                               phase: [Float](repeating: 0, count: nFrames * nFreqs),
                               nFFT: (nFreqs - 1) * 2, hopLength: 512, sampleRate: 22050)

        let result = NMFEngine(nComponents: 2, maxIter: 20).decompose(stft: stft)

        for component in result.W {
            for v in component {
                XCTAssertTrue(v.isFinite, "W must not contain NaN/Infinity after decomposition")
            }
        }
        for frame in result.H {
            for v in frame {
                XCTAssertTrue(v.isFinite, "H must not contain NaN/Infinity after decomposition")
            }
        }
    }

    /// Baseline sanity: well-formed input produces a finite, non-negative factorization whose
    /// dimensions match the request.
    func testWellFormedInput_producesFiniteNonNegativeFactorization() {
        let nFreqs = 16
        let nFrames = 10
        var magnitude = [Float](repeating: 0, count: nFrames * nFreqs)
        for t in 0..<nFrames {
            for f in 0..<nFreqs {
                magnitude[t * nFreqs + f] = Float(1 + (t + f) % 5) * 0.1
            }
        }
        let stft = STFTMatrix(magnitude: magnitude,
                               phase: [Float](repeating: 0, count: nFrames * nFreqs),
                               nFFT: (nFreqs - 1) * 2, hopLength: 512, sampleRate: 22050)

        let result = NMFEngine(nComponents: 3, maxIter: 30).decompose(stft: stft)

        XCTAssertEqual(result.W.count, 3)
        XCTAssertEqual(result.H.count, nFrames)
        for component in result.W {
            XCTAssertEqual(component.count, nFreqs)
            for v in component { XCTAssertTrue(v.isFinite && v >= 0) }
        }
        for frame in result.H {
            XCTAssertEqual(frame.count, 3)
            for v in frame { XCTAssertTrue(v.isFinite && v >= 0) }
        }
    }
}
