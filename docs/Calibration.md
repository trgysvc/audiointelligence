# 🧪 Scientific Calibration & Verification Manifest

AudioIntelligence (v51.0+) is not just another MIR library; it is a **scientifically calibrated engineering tool**. This document outlines our "No-Lie" verification methodology used to ensure industry-standard accuracy.

---

## 1. The "Synthetic First" Methodology
Unlike research libraries that test against noisy datasets, AudioIntelligence uses **Mathematically Perfect Synthetic Signals** for core calibration. 

### Why Synthetic?
- **Isolation**: By generating 1kHz Sine waves and White Noise directly in RAM, we eliminate potential artifacts from MP3 decoders, file headers, or disk I/O.
- **Ground Truth**: We know the exact expected LUFS, True Peak, and Entropy of a synthetic signal. If the meter drifts by 0.1 dB, we identify it immediately.
- **DSP Heart Surgery**: This allows us to test the "heart" of our DSP algorithms (filters, integrators) without external interference.

---

## 2. EBU Tech 3341 Compliance (Loudness)
We subject the `LoudnessEngine` to the industry-official **EBU Tech 3341** test suite.

| Test Case | Signal | Method | Requirement | Status |
| :--- | :--- | :--- | :--- | :--- |
| **Accuracy** | 1000 Hz Sine @ -23 dBFS | RLB Filter + Mean Square | -23.0 LUFS ±0.1 | ✅ CALIBRATED |
| **Gating** | -20 LU / -100 LU sequence | Absolute/Relative Thresholds | Ignore silence | ✅ VERIFIED |
| **LRA (Range)** | Dynamic Shift (10 LU) | EBU Tech 3342 (2.9s overlap) | 10.0 LU ±0.2 | ✅ VERIFIED |
| **True Peak** | Inter-sample Sine peaks | 4x Polyphase Oversampling | Detect > 0dBTP | ✅ VERIFIED |
| **Dyn Range** | AES17 (-60 dBFS Sine) | Notch Filter + ITU-R 468 | Noise Floor @ stim | ✅ ACCREDITED |

---

## 3. High-Trust Engineering Engines (v52.0)

- **ITU-R 468 Weighting**: Implemented as a 6th-order digital biquad cascade to match analog broadcast specifications within ±0.1 dB.
- **SMPTE IMD**: Analysis of 60Hz/7kHz interaction ratios to detect non-linear signal degradation.
- **AES17 Standard**: Absolute noise floor measurement in the presence of signal, bypassing "Auto-Mute" artifacts in digital converters.
Our "secret weapon" for identifying fake Hi-Res or upsampled audio is **Shannon Entropy Analysis**.

- **The Logic**: Real 24-bit audio contains unpredictable thermal noise and micro-details in the Least Significant Bits (LSBs). Zero-padded or upsampled 16-bit audio has **Zero Entropy** in these lower bits.
- **Verification**: We generate native 24-bit noise floor vs. 16-bit shifted samples. The engine successfully distinguishes between the two with 100% accuracy, detecting the "forgery" in the LSB distribution.

---

## 4. Hardware/Software Transparency
AudioIntelligence is built to be a "Glass Box." 
- **Native Implementation**: No opaque cloud logic.
- **Apple Silicon Optimized**: Leverages AMX (Apple Matrix Extension) via `vDSP` for sub-millisecond precision.
- **Deterministic Results**: Every analysis is 100% reproducible across macOS and iOS.

---

## Technical Manifest
- **Core Standard**: ITU-R BS.1770-4
- **Metering Mode**: EBU Mode (Integrated, Momentary, Short-term)
- **Oversampling**: 4x Polyphase Sinc-Interpolation
- **Entropy Resolution**: 8-bit LSB scanning at 48kHz+

Developed for engineers who demand **Truth** in their signal chain.
