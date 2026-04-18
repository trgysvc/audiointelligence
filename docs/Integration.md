# 🚀 Integration & Concurrency: Architectural Guide

This guide is for developers and system architects integrating the **AudioIntelligence SDK** into enterprise ecosystems like EliteAgent or professional Mastering Dashboards.

---

## 1. Professional Installation (SPM)

AudioIntelligence is a modular SDK optimized for the **Swift Package Manager**. It is designed to be consumed as a version-locked dependency to ensure DSP stability.

### Configuration
Update your `Package.swift` to include the Infinity Engine:

```swift
let package = Package(
    name: "MyProAudioApp",
    dependencies: [
        .package(url: "https://hub.com/trgysvc/AudioIntelligence.git", from: "6.1.0")
    ],
    targets: [
        .target(
            name: "MyTarget",
            dependencies: [
                .product(name: "AudioIntelligence", package: "AudioIntelligence")
            ]
        )
    ]
)
```

---

## 2. Structured Concurrency (Swift 6)

The SDK utilizes the **Actor Model** to ensure that heavy DSP calculations never block the Main Thread or interfere with low-latency audio capture.

### The Infinity Actor
All analysis is performed within the `AudioIntelligence` actor. This provides compile-time protection against data races when accessing shared resources like the **IntelligenceCache**.

### Async Analysis Lifecycle
```swift
import AudioIntelligence

let sdk = AudioIntelligence()

// 1. Kick off analysis (Non-blocking)
Task {
    do {
        let report = try await sdk.analyze(url: songURL) { progress, stage, detail in
            // Handle granular progress UI (0.0 to 1.0)
        }
        
        // 2. Consume DNA Models
        print("Loudness: \(report.rawAnalysis.mastering.integratedLUFS) LUFS")
    } catch let error as AudioIntelligenceError {
        // Handle categorized forensic errors
        print("DSP Failure: \(error.localizedDescription)")
    }
}
```

---

## 3. Advanced Memory & Cache Management

### Hybrid 4GB Cache Strategy
AudioIntelligence implements an intelligent persistent store to prevent redundant analysis.
- **Content Hash**: Every analysis is keyed to a SHA256 hash of the audio content. Moving, renaming, or changing file metadata will **NOT** trigger a re-analysis.
- **Resource Limits**: The cache maintains a strict **4GB Disk Limit** with an LRU (Least Recently Used) eviction policy, ensuring your application doesn't exhaust user storage.

### Clearing Cache
In forensic scenarios where a "Fresh Audit" is required:
```swift
await IntelligenceCache.shared.clear()
```

---

## 4. Hardware Optimization (Apple Silicon)

For maximum performance, ensure your host application is compiled natively for `arm64`.

- **Efficiency Cores**: Low-priority background tagging.
- **Performance Cores**: Active real-time analysis and Viterbi decoding.
- **AMX (Accelerate)**: All matrix transforms are hardware-accelerated.
- **ANE (CoreML)**: All stem-separation tasks consume zero CPU/GPU cycles.

---
*For a complete map of the project's internal structure, see [ProjectStructure.md](../../ProjectStructure.md).*
