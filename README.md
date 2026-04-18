# AudioIntelligence (v6.2 Infinity Engine)
> **The Professional Standard for Scientifically Calibrated MIR on Apple Silicon.**

AudioIntelligence is a premium, high-fidelity Music Information Retrieval (MIR) and DSP framework. Built from the ground up for **Swift 6** and **Apple Silicon**, it delivers bit-exact scientific accuracy combined with the raw power of Accelerate and Metal.

---

## 💎 State of the Art: Scientific Accreditation (v6.2)
The Infinity Engine is now formally calibrated against industry "Gold Standards":
- **ITU-R BS.1770-4 / EBU R128**: Dynamic, sample-rate independent loudness metering (±0.1 LU precision).
- **EBU Tech 3341/3342**: Verified Integrated, Momentary, Short-term, and LRA compliance.
- **SQAM Accredited**: Validated against the EBU Sound Quality Assessment Material dataset.
- **Deterministic Pipeline**: Bit-exact reproducibility across all Source Separation (NMF) runs.

---

## 🌟 Key Pillars

- **"Glass Box" Engineering**: No black boxes. Every DSP engine is mathematically transparent and verified against EBU/AES standards.
- **Apple Silicon Native**: Zero-copy vector processing using Accelerate (vDSP/vImage) and Metal.
- **Swift 6 & SPM 6.0**: Built with strict concurrency and modern modularity. Requirement: macOS 14+ / iOS 17+.
- **Forensic Integrity**: The only library with native Shannon Entropy auditing for bit-depth forgery detection.
- **Enterprise Ready**: Designed for professional mastering, broadcast, and forensic laboratory environments.

---

## 🏛️ Modular Architecture

The v6.1 Infinity Engine is organized into specialized domains for maximum performance and professional clarity:

```text
Sources/AudioIntelligenceCore/
├── Core/       # Foundation (Loading, Caching, Phase Vocoding)
├── Feature/    # Analysis (Spectral, Rhythm, Pitch, Harmonic, Mastering)
├── Effects/    # Transformation (HPSS, Stem Separation, NMF)
├── Display/    # Visualization (Metal Spectrograms, Waveforms)
└── Util/       # Governance (DNA Reporting, Calibration, DSP Helpers)
```

---

## 🧪 The Infinity Suite: 22+ Feature Engines
From time-domain forensic analysis to frequency-domain neural separation, AudioIntelligence provides a comprehensive toolkit for professional audio engineering:

### Core Analysis
- **STFT / ISTFT**: Frame-major, vDSP-optimized spectral foundations.
- **Loudness (EBU R128)**: Scientifically calibrated gating and weighting.
- **True Peak**: 4x sinc-interpolated inter-sample detection.
- **Forensic DNA**: Bit-depth integrity and forgery audit.

### Music Information Retrieval (MIR)
- **Mel / Chroma / CQT**: High-resolution pitch and timbral transforms.
- **Viterbi Decoder**: Professional sequence modeling for state analysis.
- **Onsets & Rhythm**: Multi-band rhythmic mapping and tempograms.
- **Harmony & Tonnetz**: Harmonic relationship mapping on the tonnetz grid.

### Advanced Processing
- **NMF Source Separation**: Deterministic non-negative matrix factorization.
- **HPSS**: Median-filter based Harmonic-Percussive source separation.
- **Pitch Audits**: YIN and Piptrack (parabolic interpolation) tracking.
- **AudioScience**: AES17 dynamic range and noise-floor profiling.

---

## 📚 Professional Tutorial Series

Accelerate your integration with our comprehensive engineering guides:

1. **[The Basics](docs/Tutorials/01_Basics.md)**: SPM Setup and a production-grade SwiftUI Analysis View.
2. **[MIR DNA](docs/Tutorials/02_MIR_DNA.md)**: Feature extraction and Metal-accelerated spectrograms.
3. **[Rhythm & Pulse](docs/Tutorials/03_Rhythm.md)**: Implementing beat-perfect synchronization and metronomes.
4. **[Source Separation](docs/Tutorials/04_Separation.md)**: Real-time instrumental isolation using HPSS and Neural Stems.
5. **[Scientific Forensics](docs/Tutorials/05_Forensics.md)**: Integrity auditing, EBU R128 compliance, and DNA Reporting.

---

## 📦 Installation (SPM)

```swift
.package(url: "https://hub.com/trgysvc/AudioIntelligence.git", from: "6.1.0")
```

---

## 📖 Deep Technical Manuals

- **[Project Structure](ProjectStructure.md)**: Global module map.
- **[Risk Management](RiskManagement.md)**: Strategic migration and industrial risk guide.
- **[Engine Manual](docs/Engines.md)**: Technical specs for all 36+ analysis engines.
- **[Integration Guide](docs/Integration.md)**: Swift 6 Actor-model and concurrency patterns.
- **[Calibration Manifest](docs/Calibration.md)**: Verified parity vs EBU/AES reference vectors.

---
*© 2026 trgysvc — Engineered for Professional Excellence.*
