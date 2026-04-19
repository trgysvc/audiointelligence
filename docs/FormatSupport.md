# 🎹 Supported Audio Formats & Precision Standards

AudioIntelligence leverages the industrial-grade **AVFoundation** and **Accelerate** frameworks to provide seamless support for all professional audio codecs with zero-copy efficiency on Apple Silicon.

## 📁 Supported File Formats

Through our `AudioLoader` orchestrator, we support any format recognized by the Apple ecosystem, including but not limited to:

| Format | Extension | Bit-Depth | Native Hardware Support |
| :--- | :--- | :--- | :--- |
| **PCM (Wave)** | `.wav` | 16, 24, 32-bit | ✅ Bit-exact passthrough |
| **FLAC** | `.flac` | Up to 24-bit | ✅ vDSP Optimized |
| **ALAC** | `.m4a` | Lossless | ✅ ANE/AMX Accelerated |
| **MP3** | `.mp3` | Variable/Fixed | ✅ Core Audio Hardware Decoder |
| **AAC** | `.m4a`, `.aac` | Mastering Grade | ✅ Core Audio Hardware Decoder |
| **AIFF** | `.aiff` | Professional | ✅ Native |
| **OGG** | `.ogg`, `.oga` | Opus/Vorbis | ✅ Modern AVFoundation support |

---

## 🔬 Scientific Precision

Unlike general-purpose research libraries, AudioIntelligence is engineered for **Industrial Forensic Fidelity**:

1.  **32-bit Floating Point Foundation**: All internal engines process data in `Float32` or `Float64` to prevent rounding errors.
2.  **Bit-Deep Entropy Audit**: Our `ForensicEngine` can detect if a 24-bit file is actually a 16-bit upscale by analyzing the LSB (Least Significant Bit) entropy.
3.  **SQAM Parity**: Validated against the EBU Sound Quality Assessment Material.
4.  **AES17 Compliance**: Dynamic range and frequency response metrics adhere to AES17-2020 standards.

## ⚡ Loading & Caching

Our loading pipeline is not just about reading bytes; it's about preparation:
- **Automatic Down-mixing**: Robust stereo-to-mono or multi-channel handling via `AVAudioConverter`.
- **Intelligent Resampling**: High-quality polyphase resampling to the target engine rate (default 22050Hz or 44100Hz).
- **IntelligenceCache**: Once a file is fingerprinted (SHA-256), its spectral representations are cached in a 4GB hybrid buffer for instantaneous subsequent access.
