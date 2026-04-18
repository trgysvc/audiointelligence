# 🕵️ Forensics: The Science of Signal Provenance

AudioIntelligence provides a forensic laboratory for the digital audio signal chain. This document details the mathematical and scientific principles we use to verify file authenticity and provenance.

---

## 1. Bit-Depth Entropy (Validation)

The primary indicator of audio "forgery" (upsampling) is the distribution of randomness in the Least Significant Bits (LSB).

### Mathematical Basis: Shannon Entropy
We calculate the entropy ($H$) of the lower bit-planes using:
$$H(X) = -\sum_{i=1}^{n} P(x_i) \log_2 P(x_i)$$

- **Authentic 24-bit Audio**: Contains thermal and quantization noise in the LSBs, resulting in high entropy.
- **Upsampled 16-bit Audio**: Even when stored in a 24-bit container, the lower 8 bits remain zero-padded or follow a predictable pattern, resulting in **Zero Entropy**.

### Forensic Thresholds
AudioIntelligence uses a **Confidence Gradient** rather than a binary flag. We analyze bit-density over the entire file duration to ensure that dither or noise-shaping isn't incorrectly flagged as native resolution.

---

## 2. Codec Cutoff Fingerprinting

Lossy compression (MP3, AAC) is characterized by spectral "Ceilings" or cutoffs, where high-frequency content is discarded to save bandwidth.

### Spectral Bracketing
- **MP3 (128kbps)**: Typically displays a hard low-pass filter at 16.0 kHz.
- **AAC (256kbps)**: Displays a sophisticated perceptual model with a rolling cutoff between 18.5 kHz and 20.0 kHz.

If a lossless file (WAV/FLAC) exhibits these spectral bracketing characteristics, it is flagged as a **Transcode** (original source was likely lossy).

---

## 3. Digital DNA Signature Matching

Every professional encoder (LAME, Fraunhofer, CoreAudio) leaves distinct "DNA" in the signal.

### Frame Offsets & Padding
We detect non-musical padding at the start and end of files. Specific lossy-to-lossless transcode cycles leave unique zero-padding offsets and "alias" spectral artifacts that can be used to identify the historical encoding path of the file.

### Forensic DNA Reports (.dna.md)
The ultimate output of the forensic pipeline is the **DNA Report**. This document provides:
- **Forensic Signature**: A non-lossy digital thumbprint of the audio file.
- **Tonnetz DNA Grid**: High-resolution harmonic stability maps.
- **Scientific Baseline**: Laboratory-grade metrics (AES17, IMD, 468).
- **Infinity Data Dump**: A raw JSON payload containing the complete 26-engine telemetry.

---

## 4. AES17 & Laboratory Standards

For industrial mastering and forensic laboratories, we verify the **Digital Baseline** using standardized protocols:
- **AES17 Dynamic Range**: Measured with stimulus isolation to detect effective bit-depth.
- **SMPTE IMD (Inter-modulation Distortion)**: Analysis of 60Hz/7kHz interaction ratios to detect non-linear artifacts.
- **ITU-R 468-4 Noise Weighting**: Perceptually-weighted noise floor analysis for professional broadcasting.
- **Notch Auditing**: 6th-order digital notch filtering for harmonic distortion (THD+N) verification.

---

*For a manifest of all calibrated standards tests, see [Calibration.md](Calibration.md).*
