# Tutorial 02: Extracting MIR DNA

In this tutorial, we dive into **Feature Extraction**. You will learn how to extract specific MIR (Music Information Retrieval) features and visualize them using professional components.

---

## 🧬 1. Granular Feature Selection

By default, the SDK performs a complete scan. However, for specific tasks like "Instrument Recognition" or "Genre Classification," you might only need a subset of the metadata.

```swift
let sdk = AudioIntelligence()

// Request only spectral and harmonic DNA to save processing cycles
let requestedFeatures: Set<AudioFeature> = [.spectral, .harmonic]

let result = try await sdk.analyze(url: audioURL, features: requestedFeatures)
```

---

## 📊 2. Deep Dive: Spectral Features

Spectral descriptors live under `report.measurements.spectral` (each a `Measured<Double>`,
validated for librosa parity). Heavier series like MFCC are under `report.features`.
- **Spectral Centroid**: the "brightness" of the sound.
- **Roll-off**: the frequency below which ~85% of the spectral energy lies.
- **MFCC**: the cepstral "fingerprint" (in `features.mfcc`).

```swift
let spectral = report.measurements.spectral

print("Spectral Centroid: \(spectral.centroid.value) Hz")   // .unit == .hertz
print("Spectral Flux: \(spectral.flux.value)")
print("MFCC coeffs: \(report.features?.mfcc.count ?? 0)")
```

---

## 🎨 3. Visualizing with SwiftUI (Spectrograms)

For professional audio apps, a data table isn't enough. Users need to **see** the audio DNA. `AudioIntelligenceUI` provides high-performance rendering components optimized for Metal.

```swift
import SwiftUI
import AudioIntelligence
import AudioIntelligenceUI

struct SpectrogramCard: View {
    let report: AudioReport

    var body: some View {
        VStack {
            Text("Spectral Power Distribution").font(.headline)

            // Metal-accelerated renderer fed by the heavy magnitude spectrogram
            SpectralLandscapeView(magnitudes: report.features?.magnitudeSpectrogram ?? [])
                .frame(height: 300)
                .cornerRadius(8)
        }
    }
}
```

---

## 🎼 4. Tonal & Harmonic DNA (Chroma)

To understand the musical content, we use **Chroma Features**. This represents the energy distribution across the 12 semi-tones of the chromatic scale (C, C#, D, etc.), regardless of octave.

```swift
let chroma = report.features?.chromaProfile ?? []   // 12 semitone means

// Identify the dominant note in the current frame
if let dominantNoteIndex = chroma.indices.max(by: { chroma[$0] < chroma[$1] }) {
    let noteNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
    print("Dominant Harmonic Note: \(noteNames[dominantNoteIndex])")
}
```

---
*Next Step: Explore [Tutorial 03: Rhythm & Pulse](03_Rhythm.md) to master beat tracking and onset detection.*
