# Tutorial 01: The Basics of AudioIntelligence

This tutorial covers the professional integration of the **AudioIntelligence SDK** into your macOS or iOS application, from dependency management to your first SwiftUI analysis view.

---

## 🏗️ 1. Professional Integration (SPM)

AudioIntelligence is a modular SDK optimized for the **Swift Package Manager**. Add it to your project via Xcode (File > Add Packages...) or directly in your `Package.swift` manifest:

```swift
dependencies: [
    .package(url: "https://github.com/trgysvc/AudioIntelligence.git", from: "6.1.0")
]
```

In your application target, import the library:
```swift
import AudioIntelligence
```

---

## 🛡️ 2. Safe Concurrency with Actors

The `AudioIntelligence` engine is implemented as a **Swift Actor**. This ensures that complex DSP math is isolated from your UI thread, providing compile-time safety against data races.

### Initialization
```swift
// Create a shared instance. 
// Uses automatic hardware selection (AMX/ANE) by default.
let sdk = AudioIntelligence()
```

---

## 🖼️ 3. Building a Professional Analysis View (SwiftUI)

For professional app development, you need a responsive UI that tracks the analysis progress. Below is a complete example of a DNA Analysis component.

```swift
import SwiftUI
import AudioIntelligence

struct AnalysisDashboard: View {
    @State private var progress: Double = 0
    @State private var currentStage: String = "Idle"
    @State private var isAnalyzing: Bool = false
    @State private var report: AudioReport?
    
    let sdk = AudioIntelligence()
    let audioURL: URL // Provided URL of the file
    
    var body: some View {
        VStack(spacing: 20) {
            // High-precision progress bar
            ProgressView(value: progress)
                .progressViewStyle(.linear)
                .tint(.accentColor)
            
            Text(currentStage)
                .font(.caption.monospaced())
                .foregroundColor(.secondary)
            
            Button(action: startAnalysis) {
                Label(isAnalyzing ? "Analyzing..." : "Start DNA Scan", 
                      systemImage: "waveform.path")
            }
            .disabled(isAnalyzing)
            .buttonStyle(.borderedProminent)
            
            if let report = report {
                VStack(alignment: .leading) {
                    Text("Analysis Results")
                        .font(.headline)
                    Text("BPM: \(report.rawAnalysis.rhythm.bpm, specifier: "%.1f")")
                    Text("Integrity: \(report.rawAnalysis.forensic.isUpsampled ? "⚠️ FAKE" : "✅ AUTHENTIC")")
                }
                .padding()
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(12)
            }
        }
        .padding()
    }
    
    func startAnalysis() {
        isAnalyzing = true
        report = nil
        
        Task {
            do {
                // Analysis with granular progress updates
                let result = try await sdk.analyze(url: audioURL) { progress, stage, detail in
                    self.progress = progress
                    self.currentStage = "\(stage): \(detail ?? "")"
                }
                
                self.report = result
                self.isAnalyzing = false
            } catch {
                print("Error: \(error.localizedDescription)")
                self.isAnalyzing = false
            }
        }
    }
}
```

---

## ⚡ 4. Hardware Telemetry

Professional apps should monitor hardware utilization. AudioIntelligence provides telemetry to ensure the system is running optimally on M-series chips.

```swift
Task {
    let stats = await sdk.getHardwareStats()
    print("Accelerator: \(stats["acceleration"] ?? "CPU")")
    print("Core Count: \(stats["threads"] ?? 0)")
}
```

---
*Next Step: Explore [Tutorial 02: Extracting MIR DNA](02_MIR_DNA.md) to learn about spectral features and MFCC analysis.*
