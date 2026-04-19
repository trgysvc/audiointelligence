# ⚙️ Engines: Technical Implementation Reference

This document provides a comprehensive technical reference for the **AudioIntelligence Infinity Suite**. This complete **26-engine suite** is implemented using high-priority **Apple Silicon (M4 optimized AMX/ANE)** protocols and adheres to professional broadcast and forensic standards.

---

## 🏗️ 1. Core Signal Infrastructure

The foundation of all DSP tasks within the SDK.

### STFTEngine
The fundamental spectral analyst.
- **Algorithm**: Complex-to-Complex / Real-to-Complex FFT via `vDSP_DFT`.
- **Optimization**: Supports zero-padding, periodic window coefficients, and mag-scaling for energy preservation.
- **Parity**: Adheres strictly to standardized STFT structure (nBins, nFrames).

### AudioLoader
Professional-grade I/O orchestrator.
- **Capabilities**: Multi-format support (PCM, FLAC, AAC, ALAC, MP3) with seamless down-mixing and sample-rate conversion via `AVAudioConverter`.
- **Performance**: Integrated with **IntelligenceCache** to ensure that once a file is loaded and fingerprinted, subsequent reads are instantaneous.

---

## 📈 2. Standards-Compliant Analysis

Engines calibrated against official industry test vectors.

### LoudnessEngine
- **Standards**: ITU-R BS.1770-4, EBU Tech 3341/3342.
- **Logic**: Implemented with **Double precision** energy accumulation. Uses K-weighting pre-filter followed by dual-gated integration (Absolute -70 LUFS / Relative -10 LU for Integrated, -20 LU for LRA).
- **Parity**: ±0.1 LU accuracy verified against SQAM reference material.

### TruePeakEngine
- **Standards**: ITU-R BS.1770-4.
- **Process**: 4x Polyphase oversampling Sinc-filter to identify inter-sample peaks that standard meters miss.

### RhythmEngine & OnsetEngine
- **Onset Detection**: Spectral flux and phase deviation monitoring across 7 sub-bands.
- **Rhythm Logic**: Dynamic Programming (DP) tempo-estimation using Ellis (2007) architecture.
- **Output**: Global BPM and local "Click-Track" alignment with human-feel tracking.

---

## 🧬 3. Harmonic & Melodic DNA

Engines focused on tonal content and musical structure.

### CQTEngine & VQTEngine
- **Design**: Constant-Q and Variable-Q transforms for musically-aligned frequency analysis.
- **Resolution**: 12 to 36 bins per octave for absolute musical pitch tracking.

### ChromaEngine & TonnetzEngine
- **Chroma**: 12-bin harmonic distribution for chord and key recognition.
- **Tonnetz**: 6D tonal centroid mapping representing Perfect Fifths, Major Thirds, and Minor Thirds.

### InstrumentEngine (Neural Predictor)
- **Logic**: Multi-feature classifier using Spectral Flatness, MFCC coefficients, and Transient density.
- **Output**: Instrument labels (e.g., Drums, Vocals, Bass) with confidence scores.

---

## 🧪 4. Source Separation & Sequence Modeling

Engines for decomposing complex signals and understanding sequences.

### HPSSEngine
- **Logic**: Harmonic-Percussive Source Separation using median-filter masking in the STFT domain.

### NMFEngine (Non-negative Matrix Factorization)
- **Mathematics**: Iterative KL-Divergence multiplicative updates for blind source separation and basis identification.
- **Optimization**: Metal-accelerated matrix multiplication for rapid convergence.

### StructureEngine (Segmentation)
- **Logic**: Self-Similarity Matrix (SSM) analysis for automated structural segmentation.
- **Output**: Temporal boundaries for Intro, Verse, Chorus, and Bridge sections.

### ViterbiEngine
- **Function**: Hidden Markov Model (HMM) sequence decoding.
- **Use Case**: Smoothing pitch tracks and internal state transitions to eliminate "jitter" in reports.

### PiptrackEngine
- **Logic**: Parabolic Interpolation for high-resolution fundamental frequency (F0) tracking.

---

## 🔍 5. Forensic & Scientific Auditing

Tools for provenance and authenticity verification.

### ForensicEngine
- **Entropy Analysis**: Shannon Entropy calculation for bit-depth forgery detection (detecting 16-bit to 24-bit upscales).
- **Codec Signature**: Detecting encoder-specific spectral bracketing (LAME, FhG, Lavf).

### AudioScienceEngine
- **Laboratory Metrics**: Professional characterization of **AES17 Dynamic Range**, **SMPTE IMD** (Inter-modulation Distortion), and **ITU-R 468-4** weighted noise floors.

---

## 🖼️ 6. Professional Visualization

Engines designed to render industrial-grade engineering reports.

### AudioIntelligenceUI (SwiftUI + Metal)
- **SpectrogramView**: Real-time, GPU-accelerated spectral rendering with perceptually uniform colormaps.
- **WaveformView**: Multi-resolution peak/RMS rendering for fluid zooming.
- **LoudnessMeter**: EBU R128 compliant real-time metering with Momentary, Short-term, and Integrated ballistics.

---
*For architectural details on how these engines interact, see [Architecture.md](Architecture.md).*
