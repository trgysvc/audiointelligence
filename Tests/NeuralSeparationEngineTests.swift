import XCTest
@testable import AudioIntelligenceCore

/// `NeuralSeparationEngine` had zero test coverage. It ships no real CoreML model
/// (`CoreMLSeparationModel.generateMasks` is a documented placeholder returning `[:]`), but
/// `SeparationModel` is a public protocol — a deterministic mock lets the real masking math and
/// the synthesize() (ISTFT) reconstruction it depends on be tested end-to-end without a model.
/// This engine's only output path was silently broken by the ISTFT bug (see DEVLOG Phase 22,
/// STFTRoundTripTests) until that fix — this is the first real confirmation this engine's
/// masking+reconstruction pipeline actually produces correct audio, not an assumption.
final class NeuralSeparationEngineTests: XCTestCase {
    private let sr = 22050.0

    /// Returns a mask that is 1.0 for bins within `toleranceHz` of `targetHz`, 0.0 elsewhere —
    /// simulating a (perfect) model that isolates one frequency component.
    private struct FixedMaskModel: SeparationModel {
        let stemName: String
        let targetHz: Float
        let toleranceHz: Float
        let sampleRate: Double

        func generateMasks(stft: STFTMatrix) async throws -> [String: [Float]] {
            let nFreqs = stft.nFreqs
            let binHz = Float(sampleRate) / Float(stft.nFFT)
            var mask = [Float](repeating: 0, count: stft.nFrames * nFreqs)
            for f in 0..<nFreqs {
                let freq = Float(f) * binHz
                if abs(freq - targetHz) < toleranceHz {
                    for t in 0..<stft.nFrames { mask[t * nFreqs + f] = 1.0 }
                }
            }
            return [stemName: mask]
        }
    }

    /// A two-tone mix (440Hz "vocal" + 1500Hz "other") through a mask that isolates only the
    /// 440Hz band should reconstruct a stem whose dominant, recognizable pitch is ~440Hz — not
    /// a mix of both, and not garbage (which is what the pre-fix ISTFT bug would have produced).
    func testSeparate_isolatesTargetFrequency_viaMaskAndReconstruction() async throws {
        let n = Int(sr * 1.0)
        var mix = [Float](repeating: 0, count: n)
        for i in 0..<n {
            let t = Double(i) / sr
            mix[i] = Float(0.4 * sin(2.0 * .pi * 440.0 * t) + 0.4 * sin(2.0 * .pi * 1500.0 * t))
        }

        let stftEngine = STFTEngine(nFFT: 2048, hopLength: 512, sampleRate: sr)
        let model = FixedMaskModel(stemName: "vocal", targetHz: 440.0, toleranceHz: 40.0, sampleRate: sr)
        let engine = NeuralSeparationEngine()

        let result = try await engine.separate(samples: mix, using: model, stftEngine: stftEngine)
        guard let vocalStem = result["vocal"] else {
            XCTFail("expected a 'vocal' stem in the result"); return
        }
        XCTAssertFalse(vocalStem.isEmpty)

        let pitch = YINEngine(sampleRate: sr).analyze(samples: vocalStem)
        XCTAssertFalse(pitch.voicedFrames.isEmpty, "the isolated stem should still be a recognizable pitched signal")
        XCTAssertEqual(pitch.meanF0, 440.0, accuracy: 20.0, "masking should isolate the 440Hz component, not the 1500Hz one or a mix of both")
    }

    /// A model returning a mask of the wrong size for a stem must be silently skipped (per the
    /// existing `guard mask.count == nTotal else { continue }`), not crash or produce garbage.
    private struct WrongSizeMaskModel: SeparationModel {
        func generateMasks(stft: STFTMatrix) async throws -> [String: [Float]] {
            return ["bad": [Float](repeating: 1.0, count: 3)] // deliberately wrong size
        }
    }

    func testSeparate_wrongSizedMask_isSkippedNotCrashed() async throws {
        let samples = (0..<Int(sr * 0.2)).map { Float(sin(Double($0) * 0.1)) }
        let stftEngine = STFTEngine(nFFT: 2048, hopLength: 512, sampleRate: sr)
        let engine = NeuralSeparationEngine()

        let result = try await engine.separate(samples: samples, using: WrongSizeMaskModel(), stftEngine: stftEngine)
        XCTAssertNil(result["bad"], "a wrong-sized mask should be skipped, not produce a (garbage) stem")
    }
}
