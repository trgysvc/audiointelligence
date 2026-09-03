# AudioIntelligence Calibration Manifest

The official record of what the **measurement** layer is calibrated and verified against. Each
row is backed by a test in `Tests/`. "Verified" means high-precision agreement with a reference
on the *tested* scenario — not exhaustive coverage, and not the statistical estimation layer
(tempo/key/instrument), which is reported separately in the README Validation Status.

## 🧪 Verified scenarios

| Scenario | Reference | Result | Source of truth |
| :--- | :--- | :--- | :--- |
| Integrated loudness (EBU SQAM) | ffmpeg `ebur128` | Δ ≤ 0.08 LU (18/18) | reference meter |
| True peak | ITU-R BS.1770 | Δ ≤ 0.27 dB | reference meter |
| Loudness range (LRA) | EBU Tech 3342 | Δ ≤ 0.21 LU | reference meter |
| Reference calibration (1 kHz @ −23 dBFS) | EBU Tech 3341 | −22.994 LUFS | reference signal |
| Gating / silence rejection | EBU Tech 3341 | pass | reference signal |
| AES17 THD+N / SMPTE IMD | known-distortion signals | exact | synthetic references |
| ITU-R 468 noise weighting | the standard curve | ±0.03 dB | analytic reference |
| STFT / mel | librosa 0.11 | corr 1.00000, 0% residual | librosa parity |
| A-weighting (IEC 61672-1) | closed-form analytic curve | Δ ≤ 0.01 dB through 100Hz–2kHz | analytic reference |
| Bit depth / sample rate / duration | container header | exact | header read |

## 2. Methodology

The measurement engines are verified two ways:

- **Reference signals ("digital twins")** — synthetic stimuli with a known answer (e.g. a 1 kHz
  sine at −23 dBFS for loudness calibration), analyzed in-memory to remove I/O variance.
- **Reference implementations** — `ffmpeg ebur128` for loudness, `librosa 0.11` for STFT/mel/MFCC
  parity (used only at test time; the library ships zero dependencies).

The **estimation** engines (tempo, key) are additionally benchmarked on *real music* (GiantSteps,
MIREX-annotated) — there we report measured accuracy, not perfection (see README).

## 3. Known limitations

- **CQT engine**: its correctness bugs (aliasing filter, energy rescale, octave alignment, note
  order) were fixed and independently cross-checked against a reference implementation (see
  DEVLOG Phase 10) — it is validated as a standalone engine. Key and chroma still rely on a
  high-resolution STFT chromagram, not CQT — but CQT does now have a real downstream consumer:
  `TraditionalTheoryEngine.detectBassNote` (chord inversion labeling, and chord root/quality
  tie-breaking on chroma-identical chords), wired to production's real per-chunk CQT output.
- **Neural stem separation**: the `NeuralSeparationEngine` is an interface only — no Core ML model
  ships, and it is not part of `analyze()`.

---
*Last reviewed: 2026-09-04 — AudioIntelligence 8.2.3. See [Integration.md](Integration.md).*
