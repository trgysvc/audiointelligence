# 🕵️ Forensics: The Science of Signal Provenance

AudioIntelligence provides a forensic laboratory for the digital audio signal chain. This document details the mathematical and scientific principles we use to verify file authenticity and provenance.

---

## 1. Upsampling / "fake hi-res" detection

"Fake hi-res" is a file whose container **declares** a high bit depth while the actual signal
only carries the information of a lower one (e.g. 16-bit content padded into a 24-bit container).

### How we detect it: declared vs measured bit depth
The detection compares two numbers:

- **`sourceBitDepth`** — the bit depth *declared* by the container header (read deterministically).
- **`effectiveBits`** — the bit depth actually *present* in the signal, measured from the minimum
  quantization step between sample values across non-silent regions.

A file is flagged `isUpsampled = true` **only when `sourceBitDepth > effectiveBits`** — the
container claims more resolution than the data uses.

> ⚠️ **Entropy alone is not a forgery signal.** An earlier version keyed this on Shannon entropy
> (`entropy < 0.6 ⇒ upsampled`). That is wrong: a solo instrument or a quiet passage legitimately
> has low entropy at full bit depth, so the heuristic false-flagged authentic recordings. The
> entropy score is still reported (`measurements.forensic.entropyScore`) as a descriptive
> statistic, but it does **not** drive the upsampling verdict.

---

## 2. Codec Cutoff Fingerprinting

Lossy compression (MP3, AAC) is characterized by spectral "Ceilings" or cutoffs, where high-frequency content is discarded to save bandwidth.

### Spectral Bracketing
- **MP3 (128kbps)**: Typically displays a hard low-pass filter at 16.0 kHz.
- **AAC (256kbps)**: Displays a sophisticated perceptual model with a rolling cutoff between 18.5 kHz and 20.0 kHz.

If a lossless file (WAV/FLAC) exhibits these spectral bracketing characteristics, it is flagged as a **Transcode** (original source was likely lossy).

---

## 3. Forensic output

The forensic results are part of the typed **`AudioReport`** (see
[Report Specification](REPORT_SPECIFICATION.md)), under `measurements.forensic`:

- `sourceBitDepth` (declared) and `effectiveBits` (measured)
- `isUpsampled` — the fake-hi-res verdict from §1
- `codecCutoff` (Hz) — the spectral cutoff used for transcode bracketing (§2)
- `clippingEvents`, `entropyScore` — descriptive integrity statistics

Alongside it, `measurements.fidelity` carries the laboratory metrics (AES17 THD+N, SMPTE IMD,
ITU-R 468 noise floor, SNR). The library writes no report file itself — serialize the
`AudioReport` to JSON or binary plist, or render it with `MarkdownRenderer`, as you prefer.

---

## 4. AES17 & Laboratory Standards

For industrial mastering and forensic laboratories, we verify the **Digital Baseline** using standardized protocols:
- **AES17 Dynamic Range**: Measured with stimulus isolation to detect effective bit-depth.
- **SMPTE IMD (Inter-modulation Distortion)**: Analysis of 60Hz/7kHz interaction ratios to detect non-linear artifacts.
- **ITU-R 468-4 Noise Weighting**: Perceptually-weighted noise floor analysis for professional broadcasting.
- **Notch Auditing**: 6th-order digital notch filtering for harmonic distortion (THD+N) verification.

---

*For a manifest of all calibrated standards tests, see [Calibration.md](Calibration.md).*
