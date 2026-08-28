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
        
        // Define Scientific Spectral Zones (Hz) as shared boundary edges rather than
        // independent per-zone ranges. Each edge frequency maps to exactly ONE bin index, so
        // adjacent zones can't disagree about who owns the boundary bin — previously, each
        // zone independently floor'd its own start and ceil'd its own end, so the bin(s)
        // straddling a shared edge (e.g. ~250Hz between Sub/Bass and Mid/Body) were counted
        // in BOTH zones, double-counting that energy and skewing `dominanceMap`.
        let names = ["Sub/Bass", "Mid/Body", "Presence/Lead", "Air/Treble"]
        let edgeFreqs: [Float] = [0.0, 250.0, 2000.0, 6000.0, Float(sampleRate / 2)]
        var edgeBins = edgeFreqs.map { Int(($0 / binFreq).rounded()) }
        edgeBins[0] = 0
        edgeBins[edgeBins.count - 1] = nBins // exclusive upper bound — covers the final bin

        var zoneEnergies = [String: Float]()
        var totalEnergy: Float = 0

        for i in 0..<names.count {
            let startBin = max(0, edgeBins[i])
            let endBin = min(nBins, edgeBins[i + 1]) // exclusive, so zones never overlap
            guard endBin > startBin else { zoneEnergies[names[i]] = 0; continue }

            var zoneEnergy: Float = 0
            for f in startBin..<endBin {
                var binPower: Float = 0
                // Calculate total power for this bin across all frames
                for t in 0..<nFrames {
                    let m = magnitude[t * nBins + f]
                    binPower += m * m
                }
                zoneEnergy += binPower
            }
            zoneEnergies[names[i]] = zoneEnergy
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
