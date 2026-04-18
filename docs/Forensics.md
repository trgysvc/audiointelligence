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

---

## 4. AES17 Professional Standards

For industrial mastering, we verify the **Dynamic Range (DR)** and **Signal-to-Noise Ratio (SNR)** using the AES17 protocol.
- **Notch Auditing**: We apply a 6th-order digital notch filter to the stimulus (e.g., a 1kHz tone) and analyze the residual noise and distortion floor.
- **IMD Detection**: Inter-modulation distortion analysis (SMPTE method) to detect non-linearities in the digital reproduction chain.

---
*For a manifest of all calibrated standards tests, see [Calibration.md](Calibration.md).*
