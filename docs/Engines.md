# ⚙️ Engines: The Analysis Suite Catalog

This document is a technical reference for the analysis engines in **AudioIntelligence**. The
suite spans two layers of trust (see the README Validation Status):

- **Measurement engines** (loudness, true peak, AudioScience, forensic, spectral descriptors) —
  deterministic and validated against reference implementations.
- **Estimation engines** (rhythm/key/structure/instrument/musicology) — statistical, best-effort,
  and still improving. Treat their output as estimates with a confidence, not facts.

---

## 1. Core Signal & Infrastructure
| Engine | Purpose | Logic |
| :--- | :--- | :--- |
| **STFTEngine** | Spectral Foundation | vDSP DFT-based time-frequency transform. |
| **AudioLoader** | Smart I/O | Multi-format loader with persistent caching. |
| **StereoEngine** | Spatial Analysis | Phase correlation and LR balance metrics. |

## 2. Rhythmic & Temporal DNA
| Engine | Purpose | Technical Basis |
| :--- | :--- | :--- |
| **OnsetEngine** | Event Detection | Spectral flux and multi-band energy deviation. |
| **RhythmEngine** | Tempo Tracking | Dynamic Programming (DP) for BPM estimation. |
| **TempogramEngine**| Pulse Mapping | Cyclic tempo-periodicity analysis. |
| **MeterEngine** | Time Signature | Beat-synchronous meter and bar detection. |
| **MotifEngine** | Pattern Recognition| Repetitive rhythmic and melodic motif detection. |

## 3. Harmonic, Tonal & Pitch DNA
| Engine | Purpose | Technical Basis |
| :--- | :--- | :--- |
| **CQTEngine** | Musical Pitch | Constant-Q transform. **Known limitation:** a complex-FFT bug makes it unreliable; it is **not** used in the pipeline. Key/chroma use a high-resolution STFT chromagram instead. |
| **ChromaEngine** | Tonal Distribution | 12-bin musical energy mapping (high-res STFT chromagram). |
| **TonnetzEngine** | Harmonic Centroids | 6D hexagonal tonal relationship mapping. |
| **YINEngine** | Pitch Tracking | Time-domain autocorrelation for F0 detection. |
| **PiptrackEngine** | Res. Fundamental | Parabolic Interpolation for ultra-precise pitch. |
| **ViterbiEngine** | Seq. Smoothing | Path optimization via Hidden Markov Models. |
| **ModulationEngine**| Key Changes | Detecting harmonic shifts within a signal. |

## 4. Musicological & Traditional Analysis
| Engine | Purpose | Theoretical Basis |
| :--- | :--- | :--- |
| **ReductionEngine** | Ur-Note Reduction | Schenkerian-inspired harmonic simplification. |
| **TraditionalTheoryEngine**| Vertical Harmony | Chord identification and inversion analysis. |
| **CounterpointEngine**| Structural Logic | Species-based counterpoint validation. |
| **CadenceEngine** | Structural Finish | Detection of Perfect, Imperfect, and Deceptive cadences. |
| **HistoricalEngine**| Contextual DNA | Artistic movement and historical period inference. |

## 5. Source Separation & Sequence Modelling
| Engine | Purpose | Technical Basis |
| :--- | :--- | :--- |
| **HPSSEngine** | STEM Isolation | Median-masking for Harmonic/Percussive splitting. |
| **NMFEngine** | Blind Separation | Non-negative Matrix Factorization. |
| **StructureEngine**| Segmentation | SSM-based (Self-Similarity Matrix) sectioning. |

## 6. Forensic & Scientific Auditing
| Engine | Purpose | Standard/Logic |
| :--- | :--- | :--- |
| **ForensicEngine** | Provenance | Upsampling detection via declared-vs-measured bit depth; codec-cutoff bracketing; clipping & entropy statistics. |
| **LoudnessEngine** | Metering | EBU R128 / ITU-R BS.1770-4 compliance. |
| **TruePeakEngine** | Inter-sample Peak | 4x Sinc-interpolation for TP detection. |
| **AudioScienceEngine**| Lab Metrics | AES17 Dynamic Range, THD+N, SNR, IMD. |

## 7. Advanced Timbral & Semantic Analysis
| Engine | Purpose | Technical Basis |
| :--- | :--- | :--- |
| **InstrumentEngine**| Labeling (estimation) | Data-derived, per-class-calibrated instrument labels tagged as estimates (`InstrumentCalibration`, fit on OpenMIC-2018's real train partition) — not placeholders. Held-out recall is class-dependent (strong: Drums/Bass/Piano; weak: Brass/Trumpet — root cause measured, see DEVLOG; fix needs a learned classifier, tracked separately). Genre/mood/danceability are a deliberate permanent non-goal, not a roadmap item (no classical-DSP definition exists for them). *Not* neural/ANE. |
| **WaveletEngine** | Multi-Res Analysis | Multi-level discrete wavelet transforms (DWT). |
| **SpectralZoneEngine**| Energy Budgeting | Detailed sub-band energy distribution. |

---
*Engines live under `Sources/AudioIntelligenceCore/Feature/`. Last reviewed: 2026-09-04 — AudioIntelligence 8.2.3.*
