# 🗓️ Changelog

All notable changes to the **AudioIntelligence SDK** will be documented in this file. This project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [7.1.0] - 2026-04-20
### Added
- **GPU Discovery**: Enhanced Metal initialization with explicit hardware discovery logs for M4 Silicon.
- **Asynchronous Metal**: Implemented non-blocking GPU semaphore wait patterns for improved utilization tracking.
- **Long-File DNA**: Added support for forensic aggregation of files >45 minutes (Verified with Ruben Gonzalez high-fidelity donor tracks).

### Fixed
- **Chroma Aggregation**: Corrected logical error where only the first chroma bin was aggregated; now utilizes mean fragment vectors.
- **Data Alignment**: Resolved `Index Out of Range` crashes in Musicology engines by enforcing strict fragment alignment.
- **Path Resolution**: Fixed report naming logic to correctly handle various audio extensions (.flac, .wav) during `.dna.md` generation.
- **CPU Overload**: Replaced slow Swift `map` fallbacks with high-performance `vDSP` routines in the Metal pipeline.

## [6.3.0] - 2026-04-19
### Added
- **Librosa Parity**: Added `WaveletEngine` for Discrete Wavelet Transforms (DWT).
- **Recurrence Matrices**: Added academic parity for structural similarity analysis in `StructureEngine`.
- **Transparency**: Added CI status badges and "Testing & Scientific Validation" documentation.
- **Migration Guide**: New Documentation for Librosa users.
- **Format Support**: Detailed documentation of native Apple codec support.

### Changed
- **Resampling**: Upgraded `ManipulationEngine` with vectorized `vDSP` resampling for higher audio fidelity.
- **README**: Full overhaul with UI Showcase and feature highlights.

---

## [6.2.0] - 2026-04-18
### Added
- **EBU R128 Parity**: Completed 100% mathematical parity with EBU Tech 3341/3342.
- **Dual-Gating**: Implemented Absolute and Relative gating for loudness integration.
- **SQAM**: Integrated EBU Sound Quality Assessment Material validation suite.

### Fixed
- **Energy Summation**: Corrected multi-channel energy accumulation for better precision.

---

## [6.1.0] - 2026-04-17
### Added
- **Forensic DNA**: Integrated bit-depth entropy auditing.
- **Metal Acceleration**: Restored GPU acceleration bridges for spectral rendering.
- **Copy-on-Process**: Safe architecture for protecting original user files.

### Fixed
- **Memory Leaks**: Resolved allocation issues in the CQT engine.
- **Swift 6**: Achieved full actor-isolation across the core DSP pipeline.

---

## [56.0.0] - Earlier 2026
### Added
- **Infinity Engine**: Initial rollout of the consolidated 26-engine suite.
- **NMF & HPSS**: Integrated Source Separation modules.
- **AES17 Metrics**: Added Dynamic Range and SNR lab benchmarks.

---

## [51.0.0] - Initial 2026
### Added
- **Core DSP**: Initial implementation of STFT, Mel-Spectrogram, and Loudness foundations.
- **SPM Support**: First public-ready Swift Package structure.
