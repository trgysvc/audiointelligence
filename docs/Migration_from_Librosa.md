# 🌉 Migration from Librosa to AudioIntelligence

This guide serves as a "Rosetta Stone" for developers transitioning from the Python-based Librosa research library to the high-performance, native Apple Silicon-optimized **AudioIntelligence Infinity Suite**.

## 🔄 Function Mapping

| Librosa (Python) | AudioIntelligence (Swift) | Note |
| :--- | :--- | :--- |
| `librosa.load(path)` | `AudioLoader.load(url)` | Async by default. Includes caching. |
| `librosa.stft(y)` | `STFTEngine.analyze(samples)` | vDSP-accelerated; frame-major layout. |
| `librosa.feature.melspectrogram` | `MelSpectrogramEngine.analyze()` | Built-in perceptual weighting. |
| `librosa.feature.mfcc` | `MFCCEngine.analyze()` | DCT-II optimized. |
| `librosa.feature.chroma_cqt` | `ChromaEngine.analyze()` | Constant-Q based harmonic mapping. |
| `librosa.onset.onset_detect` | `OnsetEngine.detect()` | Multi-band spectral flux algorithm. |
| `librosa.beat.beat_track` | `RhythmEngine.analyze()` | Dynamic programming tempo tracking. |
| `librosa.segment.recurrence_matrix` | `StructureEngine.recurrenceMatrix()` | Cosine-similarity focused. |
| `librosa.effects.time_stretch` | `ManipulationEngine.timeStretch()` | Phase vocoder implementation. |
| `librosa.effects.pitch_shift` | `ManipulationEngine.pitchShift()` | HQ resampled pitch shifting. |
| `librosa.decompose.hpss` | `HPSSEngine.analyze(stft:)` | Median-filter harmonic-percussive separation. |
| `librosa.display.specshow` | `SpectralLandscapeView` | SwiftUI + Metal rendering. |

---

## 🛠 Architectural Differences

### 1. Unified Engine Registry
In Librosa, you call individual functions. In AudioIntelligence, we use **Engines**. This allows for persistent state, hardware-specific setups (Metal kernels), and thread-safe actor isolation.

### 2. Thread Safety (Swift 6)
AudioIntelligence is built for **Swift 6 Actor Isolation**. You can run multiple analysis engines in parallel without worrying about data races, which is a major pain point when using Librosa/NumPy in a multi-threaded Python environment.

### 3. Native Swift, on-device
Librosa is a Python/NumPy batch library. AudioIntelligence is native Swift on Apple Silicon,
designed for on-device app integration with structured concurrency.

### 4. Hardware Acceleration
- **Librosa**: Generic CPU (NumPy/OpenBLAS).
- **AudioIntelligence**: Native **Accelerate/vDSP (incl. AMX)** and **Metal GPU**, with a CPU
  fallback. (The analysis pipeline does no ANE/Core ML inference.)

---

## 🧪 Example Comparison

### Librosa (Python)
```python
import librosa
y, sr = librosa.load("audio.wav")
tempo, beats = librosa.beat.beat_track(y=y, sr=sr)
S = librosa.feature.melspectrogram(y=y, sr=sr)
```

### AudioIntelligence (Swift)
```swift
import AudioIntelligence

let samples = try await AudioLoader.load(url: fileURL)
let tempo = await RhythmEngine().analyze(samples)
let mel = await MelSpectrogramEngine().analyze(samples)
```
