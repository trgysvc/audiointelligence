# 🌌 AudioIntelligence: Infinity Engine (v6.3)

[![Swift 6.1](https://img.shields.io/badge/Swift-6.1-orange.svg)](https://swift.org)
[![macOS 15](https://img.shields.io/badge/macOS-15-blue.svg)](https://apple.com)
[![EBU R128](https://img.shields.io/badge/EBU-R128-green.svg)](https://tech.ebu.ch)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

AudioIntelligence is a premium, high-fidelity Music Information Retrieval (MIR) and DSP framework. Built from the ground up for **Swift 6** and **Apple Silicon (M4 optimized)**, it delivers bit-exact scientific accuracy combined with the raw power of Accelerate and Metal.

---

## 🚀 Why AudioIntelligence?

While legacy libraries like Librosa are excellent for research, AudioIntelligence is engineered for **Industrial-Grade Production**:

- **⚡ Sub-millisecond Latency**: Native AMX (Apple Matrix Extension) and Metal kernels for real-time professional workflows.
- **🎨 Native SwiftUI UI**: Includes `AudioIntelligenceUI` for hardware-accelerated, real-time spectrograms, waveforms, and meters.
- **🛡️ Swift 6 Actor Isolation**: The world's first MIR library with compile-time thread safety and zero data races.
- **💿 Professional Format Support**: Mastery of ALL native Apple codecs including AAC, MP3, ALAC, and FLAC via `AVAudioConverter`.
- **4️⃣ Hybrid 4GB Cache**: Advanced persistent storage for instantaneous retrieval of forensic DNA signatures.

---

## 💎 Professional Standards & Compliance (v6.3)
The Infinity Engine is formally validated against industry "Gold Standards":
- **ITU-R BS.1770-4 / EBU R128**: bit-exact, multi-channel loudness metering (±0.1 LU precision).
- **Forensic True Peak**: 511-tap high-precision inter-sample detection (BT.1770 compliant).
- **EBU Tech 3341/3342**: Verified Integrated, Momentary, Short-term, and LRA compliance.
- **SQAM Accredited**: Validated against the official EBU Sound Quality Assessment Material dataset.

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
- **StructureEngine**: Automated structural segmentation (Intro, Verse, Chorus, Outro).

### Advanced Processing & Science
- **NMF Source Separation**: Deterministic non-negative matrix factorization.
- **HPSS**: Median-filter based Harmonic-Percussive source separation.
- **Pitch Audits**: YIN, Piptrack (parabolic), and Viterbi sequence tracking.
- **AudioScience**: AES17 dynamic range, SMPTE IMD, and ITU-R 468-4 weighting.
- **Instrument DNA**: Neural-assisted instrument fingerprinting and predictions.

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
