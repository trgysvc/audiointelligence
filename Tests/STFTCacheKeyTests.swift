import XCTest
@testable import AudioIntelligenceCore

/// `STFTEngine.analyze`'s cache key used to hash only the first 2000 + last 2000 samples (for
/// signals over 4000 samples), skipping the middle entirely. Two different signals sharing the
/// same head/tail but differing in the middle would collide on the same `STFTMemoryCache` key,
/// and the second call would silently return the first's (wrong) result. Fixed to hash the
/// full signal.
final class STFTCacheKeyTests: XCTestCase {

    func testTwoSignalsWithSameHeadTailButDifferentMiddle_doNotCollide() async {
        let sr = 22050.0
        let n = 20000 // well over the old 4000-sample partial-hash threshold
        let headTailLen = 2000

        let sharedHead = (0..<headTailLen).map { Float(sin(2.0 * Double.pi * 440.0 * Double($0) / sr)) }
        let sharedTail = (0..<headTailLen).map { Float(sin(2.0 * Double.pi * 440.0 * Double($0) / sr)) }
        let middleLen = n - 2 * headTailLen

        // Same head, same tail, but the middle differs (silence vs a loud 2kHz tone) — under
        // the old bug this hashed identically to the same signature + same sample count.
        let middleA = [Float](repeating: 0.0, count: middleLen)
        let middleB = (0..<middleLen).map { Float(0.8 * sin(2.0 * Double.pi * 2000.0 * Double($0) / sr)) }

        let signalA = sharedHead + middleA + sharedTail
        let signalB = sharedHead + middleB + sharedTail
        XCTAssertEqual(signalA.count, signalB.count)

        STFTMemoryCache.shared.clear()
        let engine = STFTEngine(nFFT: 2048, hopLength: 512, sampleRate: sr)
        let resultA = await engine.analyze(signalA)
        let resultB = await engine.analyze(signalB)

        // The middle third of the signal is wildly different (silence vs a loud tone) — the
        // resulting spectrograms must differ substantially, not be byte-identical (which is
        // exactly what a cache collision would produce).
        XCTAssertEqual(resultA.magnitude.count, resultB.magnitude.count)
        var maxDiff: Float = 0
        for i in 0..<resultA.magnitude.count {
            maxDiff = max(maxDiff, abs(resultA.magnitude[i] - resultB.magnitude[i]))
        }
        print("🔬 STFT cache-collision test: max magnitude diff = \(maxDiff)")
        XCTAssertGreaterThan(maxDiff, 0.01, "two signals differing substantially in the middle must not produce identical (cache-collided) STFT results")
    }
}
