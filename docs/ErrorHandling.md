# 🛡️ Error Handling & Robustness

AudioIntelligence is designed for mission-critical industrial audio engineering. Our error handling system focuses on **Safety**, **Traceability**, and **Scientific Integrity**.

## 🏛️ The Error Hierarchy

We use a domain-specific, hierarchical error system built on the `AudioIntelligenceError` protocol. This allows you to catch errors at the specific level of granularity your application needs.

```swift
public enum AudioIntelligenceError: Error, Sendable {
    case io(IOError)          // File reading, permissions, disk space
    case dsp(DSPError)        // Buffer overflows, mathematical instability
    case forensic(ForensicError) // Integrity violations, bit-depth forgery
    case setup(SetupError)    // Metal setup failures, hardware mismatch
}
```

### 📁 1. IOError (I/O & Format)
- `.fileNotFound`: The requested URL does not exist.
- `.unsupportedFormat`: The encoder/decoder does not recognize the bitstream.
- `.insufficientCapacity`: The `IntelligenceCache` is full and cannot be pruned.

### 🧪 2. DSPError (Signal Processing)
- `.bufferMismatch`: Incompatible frame counts between engines.
- `.unstableOutput`: Mathematical anomaly (NaN/Inf) detected in feedback loops.
- `.frequencyOverflow`: Requested bins exceed Nyquist frequency.

### 🧬 3. ForensicError (Integrity)
- `.integrityViolation`: SHA-256 fingerprint mismatch detected.
- `.bitDepthForgery`: LSB entropy suggests a fake upsampled file (e.g., 16-bit padded to 24-bit).
- `.invalidSignature`: Codec signature does not match file metadata.

---

## 🛠️ Recovery Strategies

### Safe-Trial Pattern
For non-critical analysis, we recommend the `try?` or localized `do-catch` recovery:
```swift
do {
    let samples = try await AudioLoader.load(url: url)
    let dna = await ForensicEngine().analyze(samples)
} catch AudioIntelligenceError.forensic(.bitDepthForgery) {
    print("⚠️ High-bit depth requested but source is forensicly 16-bit only.")
} catch {
    print("❌ Fatal Error: \(error)")
}
```

### Automatic Cache Recovery
The `IntelligenceCache` is self-healing. If a cached representation fails a checksum, the core engines will automatically force a re-analysis and update the entry.

## 🛡️ Thread Safety & Swift 6
Every engine in AudioIntelligence is a **Global Actor** or an **Actor-isolated** class. This ensures that you can never trigger a data race while interacting with analysis buffers across different threads. No `NSLock` or manual semaphores are required.
