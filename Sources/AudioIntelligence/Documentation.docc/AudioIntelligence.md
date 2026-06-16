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
let report = try await engine.analyze(url: audioURL)
let dna = report.rawAnalysis

print(dna.mastering.integratedLUFS)  // measurement: EBU R128 LUFS
print(dna.rhythm.bpm)                // estimation: tempo
```

> Important: `AudioIntelligence` is an `actor`; call its methods with `await`.

### Result types

`analyze(url:features:progress:)` returns an `AudioReport` whose `rawAnalysis` is a
`MusicDNAAnalysis`. Its fields group the analysis:

- **Measurement:** `mastering` (`MasteringMetrics` — LUFS, true peak, LRA),
  `forensic` (`ForensicMetrics` — bit depth, codec, clipping), `science` (THD+N, IMD, SNR).
- **Estimation:** `rhythm` (`RhythmMetrics` — tempo), `tonality` (`TonalMetrics` — key),
  `spectral`, `timbre`, `instruments`.

These value types live in the `AudioIntelligenceCore` module (re-exported by
`AudioIntelligence`), so `import AudioIntelligence` brings them into scope.

## Topics

### Essentials

- ``AudioIntelligence/AudioIntelligence``
