import Foundation
import Accelerate

/**
 * v55.1: Semantic Audio Intelligence Engine
 * Specialized in understanding the "Roles" and "Dominance" of audio components.
 */
public final class SemanticEngine: Sendable {
    
    private let sampleRate: Double
    
    public init(sampleRate: Double) {
        self.sampleRate = sampleRate
    }
    
    public struct SemanticResult: Sendable {
        public let dominanceMap: [String: Float] // Category: Percentage
        public let primaryRole: String          // Lead, Supporting, Foundational
        public let textureType: String          // Harmonic, Percussive, Hybrid
        public let presenceScore: Float         // 0.0 - 1.0 (Lead dominance)
    }
    
    public func analyze(magnitude: [Float], nFrames: Int, nFFT: Int) -> SemanticResult {
        let nBins = nFFT / 2 + 1
        let binFreq = Float(sampleRate) / Float(nFFT)
        
        // Define Semantic Zones (Hz)
        let zones = [
            ("Sub/Bass", 0.0...250.0),
            ("Mid/Body", 250.0...2000.0),
            ("Presence/Lead", 2000.0...6000.0),
            ("Air/Treble", 6000.0...Float(sampleRate/2))
        ]
        
        var zoneEnergies = [String: Float]()
        var totalEnergy: Float = 0
        
        for (name, range) in zones {
            let startBin = Int(floor(range.lowerBound / binFreq))
            let endBin = min(Int(ceil(range.upperBound / binFreq)), nBins - 1)
            
            var zoneEnergy: Float = 0
            for f in startBin...endBin {
                var sumSq: Float = 0
                // Calculate average power across all frames for this bin
                let binIndices = stride(from: f * nFrames, to: (f + 1) * nFrames, by: 1)
                for idx in binIndices {
                    let m = magnitude[idx]
                    sumSq += m * m
                }
                zoneEnergy += sumSq
            }
            zoneEnergies[name] = zoneEnergy
            totalEnergy += zoneEnergy
        }
        
        // Convert to Percentages
        var dominanceMap = [String: Float]()
        for (name, energy) in zoneEnergies {
            dominanceMap[name] = totalEnergy > 1e-12 ? (energy / totalEnergy) * 100.0 : 0
        }
        
        // Role Detection Logic
        let presenceEnergy = dominanceMap["Presence/Lead"] ?? 0
        let midEnergy = dominanceMap["Mid/Body"] ?? 0
        let bassEnergy = dominanceMap["Sub/Bass"] ?? 0
        
        var role = "Supporting"
        if presenceEnergy > 30.0 || (presenceEnergy > 20.0 && presenceEnergy > midEnergy) {
            role = "Lead"
        } else if bassEnergy > 40.0 {
            role = "Foundational"
        }
        
        // Texture Logic (Harmonic vs Percussive)
        // Simplified: Using energy distribution
        var texture = "Hybrid"
        if presenceEnergy > 50.0 {
            texture = "Harmonic (Solo)"
        } else if dominanceMap["Sub/Bass"] ?? 0 > 60.0 {
            texture = "Bass Heavy"
        }
        
        return SemanticResult(
            dominanceMap: dominanceMap,
            primaryRole: role,
            textureType: texture,
            presenceScore: presenceEnergy / 100.0
        )
    }
}
