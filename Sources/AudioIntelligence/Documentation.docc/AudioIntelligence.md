# ``AudioIntelligence``

An explainable, offline, zero-dependency Swift audio analysis library for Apple Silicon.

## Overview

AudioIntelligence analyzes an audio file and produces a single "Music DNA" report that
combines two clearly separated layers:

- **Measurement** — standards-validated, deterministic, explainable numbers (loudness per
  EBU R128, true peak per ITU-R BS.1770, THD+N/IMD per AES17, ITU-R 468 weighting,
  source bit depth). These are validated against reference implementations (`ffmpeg`,
  `librosa`) and are suitable for engineering/analytical work.
- **Estimation** — best-effort musical interpretation (tempo, key). These are statistical
  estimates, benchmarked against `librosa` on standard datasets — never 100% accurate.
  Treat them as *estimates*, not measurements.

The library is pure Swift on Accelerate/AVFoundation/Metal — no Python, no model
downloads, no network. Reference tools are used only at test time.

```swift
import AudioIntelligence

let engine = AudioIntelligence()                     // thread-safe actor
let report = try await engine.analyze(url: audioURL) // -> AudioReport

// Measurement: validated, standards-traceable
let lufs = report.measurements.loudness.integrated
print(lufs.value, lufs.unit.rawValue, lufs.standard?.rawValue ?? "")  // EBU R128 LUFS

// Estimation: statistical, carries a confidence
let tempo = report.estimations.tempo
print(tempo.value, "BPM", tempo.confidence)          // never 100% certain

// Transport: the consumer renders/persists as it wishes
let json = try report.jsonData()                     // universal
let plist = try report.plistData()                   // Apple-native, compact
let markdown = MarkdownRenderer.render(report)        // optional reference renderer
```

> Important: `AudioIntelligence` is an `actor`; call its methods with `await`.

### Result type

`analyze(url:features:progress:)` returns an ``AudioReport`` — the canonical, typed
product. A markdown/JSON/PDF document is just one *rendering* of it; the library
itself writes no files.

- **`measurements`** — certifiable figures wrapped in `Measured<T>` (value + unit +
  standard + `validated`): loudness (EBU R128 / BS.1770), fidelity (THD+N/IMD/SNR per
  AES17/SMPTE/468), stereo field, forensic integrity, spectral descriptors, separation.
- **`estimations`** — statistical results wrapped in `Estimated<T>` (value + confidence
  + method): tempo, key, time signature, structure, instruments, musicology.
- **`features`** — heavy low-level series (chromagram, MFCC, spectrogram); always in
  memory, optionally excluded from serialization via `jsonData(includingFeatures:)`.

These value types live in the `AudioIntelligenceCore` module (re-exported by
`AudioIntelligence`), so `import AudioIntelligence` brings them into scope.

## Topics

### Essentials

- ``AudioIntelligence/AudioIntelligence``
