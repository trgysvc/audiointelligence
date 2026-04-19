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
        .package(url: "https://github.com/trgysvc/AudioIntelligence.git", from: "6.3.0")
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
        
        // Access 26-engine DNA results
        print("Loudness: \(report.rawAnalysis.mastering.integratedLUFS) LUFS")
        print("Structure: \(report.rawAnalysis.segments.count) sections detected")
    } catch {
        print("Analysis Error: \(error)")
    }
}
```

---

## 3. 🎨 Native SwiftUI Visualizations

The **AudioIntelligenceUI** module provides high-performance, Metal-accelerated views for your dashboard.

### Real-Time Spectrogram
Render a professional, perceptually uniform spectrogram directly from your analysis results:

```swift
import SwiftUI
import AudioIntelligenceUI

struct AnalysisDashboard: View {
    @State private var analysis: MusicDNAAnalysis?

    var body: some View {
        VStack {
            if let results = analysis {
                // High-throughput Metal Spectrogram
                SpectrogramView(results: results)
                    .frame(height: 300)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                
                // Standards-compliant Metering
                LoudnessMeterView(lufs: results.mastering.integratedLUFS)
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

AudioIntelligence is a **Multi-Engine Hybrid** that optimizes for the modern M-series SoC:

- **AMX (Accelerate)**: High-throughput matrix/vector math on Performance cores.
- **ANE (Apple Neural Engine)**: Zero-CPU cost stem separation and instrument prediction.
- **Metal GPU**: Parallelized FFT and UI rendering.

---
*For technical specs on specific analysis engines, see [Engines.md](Engines.md).*
