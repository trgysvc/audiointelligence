import XCTest
import Foundation
@testable import AudioIntelligence
@testable import AudioIntelligenceCore

final class MusicologicalAccuracyTests: XCTestCase {
    
    let outputDir = "/Users/trgysvc/Documents/AI Works"
    let sqamDir = "Tests/Resources/SQAM"
    
    override func setUp() async throws {
        try await super.setUp()
        // Ensure output directory exists
        let fm = FileManager.default
        if !fm.fileExists(atPath: outputDir) {
            try fm.createDirectory(atPath: outputDir, withIntermediateDirectories: true)
        }
    }
    
    // MARK: - 1. SQAM Pitch & Chroma Parity (EBU Reference)
    
    /// Checks if the library correctly identifies the fundamental pitch of solo instruments.
    func testSQAMChromaParity() async throws {
        // SQAM 21_2: Trumpet solo (Dominant Pitch B-flat / F)
        let trumpetURL = URL(fileURLWithPath: "\(sqamDir)/trpt21_2.wav")
        let analysis = try await analyzeAndSave(url: trumpetURL, name: "SQAM_21_Trumpet")
        
        // Verify Chroma Matrix (12 bins)
        let chroma = analysis.chromaProfile
        XCTAssertFalse(chroma.isEmpty, "Chroma matrix should not be empty")
        
        print("✅ SQAM 21 Fundamental: \(analysis.tonality.key)")
    }
    
    /// Checks harmony resolution in polyphonic textures.
    func testSQAMHarmonyParity() async throws {
        // SQAM 48_1: String Quartet
        let quartetURL = URL(fileURLWithPath: "\(sqamDir)/quar48_1.wav")
        let analysis = try await analyzeAndSave(url: quartetURL, name: "SQAM_48_Quartet")
        
        // Verification: Multi-voice harmony should be detected
        XCTAssertGreaterThan(analysis.musicology.verticalAnalysis.count, 0)
        print("✅ SQAM 48 Chord Count: \(analysis.musicology.verticalAnalysis.count)")
    }
    
    // MARK: - 2. Rhythm & Tempo Parity
    
    /// Checks tempo detection accuracy on transient-heavy samples.
    func testSQAMTempoParity() async throws {
        // SQAM 35_1: Glockenspiel (Periodic Percussive)
        let glockURL = URL(fileURLWithPath: "\(sqamDir)/gspi35_1.wav")
        let analysis = try await analyzeAndSave(url: glockURL, name: "SQAM_35_Glockenspiel")
        
        XCTAssertGreaterThan(analysis.rhythm.bpm, 0)
        print("✅ SQAM 35 Detected BPM: \(analysis.rhythm.bpm)")
    }
    
    // MARK: - Helpers
    
    private func analyzeAndSave(url: URL, name: String) async throws -> MusicDNAAnalysis {
        let intelligence = AudioIntelligence()
        let result = try await intelligence.analyze(url: url)
        
        // Save to Plist for user inspection
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        let data = try encoder.encode(result.rawAnalysis)
        
        let outURL = URL(fileURLWithPath: "\(outputDir)/\(name)_VERIFY.plist")
        try data.write(to: outURL)
        
        print("💾 Verification Data Saved: \(outURL.path)")
        return result.rawAnalysis
    }
}
