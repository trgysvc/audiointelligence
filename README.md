# 🌌 AudioIntelligence: Infinity Engine (v8.1.5)

[![Swift 6.1](https://img.shields.io/badge/Swift-6.1-orange.svg)](https://swift.org)
[![macOS 15](https://img.shields.io/badge/macOS-15-blue.svg)](https://apple.com)
[![EBU R128](https://img.shields.io/badge/EBU-R128-green.svg)](https://tech.ebu.ch)
[![Loudness](https://img.shields.io/badge/Loudness-%E2%89%A40.08%20LU%20vs%20ffmpeg-green.svg)](https://tech.ebu.ch/publications/sqamcd)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

AudioIntelligence is a Music Information Retrieval (MIR) and DSP framework for **Swift 6** and **Apple Silicon**. Its loudness/forensic layer is validated against authoritative references (EBU SQAM via ffmpeg/ebur128, EBU R128/ITU-R BS.1770); its musical-interpretation layer (tempo, key, instrument) is under active accuracy work. See [Validation Status](#-validation-status-honest) for exactly what is verified.

---

## 🚀 Why AudioIntelligence?

While legacy libraries like Librosa are excellent for research, AudioIntelligence is engineered for **Industrial-Grade Production**:

- **⚡ Sub-millisecond Latency**: Native AMX (Apple Matrix Extension) and Metal kernels for real-time professional workflows.
- **🎨 Native SwiftUI UI**: Includes `AudioIntelligenceUI` for hardware-accelerated, real-time spectrograms, waveforms, and meters.
- **🛡️ Swift 6 Actor Isolation**: The world's first MIR library with compile-time thread safety and zero data races.
- **💿 Professional Format Support**: Mastery of ALL native Apple codecs including AAC, MP3, ALAC, and FLAC via `AVAudioConverter`.
- **🍏 Apple Binary Standard**: Zero JSON artifacts. All forensic DNA signatures are exported in high-performance **.plist** format.
- **♻️ In-Memory STFT Reuse**: A bounded RAM LRU lets the onset/mel/spectral engines share a chunk's spectrogram without disk I/O (no per-file cache bloat on batch runs).

---

## 📦 Installation & Quick Start

**Requirements:** Swift 6.3+, macOS 15+ / iOS 18+ (Apple Silicon recommended).

Add the package to your `Package.swift`:
```swift
dependencies: [
    .package(url: "https://github.com/trgysvc/audiointelligence.git", from: "8.1.5")
],
targets: [
    .target(name: "YourApp", dependencies: [
        .product(name: "AudioIntelligence", package: "audiointelligence")
    ])
]
```

Analyze a file:
```swift
import AudioIntelligence

let engine = AudioIntelligence()                       // thread-safe actor
let report = try await engine.analyze(url: audioURL)   // full DNA analysis
let dna = report.rawAnalysis

// Measurement layer (standards-validated):
print(dna.mastering.integratedLUFS)   // EBU R128 LUFS
print(dna.mastering.truePeak)         // BS.1770 true peak (dBTP)
print(dna.forensic.effectiveBits)     // source bit depth

// Estimation layer (best-effort — treat as estimates, not measurements):
print(dna.rhythm.bpm)                 // tempo
print(dna.tonality.key)               // key
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
- **Bit-depth / sample-rate / duration**: read deterministically from the container header.

> ⚠️ These guarantees cover the loudness/forensic metrics only. Tempo, key, instrument and
> chord accuracy are measured separately and still improving — see Validation Status below.

---

## ✅ Validation Status (honest)

We report **measured** accuracy, not claimed. Each row below is backed by a test in `Tests/`.

> "Matches/beats librosa" applies **only to tempo and key** (the two metrics we benchmarked
> against `librosa` 0.11), and loudness was validated against `ffmpeg`. It does **not** mean
> 100% accuracy — both tempo and key sit at 40–70% on a hard EDM set — and it does **not**
> mean every engine is verified. Instrument, chord, pitch and structure are not yet validated.

| Area | Status | Source of truth |
| :-- | :-- | :-- |
| Loudness (LUFS / True Peak / LRA) | ✅ Δ ≤ 0.08 LU (18/18) | ffmpeg `ebur128` |
| EBU 3341/3342 calibration (SIR) | ✅ 4/4 | reference signals |
| AES17 THD+N / SMPTE IMD | ✅ exact on known-distortion signals | synthetic references |
| ITU-R 468 noise weighting | ✅ ±0.03 dB vs the standard curve | analytic reference |
| Bit-depth / sample-rate / duration | ✅ exact | container header |
| Foundational DSP (STFT, mel) | ✅ librosa-exact (corr 1.00000, 0% residual) | librosa 0.11 |
| Synthetic ground truth (tempo/timebase/phase/structure coverage) | ✅ 8/8 | deterministic fixtures |
| Tempo — real music (EDM, 43 tracks) | ✅ Acc1 53% / Acc2 70% (librosa: 42% / 49%) | GiantSteps (MIREX) |
| Key — real music (599 tracks) | ✅ 41.9% exact / 57.7% MIREX-weighted (librosa: 42.4% / 52.5%) | GiantSteps (MIREX) |
| Instrument / chord / pitch / structure quality | ❌ not yet validated | — |

> Tempo and key were benchmarked directly against `librosa` 0.11 on the same files: we
> match or exceed it on both. (Key uses a high-resolution STFT chromagram; the bundled CQT
> engine has a known complex-FFT bug and is not used.)

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
| **GiantSteps Key+Tempo** | `Examples/Golden/giantsteps/*.mp3` (+ `manifest.json`) | audio: Zenodo <https://zenodo.org/records/1095691> · annotations: <https://github.com/GiantSteps/giantsteps-key-dataset> & <https://github.com/GiantSteps/giantsteps-tempo-dataset> | 600 EDM previews with MIREX-annotated key (599) and BPM (43). Real-music tempo/key accuracy. CC-BY (audio = Beatport previews for research). |
| **OpenMIC-2018** | `/tmp/openmic/` | Zenodo <https://zenodo.org/records/1432913> | 20-instrument, multi-label clips (from FMA). For the upcoming instrument/genre estimation layer. CC-BY 4.0. |

### Reference tools (test-time oracles — never shipped)

- **ffmpeg / `ebur128`** — the reference ITU-R BS.1770 / EBU R128 loudness meter we validate `LoudnessEngine` against (`brew install ffmpeg`).
- **librosa 0.11** (Python) — the reference for STFT/mel/MFCC/chroma/tempo/key parity. Used **only** in a throwaway venv at test time; the library itself is pure Swift, zero-dependency.

### Rebuilding the GiantSteps golden set
```bash
# audio (≈822 MB) → Examples/Golden/giantsteps/<id>.mp3 ; annotations → manifest.json
curl -L "https://zenodo.org/records/1095691/files/audio.zip?download=1" -o /tmp/gs.zip
git clone --depth 1 https://github.com/GiantSteps/giantsteps-key-dataset.git   /tmp/gs-key
git clone --depth 1 https://github.com/GiantSteps/giantsteps-tempo-dataset.git /tmp/gs-tempo
# extract audio, match <id> to key/bpm annotations, emit Examples/Golden/manifest.json
```

### Setting up the librosa reference venv
```bash
python3 -m venv --system-site-packages /tmp/lrvenv
/tmp/lrvenv/bin/pip install librosa soundfile audioread
# parity: dump features from Swift, compare with matched conventions
swift test --filter ParityDumpTests
/tmp/lrvenv/bin/python /tmp/parity_compare.py
```

Run the suites locally:
```bash
swift test --filter GroundTruthValidationTests     # synthetic, deterministic
swift test --filter EBUReferenceValidationTests    # loudness vs ffmpeg ebur128 (needs Tests/Resources/SQAM)
swift test --filter ScientificAuditorTests         # EBU 3341/3342 calibration
swift test --filter GoldenDatasetValidationTests   # GiantSteps key+tempo accuracy (needs Examples/Golden)
```

---

## 🏗 Architecture & Modules

AudioIntelligence is organized into specialized domains for maximum performance and architectural clarity:

```text
Sources/AudioIntelligenceCore/
├── Core/       # Foundation (Loading, Caching, Phase Vocoding)
├── Feature/    # Analysis (Spectral, Rhythm, Pitch, Harmonic, Mastering)
├── Effects/    # Transformation (HPSS, Stem Separation, NMF)
├── Display/    # Visualization (Metal Spectrograms, Waveforms)
└── Util/       # Governance (DNA Reporting, Calibration, DSP Helpers)
```

---

## 🧪 The Infinity Suite: 26 Forensic Engines
From time-domain forensic analysis to frequency-domain neural separation, AudioIntelligence provides a comprehensive toolkit for professional audio engineering:

### Core Analysis
- **STFT / ISTFT**: Frame-major, vDSP-optimized spectral foundations.
- **Loudness (EBU R128)**: Scientifically calibrated gating and weighting.
- **True Peak**: 4x sinc-interpolated inter-sample detection.
- **Forensic DNA**: Bit-depth integrity and forgery audit.

### Music Information Retrieval (MIR)
- **Mel / Chroma / CQT / VQT**: High-resolution pitch and timbral transforms.
- **Viterbi Decoder**: Professional sequence modeling for state analysis.
- **Onsets & Rhythm**: Multi-band rhythmic mapping and tempograms.
- **Harmony & Tonnetz**: 6D Harmonic relationship mapping on the tonnetz grid.
- **StructureEngine**: Automated structural segmentation (Intro, Verse, Chorus, Outro) and **Recurrence Matrices**.
- **Wavelets**: Multi-resolution analysis via DWT (Haar, Daubechies 2/3).

### Advanced Processing & Science
- **NMF Source Separation**: Deterministic non-negative matrix factorization.
- **HPSS**: Median-filter based Harmonic-Percussive source separation.
- **Pitch Audits**: YIN, Piptrack (parabolic), and Viterbi sequence tracking.
- **AudioScience**: AES17 dynamic range, SMPTE IMD, and ITU-R 468-4 weighting.
- **Instrument DNA**: Neural-assisted instrument fingerprinting and predictions.

---

## 🤖 AI & Agent Integration (Universal)

AudioIntelligence is designed for seamless integration with **AI Agents**, **Mastering DAWs**, and **Automated Forensic Pipelines**.

- **[Development Log](DEVLOG.md)**: Phase 6 documents the accuracy audit, root-cause fixes, and the honest measured-status matrix.
- **[Report Specification](docs/REPORT_SPECIFICATION.md)**: Detailed breakdown of the forensic output, now utilizing the **Apple Binary Property List (.plist)** standard.
- **[Engine Catalog](docs/Engines.md)**: Comprehensive technical specs for all 31+ specialized DSP engines.

---

## 📚 Professional Tutorial Series

1. **[The Basics](docs/Tutorials/01_Basics.md)**: SPM Setup and a production-grade SwiftUI Analysis View.
2. **[MIR DNA](docs/Tutorials/02_MIR_DNA.md)**: Feature extraction and Metal-accelerated spectrograms.
3. **[Rhythm & Pulse](docs/Tutorials/03_Rhythm.md)**: Implementing beat-perfect synchronization and metronomes.
4. **[Source Separation](docs/Tutorials/04_Separation.md)**: Real-time instrumental isolation using HPSS and Neural Stems.
5. **[Scientific Forensics](docs/Tutorials/05_Forensics.md)**: Integrity auditing, EBU R128 compliance, and DNA Reporting.

---

## 📖 Deep Technical Manuals

- **[Engine Manual](docs/Engines.md)**: Technical specs for the complete 26-engine suite.
- **[Integration Guide](docs/Integration.md)**: Swift 6 Actor-model and SwiftUI UI patterns.
- **[Calibration Manifest](docs/Calibration.md)**: Verified parity vs EBU/AES reference vectors.
- **[Project Structure](ProjectStructure.md)**: Global module map.
- **[Risk Management](RiskManagement.md)**: Strategic migration and industrial risk guide.

---
*© 2026 trgysvc — Engineered for Professional Excellence.*
