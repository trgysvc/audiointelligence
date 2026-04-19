import XCTest
@testable import AudioIntelligence
@testable import AudioIntelligenceCore

final class LibrosaParityTests: XCTestCase {
    
    // MARK: - Wavelet (DWT) Parity
    
    /// Verifies Haar DWT decomposition against mathematical ground truth.
    /// Input [1, 2, 3, 4] -> Haar Level 1:
    /// approx = [(1+2)/sqrt(2), (3+4)/sqrt(2)] = [2.1213, 4.9497]
    /// detail = [(2-1)/sqrt(2), (4-3)/sqrt(2)] = [0.7071, 0.7071]
    func testHaarWaveletParity() {
        let samples: [Float] = [1.0, 2.0, 3.0, 4.0]
        let engine = WaveletEngine()
        let result = engine.decompose(samples, wavelet: .haar, levels: 1)
        
        XCTAssertEqual(result.coefficients["cA"]![0], 2.1213, accuracy: 0.001)
        XCTAssertEqual(result.coefficients["cA"]![1], 4.9497, accuracy: 0.001)
        XCTAssertEqual(result.coefficients["cD1"]![0], 0.7071, accuracy: 0.001)
        XCTAssertEqual(result.coefficients["cD1"]![1], 0.7071, accuracy: 0.001)
    }

    // MARK: - Recurrence Matrix (SSM) Parity
    
    /// Verifies that StructureEngine.recurrenceMatrix yields a symmetric 1.0 diagonal.
    func testRecurrenceMatrixSymmetry() {
        let engine = StructureEngine()
        // 3 frames of 2-dimensional features
        let features: [[Float]] = [
            [1.0, 0.0, 1.0], // dim 0
            [0.0, 1.0, 1.0]  // dim 1
        ]
        
        let ssm = engine.recurrenceMatrix(features: features)
        
        // Diagonals must be 1.0 (self-similarity)
        XCTAssertEqual(ssm[0][0], 1.0, accuracy: 0.001)
        XCTAssertEqual(ssm[1][1], 1.0, accuracy: 0.001)
        XCTAssertEqual(ssm[2][2], 1.0, accuracy: 0.001)
        
        // Symmetry test
        XCTAssertEqual(ssm[0][1], ssm[1][0], accuracy: 0.0001)
        XCTAssertEqual(ssm[1][2], ssm[2][1], accuracy: 0.0001)
    }
    
    // MARK: - Manipulation (Resampling) Parity
    
    /// Verifies that vDSP-based resampling preserves basic DC offset.
    func testManipulationResampling() async {
        let engine = ManipulationEngine()
        let samples = [Float](repeating: 1.0, count: 1000) // DC Signal
        
        // Pitch shift by 12 steps (2x speed)
        let shifted = await engine.pitchShift(samples, steps: 12.0)
        
        // Even after resampling, the DC signal should stay near 1.0 (ignoring edge effects)
        XCTAssertTrue(shifted.count < 1000)
        XCTAssertEqual(shifted[10], 1.0, accuracy: 0.01)
    }
}
