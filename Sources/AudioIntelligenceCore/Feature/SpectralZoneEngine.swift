import Foundation
import Accelerate

/**
 * SpectralZoneEngine
 * Analyzes frequency zones to determine tonal distribution and energy balance.
 * Scientific replacement for the former 'Semantic' engine.
 */
/// Frequency Zone Analysis Engine.
/// Analyzes energy distribution across semantic frequency bands (Sub, Bass, Low-Mid, Mid, High-Mid, High).
public final class SpectralZoneEngine: Sendable {
    
    private let sampleRate: Double
    
    public init(sampleRate: Double) {
        self.sampleRate = sampleRate
    }
    
    public struct SpectralZoneResult: Codable, Sendable {
        public let dominanceMap: [String: Float] // Category: Percentage
        public let primaryZone: String          // Bass, Body, Lead, Air
        public let textureType: String          // Spectral balance description
        public let presenceScore: Float         // 0.0 - 1.0 (Presence energy)
    }
    
    public func analyze(stft: STFTMatrix) -> SpectralZoneResult {
        let nBins = stft.nFreqs
        let nFrames = stft.nFrames
        let magnitude = stft.magnitude // [t * nBins + f]
        let binFreq = Float(sampleRate) / Float(stft.nFFT)
        
        // Define Scientific Spectral Zones (Hz)
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
                var binPower: Float = 0
                // Calculate total power for this bin across all frames
                for t in 0..<nFrames {
                    let m = magnitude[t * nBins + f]
                    binPower += m * m
                }
                zoneEnergy += binPower
            }
            zoneEnergies[name] = zoneEnergy
            totalEnergy += zoneEnergy
        }
        
        // Convert to Percentages
        var dominanceMap = [String: Float]()
        for (name, energy) in zoneEnergies {
            dominanceMap[name] = totalEnergy > 1e-12 ? (energy / totalEnergy) * 100.0 : 0
        }
        
        // Zone Dominance Logic
        let presenceEnergy = dominanceMap["Presence/Lead"] ?? 0
        let midEnergy = dominanceMap["Mid/Body"] ?? 0
        let bassEnergy = dominanceMap["Sub/Bass"] ?? 0
        
        var primary = "Mid/Body"
        if presenceEnergy > midEnergy && presenceEnergy > bassEnergy {
            primary = "Presence/Lead"
        } else if bassEnergy > midEnergy && bassEnergy > presenceEnergy {
            primary = "Sub/Bass"
        }
        
        var texture = "Balanced"
        if presenceEnergy > 50.0 {
            texture = "Brilliant / Crisp"
        } else if bassEnergy > 60.0 {
            texture = "Dark / Warm"
        }
        
        return SpectralZoneResult(
            dominanceMap: dominanceMap,
            primaryZone: primary,
            textureType: texture,
            presenceScore: presenceEnergy / 100.0
        )
    }
}
