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

The spectral domain provides the most insight into the "texture" of the audio. Through the `rawAnalysis`, you have access to:
- **MFCC (Mel-Frequency Cepstral Coefficients)**: The "fingerprint" used for instrument and speech recognition.
- **Spectral Centroid**: The "brightness" of the sound.
- **Roll-off**: The frequency below which a specific percentage (typ. 85%) of the total spectral energy lies.

```swift
let spectral = report.rawAnalysis.spectral

print("Spectral Centroid: \(spectral.centroid) Hz")
print("Spectral Flux: \(spectral.flux)")
```

---

## 🎨 3. Visualizing with SwiftUI (Spectrograms)

For professional audio apps, a data table isn't enough. Users need to **see** the audio DNA. `AudioIntelligenceUI` provides high-performance rendering components optimized for Metal.

```swift
import SwiftUI
import AudioIntelligence
import AudioIntelligenceUI

struct SpectrogramView: View {
    let matrix: STFTMatrix // Extracted from the report
    
    var body: some View {
        VStack {
            Text("Spectral Power Distribution")
                .font(.headline)
            
            // Industrial-grade spectrogram renderer
            // Supports multiple color palettes: .magma, .viridis, .plasma
            SpectrogramPlot(matrix: matrix, palette: .magma)
                .frame(height: 300)
                .cornerRadius(8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.1)))
        }
    }
}
```

---

## 🎼 4. Tonal & Harmonic DNA (Chroma)

To understand the musical content, we use **Chroma Features**. This represents the energy distribution across the 12 semi-tones of the chromatic scale (C, C#, D, etc.), regardless of octave.

```swift
let chroma = report.rawAnalysis.harmonic.chroma

// Identify the dominant note in the current frame
if let dominantNoteIndex = chroma.indices.max(by: { chroma[$0] < chroma[$1] }) {
    let noteNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
    print("Dominant Harmonic Note: \(noteNames[dominantNoteIndex])")
}
```

---
*Next Step: Explore [Tutorial 03: Rhythm & Pulse](03_Rhythm.md) to master beat tracking and onset detection.*
