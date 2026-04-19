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
| `librosa.decompose.hpss` | `HPSSEngine.separate()` | Median-filter harmonic-percussive separation. |
| `librosa.display.specshow` | `SpectrogramView()` | SwiftUI + Metal real-time rendering. |

---

## 🛠 Architectural Differences

### 1. Unified Engine Registry
In Librosa, you call individual functions. In AudioIntelligence, we use **Engines**. This allows for persistent state, hardware-specific setups (Metal kernels), and thread-safe actor isolation.

### 2. Thread Safety (Swift 6)
AudioIntelligence is built for **Swift 6 Actor Isolation**. You can run multiple analysis engines in parallel without worrying about data races, which is a major pain point when using Librosa/NumPy in a multi-threaded Python environment.

### 3. Real-time vs Batch
Librosa is primarily for batch processing (offline). AudioIntelligence engines are optimized for **Sub-millisecond Latency**, making them suitable for real-time professional DAW plugins and live analysis apps.

### 4. Hardware Acceleration
- **Librosa**: Generic CPU (NumPy/OpenBLAS).
- **AudioIntelligence**: Native **AMX (Apple Matrix Extension)**, **ANE (Apple Neural Engine)**, and **Metal GPU**.

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
