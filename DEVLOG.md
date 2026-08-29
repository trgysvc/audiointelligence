# 🌌 AudioIntelligence: Comprehensive Development Log (DevLog)

This document provides a meticulous, chronological record of the development of the **AudioIntelligence Infinity Suite**. It documents our journey from raw DSP experiments to an industrial-grade, scientifically validated audio forensics and MIR ecosystem.

---

## 🏗️ Phase 1: The Bedrock (v1.0 – v20.0)
**Focus**: Foundation, Basic DSP, and Modularization.

*   **v1.0 - v10.0**: Initial implementation of the core spectral foundations.
    *   Developed the `STFTEngine` using `vDSP_DFT` (Complex-to-Complex).
    *   Implemented basic Mel-Spectrogram and MFCC extraction.
    *   Established the `AudioLoader` as a high-level wrapper for `AVFoundation`.
*   **v15.0**: The **"Great Modularization"**.
    *   The project was refactored into a domain-driven hierarchy to manage complexity.
    *   Modules created: `Core` (I/O), `Feature` (Analysis), `Effects` (DSP), `Display` (UI), `Util` (Reports).
    *   Initial `Package.swift` created with macOS 13+ support.
*   **v17.0**: The **"Green Build" Surgical Cleanup**.
    *   Resolved 21 critical technical warnings and compilation errors.
    *   Fixed "Bus Error" (SIGBUS) vulnerabilities in `CQTEngine.swift` by implementing `withUnsafeMutableBufferPointer` safety blocks.
    *   Repaired the `MetalEngine` bridge, enabling GPU-accelerated signal squaring for loudness calculation.
*   **v20.0**: Industrial Sync.
    *   Established the `IntelligenceCache` with SHA-256 fingerprinting.
    *   First full synchronization of the Tool Registry for agentic interaction.

---

## 🚀 Phase 2: High-Performance & Concurrency (v28.0 – v53.0)
**Focus**: Swift 6, Hardware Acceleration, and UI.

*   **v28.0**: The **"Infinity Integration"**.
    *   First appearance of the **Infinity Engine** concept: a unified 26-engine suite.
    *   Integrated **Forensic Audit** capabilities: bit-depth entropy and upsampling detection.
    *   Launched `AudioIntelligenceUI`: Real-time Metal-accelerated spectrograms and waveforms.
*   **v40.0**: Performance Peak.
    *   **$O(N)$ Optimization**: Replaced legacy median filtering in `HPSSEngine` with hardware-accelerated `vDSP_medfilt`.
    *   Achieved sub-millisecond latency for real-time professional DAW workflows.
*   **v47.0**: Global Compilation Guard.
    *   Resolved severe naming collisions with the `mlx-swift-lm` framework by renaming our internal `ToolError` to `AgentToolError`.
*   **v53.0**: Professional Refactor.
    *   Refined the `AudioIntelligenceError` hierarchy into specialized sub-enums (`ForensicError`, `DSPError`, `IOError`).
    *   Created the **Tutorial Series** (docs/Tutorials/01-05) to lower the barrier for professional integration.

---

## 🔬 Phase 3: Scientific Integrity & Forensics (v56.0 – v6.2)
**Focus**: Industry Compliance, Fidelity, and Security.

*   **v56.0**: **Infinity Evolution**.
    *   Introduced "Laboratory Science" metrics: AES17 Dynamic Range, THD+N, and SNR.
    *   Implemented **"Copy-on-Process"** architecture: All analysis is performed on temporary copies to protect original user files.
    *   Added **6D Tonnetz mapping** for hexagonal harmonic analysis.
*   **v6.0**: The **"Green Path" Scientific Audit**.
    *   Implemented high-precision `Double` accumulation in `LoudnessEngine`.
    *   Achieved ±0.1 LU accuracy parity with **EBU R128 / ITU-R BS.1770-4**.
    *   Validated the system against the official **SQAM** (Sound Quality Assessment Material) dataset.
*   **v6.2**: Concurrency & Logic.
    *   **Engine DAG**: Parallelized `DNAReportBuilder` using Swift 6 `async let`, reducing total analysis time by 4x.
    *   Added **Stereo Fidelity** engine with phase correlation and mono-downmix detection.

---

---

## 🏛️ Phase 5: The Forensic Master (v8.0 – v8.1.5)
**Focus**: Stability, Mathematical Parity, and M4 Silicon Lockdown.

*   **v8.0**: **The "Zero-Division" Fix**.
    - Identified a critical `SIGTRAP 133` (Integer Division by Zero) in the `MeterEngine`. Resolved by implementing strict safety guards in the denominator calculations and vectorized bound checks.
    - Achieved 100% stability across the entire 26-engine pipeline.
*   **v8.1.0**: **The Binary Migration**. 
    - **Strategic Pivot**: Completely purged all JSON artifacts from the forensic pipeline. 
    - Implemented the **Apple Binary Property List (.plist)** standard for all DNA exports, resulting in a 40% reduction in report generation time and 100% hardware-aligned data persistence.
*   **v8.1.5**: **The SQAM Forensic Audit**.
    - Conducted the "The Real Test": A comprehensive 70-track scientific audit against the **EBU SQAM (Tech 3253)** reference set.
    - Achieved 94.2% accuracy in instrument classification and ±0.1 LU loudness parity.
    - Finalized the **Scientific Integrity Report (SIR)**, sealing the library's status as a verified professional forensic tool.

---

## 🔍 Phase 6: Ground-Truth Reckoning & Accuracy Audit (2026-06-15)
**Focus**: Replacing claimed accuracy with *measured* accuracy. This phase was triggered by
a real failure: the analysis of a full Rubén González album (single 45:59 FLAC) reported
**1.33 BPM**, **0-bit depth**, a modulation timeline running to **42,750 s** (15× the real
duration), and a "CALIBRATION DRIFT" flag. We stopped trusting claims and built a
verification system with authoritative ground truth.

### Methodology shift
Built a tolerance-based validation harness *before* fixing anything, so every change is
proven, not asserted:
- **Synthetic fixtures** (deterministic WAV: click trains, quantized sines, known-key
  chords, stereo phase) — mathematically exact expected values.
- **EBU SQAM** real audio validated against the reference **ffmpeg/ebur128** tool.
- **GiantSteps** (604 tracks, MIREX-annotated key + 43 with tempo) as the real-music
  accuracy board.

### Root-cause fixes (with how)
- **`DSPHelpers.autocorrelate` computed convolution-with-reverse, not autocorrelation**
  (the filter was reversed). Every tempo/periodicity result was corrupt. Fixed by using
  the signal itself as the correlation filter. This is the true root of the "1.33 BPM".
- **`OnsetEngine.computeSuperflux` returned an all-zero envelope for every input** — the
  max-filter ran over time with a centred window that included the current frame, so the
  positive flux was always zero. Rebuilt as proper Böck SuperFlux (frequency-axis
  max-filter + temporal lag). Onset detection was previously non-functional.
- **Bit-depth** estimated statistically from resampled floats (silence → 0). Now read
  deterministically from the container header (`kAudioFilePropertySourceBitDepth`).
- **Modulation timebase** used a hardcoded `0.18 s/frame`; replaced with the real
  `hopLength / sampleRate`.
- **Tempo aggregation** collapsed to `60 / medianIBI` (= 60/45 chunk size = 1.33 BPM);
  replaced with the median of per-chunk autocorrelation BPMs.
- **Structure/NMF** only ran on the first 45 s chunk; now span the whole track.
- **Hardcoded placeholders made real**: phase correlation / stereo width / balance
  (StereoEngine), pitch stability (YIN dispersion), HPSS means, semantic descriptors,
  tonnetz stability, tempogram period, NMF reconstruction error + component energy,
  piptrack/viterbi confidence. A latent shadowing bug (instance vs local `allHPSS`) that
  pinned HPSS to 0.5/0.5 was also fixed.
- **"CALIBRATION DRIFT"** was *not* an engine error: the ScientificAuditor generated
  peak-amplitude reference sines but expected the peak value as LUFS (LUFS is RMS-based,
  −3.01 dB lower). Corrected the reference signals; loudness is genuinely EBU-compliant.
- **STFT cache**: the disk cache wrote ~42 MB per spectrogram that was never re-read across
  files (bloating to ~3.9 GB and adding seconds/file on batch runs). Replaced with a
  bounded in-memory LRU.

### Measured status (honest)
| Area | Result | Source |
| :-- | :-- | :-- |
| Synthetic ground truth | 8/8 pass | deterministic |
| Loudness (LUFS/TP/LRA) | 18/18 within ±0.5 LU, Δ ≤ 0.08 LU | ffmpeg/ebur128 |
| EBU 3341/3342 (SIR) | 4/4 pass | reference signals |
| Bit-depth / duration / sample-rate | exact | container header |
| Tempo (real music, EDM, 43 tracks) | **Acc1 53% / Acc2 70%** (librosa 0.11: 42% / 49%) | GiantSteps |
| Key (real music, 599 tracks) | **41.9% exact / 57.7% MIREX** (librosa 0.11: 42.4% / 52.5%) | GiantSteps |
| Instrument / chord / pitch / structure quality | **not yet validated** | — |

### Benchmarked against librosa 0.11 (same files)
Per the "use the reference" principle, tempo and key were run through `librosa` on the exact
GiantSteps tracks. Findings:
- **Tempo: we exceed librosa** (53/70 vs 42/49). The autocorrelate + SuperFlux fixes plus a
  wide prior and octave correction handle fast EDM better than librosa's default `tempo()`.
- **Key: the gap was our chroma resolution.** librosa's `chroma_cqt` beat our linear 2048-bin
  STFT chroma because 2048 bins smear the bass pitches that define the key root (fifth
  confusion). We tried to fix our own `CQTEngine` (real→complex FFT, effective rate, kernel
  normalization) but it is still not usable — see the Remaining section. The fix that **did**
  work: compute chroma from a **high-resolution STFT (nFFT 8192, ~2.7 Hz bins)** on the
  existing, correct STFT path, wired into the pipeline's tonal stage (same hop 512, so the
  modulation/structure timebases are unchanged; 8/8 ground-truth still passes). Validated on
  the **full 599-track set**: key rose from 26.7% → **41.9% exact / 57.7% MIREX**, matching
  librosa on exact (42.4%) and exceeding it on the MIREX-weighted score (52.5%).

> ⚠️ Scope of this benchmark: only **tempo and key** were compared to librosa, and loudness
> to ffmpeg — not every feature. "We match/beat librosa" means on those two MIR metrics; it
> does **not** mean 100% accuracy (both sit at 40–70% on a deliberately hard EDM set) nor that
> every engine is verified. Instrument, chord, pitch and structure remain unvalidated.

### Corrections to earlier claims in this log / README
The following previously-stated figures were **not substantiated** and are retracted:
- "70-track SQAM audit" — only 6 SQAM files are present in the repo.
- "94.2% instrument classification accuracy" — instrument ID is unvalidated and visibly
  misclassifies (e.g. solo trumpet → "Vocals/Chorus").
- "100% stability / bit-exact accuracy" — loudness is EBU-compliant (±0.08 LU); tempo and
  key are now *measured* and benchmarked at/above librosa, but are not "100% accurate" (key
  exact ≈ 42% on a deliberately hard EDM set).
- "Verified Librosa parity (MSE < 0.00018)" — predates the autocorrelate/superflux fixes,
  so any prior parity was against broken DSP; not currently re-verified.

### Remaining (scoped for a dedicated effort)
- **CQTEngine rewrite (attempted, still not usable)**: fixed three real bugs — the IFFT now
  uses a full complex FFT (`vDSP_fft_zip`) instead of the real packed FFT, the kernels use
  the effective post-decimation sample rate, and each kernel is L1-normalized. Output chroma
  is now *structured* but still bass-dominated and low-contrast, so key accuracy through CQT
  stays near random. Remaining suspects: the 2-tap decimation aliasing the heavily-decimated
  low octaves, and correlation-output indexing. It needs a methodical reimplementation
  against librosa's `cqt`, not more incremental patching. The high-res STFT chroma already
  reaches librosa-level key without it, so the CQT is not on the critical path.
- **Instrument classifier**: the 6-class heuristic is unvalidated and misclassifies
  (trumpet → "Vocals/Chorus"); needs a rework + ground-truth tests.
- **Ground-truth tests** for chord/vertical, pitch (YIN), and structure-segment quality.

---

## 📐 Phase 7: Axis A — Measurement-Engine Standard Validation (2026-06-15)
**Focus**: making the "measurement" layer genuinely certifiable.

### Why this phase exists (the strategic rationale)
After tempo/key reached librosa parity we had to decide what "more accurate than librosa"
actually *means* for this library, because the answer dictates where to spend effort. We
separated two categories that had been conflated:

- **Measurement** (loudness, true-peak, LRA, bit-depth, THD+N, IMD, ITU-R 468, SNR): there is
  one correct, physical/standard answer. "More accurate" is **objective and falsifiable** —
  anyone can run a reference meter and check. librosa isn't even a measurement instrument here.
- **Estimation** (tempo, key, instrument, genre): no single ground truth; accuracy is
  statistical and dataset-relative; it can **never be 100%**.

The decision: the brand's "accuracy" claim must live in the *measurement* engines and be
aggressive there; estimation is positioned honestly as "best-effort, scoped," labelled
*estimate* not *measurement*. Mixing them is the real risk — a 70% instrument estimator would
poison trust in a ±0.08 LU loudness meter if both wear one "accuracy" badge.

A second, deeper reason makes measurement-first not a preference but a **dependency order**:
the user's actual goal is "analyse the file very well, then estimate instrument and genre from
that analysis." Measurement is the *feature foundation*; it sets the estimation ceiling
(garbage features → garbage estimation). So the measurement layer must be verified before any
estimator is built on it. This phase proved the point twice over — the STFT and MFCC bugs
below would have silently capped the instrument classifier. See `Tests/AES17ValidationTests`
and `Tests/ParityDumpTests`.

Audited each standard claim against signals with a *known* answer (as we did for loudness):

- **AES17 THD+N** — was ~50× wrong (reported a true 1% distortion as 0.02%): it returned a
  power ratio instead of an RMS ratio (missing √) and a wide IIR notch leaked ~1% of the
  fundamental. Rebuilt as a Blackman-Harris-windowed FFT (fundamental excluded by a guard
  band, residual √-ratio). Now 1%→1.00%, 10%→9.95%, pure→0.01%.
- **SMPTE/DIN IMD** — was unrelated to intermodulation (it measured the 60 Hz tone's energy ×
  0.1). Rebuilt to measure the actual sideband structure (7000 ± k·60) vs the carrier. Now
  5%→5.00%, 10%→10.00%.
- **ITU-R 468 weighting** — hardcoded approximate biquads under-responded ~6 dB at the 6.3 kHz
  peak (read +6.4 dB vs the standard +12.2 dB). Replaced with the exact analytic 468 response
  R(f) applied in the frequency domain. Now 2 kHz +5.63 dB, 6.3 kHz +12.22 dB (±0.03 dB).
- **BS.1770 true-peak** — already correct: an 8× oversampled 511-tap Kaiser-sinc recovers a
  0 dBFS inter-sample peak from a −3 dBFS sample peak (measured +0.09 dB). Validated.

Three of the four "measurement" claims were materially wrong before this audit — exactly the
kind of fake number the brand cannot afford.

### The STFT was half-resolution (the biggest find)
Foundational DSP parity (#5) against librosa exposed a severe bug: `STFTEngine` used vDSP's
packed real FFT (`vDSP_fft_zrip`) with a stride-1 `ctoz`, which placed every frequency at
**half its true bin** (index k held bin 2k, dropping the odd bins). The entire frequency axis
was 2× compressed. It went unnoticed because chroma→key is octave-invariant and onset→tempo is
relative — but every *absolute-frequency* feature (spectral centroid, rolloff, mel, MFCC) was
wrong, i.e. the feature foundation for the estimation layer. Replaced with a full complex FFT
(`vDSP_fft_zip`, real signal + imag 0): bin k → index k. The STFT now matches librosa to
**machine precision** (correlation 1.00000, best-fit scale 1.0000, 0.000% residual on the mean
spectrum and on individual frames). 8/8 ground truth still passes, and — fixing the foundation
*improved* key from 38.8%/51.9% → **45.0%/56.5%** (now beating librosa's 41.2%/51.5%), vindicating
the measurement-first architecture. Validated by `Tests/ParityDumpTests` + `/tmp/parity_compare.py`.

### Mel exact, MFCC was missing its log
Extending the same harness down the feature chain: the **mel** spectrogram (128-band, Slaney,
power=2) matches librosa to machine precision (corr 1.00000, 0.000% residual). **MFCC** did
*not* — correlation −0.21 — because the pipeline DCT'd the *linear* power mel; an MFCC is the
DCT of the *log* mel. Adding `power_to_db` before the DCT brings it to corr 0.99 (the residual
14% is just the DCT-II ortho normalization convention, irrelevant since the classifier trains
on our own consistent features). This mattered: MFCC is the instrument classifier's primary
feature, and it was uncorrelated with a real MFCC. With STFT, mel and MFCC now correct and the
loudness/THD+N/IMD/468/true-peak engines validated, **Axis A (the measurement/feature
foundation) is complete** — the estimation layer can now be built on clean, verified features.

### Verification checkpoint (gate to the estimation layer)
Re-ran the full foundation suite to confirm we may proceed: library builds clean; loudness
18/18 (EBU SQAM vs ffmpeg); THD+N 3/3, IMD 3/3, ITU-468 2/2, true-peak 3/3, SIR 4/4; STFT and
mel librosa-exact (corr 1.00000, 0% residual), MFCC corr 0.99; synthetic ground truth 8/8.
**Honest scope:** "verified" means high-precision agreement with reference implementations on
the *tested* scenarios, not exhaustive coverage of every channel/sample-rate/edge case — and
it applies to the **measurement** engines, which are deterministic, explainable and standards-
referenced (usable for engineering/analytical forensic work, *not* claimed court-admissible/
certified). Estimation (tempo/key) is librosa-level, not 100% — and is not the foundation the
instrument/genre layer depends on. Gate satisfied → estimation layer may begin.

---

## Phase 8 — The reporting layer rebuilt as *data*, not a marketing document

Before building the estimation (instrument/genre) layer, we audited the output side and found
the report — not the DSP — was the weakest part of the library. Two classes of problem:

**1. It produced a document, not data.** `analyze()` returned `(analysis, reportText, mdPath)`
and, as a side effect, *wrote two files to a hardcoded `/Users/trgysvc/Documents/AI Works`
path*. For any other user that directory doesn't exist, so the call threw on the file write —
the library was literally unshippable to a second machine. A library must return data and let
the caller decide whether/where to persist it.

**2. The report text fabricated verdicts.** The markdown template hardcoded claims regardless
of the actual signal: `✅ AUTHENTIC`, `100% Data Integrity Guaranteed`, `Verified Compliance |
100% Scientific Baseline`, `M4 Silicon GPU | ✅ ACTIVE` (printed even on CPU fallback), `26
Engines Active`, and a `[FINAL AUDIT VERDICT]`. This directly contradicts the
measurement-vs-estimation honesty the whole project is built on. A second, *unused* reporter
(`MusicDNAReporter`, 470 lines) sat dead in the tree — and was ironically the more honest one.

### What we built: `AudioReport`

The product is now a single typed value, `AudioReport` (`Sources/.../Report/`), with the
measurement/estimation split encoded in the type system:

- **`Measured<T>`** — `value` + `unit` + `standard` + `validated`. The certifiable layer
  (loudness/EBU R128, true peak/BS.1770, THD+N/AES17, IMD/SMPTE, noise/468, bit depth, spectral
  descriptors validated for librosa parity). A consumer can branch on `.validated` /
  `.standard` instead of trusting a badge.
- **`Estimated<T>`** — `value` + `confidence` + `method` + ranked `alternatives`. The
  statistical layer (tempo, key, time signature, structure, instruments, musicology). Never an
  "AUTHENTIC" stamp; always a confidence the consumer thresholds itself.
- **`features`** — heavy low-level series (chromagram, MFCC, spectrogram). Always in memory;
  optionally excluded from serialization via `jsonData(includingFeatures:)` for a lean export.

**Why this shape.** The report has two audiences: humans (who want a rendered document) and
*consuming software* (which wants typed data it can integrate). We made the data canonical and
every document just a *rendering* of it. `analyze()` now returns `AudioReport` and **writes no
files**. Transport is Codable-first: `report.jsonData()` (universal — any language) and
`report.plistData()` (Apple-native, compact). `MarkdownRenderer.render(report)` is an
*optional* pure reference renderer — the caller can ignore it and render however it likes. The
validated DSP pipeline is untouched: engines still produce the internal `MusicDNAAnalysis`
aggregate; a single mapper (`AudioReport(from:context:)`) lifts it into the public schema, so
none of the Axis-A validation work was disturbed. `schemaVersion` (1.0.0) lets the upcoming
instrument layer grow the schema additively rather than breaking consumers.

Removed: the hardcoded output path, all fabricated badges, and the dead `MusicDNAReporter`.

### Forensic fix: entropy is not upsampling

Inspecting real output surfaced an engine bug the old report had been hiding behind its fake
"AUTHENTIC" stamp. A genuine 16-bit SQAM recording was flagged **"Upsampled (fake hi-res):
yes"**. Root cause (`DNAReportBuilder`): `isUpsampled` was computed as `meanEntropy < 0.6` —
keyed purely on Shannon entropy, ignoring bit depth entirely. A solo instrument legitimately
has low entropy at full resolution, so this false-positives on exactly the clean material we
validate against. (The same threshold was even *documented* as a feature: "if entropy < 0.6,
trigger FRAUD alert.")

Fixed to the correct forensic definition: **fake hi-res = the container declares more bits than
the signal actually uses.** We now compare the declared header depth (`sourceBitDepth`) against
the *measured* effective depth (`measuredEffectiveBits`, the minimum quantization step across
non-silent chunks) and flag upsampling only when `sourceBitDepth > measuredEffectiveBits`. The
report's `effectiveBits` now shows the measured value (not an echo of the header), so a 24-bit
container carrying real 16-bit data reads `source 24-bit / effective 16-bit / upsampled: yes`,
while the genuine 16-bit file correctly reads `upsampled: no`.

### Documentation reckoning

The `docs/` set had drifted badly behind the code: it still described the old `.dna.md` report
with a "hidden JSON" `MusicDNAAnalysis` dump, a "26-engine checklist", `report.reportPath`
file-writing, the now-removed entropy-fraud logic, and capabilities we don't have (ANE
instrument prediction, a "neural" InstrumentEngine — the instrument layer isn't built yet).
Rewrote the report spec, integration, forensics, validation and engine-catalog docs against the
real code; corrected the project-structure tree (the documented `Engines/`/`Forensic/`/`DSP/`
folders never existed — engines live in `Feature/`); and moved project-level manuals into
`docs/`.

**Status:** `swift build` and `swift build --build-tests` green; sample report renders cleanly
with measurements tagged `validated` + standard and estimations tagged with confidence + method;
no files written by the library. **Gate to the instrument/genre layer is now genuinely clean —
the foundation *and* its reporting are honest.**

---

## Phase 9 — Report-mapping fidelity & live progress (2026-06-18, v8.2.1)
**Focus**: three defects found by reading a *real* full-length report end-to-end, not a unit
fixture. The DSP engines were correct; the bugs lived in the `MusicDNAAnalysis → AudioReport`
mapping and in one hardcoded assembly field — exactly the seam Phase 8 introduced. The trigger
was analysing a single 45:59 Rubén González jazz FLAC (`introducing... Rubén González`) and
inspecting every surfaced field.

### The three findings (file + line, with root cause)
- **Time-signature confidence = 383% (`AudioReportMapping.swift`).** The mapping assigned
  `Estimated(timeSignature, confidence: Double(rhythm.beatConsistency))`. `beatConsistency` is a
  beat-interval *standard deviation* in `[0, ∞)` where *lower* = steadier (see
  `DNAReportBuilder` line ~620: `< 0.05 ? "Locked/Stable" : "Organic/Varied"`), so it is both
  **unbounded** and **inverted** relative to a confidence — and `Estimated.confidence` does no
  clamping of its own. A jazz album's natural rubato pushed the deviation to ~3.83 → "383%".
  Fixed to `max(0, min(1, 1 - beatConsistency))`: steady meter → high confidence, erratic → low.
  The album now reads `Complex / Poly-meter @ 0%`, which is the honest answer for a 46-minute
  aggregate.
- **THD+N / IMD = `NaN`, which is unserializable (`AudioScienceEngine` + `DNAReportBuilder`).**
  `measureTHDPlusN` / `measureSMPTEIMD` both gate on `detectTestTone` (a pure 997 Hz / 7 kHz
  stimulus) and return `Float.nan` when absent — correct for *lab* measurements, but real music
  never carries the tone, so every fragment was `NaN`. The aggregate (`science` builder) then
  propagated `Float.nan`. Two consequences: `NaN` is **invalid JSON**, so `report.jsonData()`
  could throw / round-trip badly; and the mapping stamped these `validated: true` regardless.
  Fixed: the aggregate returns `0` when no tone is present, and the mapping sets
  `validated: a.science.thdPlusN > 0` (resp. IMD) — "not measured on this material," not a fake
  certified `0%`. The lab-tone path (synthetic AES17/SMPTE fixtures from Phase 7) is unchanged
  and still reports real values with `validated: true`.
- **`waveformPeaks` always empty (`DNAReportBuilder`).** Assembly hardcoded
  `waveformPeaks: []`; the envelope was never computed even though the per-chunk mono samples
  were right there. Now accumulated in the chunk loop (`vDSP_maxmgv` over 64 buckets/chunk,
  magnitudes in `[0,1]`) and threaded into `assembleFinalDNA` as a parameter.

### Verified on the source file (release binary, full feature set)
A throwaway consumer (`Examples/CLIExample`) ran the whole 26-engine pipeline on the 2759.9 s
FLAC and printed the previously-broken fields:

| Field | Before | After |
| :-- | :-- | :-- |
| Time-sig confidence | `383%` | `0%` (clamped, inverted) |
| THD+N / IMD | `NaN` (`isNaN=true`) | `0.0000%`, `validated=false`, `isNaN=false` |
| `waveformPeaks` | `0` points | `4030` points, max `0.978` |
| JSON / plist export | could break on `NaN` | OK (730 KB JSON / 1.05 MB plist) |

(For reference, the run's estimations were sane: BPM 123 @ 98%, key C @ 25% — a reasonable
whole-album key confidence.)

### Live progress is the consumer's to render
The public `analyze(url:features:progress:)` already streams `(percent, message, detail)` to the
caller; the library does **not** print. The CLI example now wires that callback to a live,
single-line `stderr` progress bar and takes the audio path as an argument. It also persists the
report via `report.jsonData()` / `plistData()` — reinforcing the Phase-8 contract: **the library
returns `Data`; writing files is the app's job.** No library target performs report file I/O
(verified by grep across `Sources/`; the only on-disk writer is `IntelligenceCache`, an internal
fingerprinted cache, not the report).

**Status:** `swift build` green; all three fields validated against a real 46-minute album; no
new library file I/O. Mapping seam hardened — the foundation *and* its reporting remain honest.

---

## 🎼 Phase 10 — CQTEngine rewrite, dead-code removal, toolchain upgrade (2026-08-27)

### Removed: `AudioIntelligenceForensic`
Dead module (`public struct ForensicSpecialist { public init() {} }`, never referenced by
`Package.swift`'s target list or any call site). The real, live forensic logic
(`ForensicEngine.analyze` in `AudioIntelligenceCore/Feature/`) was already fully wired into
`DNAReportBuilder`/`InfinityEngine` — there was nothing to "connect," so the module was deleted
outright rather than integrated. Verified: `swift build` clean before and after.

### Toolchain & dependency upgrade
- `.swift-version` was pinned to `6.0`, a version never actually installed (`swiftly` failed
  outright on any command) — corrected to `6.3.3`, the real installed/latest release.
- `Package.swift`: `swift-tools-version` `6.1.0` → `6.3`.
- `swift package update`: swift-atomics 1.3.0 → 1.3.1, swift-argument-parser 1.7.1 → 1.8.2,
  swift-docc-plugin unchanged at 1.5.0 (already latest). Full suite green after the bump.

### CQTEngine: four real bugs fixed, with sourcing
Researched Apple's official Accelerate docs first (`vDSP_desamp`'s contract, and Apple's own
"Resampling a Signal with Decimation" tutorial — which uses the *same* naive 2-tap filter this
codebase had), then the recursive-decimation CQT literature (Brown 1991; Schörkhuber & Klapuri
2010 — already this engine's own cited references) for the parts Apple's docs don't cover.
1. **Aliasing** — the 2-tap `[0.5, 0.5]` decimation filter replaced with a 63-tap
   Blackman-windowed sinc low-pass (`vDSP_blkman_window`; Accelerate has no Kaiser window, this
   is the best-attenuation window it exposes), cut at the post-decimation Nyquist.
2. **Missing energy rescaling** — recursive-decimation CQT requires decimated-signal energy to
   be rescaled to match the original after every downsampling step, or approximation error
   compounds exponentially going down the octaves. This was entirely absent; added as an
   RMS-based rescale after each `decimateByTwo`.
3. **Octave time-misalignment** — every octave used the same fixed `hopLength` in samples
   despite each lower octave's sample rate being halved, so real-world time between frames
   doubled per octave and octaves drifted out of alignment (and produced different frame
   counts per octave). Fixed: hop now shrinks by the same decimation factor as the signal, and
   all octaves share one common frame count.
4. **Note-order bug (caught empirically, not from docs)** — `transform()` assembled octaves
   highest-first, then called `.reversed()` on the *flattened* 84-element array to get Low→High
   order. That reverses individual bins, not octave blocks — within every single octave the 12
   notes came out in descending pitch order. Caught by writing ground-truth sine-tone tests
   (`testCQTResolvesMidRangeTone` / `testCQTResolvesLowOctaveTone` in `DSPGroundTruthTests.swift`
   — a 440 Hz and a 40 Hz tone, the latter forcing the full 6-level decimation chain) before
   this fix landed: both tests initially failed with the peak bin off by a non-constant amount
   (−7 and +5), which is what exposed the block-vs-element reversal bug. Fixed by keeping
   octaves as blocks and reversing only block order.

### Independent numeric cross-check (not just internal ground truth)
Added `ParityDumpTests.testDumpCQTForParity`, dumping a two-tone (440 Hz + 1318.51 Hz) signal
and this engine's raw output as raw float32 (matching the existing `ParityDumpTests` convention),
then an independent reference CQT implementation (script kept outside the repo, not part of the
build) ran on the identical samples. Result: identical output shape (84×87 both sides), identical
top-3 dominant bins (`[45, 64, 46]` both sides — the correct bins for both tones, plus one
shared spectral-leakage neighbor), 0.9471 Pearson correlation of the mean per-bin profile.
Absolute magnitude scale differs (different normalization convention between the two
implementations), but pitch location and relative shape match.

**Status:** `swift build` green; full `swift test` green (exit 0, EBU/AES/tempo/HPSS suites all
pass, no regressions). CQTEngine's own doc comment updated to describe all four fixes and the
independent cross-check; it still has no downstream consumer (key/tonal analysis still uses the
high-res STFT chromagram) but is now validated as a standalone engine.

### InstrumentEngine — investigated, NOT yet fixed
Following the README's own "Instrument / chord / pitch / structure quality — ❌ not yet
validated" validation-status line, `InstrumentEngine.swift` (the 6-class heuristic instrument
classifier) was reviewed in
detail. Found, with real measurements, not yet corrected:
- **Dead branch**: `Fingerprint.label` for the piano profile is `"Piano/Keyboard"`, but the
  masking-correction logic compares `profile.label == "Piano"` (two call sites) — this string
  never matches, so the "relaxed threshold in percussion-heavy mixes" logic has never once
  executed.
- **Real baseline accuracy, measured against EBU SQAM** (`InstrumentBaselineTests`, 6 solo
  reference recordings — trumpet, horn, harp, vocal quartet, speech, glockenspiel): two
  back-to-back runs of the identical unmodified code gave **primary-label accuracy of 33%
  (2/6) and then 0% (0/6)** — the classifier is not just inaccurate, it is **non-deterministic**
  run-to-run on identical input. Top-2 accuracy also varied (83% → 50%). Root cause not yet
  isolated; likely tie-breaking sensitivity (many predictions land on identical coarse 60%/40%
  scores) combined with tiny upstream floating-point nondeterminism in the parallel
  Group A/B/C engine pipeline shifting a hard threshold boundary between runs.
- Test data (GiantSteps Key+Tempo 822 MB, OpenMIC-2018 2.8 GB, SQAM) fetched into
  `/Users/trgysvc/Developer/audiointelligence_tests/` for further validation work on this and
  the other unvalidated estimation engines (chord/key-quality, structure).

No code changes were made to `InstrumentEngine.swift` yet — this is scoped as its own follow-up.

---

## 🧭 Phase 11 — Critical bug fixes, more real ground truth, and a reliability scorecard (2026-08-28)

### Two critical bugs fixed and verified against real audio (not just synthetic)
- **`WaveletEngine.swift:117-118`** — `vDSP_conv` was called on an unpadded N-length buffer
  when it reads N+P-1 samples, reading past the array's end. Confirmed live (garbage/denormal
  floats, later reproduced at ~1e30 magnitude reverting the fix for a regression test). Fixed
  with tail zero-padding; verified on both a synthetic signal and real SQAM trumpet audio, and
  the regression test was confirmed to actually fail against the pre-fix code before being kept.
- **`RhythmEngine.swift:307`** — `vDSP_meanv` on very short audio (< ~0.25s) computed a
  negative length, and `vDSP_Length` (UInt) traps on a negative `Int` — a crash. Fixed with a
  guard (skip the mean, confidence falls back to 0). Verified with a regression test (n=0,1,5,10,20
  sample onset envelopes) and confirmed no regression on real music: GiantSteps SuperFlux tempo
  came back at Acc1 58.1% / Acc2 69.8% (43 tracks), matching the previously-documented baseline.

### Real test data, properly wired
Fetched five more real datasets into `/Users/trgysvc/Developer/audiointelligence_tests/`
(persistent — outside `/tmp`, which had previously lost content across reboots) and symlinked
each into a `Tests/Resources/*` path: **IRMAS** (3.3GB, 6,718 files, single-predominant-label —
a better fit than OpenMIC for `InstrumentEngine`'s single-label `primaryLabel`), **MDB-stem-synth**
(5GB, 230 stems, f0 known from re-synthesis rather than estimated — the strongest pitch ground
truth available), and **Isophonics**/**McGill Billboard** chord annotations (both audio-less —
copyright; documented as a real, named gap rather than pretending they're usable as-is).
Also fixed a real, previously-silent `.gitignore` bug: every "pattern  # trailing comment" line
in the test-material block (including pre-existing ones) was matched *literally*, comment text
included, so none of those patterns ever actually matched anything — every large dataset was
untracked-but-not-ignored. Rewritten with the comment on its own line above each pattern.

### `Examples/ReliabilityAudit` — a single, repeatable scorecard
A new tool (see `Examples/ReliabilityAudit/README.md`) that runs every engine with a real
ground-truth dataset in one pass — tempo/key (GiantSteps), instrument (IRMAS + OpenMIC-2018,
mapped onto `InstrumentEngine`'s 6 coarse classes), pitch/f0 (MDB-stem-synth, Raw Pitch Accuracy
at 50-cent tolerance) — and reports chord/structure as explicit `not_available` rows (real
reasons: no legally-obtainable audio for the standard chord datasets; SALAMI's audio isn't a
single archive). Output is a printed table, a git-ignored `reliability_report.json` snapshot,
and an append-only `history.jsonl` **tracked in git** as a versioned accuracy-over-time record.

Building this against the library's own public API surface (not `@testable`) surfaced one more
real bug: **`AdvancedSpectralMetrics` (`MusicDNAModels.swift`) had no explicit `public init`** —
Swift only synthesizes a memberwise initializer at a type's own access level, which for a
`public struct` is *internal* unless written explicitly. The type's stored properties are all
`public`, and it's a required parameter of public API (`InstrumentEngine.predict`), but no
module outside `AudioIntelligenceCore` could actually construct one. Added the explicit
`public init`, matching the pattern every other public model in this file needs to avoid the
same silent gap.

**First scorecard** (`RA_TEMPO_LIMIT=10 RA_KEY_LIMIT=10 RA_IRMAS_PER_CLASS=8 RA_OPENMIC_LIMIT=20
RA_PITCH_LIMIT=6` — a quick pass, not the full-dataset "official" run):

| Task | Metric | Value | n | Dataset |
| :-- | :-- | --: | --: | :-- |
| Tempo | MIREX Acc1 / Acc2 | 80.0% / 90.0% | 10 | GiantSteps |
| Key | exact / MIREX-weighted | 20.0% / 47.0% | 10 | GiantSteps |
| Instrument | in acceptable coarse class | 23.9% | 88 | IRMAS |
| Instrument | in acceptable coarse class | 40.0% | 20 | OpenMIC-2018 |
| Pitch/f0 | Raw Pitch Accuracy (<50¢) | 38.8% | 51,689 frames | MDB-stem-synth |
| Chord | — | not_available | — | no legal audio |
| Structure | — | not_available | — | no bulk audio archive |

Key/instrument/pitch numbers here are small-sample (or, for pitch/instrument, first real
measurements at all) — not a claim of final accuracy, a first honest reading. They point at real
follow-up work (`InstrumentEngine`'s accuracy and non-determinism from Phase 10 is now visible
in both IRMAS and OpenMIC numbers independently; pitch/f0 accuracy at 38.8% RPA on real
instrument stems is a new, previously-unmeasured data point for `YINEngine`) — tracked in
`~/Desktop/AudioIntelligence_Yapilacaklar.md`, not fixed in this pass.

### `STFTParityTests` — root-caused: wrong cache cleared, GPU path never actually ran
The two `testM4SiliconMathematicalParity` failures (GPU kernel-execution-count telemetry read
0) traced to a real bug, unrelated to anything else in this phase. `STFTEngine.analyze()` has
its own `STFTMemoryCache.shared` (an internal, in-memory LRU keyed on a sample hash + STFT
params — `nFFT`/`hop`/`window`/`center`/`pad` — with **no notion of which engine instance, or
whether its `metalEngine`, produced the cached result**). The test creates a CPU-only
`cpuEngine`, analyzes the signal (populating this cache), then creates a `gpuEngine` and
analyzes the *same* signal with identical params — which collides on the exact same cache key
and returns the CPU engine's cached result directly, never touching Metal at all. Confirmed with
temporary instrumentation: `magPhaseState`/`windowMagState` (the compiled GPU pipelines) were
both healthy (`true`/`true`), and *none* of the dispatch functions' internal guards fired either
— they were never called. The test's own comment ("Clear cache to ensure fresh GPU execution")
shows the intent was already right; it just cleared `IntelligenceCache.shared` (a separate,
disk-backed cache with its own key space) instead of `STFTMemoryCache.shared`.

Fixed two ways: added `STFTMemoryCache.clear()` (mirroring `IntelligenceCache`'s existing
`clear()`), and the test now calls it before creating `gpuEngine`. Re-ran 4× in isolation — GPU
kernels now genuinely execute and increment their counters every time; real CPU-vs-GPU numeric
parity confirmed, not a self-comparison via cache.

(My earlier note above claiming this test "passed... earlier the same session" was itself an
unverified inference from a success-print appearing in that log — `XCTAssertGreaterThan`
doesn't halt execution on failure, so the print says nothing about whether the assertions
before it passed. Not re-confirmed either way; irrelevant now that the actual mechanism is
found and fixed.)

**Status:** `swift build` green. `ReliabilityAudit` builds and runs end-to-end against real data
across all 5 measurable batteries with zero crashes. Full `swift test`: **42/42 passed, 0
failures** (4517s), including `STFTParityTests` — closing this phase clean.

---

## 🛠 Phase 12 — Nine correctness bugs, all fixed and independently verified (2026-08-28)

A systematic sweep (four parallel deep-dives across the whole `Sources/` tree, each finding
cross-checked against both its definition and every real call site) surfaced 25+ real,
evidence-backed bugs, ranked by severity. This phase closes every item ranked "high" — silent
correctness bugs that fed wrong-but-plausible values into public report fields, several already
marked `validated: true`. Each fix below shipped with at least one new regression test that
either reproduces the original failure on the pre-fix code (reverted and re-run to confirm) or
measures a real, physically-grounded before/after difference — not just a build-passes check.

1. **`ForensicEngine.detectCodecCutoff`** — the floor-detection branch had no `break`, so it
   kept overwriting the reported cutoff at every subsequent quiet bin down to `searchStartBin`,
   reporting whichever bin happened to be quiet *last* rather than the real highest-frequency
   boundary. A naive "break on first match" fix was tried and rejected — it regressed a genuine
   hard cutoff to report near-Nyquist instead, confirmed with a synthetic band-limited signal
   test that failed against that flawed fix. Corrected with a 3-bin confirm-run (ignore isolated
   single-bin dips, only stop at a *sustained* transition back to content). 4 new tests
   (synthetic hard cutoff, full-bandwidth noise, an unrelated mid-spectrum notch that must not
   override the real cutoff, and real SQAM audio) — plus a drive-by fix hoisting `meanMag.max()`
   out of the O(n) loop where it was being recomputed every iteration (O(n²)).

2. **`ScientificFilterBuilder.itu468WeightingCoefficients`** — hardcoded 48kHz-fit biquad
   coefficients, naively *scaled* (not bilinear-transformed) by `48000/sampleRate` for every
   other rate — not a valid way to retune an IIR filter, so 44.1kHz (the most common rate) used
   a mathematically wrong filter. Replaced with a real bilinear transform of the analog ITU-R
   468 prototype (1 zero, 6 poles — the same standard zero/pole/gain values used by reference
   open-source implementations of this standard, cross-referenced against the ITU's own
   published circuit values). Verified against this codebase's own already-correct, independent
   analytic curve (`AudioScienceEngine.itu468Response`, reimplemented separately in the test
   rather than imported, for genuine double-entry verification): <0.1dB match at every sample
   rate through the curve's defining calibration points (100Hz, 1kHz, 6.3kHz peak). Honestly
   documented remaining limitation: like the reference implementations of this exact standard,
   a plain (non-prewarped) bilinear transform loses accuracy approaching Nyquist, more so at
   lower sample rates (~20-25dB at 15kHz for 44.1/48kHz, ~4dB at 96kHz) — not unique to this
   port. Investigated real-world impact: this function's only consumer
   (`measureLoudnessRangeLRA` → `ScienceMetrics.dynamicRangeLRA`) turns out to never be mapped
   to any public `AudioReport` field at all (traced the whole path — dead internal data); the
   README-validated LRA figure comes from a completely separate, unaffected implementation
   (`LoudnessEngine.loudnessRange`). So this fix corrects the public library API itself (any
   external caller of `itu468WeightingCoefficients` directly) without changing any currently
   visible report field. 18/18 EBU + 4/4 AES17 + 4/4 ScientificAuditor tests confirmed no
   regression.

3. **`HistoricalEngine`** — `lufs < -18 && instruments.contains("Piano") || instruments.contains
   ("Strings")` parsed as `(lufs < -18 && Piano) || Strings` (`&&` binds tighter than `||` in
   Swift) — any track whose instrument label merely contained "Strings" was classified
   "Romantic/Classical Era" regardless of loudness. Fixed with parentheses. Extracted the pure
   branching logic into an internal `inferPeriod` static function (same behavior, now testable
   without constructing a full `MusicDNAAnalysis`) and added 3 tests.

4. **`DNAReportBuilder`'s `fullPitchPath`** — `PiptrackResult.pitches` is Hz per frame; the
   raw Hz value was passed straight through as `Int(hz)` into a path both `CounterpointEngine`
   and `MotifEngine` consume as MIDI note numbers (their own code names it `leadMidi`, counts
   "semitones"). A 440Hz A4 was read as MIDI note 440 — 30+ octaves outside any real instrument's
   range — making their interval/semitone math on real music meaningless. Added
   `DSPHelpers.hzToMIDI(_:)` (standard 69+12·log2(f/440), 0 preserved as the existing "no pitch"
   sentinel for silent frames) as a reusable, independently-tested conversion. 3 tests, including
   a real STFT->Piptrack pipeline run on a genuine 440Hz tone confirming it now tracks to MIDI 69.

5. **`ReductionEngine.reduce`** — hardcoded `512.0 / 44100.0` for converting chroma-frame count
   to real-world duration regardless of the file's actual sample rate; any non-44.1kHz file
   (48kHz is extremely common) mapped every segment's start/end time to the wrong chroma frames.
   Now takes `sampleRate`/`hopLength` as parameters. 2 tests: a synthetic chromagram with a hard
   C/G split at a known time boundary, confirmed correctly mapped at both 48kHz and 44.1kHz.

6. **`DNAReportBuilder`'s HPSS aggregation** — `HPSSEngine.analyze` ran on every 45s chunk but
   `if idx == 0 { allHPSS[0] = hpss }` only ever stored the first — the sister bug to
   `StructureEngine`'s already-fixed one in the same function (same "previously idx==0 only"
   comment pattern), just never applied to HPSS. The public `harmonicRatio`/`percussiveRatio`
   report fields (`validated: true`) for any track over 45s silently reflected only its first
   45 seconds. Fixed to `allHPSS[idx] = hpss`. Verified on real audio: EBU SQAM glockenspiel
   (59s, genuinely spans 2 chunks) analyzed in full vs. a 44s-truncated copy written to a real
   WAV file — before the fix these would be identical by construction (only chunk 0 ever used
   either way); measured after the fix: harmonicRatio 0.8312 (full) vs 0.8334 (truncated) — a
   real, non-trivial difference, proving the second chunk is now genuinely included.

7. **`SpectralFeatureEngine.spectralContrast`** — allocated `nBands + 1` result rows (matching
   `bandEdges`'s legitimate need for nBands+1 *edges*), but the fill loop only ever wrote
   `b in 0..<nBands` — the extra row was permanently zero and fed a spurious always-0 "7th band"
   into every downstream mean. Fixed the allocation to `nBands`. Test: a broadband synthetic
   signal now returns exactly `nBands` rows, every one with real (non-zero) contrast.

8. **`SpectralZoneEngine.analyze`** — each of the 4 frequency zones computed its own bin range
   independently (`floor` for its start, `ceil` for its end), so the bin(s) straddling a shared
   boundary between adjacent zones (e.g. ~250Hz between Sub/Bass and Mid/Body) were counted in
   BOTH zones, double-counting that energy in `dominanceMap`. Rewritten around one shared list of
   boundary bins with half-open `[start, end)` ranges per zone, so no bin is ever double-counted.
   Verified at the exact integer-edge case (binFreq tuned to exactly 5Hz so 250Hz lands exactly
   on bin 50): a signal with all its energy in that single boundary bin now attributes 100% to
   one zone (measured: Sub/Bass 0.0%, Mid/Body 100.0%) instead of splitting ~50/50 across both.

9. **`STFTEngine.analyze`'s cache key** — hashed only the first 2000 + last 2000 samples (+
   sample count) for signals over 4000 samples, ignoring the middle entirely. Two different
   signals sharing the same head/tail but differing in the middle (plausible in a chunked
   pipeline with shared lead-in/fade padding) would collide on the same `STFTMemoryCache` key,
   and the second call would silently return the first's wrong result. Fixed to hash the full
   signal (SHA256 is hardware-accelerated on Apple platforms; negligible next to the STFT/HPSS
   work this cache protects). Test: two 20,000-sample signals with identical head/tail but a
   substantially different middle (silence vs. a loud 2kHz tone) now produce genuinely different
   spectrograms (measured max magnitude difference: 394.6) instead of a collided, identical result.

All nine were found by the same systematic four-way audit that produced Phase 10/11's fixes —
see `~/Desktop/AudioIntelligence_Yapilacaklar.md` for the full ranked list, including the
remaining "medium" (dead-engine/placeholder) and "low" (dead-code cleanup) items not addressed
in this phase.

### A crash caught by the full suite: fixing item 7 broke a hidden downstream dependency
Running the full `swift test` after all nine fixes turned up a real fatal crash (`Fatal error:
Index out of range`) in `DNAReportBuilderHPSSTests` — not a regression in that test itself, but
in the fixed `SpectralFeatureEngine.spectralContrast` (item 7 above) surfacing a second bug it
had been silently masking. `DNAReportBuilder.swift`'s `finalContrast` aggregation hardcoded
`(0..<7)`, implicitly depending on `spectralContrast`'s old buggy nBands+1=7-length output;
once that was correctly shrunk to nBands=6, `allContrast.map { $0[6] }` read past the end of
every 6-element array. Fixed by deriving the band count from the actual data
(`allContrast.first?.count ?? 0`) instead of a hardcoded literal, and corrected the now-wrong
"7 bands" doc comments on the public `spectralContrast` field (`MusicDNAModels.swift`,
`AudioReport.swift`) to "6 bands". Re-ran `DNAReportBuilderHPSSTests` (the real >45s SQAM
pipeline test) clean after the fix — this is exactly the kind of cross-file coupling a full
suite run (not just per-file `--filter` runs) is needed to catch.

**Status:** `swift build` green throughout. Full `swift test`: **62/62 passed, 0 failures**
(4747s) — clean close for this phase.

---

## 🎛 Phase 13 — Eight more correctness bugs: dead pipeline wiring, hardcoded stand-ins, and a missing weighting filter (2026-08-29)

Continuing the same systematic audit's "medium" severity tier: engines that existed, were fully
implemented, and were even unit-tested in isolation, but were never actually connected to the
real analysis pipeline — so their public report fields silently stayed empty or hardcoded no
matter what audio came in. Each fix below shipped with new regression tests, several run against
real SQAM reference audio through the full `AudioIntelligence().analyzeRawAggregate()` path.

1. **`ViterbiEngine` was never wired in** — `DNAReportBuilder` always passed `allViterbi: []` to
   `assembleFinalDNA`, so the public `ViterbiMetrics.path` field was always empty, despite the
   engine's own doc comment describing exactly this use ("pitch path stabilization"). Added
   `ViterbiEngine.smoothPitchPath(f0Series:minMIDI:maxMIDI:)`: a Gaussian-emission HMM over a
   73-state MIDI-note space (24–96) plus a silence state, decoded with the engine's existing
   Viterbi implementation. `DNAReportBuilder` now concatenates every chunk's raw YIN f0 series and
   smooths it before assembly. 4 unit tests (isolated single-frame octave-jump glitches are
   corrected while genuine sustained pitch changes are still tracked; NaN/silent frames map to the
   existing 0 sentinel) plus a real-pipeline test on SQAM `trpt21_2.wav` confirming
   `report.viterbi.path` is now populated with valid MIDI numbers on real audio.

2. **`TempogramEngine.computeACT` was never called** — `cyclicTempoMap` was always a literal `[]`.
   Wired up using the already-concatenated track-wide onset envelope (`fullOnsetEnv`), averaging
   each lag bin's autocorrelation row into a single track-wide tempo profile. (`cyclicTempoMap`
   is computed in the caller's scope, not `assembleFinalDNA`'s, so it's now passed through as an
   explicit new parameter rather than recomputed inside.) Real-pipeline test on SQAM `trpt21_2.wav`
   confirms `report.tempogram.cyclicTempoMap` is now non-empty, with every entry finite and
   non-negative as expected of an L-infinity-normalized autocorrelation profile.

3. **`ModulationEngine.identifyPivotNotes` returned a hardcoded `["Common Tones"]`** for every
   modulation event, ignoring both key arguments entirely. Replaced with a real diatonic
   pitch-class intersection (`ModulationEngine.diatonicPitchClasses(for:)`, built from the
   standard major/natural-minor semitone-offset patterns), so the reported pivot notes are the
   actual notes shared between the two keys. 4 tests: C Major → G Major correctly reports the 6
   shared notes (only F/F# differ, the textbook closely-related-key case); C Major → A Minor
   (relative keys, identical signature) reports all 7 as shared; a tritone-distant key change
   (C Major → F# Major) reports meaningfully fewer shared notes than a closely related one; an
   unparseable key returns an empty list rather than a false claim.

4. **`CadenceEngine.identifyInversion` only recognized a root of "C"** — every one of the other 11
   possible chord roots fell through to a generic, Turkish-language fallback string
   ("Çevrimli Pozisyon (bass Bassa)") left over from the engine's original development, in a
   public English-language report field. Rewritten to parse the real root/quality/bass from
   `TraditionalTheoryEngine.formatSymbol`'s actual output convention and compute the correct
   first/second-inversion label for any of the 12 possible roots and 4 chord qualities
   (major/minor/diminished/augmented). While building tests for this, a second, independent bug
   surfaced in the same code path: `TraditionalTheoryEngine.determineFunction`'s fallback for an
   unparseable key returned the bare string `"Tonic"` instead of the `"Tonic (I)"` format every
   other branch uses — and `CadenceEngine.classify` only ever matches the `"(I)"`-suffixed form,
   so every cadence in a passage whose overall key wasn't confidently detected was silently
   dropped from the report entirely, independent of the inversion-labeling bug. Both fixed
   together. 8 tests: every inversion case across multiple non-C roots and all four chord
   qualities, a non-chord-tone bass note falling through to an English (not Turkish) generic
   label, the fallback-format fix verified directly, and an end-to-end test confirming a genuine
   V–I motion is now classified as a cadence even when the overall key is "Unclassified".

5. **`AuditMetrics` was entirely hardcoded** — identical literal values (`cqtStatus: "OK"`,
   `melSpectrogramResolution: "128x800"`, etc.) on every single analysis regardless of what
   actually ran, and — more consequential than the original audit entry suggested — directly
   reachable from the public `AudioIntelligence.analyzeRawAggregate` API, not just internal
   diagnostics. `engineCoverage` now reflects which engines genuinely produced data for that
   specific analysis; `cqtStatus` honestly reports `"Not Used (no downstream consumer in this
   pipeline)"` rather than a false "OK" (CQTEngine has no real consumer in this pipeline);
   `melSpectrogramResolution` uses the real per-analysis frame count. Verified on real SQAM audio:
   `melSpectrogramResolution` reported `"128x3101"` (matching the actual mel-spectrogram shape for
   that file) instead of the old hardcoded `"128x800"`, with every coverage flag `true` for the
   engines that actually ran.

6. **`MeterEngine.detectPolyrhythm` was a hardcoded `nil`** — honestly marked in-code as a "v7.2
   placeholder," but the public `MeterDNA.polyrhythmRatio` report field gave no indication it was
   never actually computed. Implemented via autocorrelation of the onset envelope: for each
   candidate simple-ratio relationship to the already-detected primary beat period (3:2, 4:3, 5:4
   and their inversions — the common cross-rhythm ratios; trivial multiples like 2:1 are excluded
   as just a subdivision of the same pulse, not a genuine cross-rhythm), search for a local
   autocorrelation peak near the theoretical lag. While writing the test for this, a real bug
   surfaced in the new code before it shipped: `DSPHelpers.autocorrelate` returns raw,
   energy-scaled correlation (not a normalized [0,1] coefficient), and the first version compared
   it directly against a fixed `0.3` threshold — a clean single-pulse signal with no secondary
   periodicity at all falsely triggered a "3:2" detection. Fixed by normalizing the autocorrelation
   array by its zero-lag value before threshold comparison. 2 tests: a synthetic 3-against-2
   cross-rhythm (two combined periodic pulse trains at a 40 : 27-frame ratio) is correctly
   detected as `"3:2"`; a clean single-pulse train with no secondary periodicity reports `nil`,
   not a false positive.

7. **`MeterEngine.detectMeter`'s `2/4` case fell through to `default:`** — mislabeled as
   `"Complex"`/`"Irregular"` meter type instead of `"Simple"`. Added the missing `case 2:` branch.
   The regression test for this needed its own fix during construction: a naive "strong accent on
   every even beat" test pattern ties the g=2 and g=4 grouping scores exactly (every stride-4
   sample is trivially a subset of every stride-2 sample for a uniform pattern), leaving the
   result to Swift's undefined `Dictionary` iteration order — rewritten with an alternating-strength
   accent pattern that unambiguously favors g=2 over g=4.

8. **`ScientificFilterBuilder.aWeightingCoefficients` was an unimplemented stub** — returned a
   literal `[]` regardless of sample rate, silently leaving any caller of A-weighting (an
   industry-standard loudness/environmental-noise weighting curve) completely unfiltered.
   Implemented via the same analog-prototype-plus-bilinear-transform pipeline already verified for
   `itu468WeightingCoefficients` (Phase 12, item 2): 4 zeros at s=0 and 6 real poles — a double
   pole at 20.598997057568145 Hz, a double pole at 12194.21714799801 Hz, and single poles at
   107.65264864304628 Hz and 737.8622307362899 Hz — per IEC 61672-1 / ANSI S1.4-1983. These exact
   values were confirmed against the raw source of the widely cross-referenced open-source
   `waveform-analysis` project's `ABC_weighting.py` (fetched and read as literal source code, not
   an AI-generated summary, after an initial summarized fetch was ambiguously worded about pole
   multiplicity). With no independent, pre-existing A-weighting implementation elsewhere in this
   codebase to cross-check against, the test instead verifies the digital filter against the same
   analog prototype's closed-form magnitude formula, evaluated through a separate, non-Complex-struct
   arithmetic path — still catching the class of bug that matters (a wrong bilinear transform,
   wrong pole pairing across the 3 biquad sections, or a wrong gain distribution). 3 tests: the
   digital filter matches the closed-form analytic curve within tolerance at 44.1/48/96kHz through
   several calibration frequencies (matching well-known published A-weighting reference points,
   e.g. +1.2dB at 2kHz); 1kHz reproduces the standard's 0dB reference point at every sample rate
   from 44.1kHz to 192kHz; low and high frequencies are meaningfully attenuated relative to 1kHz,
   ruling out the old bug's effective behavior (no filtering at all).

All eight were found by the same systematic four-way audit that produced Phases 10–12's fixes —
see `~/Desktop/AudioIntelligence_Yapilacaklar.md` for the full ranked list. This closes every
"medium"-severity item; the remaining "low"-severity items are dead-code/unused-implementation
cleanup candidates with no effect on any current report field, not yet scheduled.

**Status:** `swift build` green throughout every fix. Full `swift test`: **87/87 passed, 0
failures** (4838s) — clean close for this phase.

---

## 🧹 Phase 14 — Low-severity cleanup: two real bugs found along the way, one dead property, one wasted allocation (2026-08-29)

The final tier of the four-way audit's ranked list — items originally filed as "dead code /
cleanup candidates, no effect on any current report field." Investigating each one individually
turned up two genuine correctness bugs that the original triage had understandably missed (both
only manifest on inputs the initial audit didn't exercise), one real API surface honestly
returning wrong-shaped placeholder data, and two items that further investigation showed were
**not** actually dead code — corrected here rather than removed, to avoid deleting real,
intentionally-used logic.

1. **`LoudnessEngine.analyze`'s 6-channel (5.1 surround) energy sum treated every channel with
   weight 1.0** — a real gap the code's own comment already flagged ("For now, we assume 1.0...
   In a pro implementation, we check channel map"). ITU-R BS.1770-4 §2.4 requires the LFE channel
   to be excluded entirely (weight 0) and surround channels (Ls/Rs) weighted 1.41 (+1.5dB) —
   verified against the exact channel-weighting table in the reference `ffmpeg ebur128`
   implementation (`libavfilter/f_ebur128.c`, read from raw source) that this engine's stereo/mono
   accuracy is already validated against. Implemented for the one unambiguous, universally-agreed
   channel order — 6-channel 5.1 (L, R, C, LFE, Ls, Rs, the standard WAV/CoreAudio default) —
   deliberately leaving 7.1 and other layouts at the previous conservative weight of 1.0: channel
   ordering for 7.1 is not consistent across vendors, and no real 7.1 reference material exists in
   this project to verify a specific convention against. Stereo and mono (the only channel counts
   exercised by every existing SQAM/EBU test) are unaffected either way. 3 new synthetic tests
   (no real 5.1 reference audio is available): a loud LFE-channel tone must not change integrated
   loudness at all (proves exclusion); an identical tone on a surround channel must read exactly
   +1.5dB louder than the same tone on a front channel (proves the 1.41 weight); a stereo
   regression guard. All 18/18 existing SQAM loudness tests still pass unchanged.

2. **`NMFEngine.decompose`'s multiplicative-update loop guarded `H` against NaN/Infinity after
   every iteration but had no equivalent guard on `W`** — an asymmetry in what is, by
   construction, a symmetric algorithm (W and H play mirrored roles in NMF's multiplicative update
   rule). Once a NaN/Infinity entered `W` — e.g. from a degenerate input magnitude bin — it had no
   way to self-heal and multiplied itself forward every remaining iteration, permanently poisoning
   that (component, frequency) cell, while the exact same failure in `H` recovers on the very next
   iteration. Added the identical per-element guard to `W`'s update. Regression proven directly:
   a test injecting one NaN magnitude bin into a synthetic STFT matrix was confirmed to fail
   against the pre-fix code (temporarily reverted and re-run) with a genuinely non-finite `W`,
   then confirmed to pass clean after restoring the fix.

3. **`TonalMetrics.keySignature` was a hardcoded, wrong-shaped `[0.1]`** on every single analysis
   — a one-element array despite its own doc comment describing "12 semitone key weights," and
   despite `ModulationEngine` already computing exactly this kind of per-root correlation
   internally (`identifyKey`'s Krumhansl-Kessler matching), just never exposing more than the
   single winning root. Added `ModulationEngine.keyCorrelationProfile(_:)`, reusing the engine's
   own already-tested correlation/rotation logic to return the full 12-root profile (the
   strongest major-or-minor correlation at each root) instead of collapsing it to one winner.
   `DNAReportBuilder` now computes this from the real whole-track mean chromagram — the same
   vector already used for `chromaProfile`, so this also removed a duplicate inline computation.
   2 new tests: a pure C-major-shaped chroma vector correctly peaks at root 0; malformed input
   returns a correctly-shaped (12-element) neutral profile instead of crashing.

4. **`DNAReportBuilder`'s class-level `private var allHPSS` was permanently dead state** — an
   identically-named *local* variable inside the one function that does the real work
   completely shadows it for that function's entire scope (confirmed: the class property is never
   read or written anywhere). Removed.

5. **`MFCCEngine.compute(melSpectrogram:stftEngine:)`'s `stftEngine` parameter was never used**
   inside the function body, and its only call site (`createMFCC`) constructed a fresh, immediately
   discarded `STFTEngine` on every single invocation just to satisfy the signature. Confirmed zero
   external callers of `compute` exist anywhere in the project. Removed the parameter.

**Investigated and found NOT to be dead code — left unchanged, worklist corrected:**
- `NeuralSeparationEngine.generateMasks` is a real protocol requirement (`SeparationModel`) with a
  genuine `CoreMLSeparationModel` conformance, called from `separate()` — already accurately
  documented elsewhere (`docs/Calibration.md`: "interface only, no Core ML model ships").
- `RhythmEngine.onsetStrength(from:)` (static) is not unreferenced: `GoldenDatasetValidationTests`
  deliberately uses it as the "naive spectral-flux baseline" half of a real accuracy comparison
  against the production SuperFlux onset detector. Not dead code; not touched.

**Deliberately left as-is** (public API, unused by the internal pipeline, but correct and not a
bug — removing any of them would be a breaking change to a published package for no correctness
benefit): `FilterbankEngine.createChromaFilterbank`, `WaveformRenderer.swift`,
`SpectrogramRenderer.swift`, and `IntelligenceCache`'s disk-cache `set`/`get` path.

This closes every item on the original four-way audit's ranked list except the four items
tracked separately under "Instrument / chord / pitch / structure quality — not yet validated"
(`InstrumentEngine`'s non-determinism, `TraditionalTheoryEngine`'s empty-`cqtMatrix` bug,
`YINEngine`'s missing test coverage, and `StructureEngine`'s segmentation-accuracy validation),
which predate this audit and remain open.

**Status:** `swift build` green throughout every fix. Full `swift test`: **94/94 passed, 0
failures** (4843s) — clean close for this phase.

---

## 🎯 Phase 15 — Closing the "not yet validated" layer: four real bugs, one root-caused and fixed empirically (2026-08-29)

The four items tracked separately from the main audit under README's own "Instrument / chord /
pitch / structure quality — not yet validated" line (first identified in Phase 10). All four
closed.

1. **`InstrumentEngine` — a dead masking-correction branch, and genuine, empirically-reproduced
   non-determinism.** `profile.label == "Piano"` compared against a fingerprint whose real label
   is `"Piano/Keyboard"` — the comparison never matched, so the percussion-heavy masking
   correction (meant to relax centroid/flatness sensitivity for piano in dense mixes) silently
   never ran for any input. Fixed to compare against the real label.

   The non-determinism was reproduced directly, not just inferred: running the real pipeline
   twice on the same 6 SQAM reference files classified `trpt21_2.wav` as `Brass/Trumpet`
   (correct) once and `Piano/Keyboard` (wrong) once. Root-caused to the classifier's binary
   threshold scoring (`if profile.centroidRange.contains(centroid) { score += 0.4 }`) combined
   with wide, overlapping profile ranges: real audio routinely lands multiple profiles at the
   *exact same* rounded confidence (e.g. 60%), and which one wins the tie depends on whatever
   tiny floating-point noise exists upstream. The Metal `batch_dct` compute kernel (MFCC via
   GPU) was inspected directly and ruled out as that noise source — each thread computes an
   independent, sequential per-coefficient sum with no cross-thread reduction, so it's
   deterministic by construction; the likely source is AVFoundation's audio decode/resample
   path, which Apple doesn't guarantee bit-exact across runs, though the exact origin wasn't
   pinned down further. Rather than chase an elusive upstream noise source, the classifier
   itself was made robust to it: binary thresholds replaced with graded scoring (a Gaussian
   centered on each profile's centroid-range midpoint; a linear taper for flatness), which
   collapses near-ties at their source instead of leaving the classifier fragile to whatever
   magnitude of noise happens to exist upstream. Verified with **3 consecutive full-pipeline
   runs on all 6 real reference files — byte-identical confidence percentages every time**,
   including the closest remaining near-tie (`gspi35_1.wav`, Brass/Trumpet vs. Vocals/Chorus at
   53%/53% in every run). A permanent regression guard
   (`testInstrumentClassification_isDeterministicAcrossRepeatedRuns`) now runs the real pipeline
   twice within one test and asserts identical output. 2 additional unit tests confirm the
   masking correction now actually applies, and that scoring genuinely varies with distance from
   a profile's center rather than clustering at fixed binary sums.

2. **`TraditionalTheoryEngine.analyzeVertical` was always called with a literal empty
   `cqtMatrix`.** `detectBassNote`'s bounds check (`bin < cqtMatrix.count`) is always false
   against an empty array, so the detected bass note silently defaulted to bin 0 (C) on every
   single chord regardless of the real root — any non-C root chord got a spurious "/C" inversion
   suffix (e.g. a real root-position G major misreported as "G/C"). Wired a real per-chunk CQT
   transform into `DNAReportBuilder` (the same `CQTEngine` config already independently verified
   in Phase 10), concatenated the same way as the chromagram, and passed through instead of `[]`.
   Honestly documented residual limitation: CQT's own frame-count formula differs slightly from
   the chroma STFT's (no `center` padding), so the two grids can drift by roughly one frame per
   chunk near chunk boundaries — non-crashing (the existing bounds check already handles it),
   just not frame-perfect. 5 new tests verify root-position and both inversions resolve to the
   correct bass note, a non-chord-tone bass is honestly reported rather than clamped, and the old
   empty-matrix fallback still doesn't crash. (One test-design note: the test chord is C major,
   not G — a sparse 3-note chroma vector is mathematically ambiguous with the rootless
   seventh-chord a third below it by construction of the scoring, e.g. G-B-D scores identically
   as G major or rootless E-minor-7; root 0 has no smaller root that can tie it this way, making
   it the one unambiguous choice for isolating this specific bug.)

3. **`YINEngine` (time-domain pitch/f0 estimation) had zero test coverage.** Added 6 tests:
   known synthetic sine tones (A4=440Hz, C6=1046.5Hz, C1=32.7Hz), digital silence resolving to
   fully unvoiced, a rising pitch glide tracked as a genuine trend rather than aliased octaves,
   and a real SQAM trumpet recording landing in a musically plausible F0 range. One real,
   measured limitation surfaced along the way (documented, not hidden): at the engine's own
   default `frameLength` (2048 samples), a 32.7Hz tone — the engine's own documented `fMin`
   default — completes only ~3 periods per analysis frame, empirically confirmed too few for
   this implementation's trough detection (every frame came back unvoiced). Resolves cleanly
   with a longer `frameLength` (4096, verified); a caller analyzing low-pitched material needs
   that adjustment from the defaults.

4. **`StructureEngine` (structural segmentation) had only a self-similarity-matrix symmetry
   test** — never exercised boundary detection or section labeling at all. A real
   human-annotated dataset (SALAMI) still isn't available (its audio isn't a single downloadable
   archive — separate, unstarted effort). Added the ground-truth check that *is* available
   without external data: a synthetic track built from two objectively distinct, alternating
   sections (different chroma root and different MFCC/timbre profile) with known transition
   points. 3 new tests confirm detected boundaries land within a generous tolerance of the true
   transitions, segments cover the track contiguously with no gaps or overlaps, and a too-short
   input degrades gracefully to an empty result instead of crashing.

**Status:** `swift build` green throughout every fix. Full `swift test`: **111/111 passed, 0
failures** (5114s) — clean close, no regressions anywhere in the suite. This closes the last
open item from the original four-way audit.

---

## 🎼 Phase 16 — InstrumentEngine: from hand-typed guesses to a data-derived, empirically
diagnosed classifier (2026-08-29)

Phase 15 fixed `InstrumentEngine`'s two concrete bugs (a dead-branch string mismatch, and
non-determinism) but left the classifier's real-world *accuracy* untouched — a hand-typed,
6-class heuristic that had never been fit to any real audio. This phase measures that accuracy
at real scale for the first time and works through it via a strict, evidence-gated methodology:
every architectural change is preceded by a targeted measurement against real ground truth, and
no change is generalized from a small or biased sample without a full-dataset check.

### Real baseline, measured for the first time at full scale

Using the existing `Examples/ReliabilityAudit` tool against the complete datasets (not the small
default samples used previously):

| Dataset | Accuracy | Sample |
| :-- | :-- | :-- |
| IRMAS (11-class, single-predominant-instrument) | **25.3%** | 6,705 / 6,718 files |
| OpenMIC-2018 (20-class, multi-label) | **30.3%** | 13,847 / 20,000 clips |

("Accuracy" = primary predicted label falls in that true class's coarse-acceptable set — already
a lenient metric.) This confirmed the classifier was wrong roughly 3 times out of 4 on real,
diverse music, motivating the deeper rework below rather than incremental tuning.

### Determinism → real feature scale → empirically-gated scoring redesign

1. **Non-determinism, confirmed and root-caused.** Running the real pipeline twice on the same 6
   SQAM files reproduced the bug directly (`trpt21_2.wav`: `Brass/Trumpet` once, `Piano/Keyboard`
   once). Traced to binary threshold scoring (`if centroidRange.contains(x) { += 0.4 }`) with
   wide, overlapping profile ranges: real audio constantly lands multiple profiles at the exact
   same rounded confidence, and tiny upstream floating-point noise (the Metal MFCC kernel itself
   was read and ruled out — no cross-thread reduction, deterministic by construction) decides
   which one wins the tie.

2. **Replaced binary thresholds with Gaussian scoring — first pass, centroid only, still
   un-normalized.** Every profile's Gaussian peaked at the same height (0.4) regardless of its
   own spread, so a wide-variance profile paid no penalty for that width. Confusion-matrix
   tooling (`printConfusionMatrix` in `ReliabilityAudit`: raw counts, per-true-class recall,
   per-predicted-label precision) showed `Bass`/`Drums/Percussion` at **0% precision** — every
   single prediction of either was wrong, on the full 1,100-sample IRMAS check.

3. **Added proper Gaussian density normalization (1/σ) to centroid alone, isolated.** A true
   Gaussian's peak height is proportional to 1/σ; the un-normalized version let wide-spread
   classes claim full peak credit *and* wide tolerance for free. IRMAS accuracy on the same
   1,100-file set: **19.9% → 26.1%** (+6.2pp). But the "black hole" pattern didn't disappear —
   it moved to `Piano/Keyboard` and `Vocals/Chorus`, which is exactly what "one feature's
   normalization fixed, others still un-normalized" predicts.

4. **Quantified rather than assumed: MFCC-distance histogram across the full IRMAS set.** A
   biased sample of hand-picked misclassifications suggested `timbreScore` was contributing zero
   information almost everywhere (cross-dataset domain shift between OpenMIC training audio and
   IRMAS evaluation audio). Measured properly across all 6,705 files: only **23%** had zero
   timbre information (min MFCC distance to any prototype ≥ 100) — well under the 70-80%
   threshold that would confirm widespread domain shift. That hypothesis was rejected before any
   code changed on its account.

5. **A trained-vs-untrained-class accuracy split, and a self-caught confound.** IRMAS classes
   whose instrument had no direct OpenMIC training prototype (clarinet, flute — excluded from
   training as ambiguous/multi-coarse-class) scored *higher* (40%) than classes that did have a
   prototype (22%) — the opposite of what "unrepresented classes are unfairly penalized" would
   predict. Caught and reported the real explanation before drawing a conclusion: the untrained
   classes' "acceptable" set spans 2 coarse labels instead of 1, roughly doubling their chance-
   level baseline — the comparison was confounded by set size, not informative on its own.

6. **Per-class training centroid spread vs. measured precision — real but not clean.** At the
   extremes, wide-spread classes (`Drums/Percussion` σ=693.6, `Bass` σ=625.1) were exactly the
   two at 0% precision. But the middle four classes broke a clean single-variable story (`Piano`
   had the *tightest* spread, σ=524.5, yet only 23% precision; `Strings/Synth` had mid-pack
   spread, σ=537.1, yet the *best* precision at 64%) — six data points can't cleanly isolate
   three candidate explanatory variables (spread, training sample size, within-bucket acoustic
   homogeneity) at once, and the investigation didn't force one.

7. **Candidate replacement features for Bass/Drums, measured before any scoring code was
   written.** Centroid position doesn't meaningfully separate either class in real mixed
   recordings. Measured discriminating power (Cohen's d, target class vs. all others, real
   OpenMIC-2018 train-partition audio, n=60/group) for three candidates:
   - Low-band (<250Hz) energy ratio, Bass vs. rest: **d = 1.50** (large effect) — kept.
   - Onset density (onsets/sec), Drums vs. rest: **d = 0.49** (moderate) — a pre-committed
     decision rule ("adopt HPSS outright if it clears d≈1.0+") meant this was superseded rather
     than combined once the alternative below cleared that bar decisively.
   - HPSS percussive-energy-ratio, Drums vs. rest: **d = 1.80** (large effect, stronger than
     Bass's own feature) — adopted as Drums' sole spectral-shape discriminator; the r=0.461
     correlation against onset density became moot once HPSS alone cleared the threshold.

### Architecture: one consistent scoring scheme across all 6 classes, not two ad-hoc additions

Adding the two new features only to `Bass`/`Drums`'s own scoring would make confidence totals
*incomparable* across classes (some profiles summing 4 terms, others 3) — precisely the
mechanism already diagnosed as the "black hole" bug. Both new features are class-independent
per-recording measurements: withholding low-band-energy from `Piano/Keyboard`, for instance,
removes exactly the information needed to correctly place a low-lowband piano recording *away*
from `Bass`. So every one of the 4 spectral-shape features (centroid, flatness, low-band-energy,
percussive-energy) is now computed and Gaussian-scored (shared 1/σ-normalized formula, 0.15
weight each, summing with `timbreScore`'s unchanged 0.4 to the same 1.0 max as before) for every
profile — `Examples/PrototypeTrainer` was extended to fit mean+SD for all four, for all six
classes, from OpenMIC-2018's official training partition (8,173 real clips after excluding
ambiguous/multi-label ones). Distribution skewness was checked before committing to a Gaussian
fit (Piano flatness skew=1.95, Bass flatness skew=1.33 stand out as non-Gaussian; everything else
is within or close to the ±1 "close enough" band) — logged as a known imperfection, not blocking.

`InstrumentEngine.swift`'s `Fingerprint` struct now holds mean+SD for all four features; the old
ad-hoc "percussion-heavy Piano masking correction" (a `centroid *= 0.3` hack and a relaxed-
flatness fallback, both workarounds for not having a real percussive-vs-tonal feature) was
removed, superseded by the real `percussiveScore` term. `predict()`/`predictWithBreakdown()` now
take `lowBandEnergyRatio`/`percussiveEnergyRatio` as explicit parameters; a new
`DSPHelpers.lowBandEnergyRatio` utility was added (shared by production and diagnostic code); the
real production call site (`DNAReportBuilder.swift`) computes both from the STFT/HPSS results
already produced in the same per-chunk loop, at no extra pipeline cost.

### A performance bug found while iterating: 5 seconds/file that shouldn't have been

Diagnostic batch runs became unexpectedly extremely slow (~92 minutes for a 1,100-file
comparison that should take minutes). Investigated rather than just waited out — two real,
independent issues:
1. The new diagnostic tooling (`ReliabilityAudit`, `PrototypeTrainer`) never passed a
   `MetalEngine` into `HPSSEngine`, so every call fell through to the CPU path regardless of
   spectrogram size. Fixed: a shared `MetalEngine` instance wired into every call site (plus the
   `AudioIntelligenceMetal` dependency added to both targets in `Package.swift`).
2. The CPU fallback itself (`HPSSEngine.vDSPMedianFilter`) was genuinely inefficient: a full
   `vDSP_vsort` (O(w log w)) of a freshly-extracted window at *every single output pixel*, even
   though adjacent windows share all but one element. Replaced with an incremental sliding-window
   median — sort once per row/column, then an O(w) remove-plus-binary-search-insert per step as
   the window slides. Verified bit-for-bit identical output against the original brute-force
   algorithm (kept as an independent reference inside the test, not the production code being
   graded against a copy of itself) across random data, duplicate-heavy data (real spectrograms'
   long zero-runs), windows wider than the data, and single-row/single-column inputs
   (`HPSSEngineTests.swift`, 4 new tests).

### New tests

- `InstrumentEngineTests.swift` (4 tests, rewritten from Phase 15's 2): graded centroid scoring
  still varies smoothly with distance from center; `Bass`/`Drums/Percussion` are now correctly
  identified on their own real trained mean feature values — a case that was structurally
  impossible before this phase (0% precision means no input, including each class's own
  prototypical example, could have won).
- `InstrumentBaselineTests.testInstrumentClassification_isDeterministicAcrossRepeatedRuns`
  (Phase 15) remains a live regression guard against the non-determinism bug recurring.
- `HPSSEngineTests.swift` (4 tests): incremental median filter correctness, described above.

### The closing measurement: a structural finding that reframes the whole benchmark

The planned "before vs. after" comparison ran on the full 1,100-file IRMAS set. Blended accuracy
moved from **26.1% (V1, centroid-only Gaussian) to 24.4% (V2, all 4 spatial features)** — a
regression on the number being watched, reported as-is with no reframing at first.

A full 6-bucket confusion matrix (not just the 2 buckets the change targeted) made the real cause
visible: **Bass (Acoustic/Electric) and Drums/Percussion sit at exactly 0% precision on IRMAS,
both before and after the change, and cannot do otherwise.** IRMAS's 11 classes are cello,
clarinet, flute, acoustic guitar, electric guitar, organ, piano, saxophone, trumpet, violin,
voice — verified directly against `irmasToCoarse` in `Examples/ReliabilityAudit/main.swift`: none
of the 11 map to (or represent) Bass or Drums. IRMAS contains zero bass-predominant or
drums-predominant recordings by dataset design. A classifier cannot be credited for a class its
test set structurally never asks it to recognize — the 0%s are a property of the benchmark, not a
classifier defect, and the "did V2 help Bass/Drums" question can never be answered on IRMAS at
all. This also means the IRMAS blended-accuracy number already excludes Bass/Drums-predominant
recordings from its denominator with no code change needed — verified, not assumed, by the same
mapping inspection; there was nothing to recompute.

**Decision:** Bass/Drums remain genuine evaluation targets — they're shipped in the public
`InstrumentMetrics` API and real audio is classified into them regardless of whether IRMAS can
score it — but the benchmark scope is reframed: IRMAS measures the 4 classes it can fairly judge
(Piano/Keyboard, Brass/Trumpet, Vocals/Chorus, Strings/Synth), and Bass/Drums are measured
separately, on a dataset that actually contains them.

### Bass/Drums measured properly: OpenMIC-2018's held-out TEST partition

The right instrument for measuring Bass/Drums is OpenMIC-2018 itself, restricted to its official
`partitions/split01_test.csv` (5,085 keys) — clips never touched by `PrototypeTrainer`. Verified
rather than assumed, before running anything:
1. **Train/test cleanliness**, both at exact-key level and track-ID level (prefix before `_`):
   zero overlap between `split01_train.csv` (14,915 keys) and `split01_test.csv` (5,085 keys),
   confirmed via direct Python set-intersection.
2. **`PrototypeTrainer` scope**: grepped its source — it reads only `split01_train.csv`, never
   the test file.
3. **Multi-label matching rule**, defined before measuring: a test clip counts only if its entire
   positive-label set (relevance ≥ 0.5) maps to a single coarse class — the same eligibility rule
   `PrototypeTrainer` already uses for fitting, so evaluation and training treat ambiguity
   consistently.

`runOpenMICTestPartitionEval` (`Examples/ReliabilityAudit/main.swift`) groups eligible test keys
by true class first, then thins each class's list independently to a per-class cap (100), so
small classes aren't under-sampled relative to large ones. Result, 600 clips evaluated (100/class,
754 skipped as ambiguous/multi-label), explicitly **in-distribution — not comparable to IRMAS's
cross-dataset numbers**:

| Class | Recall | Precision |
|---|---|---|
| Piano/Keyboard | 64/100 (64%) | 64/130 (49%) |
| Bass (Acoustic/Electric) | 48/100 (48%) | 48/78 (62%) |
| Brass/Trumpet | 13/100 (13%) | 13/63 (21%) |
| Vocals/Chorus | 55/100 (55%) | 55/143 (38%) |
| Drums/Percussion | 61/100 (61%) | 61/110 (55%) |
| Strings/Synth | 23/100 (23%) | 23/70 (33%) |

Bass and Drums — stuck at a structurally-mandatory 0% on IRMAS — score well above the 6-class
chance baseline (~16.7%) on the dataset that can actually measure them, consistent with the
isolated Cohen's-d feature validation done earlier in this phase. But the two classes aren't
equally solid, and this is not "Bass now works":

- **Bass is precision-heavy, recall-weak (48% recall / 62% precision) — likely the same
  timbre-suppression mechanism seen in the earlier 10-clip score breakdown.** In that breakdown
  (`bass_breakdown.log`), 5 of 10 real Bass clips lost to another class, and in 4 of those 5
  losses Bass's own `timbreScore` was exactly `0.000` (MFCC too far from Bass's fitted prototype
  to contribute at all) while the winning class's timbre score was solidly positive — the
  spatial features (low-band-energy, percussive-ratio) alone weren't enough to overcome a
  zeroed-out timbre term. 48% recall means real bass clips are still being missed at close to
  this rate at full scale; when Bass does win, it's usually a clean win (62% precision). This is
  a **known, plausible, not-yet-fixed weakness**, not a solved problem — flagged for future work,
  not pursued now.
- **Drums (61%/55%) does not show this asymmetry** and is the phase's cleaner win.

Brass/Trumpet (13% recall) and Strings/Synth (23% recall) are also real remaining weaknesses,
and — unlike Bass/Drums — these ARE visible on IRMAS too. But Strings/Synth specifically shows a
pattern worth flagging before moving on: **its IRMAS (cross-dataset, the harder test) precision
was 64% — the single best score in the V1 confusion matrix (`irmas_confusion_matrix.log`,
115/177) — yet its OpenMIC in-distribution (the easier test) precision is only 33%.** Every other
class scores better in-distribution than cross-dataset, as expected; Strings/Synth is the one
inversion, and it's unlikely to be noise given the gap's size. Two candidate explanations, neither
investigated yet: (1) the `Strings/Synth` coarse bucket blends two acoustically distinct sources
(acoustic strings vs. synthesizers) in different proportions across the two datasets — the same
"bucket internal heterogeneity" concern raised earlier for the wide-SD classes — so "Strings/Synth"
may not be measuring one coherent thing in either dataset; or (2) OpenMIC's negative examples
(what's competing against Strings/Synth for the win) differ enough from IRMAS's that the class's
real discriminating power looks different per dataset. **Not chased now** — but when the 4-middle-
class ceiling (Piano/Brass/Vocals/Strings, currently capped around the 24-26% region) is revisited,
this inversion is very likely part of that ceiling and should be the first thing investigated
rather than rediscovered from scratch.

**A build-system pitfall hit and fixed during this measurement:** `swift build -c release
--target ReliabilityAudit` compiles the target but does **not** link the final executable —
several builds during this step reported "Build of target: ... complete" and exit code 0/1 while
`.build/release/ReliabilityAudit` silently kept the previous binary (or didn't exist at all after
a clean). The fix is `swift build -c release --product ReliabilityAudit`, which both compiles and
links. `swift run` is unaffected (it always builds+links+executes). Worth remembering for any
future non-`swift run` build of an executable target in this package.

**Binary provenance check for every IRMAS number quoted in this phase** (done because the
`--target`-vs-`--product` bug above raises exactly this question): every log backing the
25.3%/26.1%/24.4% sequence was re-inspected for its build header. All three used `swift build`
(no `--target` flag) or ran through `swift run` — every one shows `[.../3] Linking
ReliabilityAudit` followed by `Build of product 'ReliabilityAudit' complete!`, the linked-binary
signature, never the bare `Build of target: ... complete!` the stale-binary bug produces
(`reliability_full_run.log` → 25.3%; `irmas_diagnostic_v1_gaussnorm.log` and
`irmas_confusion_matrix.log` → 26.1%, both n=1,100; `irmas_final_correct.log` → 24.4%, n=1,100).
The `--target`-only bug was introduced for the first time in this session specifically while
building the new `runOpenMICTestPartitionEval` diagnostic, and was caught before that
measurement's real numbers were reported. The V0→V1→V2 IRMAS sequence is unaffected and stands.

**Status:** Phase 16 complete. `swift build` green throughout. Full `swift test` (post-phase
checkpoint, all suites, not just touched ones): **117/117 passed, 0 failures** (755.9s, ~12.6min —
down from Phase 15's ~75-80min for 111 tests, a further confirmation of this phase's HPSS
performance fix; +6 tests vs. Phase 15's 111 is exactly `InstrumentEngineTests` 2→4 and the new
`HPSSEngineTests`' 4). Final numbers, full IRMAS set (1,100 files), same metric throughout
(Bass/Drums structurally excluded from ever scoring, per above): pre-phase baseline 25.3% →
determinism-fix V1 26.1% → 4-feature V2 24.4%. OpenMIC-2018 held-out test partition (Bass/Drums'
fair benchmark): Bass 48%/62% (recall/precision), Drums 61%/55%, full 6-class table above.

---

## 🔑 Phase 17 — Key accuracy: a "regression" that was actually a test/production skew
(2026-08-29)

Post-Phase-16 checkpoint work (full `swift test`, 117/117 green) prompted a routine check of
README's Validation Status claims against the repo's own history. README claims Key (real music,
599 tracks) at 41.9% exact / 57.7% MIREX-weighted, sourced to Phase 6 (2026-06-15). The repo's own
`Examples/ReliabilityAudit/history.jsonl` showed 5 consecutive full-599-track runs today, all
identical at **37.2% exact / 49.9% weighted** — a real, reproducible, ~4.7-7.8pp shortfall against
the README claim, not noise. First hypothesis: a real accuracy regression introduced sometime
between Phase 6 and now (CQTEngine Phase 10, HPSS work, InstrumentEngine Phase 15-16 all touched
shared code in between).

### The actual cause: two measurement tools were silently testing the wrong code path

`DNAReportBuilder.swift` (the real production pipeline, lines ~182-183) computes key/chroma from
a **high-resolution nFFT=8192 STFT** — this is exactly the fix DEVLOG Phase 6 documented as what
raised key from 26.7% to 41.9%/57.7% in the first place. But grepping both places that measure key
accuracy showed neither one uses it:
- `Tests/GoldenDatasetValidationTests.swift`'s `testGiantStepsKeyTempoAccuracy` — the test behind
  every "official" Key number in this project — computed chroma from a **plain nFFT=2048 STFT**.
- `Examples/ReliabilityAudit/main.swift`'s `runKeyTask` — the source of every `history.jsonl` Key
  entry — did the same.

Both were silently measuring the coarser, pre-Phase-6-fix code path this whole time. A third test
in the same file, `testGiantStepsKeyCQT`, already computed BOTH paths side-by-side for comparison
(its own comment on the nFFT=8192 branch literally reads "Production key path... This is what the
pipeline uses") — a 40-track quick sample from it showed the nFFT=8192 path at 42.5%/55.0%, already
much closer to README's claim, confirming the direction of the hypothesis before committing to it.

### Verified, not assumed: full 599-track measurement of the real production path

`GS_LIMIT=0 swift test --filter testGiantStepsKeyCQT` (full 599-track set, no sampling):
```
📊 KEY over 599: STFT exact=223 (37.2%) mirex=49.9%  |  CQT exact=305 (50.9%) mirex=63.3%
```
The `STFT` (nFFT=2048, wrong path) column reproduces `history.jsonl`'s 37.2%/49.9% exactly,
confirming both measurements are internally consistent. The `CQT`-labeled column (nFFT=8192, the
real production path — the label is a holdover from an earlier exploratory version of this test
and is a high-resolution STFT chromagram, not an actual CQT) gives **50.9% exact / 63.3%
MIREX-weighted** — not just reproducing README's 41.9%/57.7% claim, but exceeding it by a wide
margin (+9pp exact, +5.6pp weighted). There was no regression; real production key accuracy is,
and very likely has been for some time, materially better than what README claimed — the
measurement layer just couldn't see it.

### Why this matters more than any single number

Both `testGiantStepsKeyTempoAccuracy` (part of the checkpoint suite that just reported 117/117
green) and `ReliabilityAudit` were validating a code path the library doesn't ship. This means the
validation layer was decoupled from production for key detection specifically — a real key
regression introduced by a future change could pass both tools silently while actually breaking
the shipped pipeline. This is a more serious finding than the number itself, and was worth fixing
regardless of what the full-599 verification showed.

**Fix applied**: both `testGiantStepsKeyTempoAccuracy` (`Tests/GoldenDatasetValidationTests.swift`)
and `ReliabilityAudit`'s `runKeyTask` (`Examples/ReliabilityAudit/main.swift`) now compute key
chroma from a dedicated `nFFT=8192` STFT, matching `DNAReportBuilder.swift` exactly, while tempo/
onset in the same functions keep their original `nFFT=2048` STFT (that path was already correct —
tempo's measured numbers already tracked README closely: 58.1%/69.8% measured vs. 53%/70% claimed).
`swift build` and `swift build --build-tests` both green after the change.

### A recurring tooling problem, now with harder evidence

Re-running the fixed `testGiantStepsKeyTempoAccuracy` on the full 599-track set to cross-check
against `testGiantStepsKeyCQT`'s clean number hit the same print-output-loss problem documented
earlier in Phase 16 — this time on a **single, isolated, filtered test** (no other test class
running concurrently), ruling out cross-suite interleaving as the sole cause. The log ends mid-way
through the per-track table (420 of 599 rows survived) with no trailing `ValidationTable` summary
at all — the process's final, largest buffered print chunk appears to have been dropped before
exit rather than reordered. Recovered a partial cross-check by independently re-implementing the
test's own `keyRelation()` classification against the surviving 420 rows: 55.5% exact / 67.2%
weighted — same direction and magnitude as `testGiantStepsKeyCQT`'s clean 50.9%/63.3% (some
divergence expected/acceptable given this is a partial, non-random-loss subsample, not a full
599 reproduction). The clean, complete `testGiantStepsKeyCQT` number remains the one this phase's
conclusions are based on. Root cause of the print-loss itself is still not conclusively identified;
treat any `swift test` run with a large printed table as unreliable for exact figures and always
prefer `--filter` isolation plus a willingness to re-run if the tail looks truncated.

### The 50.9% vs. 55.5% discrepancy: resolved, and the resolution corrected a wrong assumption

The partial-reconstruction number above (55.5% exact / 67.2% weighted, from the 420 surviving
per-track rows of a truncated log) doesn't match `testGiantStepsKeyCQT`'s clean 50.9%/63.3%. First
hypothesis: `testGiantStepsKeyCQT`'s denominator (`total`) only counts tracks where the file
exists, `parseKey` succeeds, and there are enough samples — while the real
`testGiantStepsKeyTempoAccuracy` counts every loaded track regardless of key-parseability,
scoring unparseable keys as automatic zero-credit misses. This is a real, verified code
difference between the two functions — but checking whether it actually *fires* on this dataset
disproved the hypothesis: `testGiantStepsKeyCQT`'s own log reads "📊 KEY over **599**", and
`Examples/Golden/manifest.json` has exactly 599 entries. `total == 599 == manifest size` means
**zero exclusions occurred** — every track passed every guard. The code-level denominator
difference exists but had no effect on this run. The real explanation is simpler: the 420-row
reconstruction used a *third*, narrower filter (only rows matching a strict regex — both ref-key
and det-key well-formed) that doesn't correspond to either real test's denominator, so it was
never comparable to begin with. **50.9% exact / 63.3% MIREX-weighted, N=599 (the full set, zero
exclusions verified), is the reliable number** — added to README's Key row explicitly so this
doesn't need re-deriving later.

### Print-loss root cause: four targeted reproductions, a real but bounded finding, no full repro

Two candidate environment-level fixes were tried and **both failed** to prevent the real key
test's catastrophic tail loss (missing 150+ per-track rows and the entire closing
`ValidationTable` summary): direct file redirection (`> file`, no pipe) lost the same tail at the
same byte offset as the piped version, and a PTY wrapper (`script -q /dev/null`, which forces
line-buffered stdio) made no difference either — ruling out both "the pipe is the cause" and "it's
a stdio-buffering-mode issue," the two most obvious candidate explanations.

Four synthetic reproductions were then run, each isolating one specific variable, to find what
actually triggers it (all as a temporary `Tests/ZZExitFlushDiagnosticTests.swift`, deleted after):
1. **8 GCD threads × 3,000 lines each, via `swift test`**: 23,999/24,000 survived — one line
   spliced (lost its `T3|2961|` prefix, glued to a later line). The same test as a bare
   `swift <script>.swift` process (no XCTest/SwiftPM relay involved) was 24,000/24,000 clean both
   piped and direct-redirected — proving Swift's `print()`/GCD is not the culprit by itself; the
   corruption is specific to running *through* `swift test`.
2. **600 lines, single big `print()` vs. many small `print()`s, right after real async STFT work
   on 60 real tracks (~33s)**: both variants 100% clean. Too small a scale to trigger anything.
3. **50,000 lines, same shape, same 60-track workload**: many-small-prints stayed 100% clean;
   single-big-print lost exactly one line (index 49,717) to a splice with a concurrent `stderr`
   write (from `2>&1`). Confirms one giant `print()` call is measurably more fragile than many
   small ones — but still nowhere near the real test's scale of loss.
4. **20,000 iterations of `await Task.yield()` immediately followed by `print()`** (testing
   whether Swift concurrency's thread-hopping after each `await` — the real key test's actual
   per-track loop shape — is what matters): 100% clean, no loss, no splice.

**None of the four reproduced the real failure.** This is itself informative, not a dead end: the
loss appears to require all three of (a) genuine audio I/O (not synthetic `Task.yield()` or GCD
busy-work), (b) the real test's duration/volume scale (~8 minutes, 599 tracks — not 60 tracks/33s
or a few seconds of synthetic printing), and (c) a large table printed at the very end, right
before the test function returns and the process tears down. No single one of these three, alone,
reproduced the loss in four separate attempts that each isolated one or two of them. A future
attempt at full root-causing should target *that* combination (a long real-I/O run ending in a
large print), not another synthetic microbenchmark — the four attempts above collectively rule out
"just print volume," "just thread concurrency," and "just process-exit timing" as sufficient
causes in isolation.

**Mitigation, two-tier, documented so the gap doesn't get lost:**
- **Short-term (in effect now)**: cross-check any large printed summary table by independently
  recomputing it from the surviving raw per-track lines (done twice this phase). This has a real
  gap — it only works if the raw lines themselves survive; if a future loss takes the raw data too,
  there's nothing left to recompute from.
- **Permanent fix (not yet done, tracked as its own worklist item)**: write critical summary
  metrics directly to a file via `FileHandle` with an explicit synchronous flush/close before the
  test function returns, instead of relying on captured `stdout` at all. This sidesteps whatever
  `swift test`/XCTest-relay behavior is dropping data, regardless of whether its exact mechanism
  is ever pinned down.

The rare single-line splice found in tests 1 and 3 above (call it bug **(b)**, distinct from the
unreproduced catastrophic loss, call it bug **(a)**) is real but low-impact (1 in 24,000–50,000
lines, tied to `swift test`'s relay layer) — noted here, not worth code changes on its own.

**Status:** Phase 17 complete. Root cause identified and fixed for the actual accuracy question
(measurement tools realigned to the real production key path). README's Key row updated to 50.9%
exact / 63.3% MIREX-weighted, N=599 verified full-set (up from 41.9%/57.7%, itself now understood
to have been a stale, no-longer-representative number from Phase 6, not a target this phase needed
to hit). The librosa 0.11 head-to-head comparison numbers previously in README's Validation Status
table (for both tempo and key) were removed pending independent re-verification — the comparison
script that produced them is not in this repo and could not be reproduced this session. The
print-loss investigation is closed as **honestly partially-diagnosed**: a real, bounded, low-impact
splice bug (b) is understood; the more serious tail-loss bug (a) has a verified trigger *profile*
(real I/O + full scale + end-of-run large print, together) but no pinned-down mechanism, and a
two-tier mitigation (short-term cross-check, permanent fix tracked separately) rather than a
closed fix.

---

> *"Measured, not claimed: AudioIntelligence reports what it can prove."*
