import XCTest
@testable import AudioIntelligenceCore
import AudioIntelligenceMetal

/// GPU (`MetalEngine.executeBatchDct`) and CPU (`vDSP_DCT_Execute`) MFCC paths must produce
/// numerically equivalent output. Phase 19 found they didn't: the GPU `batch_dct` shader applied
/// `sqrt(2/N)` unconditionally instead of `sqrt(1/N)` for the DC term (coeff 0) — a real bug that
/// was invisible to `Examples/PrototypeTrainer` and `Examples/ReliabilityAudit` (both call
/// `MFCCEngine` without a `metalEngine`, so they only ever exercised the always-correct CPU path)
/// but affected every real analysis, since `DNAReportBuilder.swift` calls the GPU path directly.
/// A librosa cross-check (`scripts/parity_compare.py`, MFCC section) proved the fix correct
/// against an independent reference; this is the permanent in-repo regression guard so a future
/// change to the Metal shader can't reintroduce a CPU/GPU scale mismatch silently.
final class MFCCGPUParityTests: XCTestCase {
    func testGPUAndCPUPaths_produceEquivalentMFCC() async {
        let sr = 22050.0
        let n = Int(sr * 2.0)
        let samples = (0..<n).map { i -> Float in
            let t = Double(i) / sr
            return Float(0.4 * sin(2.0 * .pi * 440.0 * t) + 0.3 * sin(2.0 * .pi * 1500.0 * t))
        }

        let stftEngine = STFTEngine(nFFT: 2048, hopLength: 512, sampleRate: sr)
        let melEngine = MelSpectrogramEngine(stftEngine: stftEngine, nMels: 128)
        let mel = await melEngine.createMelSpectrogram(from: samples)
        XCTAssertGreaterThan(mel.nFrames, 1, "GPU dispatch requires nFrames > 1 (MFCCEngine.compute)")

        let cpuEngine = MFCCEngine(melEngine: melEngine, nMFCC: 20) // no metalEngine -> CPU (vDSP_DCT) path
        let gpuEngine = MFCCEngine(melEngine: melEngine, nMFCC: 20, metalEngine: MetalEngine())

        let cpuResult = cpuEngine.compute(melSpectrogram: mel.melData)
        let gpuResult = gpuEngine.compute(melSpectrogram: mel.melData)

        XCTAssertEqual(cpuResult.fullData.count, gpuResult.fullData.count)
        let nMFCC = 20
        let nFrames = cpuResult.fullData.count / nMFCC

        var maxAbsDiffAny: Float = 0
        var maxAbsDiffDC: Float = 0
        for t in 0..<nFrames {
            for c in 0..<nMFCC {
                let diff = abs(cpuResult.fullData[t * nMFCC + c] - gpuResult.fullData[t * nMFCC + c])
                maxAbsDiffAny = max(maxAbsDiffAny, diff)
                if c == 0 { maxAbsDiffDC = max(maxAbsDiffDC, diff) }
            }
        }

        // Loose absolute tolerance (float32 GPU vs. CPU rounding), but tight enough that the
        // Phase 19 bug (a ~29% relative, sqrt(2)-scale error concentrated on coeff 0 — measured
        // via scripts/parity_compare.py against the pre-fix shader) would fail this immediately.
        XCTAssertLessThan(maxAbsDiffDC, 0.5,
            "GPU vs CPU MFCC coeff-0 (DC term) diverged by \(maxAbsDiffDC) -- this is exactly the Phase 19 scale bug's signature")
        XCTAssertLessThan(maxAbsDiffAny, 0.5,
            "GPU vs CPU MFCC diverged by \(maxAbsDiffAny) across some coefficient")
    }
}
