# 🎙️ AudioIntelligence: Pro-grade Engineering Station (v52.0)

> **"A mathematically verified, high-performance foundation for total signal truth."**

[![EBU Tech 3341](https://img.shields.io/badge/Standard-EBU%20Tech%203341-red.svg)](docs/Calibration.md)
[![EBU Tech 3342](https://img.shields.io/badge/Standard-EBU%20Tech%203342%20(LRA)-red.svg)](docs/Calibration.md)
[![AES17 Verified](https://img.shields.io/badge/Verified-AES17%20(Dynamic%20Range)-blue.svg)](docs/Calibration.md)
[![ITU-R 468](https://img.shields.io/badge/Standard-ITU--R%20468%20(Noise)-green.svg)](docs/Calibration.md)
[![Scientific Validation](https://img.shields.io/badge/Verification-100%25%20Scientific-orange.svg)](docs/Calibration.md)

**AudioIntelligence** is an elite Swift library designed for audio engineers and hardware developers who demand **absolute precision**. Optimized for **Apple Silicon**, it provides a strictly calibrated "Glass Box" for signal analysis, forensic auditing, and broadcast compliance.

---

## 💎 The Engineering Advantage

- **✅ 100% Authenticated**: Every engine is calibrated against **EBU Tech 3341** synthetic test vectors. No estimation, just math.
- **🚀 Ultra-Low Latency**: Native Swift implementation using AMX (Apple Matrix Extension) for real-time analysis on macOS and iOS.
- **🔍 Forensic Integrity**: Unique **Shannon Entropy** analysis to detect bit-depth forgery and "Fake Hi-Res" upsampling.
- **🎚️ Industry Standards**: Built-in compliance with **EBU R128** and **ITU-R BS.1770-4** for professional loudness and peak control.

---

## 🛠️ The Professional Suite (v51.0)

### 1. Mastering & Loudness Engine
Verified against the official EBU Loudness test set.
*   **Integrated LUFS**: BS.1770 Gated Loudness with ±0.1 dB accuracy.
*   **True Peak (dBTP)**: 4x Polyphase oversampling to catch inter-sample peaks missed by standard meters.
*   **Stereo Audit**: M/S (Mid/Side) balance and phase correlation indices.

### 2. Forensic & Provenance Engine
The "Röntgen" DNA analysis for audio files.
*   **Bit-Depth Entropy**: Scientifically identifies files upsampled from 16-bit to 24-bit by scanning the distribution of Least Significant Bits (LSBs).
*   **Signature Search**: Binary header scanning for encoder traces (LAME, FhG, Lavf).
*   **Provenance Metadata**: Tracking download origin and system-level metadata.

### 3. Spectral & MIR DNA
Native implementations of standard academic algorithms.
*   **Constant-Q Transform (CQT)**: Recursive downsampling for musical pitch precision.
*   **Mel-Spectrogram & MFCC**: Optimized for hardware acceleration.
*   **Higher-Order Statistics**: Moments (Skewness, Kurtosis) for timbral characterization.

---

## 🧪 Verification & Calibration
We don't ask you to trust us; we provide the proof.
See **[Calibration.md](docs/Calibration.md)** for a detailed breakdown of our "No-Lie" testing methodology using synthetic EBU test vectors.

---

## 🚀 Quick Start (Swift 6)

```swift
import AudioIntelligence

let intelligence = AudioIntelligence()

// Analyze with Forensic Verification
let result = try await intelligence.analyze(url: songURL)

print("Loudness (EBU R128): \(result.mastering.integratedLUFS) LUFS")
if result.forensic.isUpsampled {
    print("⚠️ Warning: Identified as upsampled 16-bit audio.")
}
```

---

## 📊 Why Native Matters (Apple Silicon)

| Task | Capability | Native Benefit |
| :--- | :--- | :--- |
| **STFT Analysis** | Sub-millisecond | Zero-copy vector processing |
| **Loudness Gate** | Real-time | Energy-efficient AMX execution |
| **Entropy Scan** | Forensic-level | Direct bit-access via vDSP |

---

## 📖 Technical Documentation

- **[Calibration Manifest](docs/Calibration.md)**: Standard-aligned testing results.
- **[Project Structure](docs/ProjectStructure.txt)**: Technical directory breakdown.

---

## 📄 License
Released under the **Apache License 2.0**. Developed with ❤️ for the Professional Audio Community.
