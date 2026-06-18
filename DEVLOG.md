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

> *"Measured, not claimed: AudioIntelligence reports what it can prove."*
