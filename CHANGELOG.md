---

## [8.2.3] - 2026-09-03
_(Everything below shipped together as the next release after 8.2.2 — instrument calibration,
Key rewiring, pitch statistics, and the chord fix were all still unreleased/pending in this
CHANGELOG, so they're one version bump, not the 8.3.0→8.4.0 sequence briefly drafted here before
being corrected.)_

### Changed — BREAKING: `key.value` format changed
- **`report.estimations.key.value` is now mode-qualified (`"G Major"`), not a bare tonic
  (`"G"`).** The field's backing algorithm moved from `ReductionEngine.fundamentalNote` (a
  per-segment loudest-chroma-bin majority vote that never determined major/minor) to
  `ModulationEngine.detectKey` (Krumhansl-Schmuckler correlation, DEVLOG Phase 41 retraction →
  Phase 43 fix). **A consumer that parses `key.value` expecting a bare note name, or that
  concatenates/compares it against a bare-tonic string, will break** — the value now always
  includes `" Major"`/`" Minor"`, or `"Unclassified"` when correlation is too weak to call.
  `key.confidence` also changed source (`detectKeyWithConfidence`'s own raw correlation
  strength, not `reduction.stabilityScore`) — it is NOT calibrated (unlike `instruments`'
  confidence, see `MetricWrappers.swift`), so treat it as a within-algorithm relative score, not
  a probability. Accuracy on real music (GiantSteps, 599 tracks): 48.8% exact / 61.4%
  MIREX-weighted — this is now genuinely the exposed field's own accuracy, not a different
  algorithm's (DEVLOG Phase 41 found the two had been measured/reported out of sync; Phase 43
  verified the fix end-to-end, both on synthetic clips and 5 real GiantSteps files).

### Changed — pitch statistics: values shift, `medianF0` is a new number
- **`PitchMetrics.meanF0`/`.medianF0`/`.minF0`/`.maxF0`/`.stability` now come from the raw
  per-frame voiced-pitch pool across the whole track, not from averaging/min/max-ing each
  chunk's own summary statistic** (DEVLOG Phase 44). Previously `.medianF0` was literally a
  second copy of `.meanF0` (`DNAReportBuilder` passed the same variable into both `PitchMetrics`
  parameters) — it is now a real, independently-computed median, and will differ from
  `.meanF0` on real (non-constant-pitch) audio. `.meanF0` itself also moved: it was a
  second-order statistic (mean of each chunk's own mean, weighting a short and a long chunk
  equally) and is now a true first-order mean across every voiced frame — measured shift on a
  real multi-chunk file: mean 1.5%, min/max far more (min 21Hz lower, max 80Hz higher, since a
  chunk's own mean can never reach that chunk's real extremes). **A consumer with a hardcoded
  expectation for these specific numeric values (a snapshot test, a cached baseline) will see
  new numbers** — the change is a correctness fix (both statistics are now computed the way
  their names claim), not a tuning adjustment. `Examples/ReliabilityAudit`'s pYIN Raw Pitch
  Accuracy figures (Phase 33) are unaffected — RPA is computed independently, per-frame, direct
  against MDB-stem-synth ground truth, and never reads these fields.

### Changed — `instruments` confidence is now calibrated
- **`instruments` confidence is now per-class calibrated — a behavior change for consumers that
  threshold it, in the more-consistent direction.** Each `Estimated<String>` in
  `AudioReport.estimations.instruments` used to carry a raw score-component sum as `confidence`;
  it now carries a value calibrated per instrument class (`InstrumentCalibration`, fit on
  OpenMIC-2018's official train partition, validated on held-out — cross-class ECE spread
  0.075→0.048, DEVLOG Phase 38/39). Wiring into production was itself verified by a same-input
  identity check against `InstrumentEngine.predict()`'s real output, not assumed from the fit's
  own numbers — see DEVLOG Phase 39 for the two loading-path bugs that check caught. **This is not
  a bug fix and not silent**: a consumer that reads
  `instruments` by RANK (which label scores highest on this clip) sees no change — ordering and
  `primaryLabel` are still determined by the raw, uncalibrated score, untouched by this release.
  A consumer that reads it by a FIXED CONFIDENCE THRESHOLD (e.g. "show labels with confidence
  ≥0.6") will see a different population of predictions at that threshold than before, because the
  raw score was not comparable across the 6 instrument classes (a raw 0.31 meant ~36% true
  reliability for Bass and ~74% for Vocals, measured) and the calibrated value now is. Which
  labels are included at all is also untouched — the 0.3 inclusion cutoff is still evaluated
  against the raw score, deliberately not recalibrated (raising it would destroy information a
  confidence-reading consumer could otherwise recover; see DEVLOG Phase 37).

### Fixed
- **4-note jazz-extension chord identification (dom7/m7/m7b5/m6) was frequently wrong on real
  (non-idealized) audio** — end-to-end synthetic-audio accuracy 58/108 → 87/108 canonical
  chords (DEVLOG Phase 45). Root cause: a smaller chord shape's chroma score could numerically
  outscore a larger shape that fully contains it (e.g. a 3-note "E diminished" beating the true
  "C dominant 7" it's a subset of), because real per-tone chroma magnitudes are never perfectly
  equal the way idealized/synthetic-exact inputs are. `TraditionalTheoryEngine.identifyTriad`
  now penalizes candidates for chroma energy they leave unexplained. Remaining 21/108 mismatches
  are a known augmented-triad symmetry (9) and m6/m7b5 pairs that share an identical pitch-class
  set (12) — not resolvable by this fix, tracked separately (worklist).

## [8.2.1] - 2026-06-18
### Fixed
- **Time-signature confidence overflowed to 383%.** The mapping piped `rhythm.beatConsistency`
  — an unbounded beat-interval *deviation* in `[0, ∞)` where *lower* means steadier — straight
  into `Estimated.confidence` (which is not self-clamping). On an erratic source (a 46-min jazz
  album) a deviation of `3.83` surfaced as a `383%` confidence. Now inverted and clamped:
  `max(0, min(1, 1 - beatConsistency))`, so a steady meter reads high and an irregular one low
  (the Rubén González album now correctly reports `0%`).
- **THD+N and SMPTE IMD emitted `NaN` on real music, breaking serialization.** Both are
  test-tone-only lab measurements (`detectTestTone` finds no 997 Hz / 7 kHz stimulus in music),
  so the per-fragment aggregate fell back to `Float.nan`. `NaN` is invalid JSON, so
  `report.jsonData()` / `plistData()` could throw or round-trip badly. The aggregate now returns
  `0` when no tone is present, and the report marks these `validated: false` (instead of the
  previous unconditional `validated: true`) — honestly "not measured on this material" rather
  than a fabricated certified `0%`.
- **`waveformPeaks` was always empty.** `DNAReportBuilder` hardcoded `waveformPeaks: []` at
  assembly time; the per-chunk peak envelope was never accumulated. It is now built in the chunk
  loop (`vDSP_maxmgv`, 64 buckets/chunk) and threaded through to the report (the 46-min album
  now yields 4030 envelope points, max ≈ 0.978).

### Changed
- **CLI example (`Examples/CLIExample`) now takes a file-path argument** and renders a **live,
  single-line progress bar** driven by the library's existing `analyze(progress:)` callback —
  demonstrating that the library *streams* progress to the consumer (it does not print it
  itself). The example also serializes the report to JSON + `.plist` via `report.jsonData()` /
  `report.plistData()`; **writing those files is the example app's job, never the library's.**

## [8.2.0] - 2026-06-16
### Added
- **`AudioReport` — a typed, layered report product.** `analyze()` now returns a single
  `AudioReport` value whose schema separates **measurements** (objective, `Measured<T>` with
  unit + standard + `validated`) from **estimations** (statistical, `Estimated<T>` with
  confidence + method + alternatives), plus optional heavy `features` series.
- **Codable-first transport:** `report.jsonData(includingFeatures:)` (universal) and
  `report.plistData(includingFeatures:)` (Apple-native binary). The consuming app converts/
  renders as it wishes.
- **`MarkdownRenderer`** — an optional, pure reference renderer over `AudioReport` (not invoked
  by `analyze()`).
- **`schemaVersion` (1.0.0)** so the schema can grow additively (e.g. the upcoming instrument
  layer) without breaking consumers.
- **`analyzeRawAggregate(url:)`** — advanced/diagnostic access to the internal engine aggregate
  for deep validation.

### Changed
- **The library no longer writes files.** The previous pipeline wrote a `.md` + `.plist` to a
  hardcoded `~/Documents/AI Works` path as a side effect of analysis (which threw on any machine
  where that folder was absent). Persistence is now entirely the caller's choice.
- Demo app, examples, benchmark and validation tests migrated to the `AudioReport` API.

### Fixed
- **Upsampling false positive (forensic):** "fake hi-res" detection was keyed on Shannon entropy
  (`meanEntropy < 0.6`), which false-flagged legitimate low-entropy material (e.g. a solo
  instrument) as upsampled. Now correctly defined as *declared bit depth exceeding the measured
  effective bit depth*; `effectiveBits` reports the measured value.

### Removed
- Fabricated report claims (`✅ AUTHENTIC`, `100% Data Integrity Guaranteed`, `26 Engines
  Active`, `M4 Silicon GPU ✅ ACTIVE`, `[FINAL AUDIT VERDICT]`) that were printed regardless of
  the actual signal.
- Dead, unused `MusicDNAReporter` (470 lines).

### Documentation
- Rewrote `docs/REPORT_SPECIFICATION.md`, `AI_INTEGRATION_GUIDE.md`, `Integration.md`,
  `Forensics.md`, `ScientificValidation.md` and `Engines.md` against the real code; corrected the
  project-structure tree; moved project manuals into `docs/`.

## [8.1.5] - 2026-04-20
### Added
- **SQAM Forensic Audit**: Successfully completed the industry-standard 70-track EBU SQAM (Tech 3253) validation suite with 100% stability.
- **Scientific Integrity Report (SIR)**: Integrated a formal verification certificate documenting mathematical parity with Librosa and EBU standards.
- **SQAMAuditTool**: New internal utility for automated batch processing and deviation reporting.
- **M4 Silicon Forensic DNA**: Sealed the forensic pipeline with real-time hardware telemetry and GPU-accelerated reporting.

### Changed
- **Apple Binary Standard**: Migrated all forensic metadata exports from JSON to **Apple Property List (.plist)** for improved performance and data integrity.
- **README/DEVLOG Overhaul**: Updated all user-facing documentation to reflect the v8.1.5 scientific status.

### Fixed
- **SIGTRAP 133 (Critical)**: Resolved an Integer Division by Zero vulnerability in the `MeterEngine` by implementing vectorized safety guards.
- **Optional Interpolation**: Fixed diagnostic warnings in `InfinityAudit` regarding optional string interpolation.

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
