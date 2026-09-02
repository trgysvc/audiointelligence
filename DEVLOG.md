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

### Print-loss bug (a): resolved. The four synthetic attempts above were the wrong axis — real scale, not print shape, was the variable that mattered

The session did not stop at "partially diagnosed." Real-I/O incremental scale reduction (using
`GS_LIMIT` on the actual `testGiantStepsKeyTempoAccuracy`, then temporary natural-order-preserving
truncations of `Examples/Golden/manifest.json` — backed up and restored after every run) tested
150, 300, 450, 550, and 590 real tracks (up to 98.5% of the full 599). **Every single one came back
completely clean** — full summary table, no truncation — across both the `GS_LIMIT>0` reordering
path and the real `GS_LIMIT<=0` path that had always failed at true 599. Only the genuine,
complete, unmodified 599-track manifest ever reproduced the loss.

To find out *where inside* that run things went wrong, a temporary diagnostic (`DIAGMARK
total=<N> elapsed=<seconds>s`, written to `stderr` every 25 tracks) was added to the real full-599
run. Result: **all 23 markers survived, from track 25 to track 575, in perfect linear sequence
(~20.2s per 25 tracks, no slowdown, no anomaly, right to the end of the run)**. This proved two
things at once: the per-track loop itself never loses data, no matter how long it runs or how much
volume accumulates — and there is no resource-exhaustion/memory-pressure buildup happening over
the course of the run. The loss is confined entirely to the last moment: the final
`ValidationTable.printTable()` call and the `📊 Baseline: ...` line, printed immediately before
the test function returns.

With the loss narrowed to that exact spot, two fixes were tried and tested empirically, not
assumed:
1. **`fflush(stdout)` immediately after the final prints** — the obvious first guess. Tested on a
   real full-599 run: **did not work**. The identical failure signature recurred (the last
   per-track row's ID fragment glued mid-line to an XCTest `Test Case ... passed` status message,
   the summary table missing entirely), despite DIAGMARK again proving the loop itself ran clean
   to completion. This ruled out "just needed one more flush call" as the fix.
2. **`setvbuf(stdout, nil, _IONBF, 0)` — fully unbuffered stdout for the whole test function**
   (every `print()` becomes an immediate `write()` syscall, no buffering at all, added at the very
   top of `testGiantStepsKeyTempoAccuracy`) — tested on a real full-599 run: **worked**. Full
   summary table printed cleanly (Key exact 50.92% / MIREX-weighted 63.32%, matching the
   independently-derived 50.9%/63.3% from `testGiantStepsKeyCQT` almost exactly), test suite ended
   with normal, un-corrupted status messages. Re-verified a second time after removing the
   now-redundant `fflush` call and the temporary `DIAGMARK` instrumentation, on the fully
   cleaned-up code: still clean (Key exact 50.92% / weighted 63.32%, 486.2s).

**Why `fflush` alone didn't work but full unbuffering did** is still not 100% pinned to a single
sentence — the empirical result stands regardless: this was a genuine buffering-related race
between the test process's stdout and `swift test`'s XCTest-relay/teardown mechanism, present
*only* on long, real, full-scale runs, and eliminated by preventing any buffered content from
existing at all rather than by flushing it after the fact. The rare splice bug (b) documented
above is unrelated (much smaller scale, different signature) and remains a known, low-impact,
undocumented-root-cause item — not addressed by this fix, not worth chasing further on its own.

**Fix applied**: `import Darwin` + `setvbuf(stdout, nil, _IONBF, 0)` as the first line of
`testGiantStepsKeyTempoAccuracy` in `Tests/GoldenDatasetValidationTests.swift`. `swift build` and
`swift build --build-tests` both green. Not yet applied to `testGiantStepsKeyCQT`,
`testGiantStepsTempoSuperflux`, or `Examples/ReliabilityAudit/main.swift` (all of which print
similarly large summary tables and are plausibly vulnerable to the same bug, just not yet
observed failing) — left as a follow-up decision rather than applied unilaterally everywhere.

**Status:** Phase 17 complete. Both the accuracy question (measurement tools realigned to the real
production key path) and the print-loss bug (a) that complicated verifying it are **genuinely
fixed**, not just documented as a limitation — confirmed empirically on real, full-scale runs, not
assumed. README's Key row updated to 50.9% exact / 63.3% MIREX-weighted, N=599 verified full-set
(up from 41.9%/57.7%, itself now understood to have been a stale, no-longer-representative number
from Phase 6, not a target this phase needed to hit). The librosa 0.11 head-to-head comparison
numbers previously in README's Validation Status table (for both tempo and key) were removed
pending independent re-verification — the comparison script that produced them is not in this
repo and could not be reproduced this session. The rare splice bug (b) remains a known, low-impact,
open item.

---

## 🔬 Phase 18 — Reproducing the STFT/mel librosa-exact claim (2026-08-30)

README's "Foundational DSP (STFT, mel): librosa-exact (corr 1.00000, 0% residual)" claim had been
downgraded to ⚠️ (unverifiable) in Phase 17's README pass: the comparison script,
`/tmp/parity_compare.py`, was documented as "kept outside the repo" and had been lost. Rather than
leave the claim permanently unverifiable, it was reconstructed from first principles and re-run.

`Tests/ParityDumpTests.swift` (already in the repo, untouched) dumps a deterministic 4-second
multi-tone signal (440/1320/3010/6050 Hz, non-harmonic so the comparison isn't a frame-alignment
artifact) plus this library's own STFT-magnitude and mel-spectrogram output for it, as raw float32
files under `/tmp/parity/`. Its doc comments and the actual Swift source (`STFTEngine`,
`MelSpectrogramEngine`, `FilterbankEngine.createMelFilterbank`) pin down every convention needed to
reconstruct a faithful comparison: STFT nFFT=2048/hop=512/Hann window/`center=True`/constant
padding; mel spectrogram computed from the *power* (magnitude²) spectrum through a Slaney-
normalized, `htk=False` filterbank (`fmin=0`, `fmax=sr/2`) — all defaults that match librosa's own
`stft`/`melspectrogram`/`filters.mel` defaults when passed explicitly. One real gotcha caught by
reading the Swift source directly rather than assuming: `MelSpectrogramResult.melData`'s doc
comment claims "nMels × nFrames (Row-Major)" but the actual indexing
(`melData[t * nMels + m]`, `MelSpectrogramEngine.swift`) is frame-major — the doc comment is wrong.
Reshaping the dumped mel data by its stated header order instead of its true data layout would
have silently produced a garbage (near-zero) correlation and a false "doesn't match" result.

New `scripts/parity_compare.py` (tracked in this repo, unlike the multi-GB audio/dataset material —
it's a small script with no bundled data, so keeping it doesn't fight the "ship only source code"
principle and it can't get lost again):
```
swift test --filter ParityDumpTests
/tmp/lrvenv/bin/python scripts/parity_compare.py
```
Result, on librosa 1.0.0 (the environment's current version, not the 0.11 the original claim cited
— the underlying algorithms this compares are stable across that range):
```
STFT  : corr=1.00000  residual=0.0000%
Mel   : corr=1.00000  residual=0.0003%
```
**The original claim is confirmed, not just restored on faith.** README's Foundational DSP row is
back to ✅ with the exact reproduced numbers and a pointer to the script. `swift build` green.

**Status:** Phase 18 complete for the STFT/mel parity claim specifically (open-items list item 1).
The separate, still-open tempo/key librosa 0.11 head-to-head comparison numbers (a different claim,
removed from README in Phase 17, no reconstructed script yet) remain unverified — item, not this
one, in the worklist.

---

## 🧮 Phase 19 — MFCC CPU/GPU DCT scale mismatch: a real bug, found and fixed (2026-08-30)

Open-items list item 2 asked whether the CPU (`vDSP_DCT_Execute`) and GPU (Metal `batch_dct`)
paths of `MFCCEngine.compute()` produce consistent output — never verified. Investigated by
reading both implementations side by side rather than assuming.

**The CPU path** (`MFCCEngine.swift`) applies the standard DCT-II *orthonormal* scale: the DC
term (coefficient 0) gets `sqrt(1/N)`, every other term gets `sqrt(2/N)` — this asymmetry is what
makes an orthonormal DCT-II actually orthonormal, and it's the convention librosa/scipy use.

**The GPU path** (`Sources/AudioIntelligenceMetal/AudioIntelligenceMetal.swift`'s `batch_dct`
kernel) applied `sqrt(2/N)` to *every* output index unconditionally — including index 0. That
makes the GPU's MFCC-0 coefficient `sqrt(2)` (≈41.4%) too large relative to both the CPU path and
librosa's convention. Coefficients 1–19 were unaffected (both paths already used `sqrt(2/N)` for
those).

**Verified empirically**, not just algebraically: a temporary test fed the identical synthetic
log-mel spectrogram (128 mels × 5 frames, deterministic non-flat pattern so a DC-only bug can't
hide behind an all-zero AC baseline) through both `MFCCEngine(metalEngine: nil)` (CPU) and
`MFCCEngine(metalEngine: MetalEngine())` (GPU), and diffed all 100 output coefficients (20 MFCCs ×
5 frames). Before the fix: MFCC-0 differed by the predicted `sqrt(2)` factor. After adding the
same DC-term special case to the Metal kernel: **MFCC-0 matched exactly** (`CPU=-64.48083
GPU=-64.48083, diff=0.0`); the other 19×5=95 coefficients already matched within float32 rounding
noise (max diff ~6.7e-5, max relative diff ~0.0044%) both before and after — confirming the bug
was isolated to the DC term, not a broader kernel issue.

**Fix**: `batch_dct`'s scale is now `(mfcc_idx == 0) ? sqrt(1/N) : sqrt(2/N)`, matching the CPU
path's `dcScale`/`orthoScale` split exactly.

### A real downstream consequence — not silently absorbed

`DNAReportBuilder.swift` always passes a live `MetalEngine`, so production has been running the
GPU path (`nFrames > 1` is the common case) — meaning **every MFCC-0 value this library has ever
produced in a real analysis was ~41% too large** until this fix. MFCC-0 (the log-energy/DC term)
is part of `mfccSubset`, which feeds directly into both `InstrumentEngine.predict()`'s timbre
distance calculation and `StructureEngine.analyze(mfccs:)`'s segmentation input.

At the time this phase was written, this section claimed InstrumentEngine's prototypes were
trained through the same buggy GPU path and would need re-training. **That claim was wrong — see
Phase 24, which found and corrected it before any retraining was actually carried out.** In short:
`Examples/PrototypeTrainer/main.swift` and `Examples/ReliabilityAudit/main.swift` both construct
`MFCCEngine` without passing a `metalEngine` (`MFCCEngine(melEngine:nMFCC:)`), so both the
prototypes and the OpenMIC-held-out accuracy numbers below were computed via the CPU path — which
was correct all along — and were never touched by this bug. Only `DNAReportBuilder.swift` (real
production inference) called the GPU path directly. The numbers as originally measured (Bass
48%/62%, Drums 61%/55%, Piano 64%/49%, Vocals 55%/38%, Strings 23%/33%, Brass 13%/21%) stand;
retraining was not performed because it would not have changed them.

**Status:** Phase 19 complete for the CPU/GPU DCT parity question itself (open-items list item 2).
`swift build`/`swift build --build-tests` green; a full `swift test` checkpoint was run given this
touches a shared low-level engine (`AudioIntelligenceMetal`) — see the run's own log for the
pass/fail count. See Phase 24 for the corrected downstream-consequence analysis and closure.

---

## 🎯 Phase 20 — YINEngine trough detection: a real deviation from canonical YIN, fixed (2026-08-30)

Open-items list item 3 flagged that `YINEngine`'s trough-finding might not fully satisfy canonical
YIN's (de Cheveigné & Kawahara, 2002) step 4: once the cumulative mean normalized difference
function (cmnd) dips below the threshold, the algorithm must keep descending — following the dip
to its true local minimum — not stop at the first sample that happens to be below threshold.

**The bug, precisely**: the old `findPeriod` loop accepted `tau` as soon as `cmnd[tau] < threshold
&& cmnd[tau] < cmnd[tau-1]` — checking only that the value is descending *from the previous
sample*, never checking whether it *keeps* descending *past* that sample. A `tau` still partway
down a dip satisfies this check and gets accepted immediately, well before the true bottom.

**Verified, not just reasoned about**: a hand-built `cmnd` fixture (crosses below threshold=0.1 at
tau=10 while still falling, keeps falling to a true minimum at tau=12, rises at tau=13) exposed the
bug concretely. Before the fix, `findPeriod` returned **11.25** — comparing against the true
minimum (12) at a tight 0.3 tolerance failed outright. The 11.25 wasn't even a deliberate "close
but early" answer — it's an artifact of feeding a non-trough point into the parabolic
sub-sample-interpolation step, which assumes its three input points already bracket a real local
minimum; on a still-descending triple, the same formula produces a number, just not a principled
one. After the fix: **11.9**, tight to the true minimum.

**Fix**: replaced the "descending-from-previous + below-threshold" check with the canonical
two-phase search — find the first `tau` below threshold, then advance `tau` while
`cmnd[tau+1] < cmnd[tau]` (still falling), stopping only once the dip bottoms out. `findPeriod`'s
access level was widened from `private` to `internal` (module-visible only, `@testable`-reachable)
specifically so this could be a direct, deterministic unit test rather than an indirect one
relying on a real audio fixture reproducing this exact cmnd shape by chance.

Regression check: all 6 pre-existing `YINEngineTests` still pass, including the real-SQAM-trumpet
sanity test (mean F0 491.3Hz now vs. 490.4Hz before — a ~0.2% shift, consistent with a small
precision improvement, not a behavior change). The new test
(`testFindPeriod_descendsToTrueLocalMinimum_notFirstBelowThreshold`) is now a permanent 7th test in
`YINEngineTests.swift`.

**Status:** Phase 20 complete (open-items list item 3). `swift build`/`swift build --build-tests`
green; `YINEngineTests` 7/7 green. A full-suite checkpoint was not re-run for this specific change
(smaller, self-contained fix with its own direct regression coverage already green; the last full
checkpoint — Phase 19's DCT fix — was 117/117 minutes earlier) — will batch into the next full
checkpoint per the project's "checkpoint at group completion, not every single fix" convention.

---

## 💥 Phase 21 — YINEngine/PiptrackEngine extreme-parameter crash: real, reproduced, fixed (2026-08-30)

Open-items list flagged that very short `frameLength` (YINEngine) or very few STFT frequency bins
(PiptrackEngine) combined with a high `fMax` could build an inverted `ClosedRange` (lower bound >
upper bound), which traps in Swift. Verified as a genuine crash, not a hypothetical, using the same
technique as earlier phases: apply the fix, then `git stash` it back out to run the exact
reproduction against the pre-fix code, observe the real crash, then restore the fix and re-verify.

**YINEngine** (`analyze(frameLength: 16, ...)`, default high `fMax`): `tauMin` (derived from
`fMax`) ends up larger than `validEnd` (capped by the short frame). Two separate places built this
as a raw `ClosedRange`: `findPeriod`'s first-candidate search (already restructured to a `while`
loop in Phase 20, incidentally already safe) and its "global minimum fallback" loop (still
`tauMin...validEnd`, still vulnerable), plus `computeCMND`'s two `1...maxTau` loops (vulnerable
when a very short frame makes `maxTau` 0). Reproduced: pre-fix, this call trapped with `Swift/
ClosedRange.swift:411: Fatal error: Range requires lowerBound <= upperBound`, signal 5, process
aborted. Fixed: both remaining `ClosedRange` constructions replaced with `stride(from:through:by:)`,
which is empty-safe (zero iterations, no crash) when the bounds would invert — same fix shape
Phase 20 already applied to the first loop.

**PiptrackEngine** (`track(stft:)` on a 2-bin STFT from `nFFT: 2`, default high `fMax`): `binMax`
clamps to 0 (`nFreqs - 2`) while `binStart` (from `fMin`) is already ≥1 — the same inverted-range
shape, in two loops (`max(1, binMin)...binMax`, computed identically twice). Reproduced the same
way: pre-fix, trapped with the identical fatal error; fixed with the same `stride`-based pattern
(and the duplicated `max(1, binMin)` expression consolidated into one `binStart` computed once).

**New permanent regression coverage**: `YINEngineTests.swift` gains an 8th test
(`testShortFrameLength_doesNotCrash_onInvertedTauRange`); `PiptrackEngineTests.swift` is a **new
file** (this engine had zero test coverage before), with a real-440Hz-tone sanity check plus the
crash regression (`testVeryFewFrequencyBins_doesNotCrash_onInvertedBinRange`). Both suites green
(8/8, 2/2) after the fix, confirmed via the pre-fix/post-fix stash-and-compare technique above, not
assumed from reading the code alone.

**Status:** Phase 21 complete (open-items list item, YINEngine/PiptrackEngine crash risk). `swift
build`/`swift build --build-tests` green. No stray temporary files left (git status confirmed
clean of anything but the intended source/test changes).

---

## 🔊 Phase 22 — ISTFT was reconstructing from the wrong FFT format: ~101% error, fixed (2026-08-30)

Open-items list flagged that `STFTEngine.synthesize()` (ISTFT) had never been round-trip tested.
A new `STFTRoundTripTests.swift` (analyze a real multi-tone signal, synthesize it back, measure
relative RMS error against the original in the well-overlapped interior) found a severe, genuine
bug immediately: **~101% relative RMS error** — the reconstructed signal bore essentially no
resemblance to the original, not a subtle numerical drift.

**Root cause**: `analyze()` (the forward transform) uses `vDSP_fft_zip` — the **full-complex** FFT
— specifically because an earlier phase found and fixed a real bug where the previous packed-real
FFT (`vDSP_fft_zrip`) compressed the frequency axis 2×. `synthesize()` (the inverse transform) was
**never updated to match** — it still packed magnitude/phase into the old `zrip`-specific format
(DC in `realp[0]`, Nyquist folded into `imagp[0]`) and called `vDSP_fft_zrip`'s inverse, which
expects an entirely different packed layout than what `analyze()`'s `zip`-based magnitude/phase
data actually represents. A textbook case of a fix applied to one side of a symmetric forward/
inverse pair and never propagated to the other.

**Fix**: rewrote `synthesize()` to match `analyze()`'s convention exactly — reconstruct the full
`nFFT`-length complex spectrum from the `nFreqs = nFFT/2+1` positive-frequency magnitude/phase
bins via Hermitian symmetry (`X[nFFT-f] = conj(X[f])`), run `vDSP_fft_zip`'s inverse on the full
spectrum, then scale by `1/nFFT` (vDSP's unnormalized-FFT convention: a `zip` forward+inverse
round-trip scales by `nFFT`, not the `zrip`-specific `2×nFFT` the old code used).

**Verified**: post-fix, the same round-trip test's interior relative RMS error dropped to
**0.000011%** (machine precision) — from real, ~101% garbage to essentially perfect reconstruction,
consistent with the Hann/75%-overlap window satisfying COLA (constant overlap-add).

### Real-world impact — two production features were silently broken

`synthesize()` has exactly two callers: `ManipulationEngine.timeStretch`/`pitchShift` (the
library's public time-stretch/pitch-shift API — flagged just this session, in the competitor-
research thread, as an already-working librosa-parity feature) and `NeuralSeparationEngine`'s
mask-to-audio reconstruction. **Both have been producing effectively garbage audio output any time
they were actually exercised**, until this fix — this wasn't a latent/theoretical risk, it was a
live, real bug in shipped public API surface with zero prior test coverage to catch it.

New `ManipulationEngineTests.swift` (first coverage this engine has ever had) confirms the fix in
practice, not just via the synthetic round-trip: a real 440Hz tone through `timeStretch(rate: 1.0)`
now comes back as a recognizable ~440Hz tone with real energy (previously would have been
unrecognizable noise), and `timeStretch(rate: 2.0)` produces the correct ~half-length output.
`NeuralSeparationEngine` itself still has zero test coverage — out of scope for this specific fix
(it depends on a CoreML model this library doesn't ship, per existing Calibration.md docs), noted
but not pursued further here.

**Status:** Phase 22 complete (open-items list item, ISTFT round-trip). `swift build`/`swift build
--build-tests` green. A full-suite checkpoint was run given the fix touches `STFTEngine`, a
foundational, widely-shared engine — see the run's own log for the final pass/fail count.

**Full-suite checkpoint result**: 125/125 passed, 0 failures (910.3s, ~15.2min) — no regressions
from the ISTFT rewrite.

---

## 🎭 Phase 23 — NeuralSeparationEngine: first-ever test coverage, end-to-end verified (2026-08-30)

`NeuralSeparationEngine` had zero test coverage and, per Phase 22, its only output path
(`STFTEngine.synthesize()`) had been silently broken (~101% error) until that fix — meaning this
engine's real behavior had never actually been confirmed to work, only assumed safe because it's
"interface only, no model ships" (per existing Calibration.md language, re-verified accurate this
phase: `CoreMLSeparationModel.generateMasks` is still a documented placeholder returning `[:]`).

`SeparationModel` is a public protocol, so a deterministic test-only mock can exercise the real
masking math and the ISTFT reconstruction it depends on without needing a real CoreML model — no
model is bundled with this library, and none is faked as one; the mock only supplies a
already-known spectral mask, the same input `NeuralSeparationEngine.separate()` expects from any
real model.

**Test 1** — a genuine two-tone mix (440Hz + 1500Hz) run through a mask that isolates only the
440Hz frequency band: the reconstructed "vocal" stem's pitch (measured with `YINEngine`, not
assumed) comes back at ~440Hz, not a mix of both tones and not garbage — the first real,
end-to-end confirmation that masking + the now-fixed ISTFT actually perform correct source
separation, not just "the code compiles and doesn't crash."

**Test 2** — a model returning a wrong-sized mask is silently skipped (existing `guard mask.count
== nTotal else { continue }`), confirmed not to crash or produce a garbage stem under that key
name.

**Status:** Phase 23 complete (open-items list item, `NeuralSeparationEngine` coverage).
`swift build`/`swift build --build-tests` green, both new tests green (2/2).

---

## 🔍 Phase 24 — Phase 19's retraining premise was wrong; corrected before acting on it (2026-08-30)

Phase 19 concluded that `InstrumentEngine`'s prototypes (fit by `PrototypeTrainer`) and the
OpenMIC-held-out accuracy numbers (`ReliabilityAudit`) were trained/measured through the buggy GPU
MFCC path and would need re-fitting once the shader was fixed. Before acting on that plan, the
premise was checked against the actual call sites rather than assumed:

- `Examples/PrototypeTrainer/main.swift:153` — `MFCCEngine(melEngine: mel, nMFCC: 20)`, no
  `metalEngine` argument.
- `Examples/ReliabilityAudit/main.swift:119` (`predictInstrument`, the function that produces the
  Bass/Drums/Piano/Vocals/Strings/Brass accuracy numbers) — same signature, no `metalEngine`.
- `MFCCEngine.swift:65` — `metalEngine` absent (`nil`) routes to the CPU `vDSP_DCT_Execute` branch,
  which already applied the correct `dcScale`/`orthoScale` split (confirmed via `git log`/`git
  diff`: this branch was untouched this session, pre-existing and correct).
- `Sources/AudioIntelligenceCore/Util/DNAReportBuilder.swift:243` — the only call site that
  actually used the GPU path, calling `metalEngine.executeBatchDct(...)` directly, bypassing
  `MFCCEngine` entirely.

**Conclusion: the prototypes and the held-out accuracy baseline were never touched by the GPU bug.**
Both were always computed via the CPU path, which was correct throughout. The real inconsistency
Phase 19 fixed was narrower than described: production (`DNAReportBuilder.swift`) vs.
training/measurement (`PrototypeTrainer`/`ReliabilityAudit`) — not "prototypes vs. corrected
pipeline." Retraining `PrototypeTrainer` would have reproduced the same numbers (same CPU code
path, same data) at the cost of reprocessing ~15k OpenMIC clips for nothing. It was not run.

`StructureEngine`'s MFCC input was also checked, not assumed clean by category: it consumes
`mfccSubset` from `DNAReportBuilder.swift:306`, the exact same array produced by the GPU call at
line 243 that feeds `InstrumentEngine` — one source, not a separate path, so the same closure
evidence covers it.

### Closing the real gap: an independent (librosa) ground-truth check, not self-consistency

What Phase 19 actually lacked was proof, against an external reference, that the fixed GPU shader
now produces academically-correct MFCC — self-consistency between two Swift implementations proves
they agree with each other, not that either is *right*. `Tests/ParityDumpTests.swift` already
dumped a GPU-path `swift_mfcc.f32`, unused by `scripts/parity_compare.py`. Added an MFCC section
(scipy `dct(type=2, norm="ortho")`, matching the DCT-II orthonormal convention both the CPU and
now-fixed GPU paths use, computed from an unclipped `power_to_db` to mirror the Swift log step
exactly) and re-ran the full pipeline:

```
MFCC  : corr=1.00000  residual=0.0041%  (DC-term residual=0.0011%)
```

To confirm this number actually reflects the fix (not a script bug), the shader change was
temporarily reverted (`git stash` on `AudioIntelligenceMetal.swift` alone, the same
prove-the-bug-existed technique used in Phases 21/22) and the identical pipeline re-run:

```
MFCC  : corr=0.99368  residual=28.0521%  (DC-term residual=29.2892%)
```

A real, large, measured error pre-fix; ~0 post-fix — against librosa's own convention, not just
against the CPU Swift code. The fix restored immediately after (`git stash pop`), confirmed via
`git diff --stat`, and the dumps regenerated once more against the restored (fixed) code to leave
`/tmp/parity` consistent with the current tree.

### Permanent regression coverage

A librosa cross-check requires a Python venv and isn't part of `swift test`, so it can't be the
standing guard against a future regression. Added `Tests/MFCCGPUParityTests.swift`
(`testGPUAndCPUPaths_produceEquivalentMFCC`): computes the same mel spectrogram once, feeds it
through `MFCCEngine` with and without a `metalEngine`, and asserts every coefficient (isolating
coefficient 0 specifically) agrees within float32 rounding tolerance. Verified it actually catches
the bug class it exists for: reverting the shader fix (`git stash`) failed this test immediately
(coeff-0 diff = 355.45, threshold = 0.5); restoring the fix passed it (0/2 failures). This is now
the standing guard — if a future shader edit reintroduces a CPU/GPU scale mismatch, `swift test`
catches it without needing the Python reference pipeline.

**Status:** Phase 24 complete (open-items list item 1, corrected scope). No retraining performed —
proven unnecessary rather than assumed. GPU MFCC validated against librosa's own convention
(residual 0.0041%, DC-term 0.0011%), and a permanent `swift test`-suite regression test added and
verified to actually catch the original bug. `swift build`/`swift build --build-tests` green; a
full `swift test` checkpoint was run given this adds a new test file touching the shared
`AudioIntelligenceMetal` engine — see the run's own log for the pass/fail count.

---

## 🎹 Phase 25 — Chord recognition: a real scoring bug, found, fixed, and its remainder split honestly (2026-08-30)

Open-items list item 2 ("Chord/structure 'ölçülemedi'") noted that `TraditionalTheoryEngine`'s
chord recognition (`identifyTriad`) has no accuracy measurement at all — Isophonics/Billboard only
distribute annotations, not audio, so end-to-end validation against real ground truth isn't
possible. Before building a synthetic-audio validation suite around it (the item's own proposed
workaround), a pre-existing, flagged-but-never-measured ambiguity in `identifyTriad` itself
(`Tests/TraditionalTheoryEngineTests.swift`'s doc comment) was investigated first, since building
new tests on top of an unmeasured algorithm risks calibrating against a broken baseline.

**Measured, not assumed:** `Tests/ChordScoringAmbiguityTests.swift` feeds `identifyTriad` an
idealized chroma vector (1.0 at each chord tone, 0 elsewhere — noise-free, best-case input) for
every one of its 108 canonical (root, quality) combinations (12 roots x 9 profiles: major, minor,
diminished, augmented, maj7, dom7, m7, m7b5, m6) and checks whether the returned (root, type)
matches. Result: **46/108 (42.6%) misidentified**, even under ideal conditions.

**Root cause**: `identifyTriad` scored each (root, profile) candidate as a raw, unnormalized sum of
matched chroma bins (`score += chroma[(root+offset) % 12]`), with no adjustment for how many notes
a profile has. A 4-note jazz-extension profile (maj7, dom7, m7, m7b5, m6) that happens to match 3 of
a *different* chord's notes elsewhere scores the same (3.0) as that chord's own correct 3-note
triad match — and since ties go to whichever (root, profile) is enumerated first (`score >
bestScore` is strict, and the loop scans root 0→11, profiles in declaration order), the 4-note
profile at the lower/earlier root silently wins. This is a scoring-scale artifact with no
music-theory basis, not a genuine harmonic ambiguity.

**Fix**: normalize by profile length (mean chroma energy per chord tone: `score = rawScore /
offsets.count`) instead of the raw sum, putting every profile on the same 0...1 scale regardless of
note count. Verified: **46/108 → 31/108** misidentified. Existing coverage
(`TraditionalTheoryEngineTests.swift` 5/5, `CadenceEngineTests.swift` 8/8) still green — no
regression on the previously-tested bass/inversion-formatting behavior.

**Threshold — first guess was wrong, caught by the full-suite checkpoint, not assumed correct.**
The first version of this fix set the threshold to `0.5` — reasoning (incorrectly) that this was
"the length-normalized equivalent of the original raw threshold `1.5` for a 3-note triad"
(`1.5/3 = 0.5`). That reasoning ignored that `ChromaEngine` L2-normalizes chroma per frame
(`ChromaEngine.normalizeChroma`), so real chroma values are nowhere near the 1.0-per-bin spikes the
idealized diagnostic used to validate the fix. The full `swift test` checkpoint (run as this
session's standing practice after a shared-engine change) caught it immediately:
`MusicologicalAccuracyTests.testSQAMHarmonyParity` (real SQAM string-quartet audio) regressed from
detecting chords to detecting **zero** anywhere in the file. Measured directly rather than
re-guessed: on that real recording, the best length-normalized score across all 1206 frames peaked
at **0.465** — below `0.5` in every single frame, so nothing could ever classify. `0.4` was chosen
empirically: on that same file it reproduces the *exact* frame-classification rate (41.54%) the
original raw threshold (`1.5`) produced pre-fix — real-world sensitivity preserved, while
normalization still fixes *which* root/type wins. `testSQAMHarmonyParity` passes again with `0.4`.

**The remaining 31 were not lumped into one "known limitation" bucket** — they split into two
categories with genuinely different characters, and conflating them would overstate what's
actually unfixable:

- **8 cases — augmented symmetry, irreducible.** An augmented triad's pitch-class set is *identical*
  at 3 roots a major third apart (C aug = E aug = G# aug — literally the same 3 notes). No amount
  of chroma-only analysis can recover which root is "correct" without additional information
  (typically the bass note). This is a real, standard MIR/music-theory limitation, not a defect in
  this implementation.
- **23 cases — relative-chord chroma-superset, resolvable in principle, not yet wired.** Classic
  jazz-harmony enharmonic overlaps (e.g. C6/Am7, Cmaj7/Em7, Cm6/Am7b5 share all their notes).
  Unlike the augmented case, these ARE resolvable — by bass note. `TraditionalTheoryEngine.
  detectBassNote` already computes exactly this from the real CQT (used today only for inversion
  labeling in `formatSymbol`), but `identifyTriad`'s root/type selection never sees it. Wiring the
  bass note into root selection is a separate, larger change (root selection would need to consider
  CQT data, not just chroma) — out of scope for this fix, tracked as open-items list item 3 with
  this exact count (23) as its measurable target: after that follow-up, this test's
  `relativeChordSupersetCount` assertion is the number expected to move, ideally toward 0.

Both counts are now regression-guarded by exact-value assertions in `ChordScoringAmbiguityTests`
(`augmentedSymmetryCount == 8`, `relativeChordSupersetCount == 23`) — a future change to the profile
list, scoring, or threshold that shifts either number will fail loudly instead of drifting silently.

**Status:** Phase 25 complete for the `identifyTriad` scoring-bug portion of open-items list item 2.
The item's original ask (end-to-end synthetic-audio chord accuracy suite) is still open — this
phase was a prerequisite investigation that turned up a real, independent bug worth fixing first.
`swift build`/`swift build --build-tests` green; `TraditionalTheoryEngineTests` (5/5),
`CadenceEngineTests` (8/8), `MusicologicalAccuracyTests` (3/3, including the real-audio
`testSQAMHarmonyParity` this threshold correction fixed), and `ChordScoringAmbiguityTests` (1/1)
all green. Full `swift test` checkpoint re-run clean after the threshold correction.

---

## 🎸 Phase 26 — InstrumentEngine: MFCC-0 is recording-condition noise for Bass/Drums/Strings, a real discriminative signal for Vocals/Brass (2026-08-30)

Open-items list item 4 (InstrumentEngine's weak Bass recall, 48%/62%) was investigated on real
OpenMIC TRAIN-partition audio (train, not test — per this session's train/test separation rule:
iterate and diagnose on train, touch test only once at the end for an honest final number) before
assuming retraining was the answer. First hypothesis (a chord-scoring-bug-style hidden formula
defect in `timbreScore = max(0, 0.4 - mfccDistance/250)`) was tested directly and **rejected**: on
40 real held-out Bass clips, mean `mfccDistance` for correctly- vs. incorrectly-classified clips
was statistically identical (117.3 vs. 116.1) — no hidden threshold bug, a genuine model-capacity
question.

**Confusion-matrix diagnostic** (80 unambiguous train-partition Bass clips): 39/80 (48.75%) hits,
matching the known 48% baseline. Of the 41 misses, 26 (63%) had "timbre" (MFCC Euclidean distance)
as the single largest contributing term to the wrongly-winning class's edge over Bass —
concentrated, not spread evenly across the 5 scoring terms.

**Root cause**: `mfccPattern[0]` (the DC/log-energy coefficient) ranges from -85.9 to -260.5
across the 6 class profiles — a huge, energy-dominated spread. Real Bass clips' own MFCC-0 vs.
their training-fit mean differs by 23.2 on average; Drums by 80.6. This is recording-condition
noise (DI vs. mic'd, mix level, dynamic range), not timbre.

**Symmetric case-by-case verification, not an aggregate guess** (the standard this investigation
was explicitly held to): excluding MFCC-0 from the timbre distance was checked class-by-class,
both directions.
- **Bass/Drums/Strings-Synth: 15 clips gained (wrong->correct), 0 lost (correct->wrong)** across
  train-partition samples of each — a completely one-sided win, not a trade-off.
- **Vocals/Brass: excluding MFCC-0 LOSES real, case-by-case-verified discriminating power** — 6
  Vocals and 4 Brass clips that were correctly classified flip to wrong when MFCC-0 is dropped, in
  every case because the real input's MFCC-0 was close to that class's own trained mean (Vocals
  clips: real MFCC-0 mean -95.8 vs. trained -85.9, diff 9.9 — the tightest of all 6 classes) while
  far from the wrongly-winning class's mean. Vocal/wind-instrument recordings have a genuinely
  stable, class-characteristic loudness envelope; Bass/Drums/Strings recordings don't.
- **Piano: zero difference either way** (26.7% with or without) — left unchanged; branching the
  architecture where measurement shows no benefit only adds complexity.

**Fix**: `Fingerprint` gained `mfccExcludedCoefficients: Set<Int>`, set to `[0]` for Bass,
Drums/Percussion, and Strings/Synth; `[]` (unchanged) for Piano/Keyboard, Brass/Trumpet,
Vocals/Chorus. The reasoning (not just the "what") lives in the field's own doc comment in
`InstrumentEngine.swift`, so a future reader doesn't have to rediscover why only three classes
are special-cased.

**Status:** Phase 26 complete for the diagnosed portion of open-items list item 4.
`swift build`/`swift build --build-tests` green; `InstrumentEngineTests` (4/4),
`InstrumentBaselineTests` (2/2) green, no regression. A full `RA_IRMAS_PER_CLASS=0
RA_OPENMIC_LIMIT=0` `ReliabilityAudit` re-measurement was run per the user's request, recorded
next to the historical baseline (Phase 16, pre-any-fix, same sample sizes — a fair, apples-to-
apples comparison):

| Dataset | Phase 16 baseline | Post-fix (today) | Change |
| :-- | :-- | :-- | :-- |
| IRMAS (6705/6718 files) | 25.3% | **28.5%** | +3.2pp |
| OpenMIC-2018 (13847/20000 clips) | 30.3% | **44.8%** | +14.5pp (≈48% relative) |

The first re-measurement attempt was interrupted mid-run by an unrelated external-disk migration
(OpenMIC's `n` collapsed to 513/13847 as the dataset directory was relocated out from under the
read) and was discarded, re-run once the migration completed and all `Tests/Resources/*` symlinks
(plus a stale `Examples/Golden/audio` symlink outside that directory, which the same migration
broke and which caused 4 unrelated `GoldenDatasetValidationTests` failures in the next full-suite
checkpoint until found and re-pointed) were updated to the new location, for a valid number.

### Per-class breakdown — the aggregate number alone would have hidden a real regression

`Examples/ReliabilityAudit` gained two new verbose-mode additions to get this
(`RA_IRMAS_VERBOSE=1`, already existed; `RA_OPENMIC_VERBOSE=1`, added — per-fine-class recall
restricted to clips whose entire label set maps unambiguously to one coarse class, the same
purity filter `PrototypeTrainer` itself uses, for a clean apples-to-apples comparison against the
Phase 16 baseline numbers).

**Methodology correction, caught before drawing conclusions from it**: the first `RA_OPENMIC_
VERBOSE=1` run omitted `RA_OPENMIC_TEST_ONLY=1`, so it measured train+test combined — not
comparable to the Phase 16 baseline, which was held-out-test-only. Re-run correctly:

| Class | OpenMIC recall, held-out test only (n) | Phase 16 baseline | Change |
| :-- | :-- | :-- | :-- |
| Bass (Acoustic/Electric) | **59%** (71/120) | 48% | **+11pp** |
| Drums/Percussion | 79% (364/457) | — (not previously isolated) | — |
| Piano/Keyboard | 52% (240/456) | — (not previously isolated) | — |
| Strings/Synth | 41% (444/1075) | — (33% was *precision*, a different metric — not directly comparable) | — |
| Vocals/Chorus | 22% (46/207) | — (not previously isolated) | — |
| **Brass/Trumpet** | **5%** (27/465) | 13% | **-8pp (regression)** |

IRMAS (which has no dedicated Bass class among its 11 — Bass's per-class number could only come
from OpenMIC) confirms Brass/Trumpet is genuinely, severely weak from an independent dataset too:
`sax` 3% (21/626), `tru` 5% (32/577) recall — both far below every other IRMAS class measured.

Bass's real-world gain (+11pp on the properly-restricted held-out set) confirms Phase 26's fix
generalizes. Brass/Trumpet — deliberately left untouched by the MFCC-0 fix, since Phase 26's own
case-by-case check showed MFCC-0 is a genuine, reliable signal for Brass, not noise — got *worse*,
not just unmoved, and this holds under the corrected methodology too (5% either way).

**"Scale unfairness" hypothesis tested directly and mostly rejected.** Suspected mechanism:
excluding MFCC-0 for Bass/Drums/Strings shortens their distance sum to 9 terms while Brass/Piano/
Vocals stay at 10 — since raw Euclidean distance mechanically shrinks with fewer terms (for almost
any input, not just genuine matches), this could give the 9-term classes an unfair argmax edge
regardless of true similarity. Tested on the same 80 train-partition Brass clips used to originally
diagnose this regression: replacing the raw-sum distance with a term-count-independent RMS
distance (root MEAN squared difference, not root SUM) only moved Brass's timbre-term win rate from
2/80 to 4/80 — a real but small effect, nowhere near enough to explain a 75/80 loss rate. Scale
incomparability is at most a minor contributor, not the primary cause.

**Real, unresolved cause**: Brass's own `mfccPattern` is simply a poor match for real Brass audio
— even restricted to the timbre term alone (ignoring the other 4 scoring terms entirely), Brass's
own profile is the single closest match for only 2-4 of 80 real train-partition Brass clips.
Plausible explanation, not yet verified: Brass/Trumpet's 3 constituent OpenMIC fine classes
(saxophone, trombone, trumpet) may simply be too timbrally diverse for one shared mean+SD profile
to represent well — a genuine model-capacity question, not a scoring-formula bug this time. This
is now open-items list item 5's concrete, measured starting point — no longer a stale
13%-with-no-recent-verification figure, and the two most obvious hypotheses (a hidden threshold
bug, a scale-fairness artifact) have both been tested and ruled out rather than assumed.

---

## 🎵 Phase 27 — pYIN implemented from the primary source; a severe emission-formula bug found and fixed via reference-implementation comparison (2026-08-30)

Investigated the state of the art for monophonic pitch estimation before touching
`InstrumentEngine`/`StructureEngine` further, per the user's own research-first instinct. Pitch
estimation is a comparatively solved field where pure-Swift, zero-dependency, offline-only
constraints (both explicitly confirmed) don't close off the best available *classical* method:
pYIN (Mauch & Dixon, ICASSP 2014) — a direct DSP-only extension of the `YINEngine` this codebase
already has, no CoreML/neural-net needed. Deep-learning approaches (CREPE, basic-pitch, PANNs/AST
for instrument ID) were explicitly ruled out as incompatible with the confirmed pure-Swift
constraint, not investigated further.

Implemented directly from the original paper (`YINEngine.pyinCandidates`/
`analyzePYINCandidates`, new `PYINDecoder.swift`), not a second-hand description:

**Stage 1** (multi-candidate generation): instead of `YINEngine`'s existing single first-below-
threshold candidate, sweep every threshold in the Beta(2,18) prior's support and return every
period any threshold would select, each weighted by the probability mass of thresholds selecting
it. Efficient exact algorithm (not a naive 100-threshold loop): sort CMND troughs by their own
value ascending — this is exactly the order in which they become eligible as the threshold rises
— and track a running-minimum-tau; each strict improvement is a new "winner" owning the threshold
range up to the next winner. Beta(2,18)'s CDF has a closed polynomial form for integer alpha=2,
derived directly: `CDF(x) = 1 - 19(1-x)^18 + 18(1-x)^19` — each winner's probability is the exact
analytic CDF difference over its range, not a discretized 100-point sum (a first version used the
discrete sum; switched to the analytic form since it's exact and grid-resolution-independent).

**Stage 2** (HMM pitch tracking, `PYINDecoder`): 480 pitch bins (55Hz-880Hz, 10-cent/0.1-semitone
resolution) x voiced/unvoiced per bin = 960 states — not the single shared "silence" state
`ViterbiEngine.smoothPitchPath`'s existing simplified pYIN-relative uses. Triangular pitch-
transition window (max 25-bin/2.5-semitone jump per frame), 0.99/0.01 voicing self-transition,
initial probabilities uniform over unvoiced states only — all matching the paper's stated design.
Deliberately NOT built on `ViterbiEngine.decode()`'s generic dense O(nStates^2) recursion (960^2 =
~920K ops/frame) — a dedicated banded Viterbi exploiting the +-24-bin transition window brings this
to ~188K ops/frame, since the paper itself notes the need for "an efficient version... that
exploits the sparseness of the transition matrix."

### A severe bug, invisible on synthetic data, caught by real-data validation

A pure-tone sanity check (220Hz sine) passed cleanly (82/83 frames voiced, mean 220.5Hz) — but the
real closing validation against MDB-stem-synth (synthesis-derived ground truth, the same dataset
YIN's 56.5%/50.6% baseline was measured on) told a completely different story: **RPA<50cents
collapsed to 2.0% (vs. YIN's 50.6%), with only 4353/207887 true-voiced frames ever decoded as
voiced at all** — a near-total collapse to "unvoiced" that a clean synthetic tone could never
reveal.

Root cause: the first implementation followed the paper's eq. 6 literally — `p_{m,v=1}=0.5*p*_m`,
`p_{m,v=0}=0.5*(1-Sigma p*_k)`, the SAME unvoiced value repeated identically across all 480 bins.
With a fixed 0.5/0.5 prior split, a single voiced bin's `0.5*mass` only beats the repeated
`0.5*(1-mass)` unvoiced value when that one candidate holds over half of the ENTIRE Beta-prior
probability mass — a bar real (non-idealized, harmonically messy) CMND troughs rarely clear, since
Beta(2,18) is heavily front-loaded (CDF(0.1) ≈ 58% of the whole distribution) and real troughs
often sit past that point. Root-caused by comparing directly against librosa's `pyin` source (the
de facto reference implementation) rather than re-deriving from the terse paper text alone: the
real reference formula has **no 0.5 prior factor**, and unvoiced mass is **divided across all 480
bins** (`(1-voicedProb)/nBins`), not repeated — making each individual unvoiced state's emission
tiny (spread over 480 states) so a genuine voiced candidate at one specific bin can win, which is
what a standard multi-state HMM requires.

Fixed to match the reference formula. Re-verified on the same MDB-stem-synth set
(`Tests/PYINEngineTests.swift`, 20 stems, 207,887 true-voiced ground-truth frames):

```
YIN : RPA<50cents=50.6%  GPE(>20% error)=2.1%   voicing accuracy=77.8%
pYIN: RPA<50cents=61.6%  GPE(>20% error)=3.9%   voicing accuracy=85.3%
```

Reported honestly, not as a one-sided win: pYIN beats YIN substantially on RPA (+11.0pp) and
voicing accuracy (+7.5pp) — recovering 27% more true-voiced frames as correctly voiced — but GPE
rose (+1.8pp), consistent with the newly-recovered frames including some genuinely harder cases.
This matches the literature's own characterization (pYIN's advantage is chiefly voicing/octave-
error robustness, not raw cent-accuracy) rather than an unqualified improvement on every axis.

**Status:** Phase 27 complete. `PYINEngineTests` promoted to permanent coverage with regression-
guarding assertions (pYIN RPA/voicing-accuracy must exceed YIN's; RPA must stay above 55% — the
exact signature of the emission-formula bug this phase found and fixed, verified to actually catch
it: reverting to the 0.5-prior formula collapses RPA back to ~2%). `swift build`/`swift build
--build-tests` green; `YINEngineTests` (8/8), `ViterbiPitchSmoothingTests` (4/4),
`ViterbiRealPipelineTests` (1/1) unaffected — no regression on existing YIN/Viterbi behavior.
Not yet wired into `DNAReportBuilder.swift`'s production pipeline (still YIN) — that integration,
and the known 55-880Hz 4-octave range limitation's real-world impact (bass/high-register material
outside that window can never be tracked as voiced by `PYINDecoder`, inherited directly from the
paper's original vocal-range design target), are open follow-ups, not yet done.

---

## 🗂️ Phase 28 — SALAMI downloaded (444/476 tracks, legally, via a resolved Internet Archive index); StructureEngine gets its first-ever real ground-truth measurement (2026-08-30)

Open-items list item 1 (SALAMI "requires per-track matching, no bulk download exists") was
re-investigated before accepting that premise. SALAMI's own official metadata
(`DDMAL/salami-data-public/metadata/id_index_internetarchive.csv`) turned out to already contain
476 direct `archive.org/download/...` URLs — not a matching problem, a *stale-link* problem: the
URLs are ~10-15 years old and Internet Archive items get re-derived/renamed over time. Resolved via
`archive.org/metadata/{item}` (current file listing per item) with a stem-based match (strip
`_vbr`/format-specific suffixes) — 462/476 resolved on the first pass; actual download (network
retries, timeouts, occasional archive.org 500s) landed **444/476 (93.3%), 12GB**, all legally
downloadable Live Music Archive material — no YouTube-matching or scraping needed, unlike the
official README's own suggested fallback for other SALAMI audio sources. `Tests/Resources/SALAMI`
symlinked, `annotations/`/`metadata/` from the CC0-licensed upstream repo included alongside.

A mid-session external-disk migration (the 12GB+ total across all datasets needed to move off a
nearly-full internal drive) interrupted and then relocated the whole `audiointelligence_tests`
directory; all `Tests/Resources/*` symlinks (and one outside that directory, `Examples/Golden/
audio` — see Phase 26) were re-pointed once the move completed, and the download resumed from
where its own resumability logic left off (268 already-downloaded files skipped, 176 fetched in
the final pass).

### First-ever real ground-truth measurement for StructureEngine

`StructureEngine.analyze()`'s boundary detection had never been checked against real human-
annotated structure before (`DSPGroundTruthTests.testRecurrenceMatrixSymmetry` only checks
self-similarity-matrix symmetry; `StructureEngineTests.swift`'s synthetic two-section track checks
boundary detection in principle, not accuracy against real annotation). `Tests/
StructureEngineSALAMITests.swift`: 15 real SALAMI tracks (evenly sampled), full production-
equivalent pipeline (`ChromaEngine(nFFT: 8192)`, `MFCCEngine(nMFCC: 13)`), boundary times compared
against SALAMI's "uppercase" large-scale structure layer at the two standard MIREX tolerance
windows (0.5s, 3.0s):

```
@0.5s: precision=8.2%  recall=21.9%  F=11.9%
@3.0s: precision=25.7% recall=68.7%  F=37.3%
```

**Real finding, not just a number**: predicted boundary counts run 2-3x the true counts per track
(e.g. one track: 40 predicted vs. 12 true) — `StructureEngine` over-segments. The 3.0s recall
(69%) shows most true boundaries have *some* nearby prediction, but the collapse at 0.5s (22%)
shows those predictions are rarely precisely timed even when they're in the right neighborhood.
Likely lever, not yet tested: `DSPHelpers.peakPick`'s `delta`/`wait` parameters in
`StructureEngine.analyze` are almost certainly too permissive for real audio's novelty-curve noise
floor — untouched since being hand-set, never calibrated against real annotated boundaries before
this phase, because no real annotated audio existed to calibrate against.

**Debugging note, for anyone touching this manifest format again**: the freshly-downloaded
`ia_manifest.csv` was written with CRLF line endings (Python `csv.writer`'s default) and silently
produced **zero** parsed entries in Swift — `String.split(separator: "\n")` treats `"\r\n"` as a
single extended grapheme cluster, so a bare `"\n"` separator never matches anything in a CRLF file
and the loop body never runs, with no error, no crash, just an instantly-empty result. Fixed three
places: the manifest file itself (normalized to LF), the generating Python script
(`csv.writer(..., lineterminator='\n')`), and the Swift parsing code
(`.components(separatedBy: .newlines)`, which handles any line-ending convention correctly) — the
third fix is defense in depth, not a substitute for the first two.

**Status:** Phase 28 complete for open-items list item 1's download; StructureEngine boundary
accuracy is now measured for the first time, not assumed. The over-segmentation investigation
(peak-picking recalibration against this same real ground truth) is a concrete, well-defined
follow-up, not yet done. `swift build`/`swift build --build-tests` green;
`StructureEngineSALAMITests` (1/1) green with a loose sanity floor (catches a total collapse, not
a tight regression contract on today's still-weak baseline numbers).

---

## 🎯 Phase 29 — StructureEngine peak-picking calibrated against real SALAMI ground truth; two independent, previously-undiscovered production bugs found and fixed along the way (2026-08-31)

Phase 28's open follow-up (recalibrate `DSPHelpers.peakPick`'s `delta`/`wait`, never tuned against
real audio) was picked up. A new `Examples/StructureCalibration` tool was built for this:
`StructureEngine.analyze()` was split into `prepareFeatures(chromagram:mfccs:)` (the expensive
STFT->chroma/MFCC->Foote-novelty half) and `boundaries(from:config:)` (the cheap peak-picking
half, taking a new `StructurePeakPickConfig`) so a grid search can compute each track's novelty
curve ONCE and cheaply re-run peak-picking for hundreds of parameter combinations against it — the
existing `StructureEngineSALAMITests.swift` pattern (STFT nFFT=8192 chroma, 13-dim MFCC, whole
track) was reused for feature extraction, split 38 calibration / 19 held-out (disjoint) tracks.

### Finding 1: the old `delta=0.03` was providing essentially no threshold at all

A first grid search over `delta` in `[0.02, 0.35]` (a plausible-looking range for an unfamiliar
parameter) found F@3.0s completely flat across the whole range (40.2%-40.3%) — `delta` wasn't
doing anything. Printing the novelty curve's actual statistics revealed why: `streamingFooteNovelty`
returns raw, unnormalized energy — pooled mean ≈668K, max ≈46.6M on real SALAMI tracks. An additive
`delta=0.03` against a baseline in the hundreds-of-thousands was, in effect, zero. This is the real
root cause behind Phase 28's over-segmentation finding: peak-picking was selecting almost every
local maximum, gated only by `wait` and `localMax`, never by any meaningful novelty-height bar.

### Finding 2 (independent bug, unrelated to peakPick): StructureEngine's real production call fed it a malformed MFCC array

While reasoning about whether a fixed absolute `delta` would even transfer to production,
`DNAReportBuilder.swift`'s actual per-chunk call (`mfccs: [mfccSubset]`) turned out to pass a
single 20-coefficient vector — frame 0's full MFCC only (confirmed via the `batch_dct` Metal
kernel's frame-major indexing, `id = frame_idx*n_mfcc + mfcc_idx`) — as if it were a **20-frame,
1-dimensional time series** (`StructureEngine` reads `mfccs` as `[dim][time]`). Only the first ~20
STFT frames of each ~45s chunk (out of possibly thousands) ever got a nonzero MFCC value; the rest
of every chunk's timbre-novelty term was silently computed against all-zero data, for as long as
this pipeline has existed. Fixed by reshaping `mfccRaw`'s real per-frame output into `[dim][time]`
before passing it to `StructureEngine`.

### Design change: absolute `delta` → `deltaMultiplier` (self-scaling)

Since the novelty curve's absolute scale depends on feature dimensionality (13 vs. 20-dim MFCC)
and whether it's computed whole-track or per-chunk, a fixed absolute delta calibrated under one
configuration isn't guaranteed valid under another. `StructurePeakPickConfig.deltaMultiplier` was
introduced instead: `boundaries(from:config:)` now computes `delta = deltaMultiplier *
mean(features.novelty)` at call time, so the threshold self-scales to whatever novelty curve it's
actually given. Re-running the grid search (`deltaMultiplier` in place of a fixed `delta`) found
the same basic shape of optimum, now expressed portably.

### Finding 3 (the self-scaling assumption was itself checked, not assumed): a real chunk-seam artifact

Before accepting `deltaMultiplier` as sufficient, a direct two-pipeline comparison was run on 6
real, multi-chunk SALAMI tracks: whole-track (calibration-style) boundaries vs. `DNAReportBuilder`-
style boundaries (independent 45s chunks, each `StructureEngine` call analyzing from scratch, no
continuity across the chunk edge). Result: only 15.2% of whole-track boundaries landed within 2s of
a chunk-seam multiple (45s, 90s, ...) — plausible background rate — but **40.4%** of the chunked
pipeline's boundaries did. Root cause: the Foote-novelty checkerboard kernel has no visibility past
a chunk's own edge, so the very start/end of every independent chunk looks artificially
"discontinuous," injecting a spurious boundary near almost every chunk seam — a real shape
artifact that no amount of delta-scaling can fix, exactly as anticipated before running the check.

**Fix:** matching the pattern already used for `ViterbiEngine.smoothPitchPath` (Phase "L") and
`TempogramEngine.computeACT` (Phase "M") — accumulate the whole track's continuous features first,
analyze once — `DNAReportBuilder.swift`'s per-chunk `StructureEngine(...).analyze(...)` call was
removed entirely. Each chunk now only accumulates its per-frame MFCC into a whole-track
`fullMFCCBins` buffer (mirroring the existing `fullChromagramBins` merge); `StructureEngine` runs
ONCE on the complete track's chroma+MFCC after the chunk loop. `finalSegments` (both the
`analyzeAggregate`-level and `assembleFinalDNA`-level copies — there were two independent
implementations of the same per-chunk-offset logic) simplified to a direct read of the single
result's segments, since they're already in true global time (no more `+ chunkIndex*45.0` offset
needed, and no more instant chunk-edge artifact from `analyze()`'s Foote kernel seeing a
discontinuity that was never really there).

### Final calibrated numbers

Best config (grid-searched on 38 calibration tracks, re-verified against the real unmodified
`DSPHelpers.peakPick` on both calibration and a disjoint 19-track held-out set — not just the fast
approximate search): `preMax=4 postMax=4 preAvg=24 postAvg=24 wait=12s deltaMultiplier=2.0`.

```
calibration set: F@3.0s 40.2% -> 44.7%   held-out set: F@3.0s 39.3% -> 45.7%
```

With the chunk-architecture fix also applied, `StructureEngineSALAMITests` (15 real SALAMI tracks,
the same whole-track methodology `StructureEngine` itself now always uses in production too):

```
@0.5s: precision=8.2%->21.2%  recall=21.9%->21.4%  F=11.9%->21.3%
@3.0s: precision=25.7%->40.9% recall=68.7%->41.3%  F=37.3%->41.1%
```

Recall@3.0s dropping from 69% to 41% alongside precision rising from 26% to 41% is the expected
signature of fixing over-segmentation, not a regression: the old config's very high recall came
from predicting far more boundaries than really exist (every true boundary had *something* nearby
by sheer density), which is exactly what the ~2-3x predicted/true ratio (Phase 28) already showed
was happening. Precision and recall converging together is consistent with the engine now
predicting close to the right NUMBER of boundaries, not just scattering more of them.

**Honest limitation:** the calibration/held-out split (38/19 tracks) and the chunk-artifact check
(6 tracks) both come from the same SALAMI pool `StructureEngineSALAMITests` also draws its 15
tracks from — there is no fully independent third dataset for structure (same constraint as
Phase 28: Isophonics/Billboard have annotations but no legally obtainable audio). The relative-
threshold design and the whole-track architecture fix are both principled, measured responses to
real, checked failure modes (not just parameter-fit to whichever tracks were sampled) — but the
absolute accuracy numbers above should be read as "measured on the best real data available," not
as validated against a fully disjoint corpus.

**Status:** Phase 29 complete. `StructurePeakPickConfig`/`StructureFeatures` are new public API
(`Sources/AudioIntelligenceCore/Feature/StructureEngine.swift`); `Examples/StructureCalibration`
is a new one-off tool (not part of `swift test`, matching `PrototypeTrainer`'s precedent) kept for
future recalibration if the underlying feature pipeline changes. `swift build`/`swift build
--build-tests` green. `StructureEngineTests`' synthetic two-section test needed its section width
widened (400->700 frames) to stay comfortably over the new 12s minimum segment spacing — it was
originally tuned to the old 8s default. Full `swift test` checkpoint run (DNAReportBuilder is
widely shared): **131/131 tests passed, 0 failures** (1328s, ~22 minutes) — no regression from the
per-chunk-to-whole-track StructureEngine architecture change or the MFCC-reshape fix.

---

## 🎼 Phase 30 — First real-audio, end-to-end chord-identification measurement: 4-note "jazz extension" chords degrade sharply on real signal, 3-note triads don't (2026-08-31)

Open-items list item 2's remaining ask ("synthesize known chord progressions, measure end-to-end
accuracy through the real STFT->Chroma->CQT->TraditionalTheoryEngine chain, since Isophonics/
Billboard have no legally obtainable paired audio") was picked up. `ChordScoringAmbiguityTests`
(Phase 25) already measured `identifyTriad` in isolation against idealized chroma vectors (1.0 at
each chord tone, 0 elsewhere) — 77/108 canonical (12 root x 9 quality) chords correct. What was
never checked: does a REAL signal chain (synthesized audio -> windowed STFT -> `ChromaEngine`'s
octave-folding -> the same `identifyTriad`) preserve that accuracy, or does real-world chroma
degrade it?

`Tests/ChordEndToEndSyntheticTests.swift`: the same 108 canonical chords, each synthesized as pure
additive sines at the chord tones' true frequencies (`Tests/Support/SyntheticAudio.chord`, already
existing infra), run through the exact STFT/Chroma/CQT parameters `DNAReportBuilder.swift` uses in
production (nFFT=8192 chroma, hop=512, CQT nBins=84/binsPerOctave=12/fMin=32.7), then
`TraditionalTheoryEngine.analyzeVertical`'s real per-frame chord detection (majority vote across
each 3s clip's detected frames, so a single mis-tagged transient can't fail a chord the real
pipeline mostly gets right).

**Result: 57/108 (52.8%) correct** vs. the idealized-chroma baseline's 77/108 (71.3%) — a real,
substantial 18.5pp drop. But the drop is NOT uniform across chord types:

- **3-note triads (major/minor/diminished, 36 chords): essentially undegraded** — none of these
  appear in the mismatch list at all.
- **Augmented (12 chords): degrades in line with its already-known irreducible symmetry** (9/12
  mismatched here vs. 8/12 in the idealized case — consistent, not a new failure mode).
- **4-note "jazz extension" chords (dom7/m7/m7b5/m6, 48 chords): 42/48 mismatched** — these
  collapse almost entirely on real audio, despite scoring correctly on idealized chroma.

**Likely mechanism, not yet root-caused**: the synthesized frequencies are true 12-TET pitches,
which don't land on exact STFT bin centers (nFFT=8192 at 22050Hz gives ~2.69Hz/bin) — a single
sustained pure tone leaks energy into neighboring bins even after the analysis window. A 3-note
chord has 3 tones' worth of leakage cross-talk; a 4-note chord has roughly twice as many pairwise
leakage interactions, which is consistent with (but not yet proven to be) why exactly the 4-note
chords are the ones that collapse. This mirrors a real acoustic phenomenon any real instrument
mixture would also produce — it is not obviously a code bug, but it also hasn't been distinguished
from one (e.g. `identifyTriad`'s 0.4 score threshold, itself empirically tuned on a single real
SQAM recording per Phase 25's comment, may simply be miscalibrated for the specific chroma-leakage
pattern 4-note chords produce).

**Status:** Phase 30 complete for item 2's stated task — first-ever real-audio end-to-end chord
measurement exists and is a permanent regression test (loose floor: total correct count must stay
above 50%, catches a total collapse without locking in today's number as a target). The root cause
of the 4-note-chord-specific degradation is a new, not-yet-investigated open item — not
prioritized yet, pending user decision (same stability-first ordering as the rest of this list).
`swift build`/`swift build --build-tests` green; new test passes (57/108, 7.2s).

---

## 🎹 Phase 31 — Bass note wired into chord root/quality selection: all 31 previously-ambiguous canonical chords resolved (2026-08-31)

Open-items list item 2 (later renumbered item "3" mid-session, a direct follow-up to Phase 25's
`identifyTriad` normalization fix): `TraditionalTheoryEngine.detectBassNote` already computed a
real bass note from CQT data, but only for inversion labeling (`formatSymbol`) — `identifyTriad`'s
own root/quality selection never saw it, even though the 23 "relative-chord superset" mismatches
Phase 25 measured (e.g. C6/Am7, Cmaj7/Em7 — chroma-identical pairs) are, by the project's own
prior analysis, resolvable in principle once the bass note is known.

**Implementation**: `identifyTriad(_:bassNote:)` gained an optional `bassNote: Int? = nil`
parameter (default preserves the original chroma-only behavior exactly — `ChordScoringAmbiguityTests`'
existing 31-mismatch baseline is untouched, since it never passes a bass hint). Within the scoring
loop, ties (or near-ties, epsilon 0.001 — real audio won't produce the bit-exact equality idealized
chroma does) now prefer whichever candidate's root matches the real bass note, without disturbing
`bestScore` so a later same-score-but-wrong-root candidate can't undo the match. `analyzeVertical`
now computes the bass note FIRST and passes it into `identifyTriad`, instead of only using it
afterward for the inversion suffix.

**Measured result, not assumed**: a new test (`ChordScoringAmbiguityTests.
testCatalogAmbiguity_withBassNoteHint_measuresResolution`) re-runs the exact same 108-chord
catalog, this time supplying each chord's true bass note (= its root, since every catalog entry is
constructed root-position) — **31/31 previously-mismatched chords now resolve correctly**. This
exceeds the item's own original scope: the 8 augmented-symmetry cases were explicitly called out
as "irreducible from chroma alone... without bass information" (Phase 25's own wording already
anticipated this) but turn out to be resolvable WITH bass information after all, since the true
bass note always matches exactly one of the three chroma-identical augmented-triad root candidates
— tie-breaking naturally picks it. `ChordEndToEndSyntheticTests`' real-audio end-to-end number also
ticked up slightly as a side effect (57->58/108) — `analyzeVertical`'s real pipeline call benefits
from the same fix.

**Status:** Phase 31 complete, fully verified. Targeted suite green:
`ChordScoringAmbiguityTests`/`TraditionalTheoryEngineTests`/`ChordEndToEndSyntheticTests`/
`CadenceEngineTests` (16/16, all pass, no regression on the existing bass-blind baseline test).
Full `swift test` checkpoint (this touches `TraditionalTheoryEngine`, used throughout the
musicology pipeline): **133/133 tests passed, 0 failures** (1322.5s, ~22 minutes) — up from
Phase 30's 131 (this phase added 2 new tests: `ChordEndToEndSyntheticTests` and the bass-note-hint
resolution test).

### Side work: README/self-audit accuracy pass

While investigating CQT's real usage for the bass-note fix above, found `AuditMetrics.cqtStatus`
(reachable via the public `AudioIntelligence.analyzeRawAggregate` API) hardcoded to claim CQT has
"no downstream consumer in this pipeline" — false, and had already been false before this session
(CQT has fed `detectBassNote` since the Phase-25-adjacent `cqtMatrix` wiring fix). `CQTEngine.
swift`'s own doc comment made the same stale claim. Both corrected, along with the locked-in
`AuditMetricsTests` assertion that had been asserting the false string as expected behavior.

Also brought `README.md`'s Validation Status table up to date against real, already-measured
numbers that had drifted out of sync with the code: the Instrument row still showed Phase 16's
original numbers instead of Phase 26's corrected held-out-test recall figures (Bass 48%->59%,
Brass 13%->5%, etc. — Brass is a real regression, not just a re-measurement, per Phase 26); the
Chord/Structure row still said "not yet validated" despite this session's Phase 29 (structure,
SALAMI) and Phase 30 (chord, synthesized audio) measurements; the SALAMI dataset table row still
said "(not fetched)". None of these were new numbers — all were already sitting in DEVLOG,
just not reflected in the README a reader would actually see first.

**Verification note**: this side work's edits (`DNAReportBuilder.swift`, `CQTEngine.swift`,
`AuditMetricsTests.swift`) were made concurrently with the Phase-31-main-fix full-suite run above,
which meant the 133/133 result predated them (`swift build --build-tests` confirmed this — it
recompiled exactly those 3 files on the next invocation). Re-verified separately and cleanly
afterward: a fresh `swift build --build-tests` + `swift test --filter AuditMetricsTests` (1/1
pass) confirms `cqtStatus` now genuinely returns "Used (feeds TraditionalTheoryEngine bass-note
detection)" from real, current code — not re-running the full 22-minute suite a third time for a
single self-contained string constant, since its only assertion point is that one test, which now
passes against fresh code.

---

## 🎻 Phase 32 — Strings/Synth IRMAS-vs-OpenMIC precision "anomaly" measured with corrected methodology: narrows from 31pp to 9pp, closed (2026-08-31)

Open-items list item 3's remaining gap: Phase 26 re-measured Strings/Synth's OpenMIC **recall**
under the corrected held-out-test-only methodology (41%, 444/1075) but never re-measured
**precision** — the original flagged anomaly (IRMAS precision 64% vs. OpenMIC precision 33%, a
31-point gap) had never been checked against the same methodology fix that recall got, so it was
an open question whether the anomaly was real or another instance of the same stale-partition
measurement artifact Phase 26 found for recall.

`Examples/ReliabilityAudit`'s `runOpenMICTestPartitionEval` (`RA_OPENMIC_TEST_EVAL=1
RA_OPENMIC_TEST_PER_CLASS=0`, full held-out test partition, no per-class thinning) already computes
both recall and precision per class from a single confusion matrix — it just hadn't been run and
recorded for this specific comparison before. Full run, 2780 evaluated clips (754 skipped as
ambiguous/multi-label, 0 missing):

```
Strings/Synth recall:    444/1075 (41%)   [matches Phase 26's already-recorded number exactly]
Strings/Synth precision: 444/803  (55%)
```

**Finding**: OpenMIC precision under the corrected methodology is 55%, not the originally-flagged
33% — IRMAS 64% vs. OpenMIC 55% is a 9-point gap, well within the range of an unremarkable
cross-dataset difference (different recording conditions, source distributions, label conventions
across the two datasets), not something that needs a code-level explanation. The original 31-point
gap was, like the recall-side anomaly Phase 26 diagnosed, most likely an artifact of measuring
against the wrong (non-held-out, or otherwise inconsistent) partition rather than a genuine model
weakness specific to Strings/Synth precision.

Full corrected-methodology table recorded for completeness (all 6 classes, single run):

| Class | Recall | Precision |
| :-- | :-- | :-- |
| Piano/Keyboard | 53% (240/456) | 43% (240/561) |
| Bass (Acoustic/Electric) | 59% (71/120) | 22% (71/321) |
| Brass/Trumpet | 6% (27/465) | 27% (27/99) |
| Vocals/Chorus | 22% (46/207) | 15% (46/302) |
| Drums/Percussion | 80% (364/457) | 54% (364/670) |
| Strings/Synth | 41% (444/1075) | 55% (444/803) |

**Status:** Phase 32 complete, open-items list item 3 closed — no code change, this was a
pure-measurement item and the measurement is now done. No new bugs found; this table is also a
useful by-product for future work on the other classes (e.g. Bass's precision, 22%, is the next
most striking number here but is out of THIS item's scope).

---

## 🎤 Phase 33 — pYIN wired into production; its 55-880Hz range limitation's real cost measured at 8.8% of real voiced content (2026-08-31)

Open-items list item 4's remaining task: Phase 27 implemented and validated pYIN
(RPA 50.6%->61.6%, voicing accuracy 77.8%->85.3% vs. plain YIN, measured on MDB-stem-synth) but
never wired it into `DNAReportBuilder.swift`'s real per-chunk pitch call, which still used plain
`YINEngine.analyze()`. The item also asked for the known 55-880Hz (4-octave) `PYINDecoder` window
limitation's real-world impact to be evaluated, not just noted as a caveat.

**Wiring**: `PitchResult` gained a `static func from(f0Series:)` factory (derives
`voicedFrames`/`meanF0`/`medianF0` from a raw NaN-for-unvoiced series, identical logic to what
`YINEngine.analyze()`'s tail already did) so `PYINDecoder.decode(candidatesPerFrame:)`'s `[Float]`
output — same NaN-for-unvoiced convention — slots into the same `PitchResult` shape every existing
consumer (`fullF0Series`/`ViterbiEngine.smoothPitchPath`, the report's meanF0/minF0/maxF0/
voiced-frame-ratio fields) already expects, with zero signature changes downstream. The per-chunk
loop now calls `YINEngine.analyzePYINCandidates` + `PYINDecoder().decode(...)` instead of
`YINEngine.analyze()`.

**Range-limitation impact, measured, not assumed**: `PYINDecoder`'s 480-bin HMM only represents
55-880Hz; anything outside is invisible to its emission model (`hzToBin` returns `nil`,
silently dropped) and gets pushed toward "unvoiced" regardless of what YIN's wider-range Stage 1
actually found. Measured directly from MDB-stem-synth's full ground-truth annotations (230 stems,
no audio decoding needed — pure CSV read of the already-known true f0 per frame):

```
8,651,723 true-voiced frames total
in [55, 880)Hz:  91.2%  (7,888,452)
outside:          8.8%  (763,271)  -- 6.5% too low (bass register), 2.4% too high
```

**Reading**: a real, non-trivial cost — roughly 1 in 11 true-voiced frames in this real-music-
derived corpus falls outside pYIN's representable window and would be forced toward "unvoiced"
in production, mostly on the low/bass side. Not a hidden regression, though: Phase 27's RPA/
voicing-accuracy comparison was measured on this SAME corpus (which already contains this 8.8%
of out-of-range material), and pYIN still won on both axes — so the net benefit already prices in
this cost. The honest characterization is a real, quantified trade-off (some genuinely low-bass or
very-high material will be mis-marked unvoiced where plain YIN might at least attempt a — possibly
still wrong — guess), not something to fix within this item's scope; a full fix would mean
widening `PYINDecoder`'s pitch-bin range beyond the paper's original vocal-range design target, a
separate, larger change not requested here.

**Status:** Phase 33 complete, fully verified. Targeted suite green: `AuditMetricsTests`/
`DNAReportBuilderHPSSTests`/`PYINEngineTests`/`ViterbiRealPipelineTests`/`YINEngineTests` (12/12,
all pass) — confirms pYIN's real per-chunk output flows correctly through the whole production
pipeline (HPSS/audit/Viterbi all still green against a changed pitch source). Full `swift test`
checkpoint (`YINEngine.swift`/`DNAReportBuilder.swift` are both widely shared): **133/133 tests
passed, 0 failures** (1390.1s, ~23 minutes) — no regression from switching production's pitch
source.

---

## 🎸 Phase 34 — InstrumentEngine's second frame-0-snapshot bug found and fixed; a session methodology note tightened to close a real overfitting loophole (2026-08-31)

While scoping the open-items list's new "polyphonic multi-instrument recognition" item, found a
second, independent instance of the exact bug class Phase 29 fixed in `StructureEngine`:
`DNAReportBuilder.swift`'s per-chunk `InstrumentEngine.predict()` call was fed `mfccSubset =
Array(mfccRaw.prefix(20))` — frame 0's 20 MFCC coefficients (the chunk's first ~23ms) — as "the"
MFCC representation for a whole 45-second chunk, while `spectral`/`lowBandEnergyRatio`/
`percussiveEnergyRatio` (the other three inputs to the same `predict()` call) are genuine
whole-chunk aggregates. Two independently-discovered instances of the same bug class across two
different engines is itself a signal worth tracking (a dedicated MFCC-input-integrity regression
test is now an open follow-up, not yet built).

**Fix**: average every frame's coefficients across the whole chunk (`mfccRaw.count / 20` frames,
mean per coefficient) instead of taking frame 0 alone — this single fix corrects both the report's
`TimbreMetrics.mfcc` field and `InstrumentEngine.predict()`'s input, since both consumed the same
`mfccSubset` variable. Reused the already-computed `mfccFrameCount` from the adjacent
`fullMFCCBins` accumulation (added in Phase 29) rather than recomputing it, avoiding a duplicate
declaration.

**RETRACTED (2026-08-31, caught before moving on to Stage 2 — see the follow-up section below):**
this DEVLOG entry originally reported an IRMAS/OpenMIC before/after re-measurement here
(`RA_IRMAS_PER_CLASS=300 RA_OPENMIC_LIMIT=3000`, IRMAS 28.5%->30.9%, OpenMIC 44.8%->44.4%) and
attributed the IRMAS change to this Phase's `mfccSubset` fix. **That causal claim was false.**
`Examples/ReliabilityAudit`'s `predictInstrument()` helper (what `runIRMASTask`/`runOpenMICTask`
actually call) never routes through `DNAReportBuilder.swift` at all — it builds its own
independent STFT/spectral/HPSS pipeline and gets MFCC from `MFCCEngine.createMFCC()`, whose
`.mfcc` field was already a correct whole-signal mean across frames (verified directly in
`MFCCEngine.swift:90-98`), never the frame-0-snapshot bug this Phase fixed. That bug lived only in
`DNAReportBuilder.swift`'s own separate MFCC computation. So the fix and the measurement never
touched the same code path — the measured IRMAS/OpenMIC delta was sampling noise from `thinned()`
selecting a different, smaller subset (n=3300/3000 vs. Phase 26's n=6705/13847), not evidence of
anything the fix did. **What stays true**: the `mfccSubset` frame-0 bug in `DNAReportBuilder.swift`
was and is real (unconditional, same class as the StructureEngine fix), and the code fix itself is
correct and unaffected by this retraction — only the specific "here is its measured production
impact" claim above was wrong, because no tool actually measures that path. See the follow-up
section immediately below for what this implies and what's next.

### Methodology note: the project's founding directive on academic datasets was ambiguous, and could have licensed exactly the failure mode this whole session's discipline has avoided

The user flagged that `~/Desktop/AudioIntelligence_Yapilacaklar.md`'s opening directive (added in
an earlier session, instructing that academic sources like MIREX/GiantSteps be used to "make the
engine produce the value it should") was genuinely ambiguous between two readings: (1) use these
datasets as held-out evaluation oracles to MEASURE real accuracy (what this session's actual
practice has consistently done — `PrototypeTrainer`'s OpenMIC train-partition, `StructureCalibration`'s
calibration/held-out split, pYIN's librosa-source-code-verified formula fix, none of which tuned
parameters against a single evaluation set's known answers), or (2) tune the engine's parameters
until it reproduces the known answer on the SAME set used to report accuracy — which would silently
convert every "measured" number in this project into an overfit, meaningless one, directly
contradicting the project's own "measured, not claimed" identity.

A self-audit of every measurement/calibration made this session (structure peak-picking, bass-note
wiring, pYIN wiring, this Phase's own IRMAS/OpenMIC re-measurement) found no violation — but the
audit itself was only possible because the ambiguity was raised and checked, not because the
original wording made the correct practice obvious. The note was rewritten to state the held-out-
vs-tune distinction explicitly, with concrete in-repo examples (`PrototypeTrainer`, `StructureCalibration`),
and extended to cover a subtler version of the same failure the user identified before it could
happen: **using a held-out set as a selection criterion among candidate hyperparameters/thresholds/
architectural variants is itself tuning to that set**, even without hand-forcing a specific value —
the moment a set is used to pick "whichever choice scores best," it stops being held-out. This is
directly relevant to open-items list item 2's Stage 2 (OpenMIC multi-label threshold recalibration,
not yet started): any threshold sweep there must happen on OpenMIC's TRAIN partition, with the
resulting F1 reported on the held-out test partition — never sweep thresholds by looking at
held-out scores directly, which would be the threshold-selection version of the same overfitting
error the MFCC-0-exclusion decision (Phase 26) deliberately avoided by using causal case-by-case
evidence instead of a held-out-score search.

**Status:** Phase 34 (the bug fix, open-items list item 2's Stage 1) complete and fully verified.
Targeted suite: `InstrumentEngineTests`/`InstrumentBaselineTests`/`AuditMetricsTests`/
`DNAReportBuilderHPSSTests` (8/8). Full `swift test` checkpoint (`DNAReportBuilder.swift` is
widely shared): **133/133 tests passed, 0 failures** (1506.1s, ~25 minutes) — no regression.
Open-items list item 2's Stage 2 (OpenMIC multi-label F1 measurement, conditional threshold
recalibration) is unaffected by this Phase and remains not started — its own methodology (train-set
threshold selection, held-out-set reporting) is now explicit in the project's own founding note.

---

## 🔍 Phase 35 — Auditing `ReliabilityAudit` itself: does the scorecard tool actually measure production? (2026-08-31)

Phase 34's retraction (an isolated evaluation helper couldn't have measured a bug that only lived
in `DNAReportBuilder.swift`'s separate wiring) raised a bigger question worth answering before
touching open-items list item 2's Stage 2: does `Examples/ReliabilityAudit` measure the real
production pipeline at all, anywhere, or does it consistently call engines in isolation? Audited
all 4 real (non-gap) tasks against `DNAReportBuilder.swift`'s actual wiring:

- **Tempo**: ✅ matches. `RhythmEngine.analyze(onsetResult:)` (production's real call) internally
  calls the exact same `RhythmEngine.estimateTempo(onsetStrength:sr:hopLength:)` static function
  `runTempoTask` calls directly — same computation, just skipping the beat-tracking steps a
  tempo-only measurement doesn't need.
- **Key**: ✅ matches, already deliberately verified in Phase 17 (nFFT=8192 chroma, matching
  production exactly — that phase's own fix was for this exact class of drift).
- **Instrument (IRMAS/OpenMIC)**: ⚠️ blind spot. `predictInstrument()` never routes through
  `DNAReportBuilder` — own independent STFT/MFCC/HPSS pipeline, MFCC via `MFCCEngine.createMFCC()`
  (always correctly frame-averaged, confirmed in Phase 34's retraction). Not actively wrong, but
  structurally unable to ever catch a `DNAReportBuilder`-side wiring bug like Phase 34's frame-0
  fix — this is exactly why Phase 34's before/after numbers on this task were meaningless evidence
  for that fix.
- **Pitch (MDB-stem-synth)**: ❌ actively stale. `runPitchTask` called plain `YINEngine.analyze()`
  — but Phase 33 switched `DNAReportBuilder.swift`'s real per-chunk pitch call to pYIN. The
  scorecard was reporting YIN's ~50% RPA as "current" while production had already moved to pYIN's
  ~62%. Not just an untested gap like instrument — an actively wrong "current" claim.

**Reading**: both a deliberate, reasonable design choice (calling individual engines directly
instead of running the full 30-engine `DNAReportBuilder` pipeline over 6,718-20,000 files each is
a real, justified performance decision) AND a real gap — nothing keeps these isolated call sites in
sync as production's own wiring evolves, and drift has now demonstrably happened at least once
(pitch, this same session).

### Fix 1: `runPitchTask` switched to pYIN, and given an official held-out measurement

`analyzePYINCandidates` + `PYINDecoder` (matching `DNAReportBuilder.swift`'s real call) replace
plain `YINEngine.analyze()`; the task now reports both RPA and voicing accuracy (previously RPA
only) as separate `TaskResult` rows, since voicing accuracy is pYIN's larger real gain over YIN.
This both re-syncs the tool AND provides pYIN's first *official*, scorecard-tracked measurement (a
larger, 60-stem run, vs. Phase 27's original 20-stem `PYINEngineTests` sample):

```
RPA<50cents: 62.4% (n=566,732)   [Phase 27, 20 stems: 61.6%]
voicing acc: 86.3% (n=123,881)   [Phase 27, 20 stems: 85.3%]
```

Consistent with Phase 27's original finding, now on a 3x larger sample — real, additional
confirmation, not just a re-run.

### Fix 2: a small, class-balanced production-vs-isolated parity check for instrument classification

Running the full `DNAReportBuilder` pipeline over IRMAS/OpenMIC's full 6,718/20,000-file corpora
isn't practical (that's exactly why the isolated tasks exist). Instead, added
`runInstrumentProductionParityCheck` (`RA_INSTRUMENT_PARITY=1`): a small, class-balanced,
held-out-only sample (25/class x 6 classes = 150 files) run through BOTH `predictInstrument()`
(isolated) and the real `AudioIntelligence().analyzeRawAggregate()` (production) on the exact same
files, comparing (a) whether the two paths agree on `primaryLabel`, and (b) each path's own
accuracy against ground truth. This is also, incidentally, the first REAL closing evidence for
Phase 34's frame-0 fix (the isolated path could never see it; this one does) — result in the next
DEVLOG entry once the run completes.

### Result: only 45.3% agreement, production 8.7pp worse than isolated — the frame-0 fix alone did not close the gap

```
evaluated=150 (single-coarse-class, held-out test partition)
agreement (isolated primaryLabel == production primaryLabel): 68/150 (45.3%)
isolated accuracy vs ground truth:   73/150 (48.7%)
production accuracy vs ground truth: 60/150 (40.0%)
```

Disagreements skewed systematically toward Piano/Keyboard and Bass (Acoustic/Electric) -- both
low-spectral-centroid classes -- and production occasionally returned "Unknown" (no profile
clearing the 0.3 threshold at all). A systematic directional skew plus outright non-classification
is not the signature of small numerical noise; it points at a real, structural mechanism, not
float-level GPU/CPU rounding.

### Eliminating the GPU/CPU hypothesis in one cheap run before investigating it

Before spending real time chasing a specific hypothesis, ran a discriminator: `predictInstrumentGPU`
-- byte-for-byte identical to `predictInstrument` except `STFTEngine`/`MelSpectrogramEngine`/
`MFCCEngine` are given `sharedMetalEngine` (matching production's real GPU construction) instead of
defaulting to CPU -- re-run on the same 150 files.

```
agreement isolated-CPU vs isolated-GPU: 150/150 (100.0%)
agreement isolated-GPU vs production:    68/150 (45.3%)  -- unchanged from isolated-CPU
```

GPU/CPU compute backend makes zero difference (confirming Phase 19's DCT-scale fix holds at the
label-decision level, not just the raw-coefficient level checked at the time) -- eliminated in
minutes rather than hours spent chasing the wrong layer.

### Feature-level dump finds the real mechanism: a sample-rate mismatch, not a subtle bug

Added `runInstrumentFeatureDump` (dumps `InstrumentEngine.predict()`'s exact inputs from both
paths for one file) and a matching gated diagnostic print in `DNAReportBuilder.swift`
(`AI_DEBUG_INSTRUMENT_FEATURES=1`). On one disagreement file (`004508_176640`, true=Strings/Synth):

```
                isolated      production
centroid        1473.6        1895.5      (+29%)
flatness        0.185         0.0125      (~15x LOWER)
lowBand         0.107         0.086       (-19%)
percussive      0.417         0.292       (-30%)
mfcc[2]         +4.5          -52.7       (SIGN FLIPPED)
mfcc[4]         +2.7          -47.4       (SIGN FLIPPED)
```

Differences this large (sign flips, 15x on flatness) are not GPU/CPU rounding -- they're the
signature of a structurally different analysis. `afinfo` on the file confirmed its native rate:
44100Hz, stereo. Checking the actual code: `predictInstrument()` (isolated) always calls
`AudioLoader.load(url:, targetSampleRate: 22050)`; `DNAReportBuilder.swift`'s real chunk decode
calls `AudioLoader.loadNextChunkStereoManual(..., targetSampleRate: inputFormat.sampleRate)` --
the file's OWN native rate, no resampling at all. Same nFFT=2048 at 44100Hz vs. 22050Hz roughly
halves the analysis window and doubles Nyquist -- a structurally different spectral analysis,
exactly matching the magnitude of divergence measured.

**The deeper problem**: `Examples/PrototypeTrainer` (which fit `InstrumentEngine`'s Fingerprint
profiles) *also* always resamples to 22050Hz. So the model was fit on a 22050Hz feature
distribution, but production was feeding it native-rate (typically 44100Hz) features -- a real
train/production mismatch, not just a measurement-tool blind spot. This would have been a live bug
even if `ReliabilityAudit` had never existed.

### Direction-determining measurement before fixing anything: which rate does the model actually prefer?

Two candidate fixes point opposite directions -- resample production to 22050Hz (if the model
performs better there), or retrain the model's profiles at native rate (if native performs
better) -- and picking wrong makes things worse, not better. Measured rather than assumed: the
same isolated pipeline (`predictInstrument`, unchanged), run at two internally-consistent rates
(every file in the 150-file sample loaded at 22050Hz, then the identical set reloaded at 44100Hz),
scored against ground truth:

```
accuracy @ 22050Hz (PrototypeTrainer's fitting rate): 73/150 (48.7%)
accuracy @ 44100Hz (typical native rate):             57/150 (38.0%)
```

22050Hz wins decisively (+10.7pp) in aggregate -- confirming (not assuming) that production should
resample to match the model's fitting rate. Per-class breakdown was NOT uniform (Piano/Keyboard
56%->84% and Vocals/Chorus 20%->44% actually improved at 44100Hz; Drums/Percussion 92%->32% and
Strings/Synth 44%->4% collapsed) -- an interesting, honestly-recorded observation (possibly:
Piano/Vocals' discriminative timbre partly lives above 11kHz, while Drums/Strings' high-frequency
content is comparatively more noise-like for this classifier) but NOT pursued further here -- the
aggregate verdict (22050 wins) is what determines the fix; a class-dependent-bandwidth refinement
is a separate, much later, unscoped idea, not this phase's job.

### Fix: a narrow, dedicated analytical-rate branch for InstrumentEngine only -- not a global resample

A global "resample everything in `DNAReportBuilder` to 22050Hz" fix was considered and rejected:
`LoudnessEngine`/`ForensicEngine`/`AudioScienceEngine` need native-rate fidelity for true-peak/LUFS
measurement (already validated to Δ≤0.08 LU vs. ffmpeg at native rate) -- downsampling before
measuring near-Nyquist content would likely have broken that guarantee outright, trading a real fix
for a new, unmeasured regression in a different, already-solid area.

Instead: `DNAReportBuilder.swift`'s chunk loop now decodes a SECOND, parallel buffer per chunk
(`analyticalChunk`, via a second `AudioLoader.loadNextChunkStereoManual` call at a fixed 22050Hz --
reusing the same production-grade `AVAudioConverter` resampling path already used elsewhere, not a
new hand-rolled resampler) alongside the existing native-rate `chunk`. `InstrumentEngine`'s entire
dependency chain (STFT, `SpectralEngine`, `MelSpectrogramEngine`, `MFCCEngine`, `HPSSEngine`'s
`percussiveEnergyRatio`, `lowBandEnergyRatio`) is now computed independently on `analyticalChunk`,
mirroring `Examples/ReliabilityAudit`'s `predictInstrumentGPU` construction exactly -- fed by this
chunk's real decoded audio instead of a whole-file load. Deliberately scoped narrow: the
independently-reported `allSpectral`/`TimbreMetrics.mfcc` fields (which other parts of the report
also read, beyond just `InstrumentEngine`) are untouched, still native-rate, so this fix cannot
have silently changed any OTHER already-reported metric. HPSS itself was checked for a native-rate-
validated guarantee before moving it (none found -- `DNAReportBuilderHPSSTests` only checks chunk
coverage, not harmonic/percussive separation quality against any ground truth; `HPSSEngineTests`'
own synthetic validation already uses 22050Hz) -- safe to move without risking anything measured.

### Real closing evidence: the 150-file check re-run after the fix

```
                                            before      after
agreement isolated-CPU vs production:      45.3%       88.7%
production accuracy vs ground truth:       40.0%       50.0%   (now slightly ABOVE isolated's 48.7%)
```

This is the actual closing evidence Phase 34's retracted claim was missing -- measured on the
identical 150-file, class-balanced, held-out sample, through the real production entrypoint.

### Collateral-damage checks (native-rate zone, should be untouched)

- `EBUReferenceValidationTests`/`ScientificAuditorTests`/`AES17ValidationTests`: 6/6 pass -- the
  Δ≤0.08 LU loudness guarantee is confirmed intact, not just assumed to be (these engines never
  touch `analyticalChunk`).
- Full `swift test` checkpoint (`DNAReportBuilder.swift` is widely shared): **133/133 tests passed,
  0 failures** (1386.4s, ~23 minutes) -- no regression anywhere else in the suite.
- Pitch (`runPitchProductionParityCheck`, new): isolated pYIN's whole-track mean F0 vs.
  production's real `analysis.pitch.meanF0`, 10 MDB-stem-synth files -- mean relative delta 1.6%,
  confirming (not assuming) Pitch was already correctly aligned (`runPitchTask` and
  `DNAReportBuilder.swift` both already use pYIN at native rate, no forced-22050 resample on either
  side, unlike Instrument's case).

### Scope note: Tempo, Key, and Structure share the exact same root cause, not yet fixed

Checked (not assumed) each analytical engine's actual fitting/validation rate against its real
production rate:

| Engine | Isolated/validation rate | Production rate | Status |
| :-- | :-- | :-- | :-- |
| Instrument | 22050 (`PrototypeTrainer`) | native | **fixed this phase** |
| Tempo | 22050 (`GoldenDatasetValidationTests`) | native | not yet fixed |
| Key/Chroma | 22050 (`GoldenDatasetValidationTests`) | native | not yet fixed |
| Structure | 22050 (`StructureCalibration`/`StructureEngineSALAMITests`, Phase 29) | native | not yet fixed |
| Pitch | native (`PYINEngineTests`) | native | confirmed matched, no fix needed |

GiantSteps (Tempo/Key's dataset) and SALAMI (Structure's dataset) were both confirmed natively
44100Hz via `afinfo`, same as the OpenMIC file that exposed Instrument's mismatch -- so Tempo, Key,
and Structure most likely carry the exact same train/production sample-rate mismatch Instrument
just had, unverified and unfixed. Phase 29's own StructureCalibration numbers are a special case
worth naming directly: they were calibrated at 22050Hz, so this same class of fix (once applied to
`StructureEngine`) would actually make Phase 29's calibration *newly valid* against production
rather than invalidating it -- production doesn't yet run at the rate Phase 29 calibrated for.

Deliberately not fixed in this phase -- the user's explicit caution: migrating Tempo/Key/Structure
in the same change as Instrument would make it impossible to attribute a regression (if any) to a
specific engine, mirroring exactly why the frame-0 fix and the sample-rate fix needed to be
verified as SEPARATE, individually-attributed causes rather than one bundled change. Each remains
an open, honestly-labeled follow-up with a known, concrete fix pattern (a second `analyticalChunk`-
style decode, migrating each engine's dependency chain one at a time, each with its own 150-file-
style closing evidence) -- not a mystery, just not yet done.

**Status:** Phase 35 complete for Instrument (fixed and verified) and Pitch (confirmed already
correct). Tempo/Key/Structure identified as carrying the same root cause, tracked as open follow-up
work, not fixed here.

---

## Phase 36 (2026-09-01): Tempo/Key/Structure sample-rate mismatch — direction measured per engine, NOT assumed; the fix was the opposite of Instrument's for two of the three

Direct follow-up to Phase 35's open item. The user was explicit going in: do not assume this is a
mechanical copy of Instrument's fix (resample the analytical branch to 22050). Instrument is a
fitted prototype-matcher, trained at 22050 -- Tempo/Key/Structure are algorithmic (onset
autocorrelation, chroma correlation, novelty peak-picking), with no training step to be consistent
with. Direction was measured for each engine independently, at full unthinned sample sizes, before
any code changed.

### Method

For each engine, the exact isolated pipeline (`GoldenDatasetValidationTests`'s onset/chroma path
for Tempo/Key, `StructureEngine.analyze()` with the Phase 29 `.calibrated` config for Structure)
was run at both 22050Hz and 44100Hz over the full annotated set, no `thinned()` subsampling:
GiantSteps' 43 MIREX-BPM tracks and all 599 MIREX-key tracks; SALAMI's same 15-track sample Phase
29 was calibrated against.

A live lesson landed mid-measurement: the first Key pass used a 60-track `thinned()` sample and
showed 44100 slightly ahead (+1.7pp). The full 599-track pass **reversed** that -- 22050 came out
ahead by +2.2pp. The 60-track read was noise, not signal, in the wrong direction. This is exactly
why direction gets measured at full scale before any conclusion is drawn, not estimated from a
convenient subsample.

### Results

| Engine | @22050Hz | @44100Hz (native) | Direction | N |
| :-- | :-- | :-- | :-- | :-- |
| Tempo | Acc1 58.1% / Acc2 69.8% | Acc1 69.8% / Acc2 81.4% | **native decisively better** (+11.7/+11.6pp) | 43 (full) |
| Key | exact 50.9% / MIREX 63.3% | exact 48.7% / MIREX 61.4% | 22050 slightly better (+2.2/+1.9pp) | 599 (full) |
| Structure | F@3.0s 41.1% (p=40.9 r=41.3) | F@3.0s 41.3% (p=36.1 r=48.3) | tied on F-measure, composition differs | 15 (full) |

Production for all three engines has never been touched -- it has always run at the file's native
rate (unlike Instrument, which was migrated onto a separate 22050 `analyticalChunk` branch in Phase
35). So the question these numbers actually answer is: was production wrong, or was the isolated
test wrong? For all three, it was the test.

### Tempo: production was already right; the test under-measured it (not a real improvement) -- plus a correction on the exact number, caught by the user

Tempo's onset-autocorrelation algorithm benefits from native-rate high-frequency content --
percussive transients (hi-hat, ride, snare attack) stay sharper at 44100Hz, giving cleaner onset
peaks and more accurate autocorrelation-period estimates than 22050Hz's mild low-pass/decimation
blur. This is the opposite of Instrument's case because Tempo has no training step to be consistent
with -- it's the raw signal quality that matters, and native has more of it. That's the explanation
for why this engine's correct rate is the opposite of Instrument's: one is a fitted model needing
train/serve consistency, the other is a from-scratch DSP algorithm that just wants more signal.

**Measurement evolution (corrected in place, not silently):**

1. Direction was first measured with `runTempoSampleRateComparison` (`Examples/ReliabilityAudit`),
   whose onset computation is `OnsetEngine(sampleRate: rate).onsetStrength(samples)` -- the exact
   same call `DNAReportBuilder.swift:186` makes in production (default SuperFlux + mel). Full
   43-track, unthinned result at 44100Hz: **Acc1 69.8% / Acc2 81.4%**. This number was reviewed and
   approved as the basis for the README update.
2. For "closing evidence" through the permanent test suite, `GoldenDatasetValidationTests.
   testGiantStepsKeyTempoAccuracy` was fixed to measure at native 44100Hz and re-run. It reported
   **Acc1 65.1% / Acc2 74.4%** -- a third, different number from either the old 22050 baseline or
   the just-approved 69.8%/81.4%. This got written into the README without being checked against
   step 1's number first. **That was the mistake:** two different measurements were treated as
   interchangeable without verifying they measured the same thing.
3. The user caught the discrepancy and asked where each number came from. Investigation found the
   real cause was not sample size or thinning -- it was an algorithm mismatch, independent of the
   sample-rate fix this phase was about. `testGiantStepsKeyTempoAccuracy` computed its onset
   envelope via `RhythmEngine.onsetStrength(from: stft)`, a simple linear-STFT rectified
   spectral-flux function. `grep -rn "RhythmEngine.onsetStrength" Sources/` confirms this function
   is called **nowhere in production code** -- it exists only in this one test. Production's real
   algorithm is `OnsetEngine`'s SuperFlux+mel (step 1's method). The two functions are genuinely
   different computations (mel-spectrogram multi-band flux with max-filtering vs. raw linear-STFT
   rectified difference), not two views of the same one -- this is why they gave different numbers
   at the *same* sample rate. This mismatch predates this phase; it was only surfaced now because
   the sample-rate fix required re-running this specific test and its number was checked against
   an independent measurement.
4. Fixed `testGiantStepsKeyTempoAccuracy` to call `OnsetEngine(sampleRate: sr).onsetStrength(...)`
   instead (matching `DNAReportBuilder.swift:186` exactly), removing the now-redundant standalone
   nFFT=2048 STFT it no longer needs. Re-ran the full 599-track suite: **Acc1 69.77% (30/43) / Acc2
   81.40% (35/43)** -- matching step 1's approved number (69.8%/81.4%) to within rounding. Key's
   numbers (48.75%/61.40%) are unaffected -- Key's chroma computation was never part of this
   mismatch.

**Final, verified number: Acc1 69.8% / Acc2 81.4%.** This is a measurement correction, not an
accuracy improvement -- production's tempo detection did not get better today; it was always this
good, and this is the first time it was measured correctly, through the algorithm production
actually runs. The 58.1%→69.8%/69.8%→81.4% jump in the README must not be read as "we fixed tempo"
-- nothing about `RhythmEngine.estimateTempo` or `OnsetEngine` itself changed; only which onset
function the *test* calls changed, to match what production always called.

### Key: 2.2pp measured, inside tolerance, left on the table on purpose

Two separate decisions here, not one:

1. **Does this trigger an architecture change (migrate Key onto its own analytical-22050 branch,
   like Instrument)?** No. +2.2pp exact / +1.9pp MIREX-weighted, at N=599, sits inside the
   established tolerance band ([[feedback-closure-tolerance-standard]]: >300 samples → 10pp
   acceptable gap). Instrument's fix closed a 45%→89% agreement gap and a 40%→50% accuracy gap --
   this is a different order of magnitude. Adding a second per-chunk analytical decode purely for
   Key, at real per-track compute cost, is not justified by a gain this small.
2. **What does the README report?** Production has always run Key at native rate, so the README
   must report what production actually produces: native's 48.75% exact / 61.40% MIREX-weighted
   (`testGiantStepsKeyTempoAccuracy`, full 599 tracks, now fixed to measure at native 44100Hz
   instead of the old forced 22050). This number is *lower* than the old 22050-measured 50.9%/63.3%
   -- an honest downward correction, the opposite direction from Tempo's.

These two decisions combine into a specific, deliberate engineering choice, and it's the choice
itself -- not just the corrected number -- that belongs in the record: **production leaves ~2.2pp
of measured Key accuracy on the table, on purpose, because the architecture cost of capturing it
(a second analytical-rate decode path, mirroring Instrument's) exceeds the value of a gain this
small relative to our own tolerance standard.** If someone re-measures Key at 22050 in six months
and gets 50.9%, sees production reporting 48.75%, and asks "why are we leaving accuracy on the
table" -- the answer is already here: it was measured, it was small, and taking it wasn't worth the
added architecture. This is not an unresolved discrepancy; it's a closed decision with its
reasoning attached.

### Structure: F-measure tied, but not identical underneath -- and that's now on record too

F@3.0s came back statistically equal (41.1% vs 41.3%, 15/15 tracks usable at both rates) --
**this equality is what confirms Phase 29's seconds-based `.calibrated` `StructurePeakPickConfig`
(waitSeconds/preAvg/postAvg etc.) correctly self-adjusts to native sample rate**, since those
parameters are expressed in seconds and converted to frame counts via hopLength/sampleRate
internally rather than being frame-count constants tuned at one specific rate. No recalibration is
needed, and this is now the specific measurement backing that claim (`testStructureEngine_
sampleRateComparison_onRealSALAMI`, new test in `StructureEngineSALAMITests.swift`) -- not an
assumption.

The F-measure equality hides a real composition difference the aggregate score can't see:
22050Hz is balanced (precision 40.9%, recall 41.3%), native is recall-weighted (precision 36.1%,
recall 48.3%) -- native finds more of the true boundaries but with a worse hit rate on what it
predicts. F stays flat because the precision loss and recall gain happen to offset. No action taken
now -- production is native and stays native, nothing here crosses the fix-it bar -- but if a
future product decision favors precision over recall (or vice versa) for Structure's boundaries,
this composition shift is the first place to look, and the measurement to re-run is already built.

### The bigger pattern across all three (plus Pitch, plus Instrument): test-rate ≠ production-rate, in either direction

Four times this session, an engine's isolated/validation test turned out to be measuring at a
different sample rate than its real production path:

| Engine | Isolated/test rate | Production rate | Who was wrong | Resolution |
| :-- | :-- | :-- | :-- | :-- |
| Instrument | 22050 (fitted) | was native, now 22050 (`analyticalChunk`) | **production** | migrated production to match the fitted rate (Phase 35) |
| Pitch | native | native | neither | confirmed already aligned (Phase 35) |
| Tempo | was 22050, now native | native | **the test** | fixed the test to match production (this phase) |
| Key | was 22050, now native | native | **the test** | fixed the test to match production (this phase) |
| Structure | 22050 (unchanged) | native | neither, in effect | F-measure equal at both rates, no fix needed, but confirmed rather than assumed |

The common root across every row is the same: nothing in this codebase enforces or checks that a
given engine's test/calibration sample rate equals its real production sample rate. The direction
of the mismatch (production wrong vs. test wrong) had to be independently discovered each time.
This has now surfaced by hand four times in one session. `Yapilacaklar.md` gets a new, separate
open item for a permanent test-vs-production sample-rate parity check (not built in this phase --
scope discipline; recorded so a fifth occurrence doesn't slip through silently).

**Status:** Phase 36 complete. Tempo and Key: `GoldenDatasetValidationTests.
testGiantStepsKeyTempoAccuracy` fixed to measure at native 44100Hz; README updated with the new
numbers and the measurement-correction-vs-improvement distinction for Tempo. Structure: no code
change, calibration-validity claim now backed by an explicit same-config two-rate measurement.
Tempo's number went through one in-place correction after the user caught a discrepancy between
the approved direction-measurement (69.8%/81.4%) and the first XCTest closing-evidence run
(65.1%/74.4%) -- root cause was an independent onset-algorithm mismatch in the test (not the
sample-rate fix itself), now also fixed; final verified number is Acc1 69.8% / Acc2 81.4%, matching
the originally-approved measurement. Yapilacaklar.md item 3 closed with per-engine evidence; new
item opened for the durable sample-rate parity check.

---

## Phase 37 (2026-09-01, pre-registration): Instrument Stage 2 (OpenMIC multi-label F1) — proxy-legitimacy threshold fixed BEFORE running Step A

Open item 2's Stage 2 (multi-label F1 against OpenMIC's real ground truth) starts here. Before
writing any measurement code, three methodology gaps were closed:

**1. Found and fixed a second production bug while designing the check, not as part of it.**
`DNAReportBuilder.swift` (previously line 866) truncated the production-exposed
`InstrumentMetrics.predictions` to `.prefix(5)`, even though `finalInstruments` can never exceed 6
entries (`instrumentAccumulator` is keyed by label, and `InstrumentEngine.profiles` has exactly 6
coarse classes). No comment or git history anywhere justifies capping below the maximum possible
population -- this reads as an arbitrary leftover (a generic "top-5" idiom applied to a 6-class
domain), not a deliberate product decision. Left in place, it would have (a) made the multi-label
agreement check misdiagnose a truncation artifact as a real isolated-vs-production divergence on
any clip where all 6 classes crossed threshold, and (b) silently dropped a true positive from
every real API consumer on such a clip, artificially lowering recall for whichever class landed
6th. Fixed: `return InstrumentMetrics(predictions: finalInstruments, primaryLabel: ...)`, no cap.
Verified: `swift build -c release --product ReliabilityAudit` succeeds.

**2. The existing 88.7% agreement number does not cover what Stage 2 needs.**
`runInstrumentProductionParityCheck`'s 88.7% (Phase 35) compares only `primaryLabel` (top-1
argmax) between isolated and production. Stage 2's F1 depends on the FULL predicted label set --
including secondary labels that cross the 0.3 threshold without being the top pick. Argmax
agreement and threshold-crossing agreement are different questions; the latter is inherently
noisier (profiles near 0.3 can flip on small feature differences) and has never been measured.
Reporting one blended "Jaccard similarity" number would hide exactly this: primary could measure
95% while secondary measures 60%, and Stage 2's whole value is in the secondary labels (that's
what makes it multi-label instead of single-label). So Step A measures primary and secondary
agreement SEPARATELY, not as one pooled figure.

**3. Ground-truth partial-label handling, verified against OpenMIC's official arrays.**
`openmic-2018-aggregated-labels.csv` was previously parsed for positives only (relevance≥0.5),
discarding which (clip, instrument) pairs were reviewed-and-negative vs. never-reviewed. Rebuilt
to track all three states (positive / known-negative / unknown) and cross-checked the
reconstruction against the official `openmic-2018.npz`'s `Y_true`/`Y_mask`: 41,268/41,268 known
pairs match exactly, 5-pair rounding disagreement at the 0.5 boundary (negligible). Coarse-level
aggregation extends the existing OR-for-positive convention (`openmicToCoarse`'s
`fine.flatMap { ... }`) symmetrically: a coarse class is positive if any mapped fine label is
positive; known-negative if any mapped fine label was reviewed and none was positive; unknown
(excluded from F1 entirely -- not counted as TP/FP/FN/TN) if no mapped fine label was ever
reviewed for that clip. Real counts in the held-out test partition (5,085 clips) confirm no
sample-size problem: even the smallest class (Bass) has 134 positive + 329 known-negative = 463
evaluable clips; the rest have 900-3,000+.

**Proxy-legitimacy threshold -- fixed now, before Step A runs, specifically so the result cannot
retroactively influence the criterion:**

Step A measures per-class agreement (isolated vs. production, full label set, i.e. does each
path's above/below-0.3-threshold decision for each of the 6 coarse classes match, on a
~30-per-class held-out-test sample). The isolated path is a legitimate proxy for Stage 2's
larger-scale F1 measurement **if and only if every one of the 6 coarse classes' per-class
agreement is ≥85%.** A class scoring below 70% is separately flagged as "collapsed" -- a stronger
failure than a borderline miss, useful for diagnosis, but any class below 85% already fails the
overall legitimacy bar regardless of the 70% flag. If all 6 clear 85%: proceed to Stage 2's F1
measurement on the isolated path at a larger sample, documented as a proxy backed by this specific
number. If any class fails: stop, do not compute a proxy-based F1 for that class (or at all, if
the failure looks systemic) -- investigate the specific divergence first, the same way Phase 35's
initial 45.3% agreement was investigated rather than accepted.

**Status:** threshold and methodology fixed; Step A not yet run. Results and the pass/fail verdict
against this pre-registered threshold will be appended below, not used to adjust the threshold
itself.

### Step A results (measured against the threshold above, not the other way around)

`runInstrumentMultiLabelParityCheck`, 180 held-out-test files (30/class × 6 classes), isolated
(CPU) vs. real production (`DNAReportBuilder` via `AudioIntelligence().analyzeRawAggregate`),
full multi-label prediction set on both sides:

| | agreement |
| :-- | :-- |
| primaryLabel (argmax) | 168/180 (93.3%) -- re-confirms, doesn't just repeat, Phase 35's 88.7% (different sample) |
| secondary-label only (non-top-1 in either path) | 847/892 (95.0%) |
| mean per-clip Jaccard (informational) | 93.7% |

| class | agreement | verdict |
| :-- | :-- | :-- |
| Piano/Keyboard | 178/180 (98.9%) | PASS |
| Bass (Acoustic/Electric) | 172/180 (95.6%) | PASS |
| Brass/Trumpet | 170/180 (94.4%) | PASS |
| Vocals/Chorus | 168/180 (93.3%) | PASS |
| Drums/Percussion | 176/180 (97.8%) | PASS |
| Strings/Synth | 171/180 (95.0%) | PASS |

All 6 classes clear the pre-registered 85% bar, with margin (lowest is Vocals/Chorus at 93.3%,
still 8.3pp above the bar). **The specific worry the threshold was designed to catch --
secondary/threshold-crossing labels agreeing worse than the primary argmax -- did not happen**:
secondary agreement (95.0%) is if anything slightly higher than primary (93.3%), not lower. No
class shows any sign of the "high average hides one collapsed class" failure mode this whole
check was built to catch.

**Verdict: PASSES.** The isolated path is a legitimate, evidence-backed proxy for Stage 2's
larger-scale OpenMIC multi-label F1 measurement. Proceeding to Step B.

### Step B results: real multi-label F1, and why Stage 2 stays OPEN, not closed

`runInstrumentMultiLabelF1`, full held-out test partition (5,085/5,085 clips, 0 load failures,
isolated path -- legitimate proxy for production per Step A above, run after the `.prefix(5)`
truncation fix). Ground truth: three states per (clip, fine-instrument) -- positive
(relevance≥0.5), known-negative (reviewed, relevance<0.5), unknown (never reviewed, excluded
entirely from F1, never counted as negative) -- aggregated to coarse level via `openmicToCoarse`'s
existing OR-for-positive convention, extended symmetrically for known-negative. Cross-validated
against an independent Python reconstruction of the same CSV (itself verified against OpenMIC's
official `Y_true`/`Y_mask`, 41,268/41,268 exact match): for all 6 classes, TP+FN and FP+TN from
the Swift run match the Python positive/known-negative totals exactly (e.g. Piano 749+228=977,
590+413=1003, both exact) -- strong evidence the aggregation logic is correct, not coincidental.

| class | TP | FP | FN | TN | precision | recall | F1 |
| :-- | --: | --: | --: | --: | --: | --: | --: |
| Piano/Keyboard | 749 | 590 | 228 | 413 | 55.9% | 76.7% | 64.7% |
| Bass (Acoustic/Electric) | 123 | 220 | 11 | 109 | 35.9% | 91.8% | 51.6% |
| Brass/Trumpet | 614 | 864 | 147 | 403 | 41.5% | 80.7% | 54.8% |
| Vocals/Chorus | 206 | 71 | 18 | 79 | 74.4% | 92.0% | 82.2% |
| Drums/Percussion | 564 | 224 | 142 | 259 | 71.6% | 79.9% | 75.5% |
| Strings/Synth | 1488 | 1168 | 204 | 311 | 56.0% | 87.9% | 68.4% |

**Macro-F1: 66.2%.** Labeled here as **production-representative** (not merely an isolated-engine
number), because Step A's per-class agreement check (all 6 classes ≥85%, see above) was measured
AFTER the top-5 truncation fix and specifically validates that the isolated path's full label set
matches what production actually returns.

**The finding: recall is high and uniform (76.7%-92.0%, every class, no exceptions); precision is
low and volatile (35.9%-74.4%).** This is not noise -- the same asymmetry appears in all 6 classes
independently, with no counter-example. It directly measures what open item 2 Stage 2's own
closure note only suspected: *"0.3 eşiği tek-etiket rejimi için ayarlanmış olabilir; çoklu-etikette
çok fazla ... yanlış davranabilir."* It does. The finding also resolves an apparent contradiction
with open item 4 (Brass/Trumpet argmax recall measured at 5%, OpenMIC held-out): 80.7%
threshold-crossing recall + 5% argmax recall are consistent, not contradictory -- Brass/Trumpet's
profile clears 0.3 often, it just rarely wins the argmax against a higher-scoring competitor on
the same clip. Confirms items 2-Stage-2 and 4 are measuring genuinely different things (absolute
threshold-crossing vs. relative ranking) and should stay separate items, not be merged.

**Framing, deliberately: this is a wrong OPERATING POINT, not an engine failure.** High
recall/low precision is what a threshold set too low for the regime it's being used in produces --
not evidence the underlying scoring is broken. The fix implied is moving the threshold (likely
per-class, given precision varies 35.9%-74.4% across classes -- a single global threshold cannot
be right for all of them at once), not redesigning `InstrumentEngine`. Raising the threshold would
trade recall for precision; which trade is correct depends on product intent (for a
recommendation-style output, showing a wrong instrument is probably costlier than missing one,
i.e. precision likely matters more than recall here) -- a product decision, not something this
measurement can answer on its own.

**Why Stage 2 does NOT close here:** open item 2's own stated closure condition was "eşik
çoklu-etikette iyi çalışıyorsa madde kapanır; bozuksa hedefli kalibrasyon gerekir." This
measurement answered that question -- the threshold does not work well in the multi-label
regime -- so by the item's own logic, closure requires the calibration, which has not been done.
**Deliberately not done in this phase**: searching the calibration on this same 5,085-clip
held-out set the F1 above was measured on would be exactly the held-out-contamination the
methodology notes forbid -- any threshold search must run on OpenMIC's TRAIN partition only, with
F1 re-reported on held-out afterward, or the 66.2% (and everything derived from a re-tuned
threshold) becomes meaningless as an evaluation number. Tracked as new, separate Yapilacaklar.md
open item (per-class threshold recalibration, train-search/held-out-report discipline,
precision-priority operating point, NOT started).

**Status:** Stage 2 measured, not closed. Macro-F1 66.2% (production-representative, per Step A).
Precision/recall asymmetry recorded as Stage 2's substantive finding. New follow-up item opened
for threshold recalibration; not built this phase.

---

## Phase 38 (2026-09-01): Instrument multi-label confidence calibration — fit, a self-check catching a real bug on its first run, and robust closing evidence

Direct follow-up to Phase 37's threshold-recalibration item. Design was fixed before any fitting
code was written: method by train sample size (n<600 -> Platt, n>=600 -> isotonic, chosen for
Strings/Synth's climb-then-plateau shape a sigmoid would misfit), fit on OpenMIC's official train
partition only (bounded to an OOM-safe 5,000-clip evenly-thinned sample, same mitigation as the
earlier full-corpus SIGKILL), validated on the full 5,085-clip held-out partition -- code-level
separation, `split01_test.csv` never read inside the fitting code path.

### Pre-check: is each class's raw score even calibration-amenable?

Before fitting anything, checked whether each class's raw (unthresholded, `predictWithBreakdown`)
score carries genuine monotonic signal, via AUC on the train partition (5,000-clip bounded sample,
same OOM-safe limit). No class was flat: Vocals 0.839, Drums 0.784, Bass 0.691, Brass 0.629, Piano
0.627, Strings/Synth 0.577 (weakest, but still real -- its own bin table climbs from 36.9% to a
~55-59% plateau, not flat). Calibration is legitimate for all 6 classes; none needed routing to
item 4/5 as a pure profile-quality problem instead.

### A sign bug, caught by the exact self-check this whole approach exists to justify

The first `fitPlatt` run had a real gradient sign error: `diff = pr - t` where the correct
derivative (from `NLL = softplus(z) - (1-t)*z`, verified by hand) is `t - pr`. Isotonic regression
can't have this bug -- pool-adjacent-violators enforces non-decreasing output by construction --
but Newton's method on the flipped gradient climbed the loss instead of descending it. This was
invisible in the isotonic classes' output and would have been easy to miss by eye in Platt's,
too: the first run's held-out numbers (Bass AUC 0.712 raw -> 0.346 calibrated, Vocals 0.826 ->
0.280 -- calibration making both classes *worse than chance*) were sitting in a wall of otherwise-
plausible-looking numbers.

**The AUC-invariance self-check caught it immediately and mechanically, no human inspection
required**: calibration is a monotonic transform, so AUC must not move; 0.712 -> 0.346 is not a
small drift, it's impossible for a correctly-implemented monotonic fit, and the self-check flagged
it the moment the corrected code re-ran on the (cheap) train partition -- before the expensive
held-out run even started. This is the concrete argument for open item 8 (test-production /
invariant-testing infrastructure): this session caught five instances of "the measurement doesn't
actually measure what it claims to" by hand (frame-0, sample-rate, onset-function, a missed Step A
report, and now this sign bug) -- this is the first time the *tool itself* caught one, on its first
run, without a human re-deriving the math from the output. That is what item 8 is worth building
more of, not a one-off scare.

Fix: L2-regularized, damped (backtracking line search) Newton's method, plus the sign correction.
Verified on synthetic data shaped like Bass (n=440, moderately separable) before re-running the
real ~30-minute pipeline -- cheap synthetic check first, expensive real run second, the same
discipline as every other verify-before-trust step this session. Also added a permanent train-side
AUC self-check (`RA_INSTRUMENT_CALIBRATION`'s own output) and a standalone synthetic regression
probe (`RA_PLATT_SELFTEST=1`) so this exact bug class can't silently reappear.

### Corrected results

Train fit (5,000/14,915 clips, method chosen by size):

| class | n | method | ECE raw->calibrated (train) | AUC raw/cal (train) |
| :-- | --: | :-- | :-- | :-- |
| Piano/Keyboard | 2043 | isotonic | 0.121 -> 0.000 | 0.627 / 0.635 |
| Bass | 440 | Platt | 0.177 -> 0.020 | 0.691 / 0.691 |
| Brass/Trumpet | 1907 | isotonic | 0.080 -> 0.000 | 0.629 / 0.638 |
| Vocals/Chorus | 407 | Platt | 0.185 -> 0.061 | 0.839 / 0.839 |
| Drums/Percussion | 1168 | isotonic | 0.129 -> 0.000 | 0.784 / 0.792 |
| Strings/Synth | 3094 | isotonic | 0.121 -> 0.000 | 0.577 / 0.585 |

**Closing evidence** (full held-out partition per class, 374-3171 samples -- not a single bin):

| class | n (held-out) | ECE raw -> calibrated | AUC raw/cal |
| :-- | --: | :-- | :-- |
| Piano/Keyboard | 1980 | 0.109 -> 0.015 | 0.632 / 0.629 |
| Bass | 463 | 0.160 -> 0.026 | 0.712 / 0.712 |
| Brass/Trumpet | 2028 | 0.075 -> 0.019 | 0.619 / 0.613 |
| Vocals/Chorus | 374 | 0.149 -> 0.043 | 0.826 / 0.826 |
| Drums/Percussion | 1189 | 0.140 -> 0.046 | 0.754 / 0.751 |
| Strings/Synth | 3171 | 0.139 -> 0.026 | 0.558 / 0.560 |

**Cross-class ECE spread (max-min, held-out, full n): 0.085 -> 0.031.** AUC invariance holds
(within isotonic's expected small tie-collapse) -- confirming the fit is a true monotonic
recalibration, not a distortion. No train/held-out ECE gap exceeded the 0.05 overfit-watch
threshold for any class, including Bass, the smallest and highest-risk one.

An earlier version of this evidence used a single confidence≈0.6 point (before/after spread
41.1pp -> 22.5pp). That table is kept in the tool's output but explicitly demoted to
"illustration only" -- its per-class "after" n's (14-16-45-60) are too small to be closing
evidence on their own, and calibration remaps which clips even fall in a fixed confidence window,
so it isn't a clean same-population before/after the way the full-curve, same-partition ECE
comparison above is. The ECE spread is the real evidence; the single-point table is illustrative
of the same effect, not proof of it.

**Strings/Synth stayed "honest but low-ceiling" as predicted**: its ECE improved as much as any
other class (0.139->0.026), but its AUC (0.558-0.560) is unchanged and remains the lowest of the
6 -- calibration made its confidence values truthful, it did not and could not raise its underlying
separating power. Raising that ceiling is an `InstrumentEngine` profile-quality question (open item
5), explicitly out of this item's scope.

### Status and what's still open

Item 3 (multi-label threshold recalibration) is **closed as a measurement/calibration-design
deliverable**: the fit-validate-self-check loop is built, a real bug in it was caught and fixed
using the loop's own invariant, and the closing evidence (cross-class ECE spread) is robust
(full-n, same-partition, not a noisy single point).

**Not done, and deliberately separated out**: wiring these calibration parameters into
`InstrumentEngine`'s actual production output (`predict()` returning calibrated confidence instead
of the raw component sum). Everything in this phase is measurement/audit layer
(`Examples/ReliabilityAudit`) -- production code was not touched. Wiring is real, separate work
with its own risk (it changes `InstrumentPrediction.confidence` for every consumer of the public
API) and needs its own explicit decision, tracked as a new open item. One thing already verified,
not left to check later: the calibration was fit on features from `predictInstrumentBreakdown`,
which calls `AudioLoader.load(url:, targetSampleRate: 22050)` -- the same 22050Hz rate
`DNAReportBuilder.swift`'s `analyticalChunk` branch feeds `InstrumentEngine` in production (Phase
35's fix). Fit-rate and serve-rate are already consistent; this does not need to be re-checked when
wiring happens, only re-confirmed if that analytical-feed architecture ever changes.

Also unchanged, deliberately: the 0.3 inclusion threshold (Phase 37's finding that raising it would
destroy recoverable-by-consumers-only information stands; calibration fixes what confidence means,
not which labels get included at all).

---

## Phase 39 (2026-09-02): Wiring instrument calibration into production, and a same-input identity check that caught a real loading-path bug

Direct follow-up to Phase 38's deliberately-deferred item: `InstrumentEngine.predict()` now returns
calibrated confidence (`InstrumentCalibration.calibrate(label:rawScore:)`, new file) instead of the
raw component-sum. `primaryLabel`/inclusion ordering is deliberately still decided on the RAW score
(sorted before calibration is applied) -- calibration was fit and validated as a confidence-meaning
correction, not a re-ranking signal, and changing what determines `primaryLabel` would silently
invalidate all of that phase's ranking-dependent evidence (Phase 35 production-parity, item 4's
recall numbers). Only the reported number changes; which label wins and which labels are included
are both untouched, matching the doc comment on `InstrumentCalibration.swift`.

### The wiring's own closing evidence: a same-input identity check, and what it caught

The standard this session held itself to: wiring calibration into `predict()` is not "closed" just
because the fit's own held-out ECE/AUC numbers looked good (Phase 38) -- that only proves the FIT
is good, not that production actually *uses* it correctly. The closing evidence has to be
`InstrumentEngine`'s actual production output, on the same clips, compared against the offline
fit's own calibrated value. `RA_INSTRUMENT_CALIBRATION_WIRING_CHECK=1` does exactly that: re-fits
the offline models (train partition), then for each held-out clip calls production's real
`AudioIntelligence().analyzeRawAggregate()` and the offline `predictInstrumentBreakdownProductionMix`
side by side, comparing calibrated confidence for the same (clip, class) pair.

**First run of this check failed** (82 of ~138 pairs mismatched, max |offline-production| = 0.194)
-- not a calibration-math bug, a loading-path bug: the offline comparison path was mixing stereo to
mono via `AudioLoader.load()`'s internal `AVAudioConverter`, while production's `analyticalChunk`
mixes explicitly (`(L+R)*0.5` via vDSP) after per-channel resampling. Those two mono-mixdowns are
not numerically identical. Fixed by making the offline side call the same explicit mixdown
production uses. This also invalidated Phase 38's original calibration fit (it was trained on the
converter-mixdown's scores) -- refit on the corrected loading path; the new fit's closing evidence
(cross-class ECE spread 0.075 -> 0.048, every class's own ECE dropped individually) is what's
embedded in `InstrumentCalibration.swift` now, and is what Phase 38's table above predates.

**Re-run after the mixdown fix**: 138 pairs evaluated, max residual dropped ~500x (0.194 -> 0.00038,
16 mismatches), all of them confined to the two Platt classes (Bass, Vocals) and none to isotonic --
informative rather than concerning, since Platt's smooth continuous curve reflects any nonzero
raw-score gap proportionally while isotonic's flat blocks absorb one unless it crosses a block
boundary. Root-caused the remaining gap to a second, smaller loading-path difference: the offline
comparison's whole-file loader (`AudioLoader.loadStereo`) sized its buffer from `totalFrames`, while
production's `loadNextChunkStereoManual` sizes it from the actual chunk's `frameLength` -- fixed by
switching the offline comparison to call `loadNextChunkStereoManual` directly, matching production's
exact low-level call.

**Re-run after the loader fix**: max residual 0.00208 (55/138 pairs), smaller per-clip for Bass
(~1e-5, down another order of magnitude from 0.00038) but newly present in Piano/Keyboard
(isotonic) at a few clips. First checked whether this was actually a regression before accepting
any explanation for it: `maxDiff` in the identity-check code (`Examples/ReliabilityAudit/main.swift`)
is updated unconditionally for every evaluated pair, before the mismatch-recording branch -- so the
printed max is a true max over all 138 evaluated pairs (all 55 mismatches, not just the 20 the tool
prints detail for), not a sampled or best-case number. Both 0.00038 and 0.00208 are therefore
complete-coverage bounds.

The candidate explanation -- that the offline side re-fits its isotonic/Platt models fresh from
that run's training scores every time this check runs, and that this codebase already has a
documented, independent source of sub-percent run-to-run noise (the AUC self-check section above,
and an earlier phase's finding that AVFoundation's decode/resample path is not guaranteed bit-exact
across runs) -- was **verified, not accepted on plausibility alone**, precisely because this same
turn had already found two real bugs that a "probably just noise" read would have missed
(converter-mixdown, buffer-sizing). Checked directly: two of the mismatched Piano offline values
(`y=0.6010928961748634` and `y=0.53125`) do not match any block `y` in the Piano isotonic model
currently embedded in `InstrumentCalibration.swift` -- meaning this run's offline re-fit produced a
measurably different isotonic curve, not merely a boundary-adjacent raw score evaluated against the
*same* curve. That confirms real run-to-run non-reproducibility in the fit itself (contradicting the
tool's own `=== Re-fitting (deterministic) ===` banner text, now scare-quoted to
`(\"deterministic\")` with a comment pointing at this section, since the claim is demonstrably
false),
not just a hypothesis consistent with the numbers. Platt (Bass) has no comparable block-boundary
sensitivity, which is why its residual shrank smoothly instead of shifting sideways like Piano's.

**Closing standard, fixed before this last run, not after, and closure rests on it -- not on the
noise explanation above**: `Estimated`/CLI confidence is exposed to consumers rounded to the
nearest whole percent (`pct()`: `Int((x*100).rounded())%`), so any residual under 0.005 can never
change what a consumer sees. Both the 0.00038 and 0.00208 complete-coverage maxima clear that bar
with more than 2x margin. This is closed at consumer-visible precision, not at floating-point
equality -- floating-point equality between two independently-refit models was never the right bar,
confirmed above to be unreachable in practice for isotonic classes.

**Consequence for future readers, recorded so it isn't rediscovered as a regression**: because the
fit is measurably sensitive to decode noise, the parameters embedded in `InstrumentCalibration.swift`
are a snapshot of one specific fit run, not a value guaranteed to be reproduced exactly by a future
re-fit. Re-running `RA_INSTRUMENT_CALIBRATION` later and getting slightly different block values is
expected, not a bug -- the thing that would actually need attention is the resulting residual
against a re-run of the wiring identity check exceeding the 0.005 bound above, not the parameters
themselves changing.

### Status

Item 3 (multi-label confidence calibration) is now **fully closed, fit through production wiring**:
`InstrumentEngine.predict()` returns calibrated confidence; the wiring was verified against
production's actual output, not assumed from the fit's own numbers; two real loading-path bugs were
caught and fixed by that verification (converter-mixdown vs. explicit mixdown; whole-file buffer
sizing vs. per-chunk); and the remaining residual is bounded, explained, and below the precision at
which any consumer could observe it.

**Filed separately, bigger than item 3**: this phase didn't just bound a residual, it turned a
standing hypothesis into a measured fact. Phase 15 item 1 (`InstrumentEngine` non-determinism)
hypothesized AVFoundation's decode/resample path is not bit-exact run-to-run, and worked around it
with graded scoring so near-ties collapse below the visible threshold -- a mitigation, not a fix
for the underlying noise. This phase directly measured that same noise moving calibration fit
parameters between two nominally-identical re-fits (two Piano isotonic block values that don't
exist in the other run's model). **Decode-noise is now a confirmed, load-bearing property of this
codebase, not a plausible-sounding explanation reached for once**: anything downstream of MFCC/raw
audio decode -- calibration fit included -- inherits it, and is only as stable as the margin
between its own noise and whatever threshold or tie-breaking absorbs it (Phase 39's 0.005 for
calibration; the graded-scoring near-tie collapse for classification). This is a reproducibility
*bound*, not a fixed reproducibility guarantee, and is worth its own line wherever this codebase's
open items are tracked outside DEVLOG, not just the note left on `InstrumentCalibration.swift` and
in this section: *decode-noise is proven, not hypothesized (Phase 39); every MFCC-derived parameter
in this codebase is bounded-not-guaranteed reproducible by it.*

---

## Phase 40 (2026-09-02): 4-note jazz-extension chord degradation — root cause found and measured, fix deferred

Direct follow-up to the open item flagged when `ChordEndToEndSyntheticTests` first ran (Phase 30):
real-audio end-to-end chord identification lands at 57-58/108 vs. idealized chroma's 77/108, and
the gap is not evenly spread — 4-note jazz-extension chords (dom7/m7/m7b5/m6) are nearly all wrong
while plain triads are almost untouched. Two candidates were on the table, neither measured: STFT
spectral leakage from unwindowed pure tones, or `identifyTriad` being generically fragile to
non-ideal chroma.

**Method: a throwaway diagnostic, not a guess.** Added a temporary test
(`Tests/ChordFourNoteDiagnosticTests.swift`, deleted after use) that runs the exact same
synthesis -> STFT(8192) -> `ChromaEngine` pipeline `ChordEndToEndSyntheticTests` uses, but dumps
the raw mid-clip chroma vector and `identifyTriad`'s winning (root, type, score) instead of just
the final classification. This is the same "cheap, disposable measurement before conclusion"
discipline as Phase 38's synthetic Platt self-test — build the smallest thing that can falsify a
hypothesis, not the fix itself.

**Finding: not leakage, not fragility — a real, structural scoring gap.** For a synthesized C
dominant-7 (C-E-G-A#, pure sine tones, equal synthesis amplitude), the chroma at the true chord
tones is `[0.4529, 0.4891, 0.5015, 0.4996]` (C, E, G, A# respectively) -- `identifyTriad`'s own
0.4-per-tone-average threshold is comfortably cleared (avg 0.4858). The chroma vector is not
corrupted or noisy in any qualitative sense. The failure is a scoring COMPETITION: dropping the
chord's own root (C, the weakest of the four real tone values -- not by assumption, measured) and
averaging only the remaining three (E, G, A#) yields 0.4967, higher than the true 4-note average,
because those three already-strong bins are no longer diluted by the comparatively weaker root.
`identifyTriad`'s pure `>` argmax has no mechanism to prefer a candidate that accounts for MORE of
the chord's active energy — it picks whichever raw average is numerically larger, full stop. The
winning wrong answer is `E diminished` (E-G-A#), a literal 3-of-4-note subset of the true chord.

Verified this is the general mechanism, not a one-chord coincidence, by tracing all 12 roots: dom7
fails 10/12, m7 10/12, m7b5 11/12, m6 10/12 -- every failure resolves to the same pattern, a
subset/relative-chord candidate numerically outscoring the true chord. `maj7` is the one 4-note
quality that passes 12/12 -- its own 3-note subsets (dropping the root yields a minor triad on the
major third) never happen to outscore it in this synthesis, which is itself consistent with the
mechanism (no subset always wins; it depends on which tone in a given chord shape happens to carry
less real energy) rather than contradicting it.

**This is not a new class of bug -- it's the SAME "relative-chord-superset" ambiguity
`ChordScoringAmbiguityTests` already named and measured on idealized chroma (23 of that test's 31
mismatches).** The only thing real audio changes is the margin: on idealized chroma (every chord
tone exactly 1.0), a 4-note chord and its 3-note subset score an exact tie, and Phase 31's
bass-note tie-break (`identifyTriad`'s `bassNote` parameter, `tieEpsilon = 0.001`) resolves it
correctly. On real audio, chord-tone magnitudes are never bit-equal, so the subset doesn't tie the
full chord — it wins outright, by a margin (0.0109 in the C7 example) that clears
`tieEpsilon` by 10x, so the existing tie-break mechanism never fires. Same known ambiguity class,
already-built partial mitigation, just not wide enough for real-world (non-ideal) margins.

**Re-measured with the current codebase** (Phase 31's bass-note wiring already in place): 58/108
(53.7%) end-to-end, 50 mismatches (9 augmented-symmetry, already-understood and unrelated; 41
other, all attributable to this mechanism) -- a small drift from the 57/108 figure recorded when
this item was first opened, plausibly downstream of Phase 31's own bass-note changes, not a new
regression.

### Status: root cause closed as a measurement, fix explicitly deferred by user decision

Presented three candidate fixes, un-implemented, for a future turn:

1. **Subset-preference rule** (most targeted, provisionally lowest-risk-LOOKING -- not yet
   measured, see caveat below): when candidate B's chord-tone set is a literal subset of a
   higher-scoring, threshold-clearing candidate A's set, prefer A. This is a NEW, separate
   comparison (subset-containment between two already-fully-scored candidates), not a widening of
   `identifyTriad`'s existing `tieEpsilon`/bass-note tie-break -- see the framing caveat below for
   why that distinction is load-bearing, not cosmetic.
2. **Explained-energy penalty** (more principled, more invasive): score candidates down for
   strong, unmatched bins left over: rewards accounting for more of the observed chroma energy,
   not just raw per-tone average. Needs new threshold/weight tuning, more surface area for
   regression.
3. **Bass note as primary signal, not tie-break**: `detectBassNote` is already computed before
   `identifyTriad` runs; promote it from last-resort disambiguator to a search-order prior. Largest
   behavior change, highest risk to already-locked chroma-only test numbers.

**Explicitly not implemented this turn.** Any of these three changes `identifyTriad`'s scoring
behavior, which `ChordScoringAmbiguityTests`' locked idealized-chroma numbers (31 mismatches) and
this phase's own 58/108 real-audio baseline both depend on — changing it deserves its own turn,
with its own before/after measurement on both suites, not a same-turn addendum to a root-cause
investigation. The open item (Yapilacaklar madde 1) is updated to record the confirmed mechanism
and these three options; it stays open pending a future decision on which (if any) to build.

**Two framing constraints for whichever fix that future turn picks -- binding on the fix turn,
fixed now so they can't be reached-for after seeing that turn's numbers:**

1. **Closure evidence must be bidirectional, not one-sided.** "4-note accuracy went up" is not
   sufficient proof on its own -- any of the three options above changes when a smaller candidate
   is allowed to beat a larger one, which is exactly the mechanism that also protects genuine
   3-note triads (major/minor/diminished) from being out-voted by a coincidentally-higher-scoring
   *unrelated* 4-note candidate. The fix turn must re-run both `ChordEndToEndSyntheticTests` (all
   108, not just the 4-note subset) AND `ChordScoringAmbiguityTests` (idealized-chroma, currently
   31 locked mismatches) before/after, and report both directions -- gain on 4-note chords AND no
   new loss on 3-note ones. This is the same shape of evidence Phase 15's graded-scoring fix used
   (a fix in one direction proven not to break the other), not a new standard invented here.
2. **The fix is a NEW comparison, not a wider tie-break -- do not implement it as raising
   `tieEpsilon` or loosening the bass-note near-tie window.** The measured C7 case is not a tie:
   E-diminished beats C7 by 0.0109, over 10x `tieEpsilon` (0.001). Widening the tolerance that
   treats scores as "effectively equal" would also start treating GENUINELY DIFFERENT chords as
   ties, corrupting real discrimination the current threshold correctly protects elsewhere (that
   is precisely why `tieEpsilon` was set to a value tight enough to only catch float-precision
   noise on idealized input, not real-world score gaps -- see this phase's own measurement that
   0.0109 is a real, structural gap, not noise). Option 1 above must compare finished
   candidate-vs-candidate results by subset-containment, a separate check from the score-distance
   comparison `tieEpsilon` already does, not a parameter tweak to that existing comparison.

---

## Phase 41 (2026-09-02): permanent production-vs-isolated identity tests (item 8's light layer) — and a retraction they immediately earned their keep by finding

Direct follow-up to Phase 39's closing observation: this session caught the same class of bug five
separate times by hand (frame-0 snapshot, sample rate, onset function, mixdown, buffer sizing) --
an isolated/validation pipeline silently diverging from what production's real code path does. Item
8 (Yapilacaklar) proposed a permanent, automatic version of the comparison so this stops depending
on someone remembering to check. Design, fixed before writing code: (1) depth = full output-identity
per engine (Phase 39's wiring-check shape), not just sample-rate equality -- root-cause-agnostic, so
it catches whichever of the five failure shapes recurs, not only the one item 8 was originally
written against; (2) location = two layers, not one -- a heavy, real-audio `RA_*` diagnostic
(release-time, not built this phase) and a light, synthetic-audio permanent XCTest (every `swift
test`, built this phase); (3) CI wiring deliberately deferred to a separate turn, after both layers
are proven to work locally -- connecting an unverified test to shared, every-push automation was
explicitly rejected as the CI-shaped version of this session's core discipline (verify before
trusting a result).

### The light layer: `Tests/ProductionPipelineIdentityTests.swift`

Three tests (Tempo, Key, Pitch), each a miniature of Phase 39's wiring check: synthesize a short
clip (`SyntheticAudio`, no real audio files), run the REAL production entry point
(`AudioIntelligence().analyze(url:)`) and an ISOLATED helper mirroring what
`GoldenDatasetValidationTests` calls, on the literal same file, assert agreement. Per-metric
tolerance derived from each field's own consumer-visible display precision (Tempo: 2 BPM, tighter
than the 1-decimal display since production/isolated should be bit-identical; Key: exact string,
categorical; Pitch: 1Hz, matching `MarkdownRenderer`'s display precision) -- not Phase 39's 0.005
bound, which is specific to a percent-rounded 0..1 confidence and has no meaning here.

**Verified all three tests actually catch something, not just pass by construction** (the standard
this session held the AUC self-check to, Phase 38) -- and initially only did this for one of the
three, which is itself worth recording. Injected Phase 36's real regression (isolated helper
hardcoded to 22050Hz instead of native) into the Tempo test and confirmed it fails (120.19 vs.
117.45 BPM, correctly over the 2.0 tolerance) before reverting to the clean, passing version. Key's
version of this verification is stronger than an injected test: building it caught a REAL
divergence on its first real run (below). Pitch, however, was first reported "passing" with NO
catch-capability evidence at all -- a clean pass on a test that might just always pass regardless
of input is not the same guarantee as Tempo's or Key's, and reporting all three as equally verified
would have overclaimed. Caught on review (not by this session's own initiative) and closed the same
way: injected the same 22050Hz-hardcode regression into Pitch's isolated helper, confirmed it fails
(441.06Hz production vs. 440.0Hz isolated, over the 1.0Hz tolerance), reverted. All three tests now
have the same standard of evidence behind them: each demonstrated catching a real, specific
divergence, not merely "currently green."

### The retraction: Key's isolated helper wasn't wrong — the method label was

The first version of the Key test asserted production's key against `ModulationEngine.detectKey`
(Krumhansl-Schmuckler), mirroring exactly what `GoldenDatasetValidationTests.
testGiantStepsKeyTempoAccuracy`'s own comment claims ("this matches the real production key path").
It failed: production "G", isolated "C Major", on an unambiguous synthetic C major clip. Traced
before assuming either side was buggy (this session's standard, re-applied here rather than
patching the test to pass): `AudioReportMapping.swift`'s `key = Estimated(a.tonality.key, ...,
method: "Krumhansl-Schmuckler on high-res STFT chroma")` -- but `a.tonality.key` is
`reduction.fundamentalNote` (`DNAReportBuilder.swift` ~819), NOT `detectKey`'s output.
`ReductionEngine.reduce` (read in full, not inferred) computes something categorically different: a
per-segment loudest-chroma-bin argmax ("segment tonic"), then a majority vote across segments
(first/last segment weighted +1) -- no Krumhansl correlation anywhere in it, and no major/minor
determination at all (`ChromaResult.noteNames[fundamentalBin]` is a bare note name). `detectKey` IS
computed in `DNAReportBuilder` (`detectedGlobalKey`/`verticalKey`) but only feeds
`TraditionalTheoryEngine.analyzeVertical`'s chord-function labeling -- confirmed by grep, exactly
one `TonalMetrics(` construction site in the whole codebase, `key: reduction.fundamentalNote`, no
other path to `Estimations.key`.

**Why this is a bigger, categorically different finding than the other five** (per the user's
framing, kept intact here): the other five were production running the CORRECT algorithm, measured
at the wrong rate/via the wrong test function. This one is `report.estimations.key.value` --
what a real caller actually receives -- coming from an algorithm that has NEVER been accuracy-
validated against any ground truth, while the algorithm this project's own README/DEVLOG cites as
"Key accuracy: 48.8% exact / 61.4% MIREX-weighted, N=599, GiantSteps" (Phase 17, Phase 36) measures
a DIFFERENT algorithm that isn't wired to that field at all. Not a stale number — a live, currently-
published accuracy claim attached to the wrong algorithm, discovered while building an unrelated
permanent test.

**Retracted immediately** (this session's established pattern -- correct the live false claim, not
just log it for later):
- `AudioReportMapping.swift`: `method` string corrected to accurately name `ReductionEngine`'s real
  algorithm and explicitly state accuracy is unmeasured, with a comment explaining what was
  previously claimed and why it was wrong.
- `AudioReport.swift`: `key`'s doc comment previously showed `// e.g. "A minor"` -- a mode-qualified
  example the actual value can never produce (the algorithm never determines mode). Corrected to a
  bare-note example with an explanation.
- `README.md`: added an explicit retraction note in the Validation Status preamble, and changed the
  Key row from ✅ to ⚠️ with the same clarification -- the 48.8%/61.4% figures stay in the table
  (they are real, reproducible numbers for `detectKey`) but are now correctly attributed, not
  presented as the exposed field's accuracy.
- Completed item 8's Key test against the REAL chain instead of `detectKey`: whole-track
  STFT(8192)/`ChromaEngine` chroma + whole-track STFT(2048)/Mel/`MFCCEngine` MFCC ->
  `StructureEngine.prepareFeatures`/`.boundaries` for segments -> `ReductionEngine.reduce`. Passes
  (production and isolated agree exactly on the synthetic clip) -- item 8's Key sub-test is now
  complete and tests what production actually exposes, not a plausible-sounding stand-in.

### A second, smaller instance of the same pattern, found in passing

Building the Pitch test surfaced `DNAReportBuilder.swift:829`:
`PitchMetrics(meanF0: meanF0, medianF0: meanF0, ...)` -- the `medianF0` parameter is passed the
track-wide MEAN variable, not a computed median (`PitchResult.medianF0`, a true median, exists at
the per-chunk level but is never aggregated to the top level). `.medianF0` is currently a second
copy of the mean. The Pitch test was written to match this actual current behavior (asserting
against what `.medianF0` really holds), with a doc comment explaining why, rather than asserting
against a true median and failing for an unrelated reason. Not fixed this phase -- scope kept to
production-vs-isolated wiring parity; filed as its own item (below), same family as the Key finding
but smaller (a field name promises something the value doesn't deliver, not a wrong-algorithm
mismatch).

### Two new open items, not this phase's to close

1. **`ReductionEngine.fundamentalNote` accuracy has never been measured against any ground truth.**
   Now that item 3's precedent (retract a live claim, then re-validate what's actually exposed) is
   set, the natural next step is measuring this algorithm's real accuracy on GiantSteps -- but its
   own design needs thought first (no major/minor output means the existing exact/MIREX-weighted
   scoring can't apply as-is; likely bare-tonic-name agreement only). Deliberately not done this
   phase -- keeps item 8 from expanding into an open-ended accuracy investigation.
2. **`medianF0` mislabeling** (above) -- same "exposed field's real source doesn't match its name/
   doc" family as the Key finding, smaller in scope. Worth checking whether
   `AudioReportMapping`/`DNAReportBuilder`'s report-assembly layer has other instances of this
   pattern, not just fixing this one field.

### Status

Item 8's light layer is built and now fully verified, all three tests to the same standard
(demonstrated catching a real divergence, not just "currently passing"): injected-regression catch
for Tempo and Pitch, a real catch for Key during construction. Per explicit decision, NOT yet wired
into CI; that connection is a separate, later decision once confidence in the mechanism is fully
established. The heavy, real-audio `RA_*` parity diagnostic (the other half of item 8's design) is
not built this phase.

**Pattern worth flagging for whenever item 8 is extended next**: this phase produced three
instances of "an exposed field's real source doesn't match what its label/name/doc comment claims"
(Key's `method` string, `medianF0`'s naming, and Phase 39's earlier "matches exactly" overclaim in
`InstrumentCalibration.swift`). Three independent instances in the same report-assembly layer
(`AudioReportMapping`/`DNAReportBuilder`) is enough to suspect a systematic gap, not a coincidence
-- item 8's next extension is probably not just "does the test call what production calls" but also
"does the exposed field's label match what actually computed it," as its own pass over that layer.
Not scoped or started this phase.

---

## Phase 42 (2026-09-02): `ReductionEngine` vs `ModulationEngine.detectKey`, tonic-only, on real GiantSteps -- measured, and the plausible-sounding hypothesis didn't hold

Direct follow-up to Phase 41's Key retraction: `report.estimations.key.value` (what production
actually exposes) comes from `ReductionEngine.fundamentalNote`, never accuracy-validated; the
algorithm this project's own numbers (Phase 17/36, 48.8%/61.4%) measure, `ModulationEngine.
detectKey`, is computed but never reaches that field. Two questions, not one: how accurate is the
exposed algorithm, and should the hidden one replace it?

**Metric fixed before running, not after**: standard exact-match/MIREX-weighted key scoring is
mode-sensitive, and `ReductionEngine` never determines major/minor (`fundamentalNote` is a bare
pitch class) -- scoring it against mode-qualified ground truth with a mode-sensitive metric would
fail on mode by construction and conflate "wrong tonic" with "no mode to be wrong about." Both
algorithms scored TONIC-ONLY, mode ignored on both sides: exact pitch-class match, or a
perfect-fifth-related tonic (the one MIREX partial-credit category that's itself mode-independent),
else no credit. Not comparable to Phase 17/36's mode-inclusive numbers -- different question.

**Measured each algorithm from the path Phase 41's own finding requires**: `ReductionEngine`'s side
read from `AudioIntelligence().analyze(url:).estimations.key` -- production's REAL output, not an
isolated call (an isolated `ReductionEngine` call was exactly the failure mode that produced the
original false claim this phase follows up on). `detectKey` has no exposed path at all (confirmed
in Phase 41), so it was necessarily computed via an isolated helper built to match
`DNAReportBuilder`'s own internal computation exactly (same whole-track STFT(8192)/`ChromaEngine`
chroma, native 44100Hz -- not the isolated-22050Hz mistake this project has made four separate
times before). Cost measured directly before committing to a sample size: one full `analyze(url:)`
call ≈ 50s (all 599 GiantSteps files would be hours) -- capped to 43 files (`GS_KEY_TONIC_LIMIT`),
run ≈ 36 minutes.

### Result: no meaningful difference, not the expected win for `detectKey`

| algorithm | exact | fifth-weighted | exact count |
| :-- | --: | --: | --: |
| `ReductionEngine` (exposed) | 44.2% | 58.1% | 19/43 |
| `ModulationEngine.detectKey` (hidden) | 46.5% | 60.5% | 20/43 |

A 1-file difference in exact matches. Checked whether this is real before reporting a direction:
paired (same 43 files, same ground truth) breakdown is 15 both-correct, 19 both-wrong, 4
`ReductionEngine`-only-correct, 5 `detectKey`-only-correct -- 9 discordant pairs, an exact sign test
on the discordant split gives p=1.0. **Not significant, not close.** The plausible-sounding
hypothesis going in -- Krumhansl-Schmuckler correlation should be "richer" than a bare
loudest-chroma-bin argmax and should therefore also pick the tonic better -- did not hold at this
sample size. This is itself a real finding, not a null result to discard: a mechanistically
reasonable expectation, tested, not confirmed. Whether it would separate at a larger N is unknown
and not claimed either way -- 43 files is what the cost analysis above supports for this phase, not
a claim of a definitively-tied population accuracy.

**One asymmetry the tonic-only metric cannot see, and shouldn't be lost in the tie**: `detectKey`
also determines mode; `ReductionEngine` categorically never can. Tonic accuracy being statistically
indistinguishable does not mean the two algorithms are equally good choices for `key.value` --
`detectKey` gives strictly more information (a consumer gets "C Major", not just "C") at no measured
tonic-accuracy cost on this sample. That is a real argument for wiring `detectKey` into `key.value`
instead, independent of the (tied) tonic race -- but it's a design/API-surface argument, not one
this measurement itself proves quantitatively.

### Status

Item 9 is closed as a measurement: both candidate algorithms' tonic-only accuracy against real
GiantSteps ground truth is now on record, using production's actual output path for the exposed
one. **Not decided or implemented this phase**: whether to rewire `key.value` to `detectKey`. The
tonic-accuracy case for doing so is weaker than expected (statistically tied, not a clear win); the
mode-completeness case is real but separate from what was measured. That decision, and its
downstream impact (report format, any consumer expecting a bare tonic), is left to a future,
explicit turn -- consistent with treating an exposed-field/API change as its own decision, not a
same-turn consequence of a measurement.

---

## Phase 43 (2026-09-02): `key.value` rewired to `detectKey` — item 11 implemented, not just measured

Direct follow-up to Phase 42: tonic-only accuracy was statistically tied between the exposed
algorithm (`ReductionEngine.fundamentalNote`) and the hidden one (`ModulationEngine.detectKey`),
so item 11 (should `key.value` move to `detectKey`?) wasn't answerable from that measurement alone.
Before implementing, four specific questions were closed, in order, each a real gate:

1. **Is `detectKey`'s mode signal real or noise?** Computed from Phase 42's already-logged data
   (no re-run needed): mode (major/minor) accuracy 86.0% (37/43) independent of tonic correctness,
   and 95.0% (19/20) among clips where `detectKey`'s own tonic call was already right. Real,
   substantial signal — the entire premise of wiring `detectKey` for its mode information holds.
2. **Does `detectKey` see the same chroma production would wire it to in practice, or a different
   one?** Read `DNAReportBuilder.swift` directly (not assumed): `detectKey`'s `meanChromaVec` and
   `ReductionEngine.reduce`'s `chromagram:` argument are BOTH `fullChromagramBins` — same array,
   three lines apart. Zero divergence risk from this rewiring — this session's six-times-repeated
   trap (isolated helper silently sees different input than production) doesn't apply here because
   there's no isolated helper on this side; `detectKey` was already running on production's real
   chroma, just not surfaced. (Bonus behavioral cross-check: Phase 42's isolated `detectKey` full
   exact-match on N=43 landed at 44.2%, close to Phase 36's independently-measured 48.8% on
   N=599 — consistent with the isolated helper computing what production's internal call already
   computes, not a coincidence.)
3. **Would this break any real consumer?** Grepped every `.estimations.key`/`.key.value` site in
   `Sources/`+`Examples/` (`AIBenchmark`, `CLIExample`, `SQAMAuditTool`): all three print or compare
   the string as opaque data, none parse its structure (no length/space-count assumptions). No
   breaking-change risk found.
4. **Was the original wiring deliberate or an oversight?** `git log -S` on `DNAReportBuilder.swift`:
   `key: reduction.fundamentalNote` was introduced 2026-04-20 (`8bb0f7e`), replacing a hardcoded
   `"C Minor"` placeholder — `ReductionEngine` was the ONLY key mechanism in the codebase at that
   moment. `ModulationEngine().detectKey` (as `detectedGlobalKey`) wasn't added until 2026-06-16
   (`2432341`), ~2 months later, inside a broad, unrelated commit ("import Golden dataset with
   manifest and update audio loading logic") — added specifically to fix `analyzeVertical`'s own
   hardcoded `"C Major"` for chord-function labeling. The commit never touches `TonalMetrics`/
   `Estimations`. Reads as an oversight (the public field was never revisited when a better
   algorithm became available for an adjacent need), not a considered choice this change overrides.

All four cleared. Implemented.

### The change

`ModulationEngine.swift`: `identifyKey` (private, string-only) became `identifyKeyWithConfidence`
(private, returns `(key: String, confidence: Float)`) — `detectKey`'s existing public signature is
unchanged (still just extracts `.key`, so every other call site, including
`GoldenDatasetValidationTests` and this session's own parity tests, needed no changes) and a new
public `detectKeyWithConfidence` exposes the winning candidate's own correlation strength. Chosen
over leaving `keyConfidence` on `reduction.stabilityScore`: that would have re-created the exact
bug class this whole arc started from — a value from one algorithm carrying a confidence that
describes a different one.

`DNAReportBuilder.swift`: `detectedGlobalKey` is now captured alongside its confidence
(`detectKeyWithConfidence`, not `detectKey`), threaded through `assembleFinalDNA` as two new
parameters, and `TonalMetrics(key:keyConfidence:...)` now reads from them instead of
`reduction.fundamentalNote`/`reduction.stabilityScore`. Deliberately NOT touched:
`strength`/`harmonicStability`/`tendency` stay on `reduction.stabilityScore` — those describe
tonal-center CONSISTENCY across segments (`harmonicStability`'s own doc comment: "chroma variance
score"), a genuinely different concept from confidence in the key label itself; only the field
whose underlying algorithm changed needed its confidence source to move with it.

`AudioReportMapping.swift` / `AudioReport.swift`: `method` string and the `key` doc comment's
example flipped back to describing Krumhansl-Schmuckler / a mode-qualified example — both are true
again now that the source moved back to `detectKey`. Comments on all three sites keep the full
two-hop history (`ReductionEngine` originally → mislabeled as K-S → corrected label → now genuinely
K-S again) rather than just the current state, since a future reader hitting this field cold
deserves the why, not just a snapshot.

### Closing evidence — verified the wiring, not just the chroma-input claim

Gate #2 above showed the chroma INPUT is shared statically; that is not the same claim as "the
public field's RUNTIME output now equals `detectKey`'s" — this session found real bugs exactly in
that gap before (Phase 39's wiring check caught two). `Tests/ProductionPipelineIdentityTests.swift`'s
Key test (item 8's parity test) was updated to assert against `detectKeyWithConfidence` instead of
the old `ReductionEngine` chain (both the key string AND the confidence, since both were rewired) —
this is the SAME test that failed the first time it asserted against `detectKey` (Phase 41, before
the rewiring existed) and is now expected to pass because the wiring itself changed, not because
the test was loosened. Ran clean: production and the isolated `ChromaEngine`+
`ModulationEngine.detectKeyWithConfidence` pipeline agree exactly, key string and confidence, on
the same synthetic clip.

Also spot-checked on real audio (a different decode path than the synthetic-WAV parity test
exercises): 5 real GiantSteps MP3s, comparing production's new `key.value` against the exact
`detectKey` strings already logged in Phase 42's 43-file run for those same file IDs (not a
re-measurement — a check that production's real output now equals what was already measured as
"the hidden algorithm"). **5/5 matched exactly** (`F Minor`, `F Minor`, `D Major`, `F Minor`,
`E Minor` — production's live output on each real file byte-for-byte equal to the isolated value
logged hours earlier from the same chroma-computation logic). Throwaway test, deleted after use.

### One more gate, caught on review: is `keyConfidence` calibrated?

Newly exposing a confidence invites the exact question Phase 38 spent a whole item answering for
`instruments` — is this number a probability-like, cross-comparable quantity, or a raw
within-algorithm score? Checked directly, not assumed: `detectKeyWithConfidence`'s confidence is
`max(0, min(1, maxCorr))` — the winning Krumhansl-Kessler correlation, clamped, with no
Platt/isotonic fit against ground-truth accuracy anywhere in this change. **Raw, not calibrated.**
`MetricWrappers.swift`'s `Estimated.confidence` doc comment already frames this correctly by
default (only `instruments` is named as the calibrated exception; everything else, `key` included,
is "not a probability guarantee, a relative score... not necessarily comparable across different
metrics") — so no factual claim needed correcting here, unlike Phase 41's `method` label. But
"technically already covered by the general default" isn't the same as "won't be misread" -- a
future reader seeing a freshly-added confidence right after Phase 38's calibration work could
reasonably assume the same treatment happened here. Made explicit rather than left implicit, in
both places a reader would land on this value: `detectKeyWithConfidence`'s own doc comment
(`ModulationEngine.swift`) and the `key` construction site (`AudioReportMapping.swift`) now both
say directly "RAW, not calibrated like `instruments`" with the reasoning, not just a cross-
reference to infer it from.

### Status

Item 11 is implemented, not just measured: `key.value`/`keyConfidence` now come from `detectKey`,
verified end-to-end on both synthetic and real audio, with the four pre-implementation questions
(mode-signal reality, chroma-path safety, consumer-breakage risk, deliberate-vs-oversight history)
all closed with evidence rather than assumed -- plus a fifth question raised on review after
implementation (is the newly-exposed confidence calibrated?), also closed with evidence (no, and
now stated explicitly rather than left inferable). The arc from Phase 41's retraction to here:
found a false claim → retracted it → measured both candidates properly → verified the fix was
implementable safely → implemented it → verified the implementation itself, not just its
precondition → verified the new field it added doesn't quietly imply something untrue either.
README's Key row is ✅ again, and this time the number it shows is the accuracy of the algorithm
actually wired to the field a caller reads.

---

> *"Measured, not claimed: AudioIntelligence reports what it can prove."*
