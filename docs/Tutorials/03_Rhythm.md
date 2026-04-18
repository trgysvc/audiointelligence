# Tutorial 03: Rhythm, Pulse & Beat Tracking

Understanding the temporal structure of audio is vital for DJ applications, music production tools, and rhythmic analysis. This tutorial covers **Tempo (BPM)** estimation and **Beat Tracking** (identifying the timestamp of every beat).

---

## 🥁 1. Global Tempo Estimation

The `RhythmEngine` provides a global BPM estimate by analyzing the autocorrelation of the **Onset Strength Envelope**.

```swift
let rhythm = report.rawAnalysis.rhythm

print("Estimated BPM: \(rhythm.bpm)")
print("Confidence: \(Int(rhythm.bpmConfidence * 100))%")
```

> [!TIP]
> **Confidence Metric**: A confidence score below 0.4 usually indicates complex polyphonic material (like ambient textures or free-jazz) where a steady pulse is difficult to identify mathematically.

---

## 📍 2. Beat Tracking (The "Click Track")

Identifying where each beat occurs in time is a much harder problem than just finding the average tempo. We use the **Ellis (2007) Dynamic Programming** approach to find the maximum-likelihood sequence of beats.

```swift
// Array of timestamps (in seconds) where each beat occurs
let beats = rhythm.beatTimes

for (index, timestamp) in beats.enumerated() {
    print("Beat \(index + 1) at: \(timestamp) s")
}
```

---

## ⚡ 3. Onset Detection (Note Starts)

If you need to know exactly when a new sound starts (a drum hit, a piano note, or a vocal transient), you can access the **Onsets**.

```swift
let onsets = report.rawAnalysis.onsets

print("Detected \(onsets.count) discrete onsets.")
```

---

## 🖼️ 4. SwiftUI Implementation: Rhythmic Metronome

Here's how to build a visual "Metronome" that highlights the beat during playback using the analysis data.

```swift
import SwiftUI
import AudioIntelligence

struct RhythmicMetronome: View {
    let beats: [Double]
    @State private var currentBeatIndex = 0
    let playbackTimer = Timer.publish(every: 0.01, on: .main, in: .common).autoconnect()
    @State private var currentTime: Double = 0
    
    var body: some View {
        HStack {
            ForEach(0..<4) { index in
                Circle()
                    .fill(index == (currentBeatIndex % 4) ? Color.accentColor : Color.gray.opacity(0.3))
                    .frame(width: 20, height: 20)
                    .scaleEffect(index == (currentBeatIndex % 4) ? 1.2 : 1.0)
                    .animation(.spring(), value: currentBeatIndex)
            }
        }
        .onReceive(playbackTimer) { _ in
            currentTime += 0.01
            // Check if we passed a beat timestamp
            if currentBeatIndex < beats.count && currentTime >= beats[currentBeatIndex] {
                currentBeatIndex += 1
            }
        }
    }
}
```

---

## 🔬 5. Behind the Scenes: PLP (Predominant Local Pulse)

For tracks with changing tempos or "human" swing, we use **PLP Analysis**. This tracks the pulse as it evolves over time, rather than assuming a fixed rigid grid.

- **Sub-Band Analysis**: We analyze Low, Mid, and High frequencies independently.
- **Pulse Synthesis**: We synthesize a local pulse curve that represents the tracking "stability" of the engine.

---
*Next Step: Explore [Tutorial 04: Source Separation](04_Separation.md) to isolate instruments using HPSS and ANE-optimized Neural models.*
