# AudioIntelligence 🧬 Infinity Engine (v6.1)

**AudioIntelligence** is an enterprise-grade, silicon-native audio engineering and Forensic DNA library for the Apple ecosystem. Built entirely in Swift 6, it leverages the unique hardware advantages of the Apple Neural Engine (ANE) and Apple Matrix Extension (AMX) to provide industry-leading precision and throughput.

---

## 🌟 Key Pillars

- **"Glass Box" Engineering**: No black boxes. Every DSP engine is mathematically transparent and verified against EBU/AES standards.
- **Apple Silicon Native**: Zero-copy vector processing using Accelerate (vDSP/vImage) and Metal.
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

## 🚀 Capabilities

### 1. MIR DNA (Music Information Retrieval)
- **Spectral DNA**: STFT, Mel-Spectrogram, MFCC, Spectral Flux/Centroid.
- **Rhythmic DNA**: **Ellis (2007) Beat Tracking**, PLP Pulse Estimation, BPM Confidence.
- **Harmonic DNA**: Chroma sequence analysis, Tonnetz tonal centers.
- **Pitch DNA**: **YIN/Viterbi** fundamental frequency tracking.

### 2. Forensic & Scientific Auditing
- **Bit-Depth Entropy**: Conclusive 16-to-24-bit upsampling (fake hi-res) detection.
- **Codec Provenance**: Historical codec signature identification (MP3/AAC signatures).
- **Compliance**: EBU R128 Loudness, AES17 Dynamic Range, ITU-R BS.1770-4.

### 3. Source Separation (Effects)
- **HPSS**: Optimized **vDSP_medfilt** ($O(N)$ complexity) for Harmonic-Percussive separation.
- **Neural Stems**: ANE-housed isolation of Vocals, Drums, Bass, and accompaniment.

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
