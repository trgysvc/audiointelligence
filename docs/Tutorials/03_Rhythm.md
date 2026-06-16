# Tutorial 03: Rhythm, Pulse & Beat Tracking

Understanding the temporal structure of audio is vital for DJ applications, music production tools, and rhythmic analysis. This tutorial covers **Tempo (BPM)** estimation and **Beat Tracking** (identifying the timestamp of every beat).

---

## 🥁 1. Global Tempo Estimation

The `RhythmEngine` provides a global BPM estimate by analyzing the autocorrelation of the **Onset Strength Envelope**.

Tempo is an **estimation** — `report.estimations.tempo` carries the value, a confidence and the
method.

```swift
let tempo = report.estimations.tempo

print("Estimated BPM: \(tempo.value)")
print("Confidence: \(Int(tempo.confidence * 100))%")
print("Method: \(tempo.method)")
```

> [!TIP]
> **Confidence Metric**: A confidence below ~0.4 usually indicates complex polyphonic material
> (ambient textures, free-jazz) where a steady pulse is hard to identify. Threshold it before
> presenting BPM as fact.

---

## 📍 2. Structure (sections)

The public `AudioReport` exposes the **section structure** (intro/verse/chorus…) under
`estimations.structure`. (Per-beat timestamps and the raw onset envelope are internal to the
pipeline and are not part of the public schema; use `analyzeRawAggregate(url:)` if you need them.)

```swift
for seg in report.estimations.structure {
    print("\(seg.label): \(seg.start)s – \(seg.end)s")
}
```

---

## 🖼️ 4. SwiftUI Implementation: Rhythmic Metronome

Here's how to build a visual "Metronome" that highlights the beat during playback using the analysis data.

```swift
import SwiftUI
import AudioIntelligence

struct RhythmicMetronome: View {
    let bpm: Double                       // report.estimations.tempo.value
    @State private var currentBeatIndex = 0
    @State private var currentTime: Double = 0
    let playbackTimer = Timer.publish(every: 0.01, on: .main, in: .common).autoconnect()

    private var beatInterval: Double { 60.0 / max(bpm, 1) }

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
            // Even click grid derived from the estimated tempo
            if currentTime >= Double(currentBeatIndex + 1) * beatInterval {
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
*Next Step: Explore [Tutorial 04: Source Separation](04_Separation.md) to work with HPSS harmonic/percussive content.*
