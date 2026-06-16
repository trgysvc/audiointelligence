# Tutorial 04: Source Separation

AudioIntelligence offers two separation paths: **HPSS** (classical DSP, built in) and an optional
**Core ML separation interface** (you supply the model).

---

## 🎻 1. Harmonic / Percussive content (HPSS)

HPSS splits a mix into tonal (harmonic) and transient (percussive) energy. It is vDSP-accelerated
and needs no model. The `analyze()` pipeline surfaces the **energy ratios** in the report:

```swift
let report = try await sdk.analyze(url: audioURL, features: [.separation])
let sep = report.measurements.separation

print("Harmonic ratio: \(Int(sep.harmonicRatio.value * 100))%")
print("Percussive ratio: \(Int(sep.percussiveRatio.value * 100))%")
```

> These are **measurements** (deterministic energy ratios), not separated audio. To obtain the
> actual harmonic/percussive *signals*, use `HPSSEngine` directly on an STFT — that is a lower-level
> API, not part of `analyze()`.

---

## 🧩 2. Stem isolation (optional, bring-your-own model)

Isolating Vocals / Drums / Bass / Other is **not** part of `analyze()` and **no model ships** with
the library. AudioIntelligence provides an *interface*, `NeuralSeparationEngine`, that applies the
spectral masks produced by a `SeparationModel` you supply (e.g. a Core ML model running on the ANE):

```swift
// You implement SeparationModel around your own Core ML model.
let engine = NeuralSeparationEngine()
let stems = try await engine.separate(samples: samples,
                                      using: myModel,        // your SeparationModel
                                      stftEngine: STFTEngine())
let vocals = stems["vocals"]
```

> If you don't provide a model, there is no neural stem separation — only the HPSS ratios above.

---

## 🖼️ 3. SwiftUI pattern: a stem mixer

If you have produced stems (via your own model + `NeuralSeparationEngine`, or your own audio
graph), a mixer UI is straightforward. This is a pure UI pattern — it does not depend on any
specific separation backend:

```swift
import SwiftUI

struct StemMixer: View {
    @StateObject var mixer = StemMixerManager()   // your AVAudioEngine wrapper

    var body: some View {
        HStack(spacing: 30) {
            StemChannel(name: "Vocals", icon: "mic", volume: $mixer.vocalVolume)
            StemChannel(name: "Drums", icon: "drum", volume: $mixer.drumVolume)
            StemChannel(name: "Bass", icon: "guitars", volume: $mixer.bassVolume)
            StemChannel(name: "Other", icon: "music.note", volume: $mixer.otherVolume)
        }
        .padding().background(Color.black.opacity(0.8)).cornerRadius(20)
    }
}

struct StemChannel: View {
    let name: String, icon: String
    @Binding var volume: Double
    var body: some View {
        VStack {
            Slider(value: $volume, in: 0...1)
                .rotationEffect(.degrees(-90)).frame(width: 40, height: 150)
            Image(systemName: icon).font(.title2)
            Text(name).font(.caption2.bold())
        }
    }
}
```

---
*Next Step: Explore [Tutorial 05: Forensic Auditing](05_Forensics.md) to evaluate signal integrity and detect upsampling.*
