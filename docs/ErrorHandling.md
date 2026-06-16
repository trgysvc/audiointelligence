# 🛡️ Error Handling & Robustness

AudioIntelligence is designed for mission-critical industrial audio engineering. Our error handling system focuses on **Safety**, **Traceability**, and **Scientific Integrity**.

## 🏛️ The Error Hierarchy

We use a domain-specific, hierarchical error system built on the `AudioIntelligenceError` protocol. This allows you to catch errors at the specific level of granularity your application needs.

```swift
public enum AudioIntelligenceError: LocalizedError, Sendable {
    case io(IOError)              // File reading, permissions, decode, format
    case dsp(DSPError)            // FFT setup, dimension/rate mismatch, overflow
    case gpu(GPUError)            // Metal device/queue/kernel/shader failures
    case neural(NeuralError)      // Core ML separation model issues
    case forensic(ForensicError)  // Provenance / bit-depth resolution
    case logic(LogicError)        // Invalid parameters, state violations
    case caching(CacheError)      // Cache read/write failures
}
```

### 📁 1. IOError (I/O & Format)
- `.fileNotFound(URL)`, `.permissionDenied(URL)`: the source can't be accessed.
- `.decodeFailed(URL)`, `.formatNotSupported(String)`: the bitstream can't be decoded.
- `.streamInterrupted`: the input stream ended unexpectedly.

### 🧪 2. DSPError (Signal Processing)
- `.fftSetupFailed`, `.invalidWindowSize(Int)`: transform configuration problems.
- `.dimensionMismatch(expected:actual:)`, `.sampleRateMismatch(expected:actual:)`: incompatible buffers between engines.
- `.calculationOverflow`: a numerical overflow was detected.

### 🧬 3. ForensicError (Integrity)
- `.bitDepthResolutionFailure`: the effective bit depth could not be measured.
- `.codecSignatureMismatch`: the codec signature is inconsistent with the metadata.
- `.entropyCalculationFailed`: the entropy statistic could not be computed.

---

## 🛠️ Recovery Strategies

### Safe-Trial Pattern
For non-critical analysis, we recommend the `try?` or localized `do-catch` recovery:
```swift
do {
    let report = try await AudioIntelligence().analyze(url: url)
    if report.measurements.forensic.isUpsampled {
        print("⚠️ Declared \(report.measurements.forensic.sourceBitDepth.value)-bit, "
            + "but effective resolution is only \(report.measurements.forensic.effectiveBits.value)-bit.")
    }
} catch AudioIntelligenceError.io(.fileNotFound(let url)) {
    print("❌ Not found: \(url.lastPathComponent)")
} catch {
    print("❌ Error: \(error.localizedDescription)")
}
```

### Automatic Cache Recovery
The `IntelligenceCache` is self-healing. If a cached representation fails a checksum, the core engines will automatically force a re-analysis and update the entry.

## 🛡️ Thread Safety & Swift 6
Every engine in AudioIntelligence is a **Global Actor** or an **Actor-isolated** class. This ensures that you can never trigger a data race while interacting with analysis buffers across different threads. No `NSLock` or manual semaphores are required.
