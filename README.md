# 🌌 AudioIntelligence: Infinity Engine (v8.2.3)

[![Swift 6.3](https://img.shields.io/badge/Swift-6.3-orange.svg)](https://swift.org)
[![macOS 15](https://img.shields.io/badge/macOS-15-blue.svg)](https://apple.com)
[![EBU R128](https://img.shields.io/badge/EBU-R128-green.svg)](https://tech.ebu.ch)
[![Loudness](https://img.shields.io/badge/Loudness-%E2%89%A40.08%20LU%20vs%20ffmpeg-green.svg)](https://tech.ebu.ch/publications/sqamcd)
[![License: Apache 2.0](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](LICENSE)

AudioIntelligence is a Music Information Retrieval (MIR) and DSP framework for **Swift 6** and **Apple Silicon**. Its loudness/forensic layer is validated against authoritative references (EBU SQAM via ffmpeg/ebur128, EBU R128/ITU-R BS.1770); its musical-interpretation layer (tempo, key, instrument) is under active accuracy work. See [Validation Status](#-validation-status-honest) for exactly what is verified.

---

## 🚀 Why AudioIntelligence?

While legacy libraries like Librosa are excellent for research, AudioIntelligence is engineered for **Industrial-Grade Production**:

- **⚡ Hardware-Accelerated DSP**: Accelerate (AMX-backed) and Metal kernels make batch file analysis fast. *(A true streaming/real-time API — analyzing a live, unbounded input with incrementally-updating results, e.g. live BPM/key sync or continuous broadcast loudness monitoring — is a planned goal, not yet implemented; `analyze()` today is file-in/report-out batch, see worklist.)*
- **🎨 Native SwiftUI UI**: Includes `AudioIntelligenceUI` for hardware-accelerated, real-time spectrograms, waveforms, and meters.
- **🛡️ Swift 6 Actor Isolation**: Compile-time thread safety — the analysis engine is an `actor`, checked for data races at build time.
- **💿 Professional Format Support**: Native Apple codec support (AAC, MP3, ALAC, FLAC, WAV, AIFF) via `AVAudioFile`/`AudioToolbox`, with `AVAudioConverter` handling sample-rate/format conversion.
- **📤 Codable-first output**: `analyze()` returns a typed `AudioReport`; the *caller* serializes it to **JSON** (universal) or **binary `.plist`** (Apple-native) and renders it however it wants. The library writes no files.
- **♻️ In-Memory STFT Reuse**: A bounded RAM LRU lets the onset/mel/spectral engines share a chunk's spectrogram without disk I/O (no per-file cache bloat on batch runs).

---

## 📦 Installation & Quick Start

**Requirements:** Swift 6.3+, macOS 15+ / iOS 18+ (Apple Silicon recommended).

Add the package to your `Package.swift`:
```swift
dependencies: [
    .package(url: "https://github.com/trgysvc/audiointelligence.git", from: "8.2.3")
],
targets: [
    .target(name: "YourApp", dependencies: [
        .product(name: "AudioIntelligence", package: "audiointelligence")
    ])
]
```

Analyze a file — `analyze()` returns a typed **`AudioReport`** whose schema separates
measurements from estimations:
```swift
import AudioIntelligence

let engine = AudioIntelligence()                       // thread-safe actor

// The library *streams* progress to you; it never prints or writes anything itself.
let report = try await engine.analyze(url: audioURL) { percent, message, _ in
    print("\(Int(percent))% — \(message)")             // render however your app likes
}                                                      // -> AudioReport

// Measurement layer — objective, standards-traceable (Measured<T>):
let lufs = report.measurements.loudness.integrated
print(lufs.value, lufs.unit.rawValue, lufs.standard?.rawValue ?? "")  // EBU R128 LUFS
print(report.measurements.loudness.truePeak.value)     // BS.1770 true peak (dBTP)
print(report.measurements.forensic.sourceBitDepth.value)

// Estimation layer — statistical, carries a confidence (Estimated<T>):
let tempo = report.estimations.tempo
print(tempo.value, "BPM @", tempo.confidence)          // never 100% certain
print(report.estimations.key.value)                    // key

// Transport & rendering are the caller's choice — the library writes no files:
let json = try report.jsonData()                       // universal
let plist = try report.plistData()                     // Apple-native, compact
let markdown = MarkdownRenderer.render(report)          // optional reference renderer
```

> `AudioIntelligence` is an `actor`; call its methods with `await` from an async context.
> See [Validation Status](#-validation-status-honest) for which outputs are measurements vs estimates.

---

## 🎨 UI Showcase: AudioIntelligenceUI
Built with **SwiftUI** and **Metal**, `AudioIntelligenceUI` provides ready-to-use, hardware-accelerated components for real-time spectrograms, waveforms, and meters.

---

## 🌉 The Librosa Bridge
Coming from the Python world? AudioIntelligence mirrors many Librosa APIs to ease migration. (Numerical parity is per-feature and not universally verified — treat it as a porting aid, not a drop-in equivalence.)

- **[Migration Guide](docs/Migration_from_Librosa.md)**: A Rosetta stone for Librosa users.
- **[Format Support](docs/FormatSupport.md)**: Native support for WAV, MP3, FLAC, and more.

---

## 💎 Standards & Compliance (loudness / forensic layer)
Validated against authoritative references:
- **ITU-R BS.1770-4 / EBU R128**: integrated loudness matches the reference ffmpeg/ebur128
  implementation to **Δ ≤ 0.08 LU** across the available EBU SQAM material (true peak Δ ≤ 0.27 dB,
  LRA Δ ≤ 0.21 LU).
- **EBU Tech 3341/3342**: calibration, gating, LRA and SNR self-tests pass (4/4).
- **IEC 61672-1 / ANSI S1.4-1983 (A-weighting)**: bilinear-transformed from the standard's
  analog zero/pole/gain prototype (double poles at 20.6 Hz and 12194.2 Hz, single poles at
  107.7 Hz and 737.9 Hz, per IEC 61672-1); matches the closed-form analytic curve to
  **Δ ≤ 0.01 dB** through 100 Hz–2 kHz. Same bilinear-transform accuracy trade-off as ITU-R 468
  approaching Nyquist — see DEVLOG Phase 13.
- **Bit-depth / sample-rate / duration**: read deterministically from the container header.

> ⚠️ These guarantees cover the loudness/forensic metrics only. Tempo, key, instrument and
> chord accuracy are measured separately and still improving — see Validation Status below.

---

## ✅ Validation Status (honest)

We report **measured** accuracy, not claimed. Each row below is backed by a test in `Tests/`.

> Loudness was validated against `ffmpeg`; tempo and key were measured on real music (GiantSteps,
> a hard EDM set) and sit at 40–70% there. Earlier `librosa` 0.11 head-to-head numbers for
> tempo/key are **not currently reproducible** (the comparison script isn't in this repo) and
> have been removed from this table pending re-verification — see the open items in this
> project's worklist. Instrument (held-out-test recall, re-verified) and pitch (real-corpus RPA)
> now have measured real-music numbers too; structure now has a first real-ground-truth
> measurement (SALAMI); chord identification is measured end-to-end on synthesized (not yet real)
> audio — real paired chord/audio material still doesn't exist for this project (see worklist).
>
> ✅ **Wiring fixed (2026-09-02, DEVLOG Phase 41 retraction → Phase 43 fix): the Key row below now
> measures what's actually exposed.** Originally found wrong: the 48.8%/61.4% figures were always
> `ModulationEngine.detectKey` (Krumhansl-Schmuckler)'s accuracy, but `report.estimations.key.value`
> was computed by a different algorithm (`ReductionEngine.fundamentalNote`, a bare tonic, no
> major/minor, never itself accuracy-measured). Rather than just re-label the mismatch, it was
> resolved: both algorithms were measured side by side on real GiantSteps (tonic-only accuracy,
> statistically indistinguishable, p=1.0 at N=43) plus `detectKey`'s major/minor signal was checked
> and found real (86% mode accuracy, 95% when its own tonic call is right) where `ReductionEngine`
> can never provide one at all; git history confirmed the original wiring was an oversight (from
> when `ReductionEngine` was briefly the only key mechanism that existed), not a deliberate choice.
> `key.value` is now wired to `detectKey` — the number below is once again the exposed field's own
> accuracy, verified end-to-end (not just re-labeled) via a production-vs-isolated identity test.

| Area | Status | Source of truth |
| :-- | :-- | :-- |
| Loudness (LUFS / True Peak / LRA) | ✅ Δ ≤ 0.08 LU (18/18) | ffmpeg `ebur128` |
| EBU 3341/3342 calibration (SIR) | ✅ 4/4 | reference signals |
| AES17 THD+N / SMPTE IMD | ✅ exact on known-distortion signals (test-tone only — on music they report `0` with `validated: false`) | synthetic references |
| ITU-R 468 noise weighting | ✅ ±0.03 dB vs the standard curve | analytic reference |
| A-weighting (IEC 61672-1) | ✅ Δ ≤ 0.01 dB through 100Hz–2kHz vs the closed-form analytic curve | analytic reference |
| Bit-depth / sample-rate / duration | ✅ exact | container header |
| Foundational DSP (STFT, mel) | ✅ librosa-exact (STFT corr 1.00000, 0.0000% residual; mel corr 1.00000, 0.0003% residual) — reproducible via `scripts/parity_compare.py` | librosa 1.0.0 |
| Synthetic ground truth (tempo/timebase/phase/structure coverage) | ✅ 8/8 | deterministic fixtures |
| Tempo — real music (EDM, 43 tracks) | ✅ Acc1 69.8% / Acc2 81.4% (measurement correction, not a real improvement — the prior 53%/70% under-measured this same production algorithm at the wrong sample rate; see DEVLOG Phase 36) | GiantSteps (MIREX) |
| Key — real music (599 tracks) | ✅ 48.8% exact / 61.4% MIREX-weighted (N=599, native sample rate, DEVLOG Phase 36) — `report.estimations.key.value` is `ModulationEngine.detectKey`, wired and verified end-to-end (DEVLOG Phase 43) | GiantSteps (MIREX) |
| Instrument — real music | ✅ OpenMIC-2018 held-out test partition recall (isolated `InstrumentEngine.predict()` pipeline, single call per clip): Drums 79%, Bass 59%, Piano 52%, Strings/Synth 41%, Vocals 22%, Brass/Trumpet 5% (root cause for the weak end measured, see DEVLOG — no fix applied yet, needs a learned classifier); IRMAS (4 classes it can measure): 28.5% blended. Real production (`report.estimations.instruments.primaryLabel`, chunked pipeline) agrees with this isolated measurement 89.3% of the time on the same 150-file held-out sample — see `RA_INSTRUMENT_PARITY` below, not identical by construction. | IRMAS + OpenMIC-2018 |
| Pitch/f0 — real music | ✅ Raw Pitch Accuracy (<50 cents), see `Examples/ReliabilityAudit` scorecard for the current run's % | MDB-stem-synth |
| Structure — real music (15 tracks) | ✅ boundary F-measure @3.0s tolerance: 41.1% (@0.5s: 21.3%) | SALAMI |
| Chord identification — synthesized audio, real signal chain | ✅ 87/108 canonical (root, quality) chords correct end-to-end (STFT→Chroma→CQT→TraditionalTheoryEngine) — up from 58/108 (DEVLOG Phase 45: explained-energy penalty fixed a real scoring bug where a smaller chord shape could outscore a larger one it's a subset of; remaining 21 mismatches are 9 known augmented-symmetry ties plus 12 m6/m7b5 pairs sharing identical pitch-class sets, unresolvable without a working bass-note signal — see worklist); real-corpus measurement still blocked (no legally-obtainable paired chord/audio material) | self-synthesized, 100%-exact ground truth |

---

## 📚 Test & Validation Material

The library ships **only source code** — all test audio/datasets and the reference tools are
**git-ignored** (see `.gitignore`) to keep the repo lean. They are not runtime dependencies;
they are used **at test time only**, as ground-truth oracles. Reproduce any validation by
fetching the material below into the indicated paths.

### Reference audio & annotation datasets

| Material | Path (git-ignored) | Source | What it is / used for |
| :-- | :-- | :-- | :-- |
| **EBU SQAM** (Tech 3253) | `Tests/Resources/SQAM/*.wav` | EBU — <https://tech.ebu.ch/publications/sqamcd> | 6 broadcast reference recordings (trumpet, horn, harp, quartet, speech, glockenspiel). Loudness + instrument tests. |
| SQAM reference values | `Tests/Resources/sqam_reference_values.txt` *(kept; small text)* | generated by `ffmpeg` `ebur128` | Authoritative integrated LUFS / true-peak / LRA for the SQAM files. |
| **GiantSteps Key+Tempo** | `Examples/Golden/audio/*.mp3` (+ `manifest.json`) | audio: Zenodo <https://zenodo.org/records/1095691> · annotations: <https://github.com/GiantSteps/giantsteps-key-dataset> & <https://github.com/GiantSteps/giantsteps-tempo-dataset> | 600 EDM previews with MIREX-annotated key (599) and BPM (43). Real-music tempo/key accuracy. CC-BY (audio = Beatport previews for research). |
| **OpenMIC-2018** | `Tests/Resources/OpenMIC/` | Zenodo <https://zenodo.org/records/1432913> | 20-instrument, multi-label clips (from FMA), 20,000 files. `InstrumentEngine` baseline. CC-BY 4.0. |
| **IRMAS** | `Tests/Resources/IRMAS/` | Zenodo <https://zenodo.org/records/1290750> | 11-instrument, single-predominant-label clips, 6,718 WAV files — a closer fit than OpenMIC for `InstrumentEngine`'s single-label `primaryLabel` output. CC BY-NC-SA 4.0. |
| **MDB-stem-synth** | `Tests/Resources/MDBStemSynth/` | Zenodo <https://zenodo.org/records/1481172> | 230 real-instrument stems (from MedleyDB) re-synthesized with exactly known f0 — a synthesis-derived ground truth, not a human estimate. `YINEngine` (pitch/f0) validation. CC BY-NC 4.0. |
| **Isophonics (Beatles)** | `Tests/Resources/Isophonics/` | <https://isophonics.net/content/reference-annotations-beatles> | Chord/key/structure/beat annotations for 179 Beatles songs. **Annotations only — no audio** (copyright); needs a legally-owned copy of the audio to pair with. `TraditionalTheoryEngine` (chord) validation target once paired. |
| **McGill Billboard** | `Tests/Resources/McGillBillboard/` | <https://ddmal.ca/research/The_McGill_Billboard_Project_(Chord_Analysis_Dataset)/> | Chord/structure annotations for 890 Billboard chart slots (3 decades of pop). **Annotations only — no audio** (copyright), same pairing requirement as Isophonics. |
| **SALAMI** (structure) | `Tests/Resources/SALAMI/` | <https://github.com/DDMAL/salami-data-public> | 1,359 tracks, hierarchical structure annotations by 10 expert annotators. Audio is split across several original sources; 444/476 tracks (93.3%) resolved and legally downloaded via the Internet Archive Live Music Archive (the official metadata's stale-but-resolvable `archive.org` URLs — no per-track manual matching needed). `StructureEngine` boundary-detection validation. |

### Reference tools (test-time oracles — never shipped)

- **ffmpeg / `ebur128`** — the reference ITU-R BS.1770 / EBU R128 loudness meter we validate `LoudnessEngine` against (`brew install ffmpeg`).
- An independent reference DSP/MIR implementation (Python, throwaway venv) — used **only** at test time for numeric cross-checks (STFT/mel/MFCC/chroma/tempo/key/CQT parity); the library itself is pure Swift, zero-dependency. Setup and usage below.

### Rebuilding the GiantSteps golden set
```bash
# audio (≈822 MB) → Examples/Golden/audio/<id>.mp3 ; annotations → manifest.json
curl -L "https://zenodo.org/records/1095691/files/audio.zip?download=1" -o /tmp/gs.zip
git clone --depth 1 https://github.com/GiantSteps/giantsteps-key-dataset.git   /tmp/gs-key
git clone --depth 1 https://github.com/GiantSteps/giantsteps-tempo-dataset.git /tmp/gs-tempo
# extract audio, match <id> to key/bpm annotations, emit Examples/Golden/manifest.json
```

### Setting up the reference cross-check venv
```bash
python3 -m venv --system-site-packages /tmp/lrvenv
/tmp/lrvenv/bin/pip install librosa soundfile audioread
# parity: dump features from Swift, compare with matched conventions
swift test --filter ParityDumpTests
/tmp/lrvenv/bin/python scripts/parity_compare.py
```
`scripts/parity_compare.py` is tracked in this repo (not `.gitignore`d, unlike the audio/dataset
material above) — it's a small script with no bundled data, so it stays reproducible.

Run the suites locally:
```bash
swift test --filter GroundTruthValidationTests     # synthetic, deterministic
swift test --filter EBUReferenceValidationTests    # loudness vs ffmpeg ebur128 (needs Tests/Resources/SQAM)
swift test --filter ScientificAuditorTests         # EBU 3341/3342 calibration
swift test --filter GoldenDatasetValidationTests   # GiantSteps key+tempo accuracy (needs Examples/Golden)
```

### Reliability scorecard

`Examples/ReliabilityAudit` is a single, repeatable tool that runs every engine with a real
ground-truth dataset in one pass (tempo, key, instrument ×2, pitch/f0) and writes a dated,
versioned scorecard. Chord still reports `not_available` (no legally-obtainable paired chord/audio
material exists — see Validation Status above for the synthesized-audio measurement that stands in
for it). Structure's `not_available` row here is a known gap in the tool itself, not the data: real
ground truth (SALAMI) now exists and `StructureEngine` is validated against it (see Validation
Status), but this specific scorecard tool hasn't been updated to run that measurement yet. See
`Examples/ReliabilityAudit/README.md`.
```bash
swift run -c release ReliabilityAudit
```

Two additional, env-var-gated diagnostics in the same tool guard `InstrumentEngine` specifically
against production-vs-isolated-pipeline drift (not run by default — real audio, several minutes):
`RA_INSTRUMENT_PARITY=1` (label-agreement between real production and the isolated pipeline, real
OpenMIC held-out audio, fixed 80% floor) and `RA_INSTRUMENT_CALIBRATION_WIRING_CHECK=1` (reported-
confidence fidelity, ~0.005 tolerance). Both real, not aspirational — the first caught and helped
fix a genuine two-session-old silent regression in production's instrument-label selection; see
DEVLOG.

---

## 🏗 Architecture & Modules

AudioIntelligence is organized into specialized domains for maximum performance and architectural clarity:

```text
Sources/AudioIntelligenceCore/
├── Core/       # Foundation (Loading, Caching, Errors)
├── Feature/    # Analysis engines (Spectral, Rhythm, Pitch, Harmonic, Mastering, Forensic)
├── Effects/    # Transformation (HPSS, Stem Separation, NMF, Manipulation)
├── Report/     # AudioReport schema (Measured/Estimated), mapping, MarkdownRenderer
├── Display/    # Visualization data (Spectrograms, Waveforms)
├── Models/     # Public value types (AudioReport, AudioFeature)
└── Util/       # Pipeline (DNAReportBuilder), DSP helpers, calibration, auditing
```

---

## 🧪 The Infinity Suite: 30+ Analysis Engines
From time-domain forensic analysis to frequency-domain source separation, AudioIntelligence provides a comprehensive toolkit for professional audio engineering. Note the honest split: the **measurement** engines below are validated; the **estimation** engines (key/tempo/instrument/musicology) are statistical and still improving (see Validation Status).

### Core Analysis
- **STFT / ISTFT**: Frame-major, vDSP-optimized spectral foundations.
- **Loudness (EBU R128)**: Scientifically calibrated gating and weighting.
- **True Peak**: 4x sinc-interpolated inter-sample detection.
- **Forensic DNA**: Bit-depth integrity and forgery audit.

### Music Information Retrieval (MIR)
- **Mel / Chroma**: High-resolution timbral and tonal transforms (key uses a high-res STFT chromagram; the CQT engine, correctness-fixed and independently cross-checked, feeds `TraditionalTheoryEngine`'s real bass-note detection — used for chord inversion labeling and for chord root/quality tie-breaking on chroma-identical chords).
- **Viterbi Decoder**: Gaussian-emission HMM sequence modeling — smooths the raw per-frame pitch estimate into a stable note path (73-state MIDI space + a silence state).
- **Onsets & Rhythm**: Multi-band rhythmic mapping, autocorrelation-based cyclic tempograms, and cross-rhythm/polyrhythm detection (3:2, 4:3, 5:4 and their inversions).
- **Harmony & Tonnetz**: 6D Harmonic relationship mapping on the tonnetz grid.
- **StructureEngine**: Automated structural segmentation (Intro, Verse, Chorus, Outro) and **Recurrence Matrices**.
- **Wavelets**: Multi-resolution analysis via DWT (Haar, Daubechies 2/3).

### Advanced Processing & Science
- **NMF Source Separation**: Deterministic non-negative matrix factorization.
- **HPSS**: Median-filter based Harmonic-Percussive source separation.
- **Pitch Audits**: YIN, Piptrack (parabolic), and Viterbi sequence tracking.
- **AudioScience**: AES17 dynamic range, SMPTE IMD, and ITU-R 468-4 / IEC 61672-1 (A-weighting) noise weighting.
- **Instrument DNA**: Data-derived, per-class-calibrated predictions (`Estimated<String>`, `InstrumentEngine`, fit on OpenMIC-2018's real train partition, confidence calibrated per class) — not placeholders. Held-out recall varies widely by class (see Validation Status): strong for Drums/Bass/Piano, weak for Brass/Trumpet (root cause measured — no strong distinguishing scalar feature rescues it from the shared, universal MFCC-space ambiguity every class has; fixing it needs a learned/data-derived classifier, not a hand-tuned formula tweak — see DEVLOG). Genre/mood/danceability are a deliberate, permanent non-goal (no classical-DSP definition exists for them; see the worklist's scope-out note) — not a roadmap item.

---

## 🤖 AI & Agent Integration (Universal)

AudioIntelligence is designed for seamless integration with **AI Agents**, **Mastering DAWs**, and **Automated Forensic Pipelines**.

- **[Development Log](DEVLOG.md)**: Phase 6–7 document the accuracy audit and root-cause fixes; **Phase 8** documents the `AudioReport` rewrite and the forensic upsampling fix; **Phases 10–13** document a full four-way correctness audit — 25+ real bugs found and fixed, including dead pipeline wiring (pitch-path smoothing, cyclic tempogram), hardcoded stand-in values, and a from-scratch IEC 61672-1 A-weighting implementation.
- **[Report Specification](docs/REPORT_SPECIFICATION.md)**: The `AudioReport` schema (Measured/Estimated layers) and its JSON / binary-plist transport.
- **[Engine Catalog](docs/Engines.md)**: Technical specs for the analysis engines.

---

## 📚 Professional Tutorial Series

1. **[The Basics](docs/Tutorials/01_Basics.md)**: SPM Setup and a production-grade SwiftUI Analysis View.
2. **[MIR DNA](docs/Tutorials/02_MIR_DNA.md)**: Feature extraction and Metal-accelerated spectrograms.
3. **[Rhythm & Pulse](docs/Tutorials/03_Rhythm.md)**: Implementing beat-perfect synchronization and metronomes.
4. **[Source Separation](docs/Tutorials/04_Separation.md)**: Instrumental isolation using HPSS and NMF.
5. **[Scientific Forensics](docs/Tutorials/05_Forensics.md)**: Integrity auditing, EBU R128 compliance, and the `AudioReport` output.

---

## 📖 Deep Technical Manuals

- **[Engine Manual](docs/Engines.md)**: Technical specs for the analysis engines.
- **[Integration Guide](docs/Integration.md)**: Swift 6 Actor-model and SwiftUI UI patterns.
- **[Report Specification](docs/REPORT_SPECIFICATION.md)**: The `AudioReport` schema and transport.
- **[Calibration Manifest](docs/Calibration.md)**: Verified parity vs EBU/AES reference vectors.
- **[Project Structure](docs/ProjectStructure.md)**: Global module map.
- **[Risk Management](docs/RiskManagement.md)**: Strategic migration and industrial risk guide.

---
*© 2026 trgysvc — Engineered for Professional Excellence.*
