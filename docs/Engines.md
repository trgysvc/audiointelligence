# ⚙️ Engines: The Infinity Suite Catalog (v7.1)

This document provides a comprehensive technical reference for all analysis engines integrated into the **AudioIntelligence Infinity Suite**.

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
| **CQTEngine/VQTEngine** | Musical Pitch | Constant-Q/Variable-Q transforms. |
| **ChromaEngine** | Tonal Distribution | 12-bin musical energy mapping. |
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
| **ForensicEngine** | Truth Detection | Entropy analysis and Codec bracketing. |
| **LoudnessEngine** | Metering | EBU R128 / ITU-R BS.1770-4 compliance. |
| **TruePeakEngine** | Inter-sample Peak | 4x Sinc-interpolation for TP detection. |
| **AudioScienceEngine**| Lab Metrics | AES17 Dynamic Range, THD+N, SNR, IMD. |

## 7. Advanced Timbral & Semantic Analysis
| Engine | Purpose | Technical Basis |
| :--- | :--- | :--- |
| **InstrumentEngine**| Labeling | Neural-assisted prediction using MFCCs. |
| **WaveletEngine** | Multi-Res Analysis | Multi-level discrete wavelet transforms (DWT). |
| **SpectralZoneEngine**| Energy Budgeting | Detailed sub-band energy distribution. |

---
*Last Updated: 2026-04-20 — Total Engines: 31+*
