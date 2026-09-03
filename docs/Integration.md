# 🚀 Integration & Concurrency: Architectural Guide

This guide is for developers and system architects integrating the **AudioIntelligence SDK** into enterprise ecosystems or professional Mastering Dashboards.

---

## 1. Professional Installation (SPM)

AudioIntelligence is a modular SDK optimized for the **Swift Package Manager**.

### Configuration
Update your `Package.swift` to include the Infinity Engine:

```swift
let package = Package(
    name: "MyProAudioApp",
    dependencies: [
        .package(url: "https://github.com/trgysvc/audiointelligence.git", from: "8.2.3")
    ],
    targets: [
        .target(
            name: "MyTarget",
            dependencies: [
                .product(name: "AudioIntelligence", package: "AudioIntelligence"),
                .product(name: "AudioIntelligenceUI", package: "AudioIntelligence") // Add for UI views
            ]
        )
    ]
)
```

---

## 2. Structured Concurrency (Swift 6)

The SDK utilizes the **Actor Model** to ensure that heavy DSP calculations never block the UI thread or interfere with low-latency audio tasks.

### The Infinity Actor
All analysis is performed within the `AudioIntelligence` actor. This provides compile-time protection against data races.

### Async Analysis Lifecycle
```swift
import AudioIntelligence

let sdk = AudioIntelligence()

Task {
    do {
        let report = try await sdk.analyze(url: songURL) { progress, stage, _ in
            print("[\(stage)] \(Int(progress * 100))%")
        }

        // Measurement (validated) vs estimation (statistical):
        print("Loudness: \(report.measurements.loudness.integrated.value) LUFS")  // EBU R128
        print("Structure: \(report.estimations.structure.count) sections detected")
        print("Tempo: \(report.estimations.tempo.value) BPM @ \(report.estimations.tempo.confidence)")
    } catch {
        print("Analysis Error: \(error)")
    }
}
```

---

## 3. 🎨 Native SwiftUI Visualizations

The **AudioIntelligenceUI** module provides high-performance, Metal-accelerated views for your dashboard.

### Dashboard & spectral views
The module ships `MainDashboardView` (a full engineering dashboard) and the
`SpectralLandscapeView` component. Both consume the typed `AudioReport`:

```swift
import SwiftUI
import AudioIntelligenceUI

struct AnalysisDashboard: View {
    @State private var report: AudioReport?

    var body: some View {
        VStack {
            if let report {
                // Full engineering dashboard
                MainDashboardView(report: report)

                // Or drive an individual component from the heavy feature series
                SpectralLandscapeView(magnitudes: report.features?.magnitudeSpectrogram ?? [])
                    .frame(height: 300)
            }
        }
    }
}
```

---

## 4. Advanced Memory & Cache Management

### Hybrid 4GB Persistent Cache
AudioIntelligence implements an industrial-grade persistent store:
- **Identifier**: Keyed to a SHA256 content hash. Moving or renaming files does **NOT** trigger re-analysis.
- **Auto-Eviction**: Maintains a strict 4GB disk limit with an LRU policy.

### Manual Invalidation
```swift
await sdk.invalidateCache() // Clears the hybrid store
```

---

## 5. Hardware Optimization (Apple Silicon)

AudioIntelligence optimizes for the modern M-series SoC:

- **Accelerate / vDSP (incl. AMX)**: High-throughput FFT and matrix/vector math.
- **Metal GPU**: Parallelized DSP kernels and UI rendering, with a CPU fallback when Metal is
  unavailable.

> The **analysis pipeline** (`analyze()`) is pure Swift on Accelerate/AVFoundation/Metal — no
> Core ML, no ANE inference, no network. (There is a separate `NeuralSeparationEngine` interface
> that *can* host a Core ML model for stem separation, but no model ships and it is not part of
> `analyze()`. The instrument layer IS built and data-derived — `InstrumentEngine`, fit and
> calibrated on real OpenMIC-2018 audio, no Core ML/ANE — but held-out accuracy is class-dependent;
> see README Validation Status.)

---
*For technical specs on specific analysis engines, see [Engines.md](Engines.md).*
