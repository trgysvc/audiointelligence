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
- **Capabilities**: Multi-format support (PCM, FLAC, AAC, ALAC) with seamless down-mixing and sample-rate conversion.
- **Performance**: Integrated with **IntelligenceCache** to ensure that once a file is loaded and fingerprinted, subsequent reads are instantaneous.

---

## 📈 2. Standards-Compliant Analysis

Engines calibrated against official industry test vectors.

### LoudnessEngine
- **Standards**: ITU-R BS.1770-4, EBU Tech 3341.
- **Logic**: Implements K-weighting pre-filter (RLB) followed by gated integration (Absolute -70 LUFS / Relative -10 LU).

### TruePeakEngine
- **Standards**: ITU-R BS.1770-4.
- **Process**: 4x Polyphase oversampling Sinc-filter to identify inter-sample peaks that standard meters miss.

### RhythmEngine
- **Logic**: Dynamic Programming (DP) tempo-estimation using Ellis (2007) architecture.
- **Output**: Global BPM and local "Click-Track" alignment with human-feel tracking.

---

## 🧬 3. Harmonic & Melodic DNA

Engines focused on tonal content and musical structure.

### CQTEngine (Constant-Q Transform)
- **Design**: Logarithmically-spaced frequency bins (12 per octave) for absolute musical pitch tracking.
- **Resolution**: Variable window sizes to maintain a constant Q-factor across the spectrum.

### ChromaEngine & TonnetzEngine
- **Chroma**: 12-bin harmonic distribution for chord and key recognition.
- **Tonnetz**: 6D tonal centroid mapping representing Perfect Fifths, Major Thirds, and Minor Thirds. The engine outputs a high-stability harmonic grid used for **Tonnetz DNA** visualization.

### InstrumentEngine (Neural Predictor)
- **Logic**: Neural-assisted classification of dominant sound sources.
- **Output**: Instrument labels (e.g., Drums, Vocals, Bass) with associated confidence scores based on spectral flux and flatness.

### YINEngine & ViterbiEngine
- **YIN**: Time-domain fundamental frequency (F0) estimation for pitch tracking.
- **Viterbi**: HMM-based sequence modeling to prevent "jitter" or octave-jumps in tracking reports.

---

## 🧪 4. Source Separation & Neural Isolation

Engines for decomposing complex signals.

### HPSSEngine
- **Logic**: Harmonic-Percussive Source Separation using median-filter masking in the STFT domain.
- **Performance**: AMX-accelerated vector comparison for real-time splitting.

### NeuralSeparationEngine
- **Hardware**: Runs exclusively on the **Apple Neural Engine (ANE)** via CoreML.
- **Capabilities**: Professional isolation of Vocals, Drums, Bass, and Other components (Stem Separation).

### NMFEngine (Non-negative Matrix Factorization)
- **Mathematics**: Iterative KL-Divergence multiplicative updates for blind source separation.
- **Use Case**: Identifying recurring spectral patterns and basis components in unlabelled data.

---

## 🔍 5. Forensic & Scientific Auditing

Tools for provenance and authenticity verification.

### ForensicEngine & AudioScienceEngine
- **Entropy Analysis**: Shannon Entropy calculation for bit-depth forgery detection (16-bit to 24-bit upscales).
- **Codec Signature**: Detecting transcode ceilings and encoder-specific spectral bracketing.
- **Laboratory Metrics**: Professional characterization of **AES17 Dynamic Range**, **SMPTE IMD** (Inter-modulation Distortion), and **ITU-R 468-4** weighted noise floors.

### ScientificAuditor
- **Function**: Unified diagnostic portal that subjects the entire library to automated EBU/AES17 calibration audits.

---

## 🖼️ 6. Professional Visualization

Engines designed to render industrial-grade engineering reports.

### SpectrogramRenderer
- **Palettes**: Magma, Viridis, Plasma, and Inferno (CIE Cam02-Uniform).
- **Scale**: Linear, Logarithmic, and Mel-scale rendering with high-throughput vImage performance.

### WaveformRenderer
- **Logic**: Multi-resolution peak/RMS bracketing for smooth zooming and professional waveform auditing.

---
*For architectural details on how these engines interact, see [Architecture.md](Architecture.md).*
