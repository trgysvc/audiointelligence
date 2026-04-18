# Tutorial 04: Source Separation & Neural Isolation

Source separation is the art and science of "unmixing" a recording into its constituent parts. AudioIntelligence provides two professional-grade methodologies for this task: **HPSS** (Classical DSP) and **Neural Isolation** (Deep Learning).

---

## 🎻 1. Harmonic-Percussive Separation (HPSS)

HPSS is a "Mathematical Scalpel" that separates a mix into tonal elements (Harmonic) and transient elements (Percussive). 

- **Harmonic**: Sustained notes, vocals, piano, pad textures.
- **Percussive**: Drum hits, cymbals, percussive plucks.

### Why use HPSS?
HPSS is incredibly efficient on Apple Silicon (vDSP-accelerated) and doesn't require a neural model. It is perfect for real-time applications where you need to track a drummer or a melodic lead separately.

### Usage
```swift
let results = try await sdk.analyze(url: audioURL, features: [.separation])
let hpss = results.rawAnalysis.separation.hpss

print("Mix Characterization: \(hpss.characterization)")
print("Percussive Ratio: \(Int(hpss.percussiveEnergyRatio * 100))%")
```

---

## 🧠 2. Neural Stem Isolation (ANE)

For professional isolation (Vocals vs. Drums vs. Bass), we use our **Neural Isolation Engine**. This leverages the **Apple Neural Engine (ANE)** to provide world-class isolation with zero impact on your CPU thermals.

> [!IMPORTANT]
> **Hardware Support**: Neural Isolation automatically falls back to the GPU (Metal) if an ANE is not available on older hardware.

```swift
// Start isolation task
let stems = try await sdk.isolateStems(url: audioURL)

// Access individual stems as AudioBuffers or URLs
let vocals = stems.vocals
let drums = stems.drums
let bass = stems.bass
```

---

## 🖼️ 3. SwiftUI Integration: Multi-Stem Mixer

Building a professional "Stem Player" is easy with AudioIntelligence. Here is a UI pattern for a 4-channel stem mixer.

```swift
import SwiftUI
import AudioIntelligence

struct StemMixer: View {
    @StateObject var mixer = StemMixerManager() // Custom AudioEngine wrapper
    
    var body: some View {
        HStack(spacing: 30) {
            StemChannel(name: "Vocals", icon: "mic", volume: $mixer.vocalVolume)
            StemChannel(name: "Drums", icon: "drum", volume: $mixer.drumVolume)
            StemChannel(name: "Bass", icon: "guitars", volume: $mixer.bassVolume)
            StemChannel(name: "Other", icon: "music.note", volume: $mixer.otherVolume)
        }
        .padding()
        .background(Color.black.opacity(0.8))
        .cornerRadius(20)
    }
}

struct StemChannel: View {
    let name: String
    let icon: String
    @Binding var volume: Double
    
    var body: some View {
        VStack {
            Slider(value: $volume, in: 0...1)
                .rotationEffect(.degrees(-90))
                .frame(width: 40, height: 150)
            
            Image(systemName: icon)
                .font(.title2)
            Text(name)
                .font(.caption2.bold())
        }
    }
}
```

---

## 🚀 4. Performance Considerations: AMX vs. ANE

- **HPSS (AMX)**: Optimized via `vDSP_medfilt`. Performance is linear with file duration. A 5-minute track is separated in ~200ms on an M2 chip.
- **Neural (ANE)**: Optimized for batch inference. A 5-minute track typically takes 2-3 seconds to isolate all 4 stems in high-quality mode.

---
*Next Step: Explore [Tutorial 05: Forensic Auditing](05_Forensics.md) to evaluate signal integrity and detect bit-depth forgery.*
