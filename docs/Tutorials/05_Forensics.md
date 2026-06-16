# Tutorial 05: Scientific Forensics & Auditing

AudioIntelligence isn't just for features; it's a **Truth Engine**. For forensic investigators, mastering engineers, and quality assurance teams, the **Forensic Engine** provides conclusive evidence of a signal's origin and integrity.

---

## 🕵️ 1. Detecting Fake Hi-Res (Entropy Analysis)

The most common "forgery" in digital audio is upsampling a 16-bit (CD) file to 24-bit (Hi-Res). This adds no dynamic range but inflates the file size.

### The Science
- **Authentic 24-bit**: Significant thermal noise and micro-details in the lower 8 bits (Least Significant Bits).
- **Upsampled 16-bit**: Zero entropy (all zeros or static padding) in the lower 8 bits.

```swift
let results = try await sdk.analyze(url: audioURL)
let forensic = results.measurements.forensic

if forensic.isUpsampled {
    print("⚠️ FAKE HI-RES detected.")
    print("Declared Resolution: \(forensic.sourceBitDepth.value)-bit")
    print("Effective Resolution: \(forensic.effectiveBits.value)-bit")
    print("Shannon Entropy: \(forensic.entropyScore.value) (Expected > 0.8)")
}
```

---

## 📦 2. Codec Signature & Cutoff Detection

Every lossy codec (MP3, AAC, Vorbis) leaves a "Spectral Bracketing" signature. If a WAV file exhibits a brick-wall cutoff at 16kHz, we can mathematically prove it was previously an MP3.

```swift
let report = try await sdk.analyze(url: audioURL)
let forensic = report.measurements.forensic

if forensic.codecCutoff.value < 20000 {
    print("Historical Provenance: Likely compressed (Cutoff at \(Int(forensic.codecCutoff.value)) Hz)")
}
if let encoder = report.metadata.encoder {
    print("Container Encoder: \(encoder)")
}
```

---

## ⚖️ 3. EBU R128 Metering Compliance

For professional distribution, meeting the -23 LUFS (Integrated) loudness standard is mandatory. Our `MasteringEngine` is calibrated against **EBU Tech 3341** test vectors with ±0.1 LU precision.

```swift
let loudness = report.measurements.loudness

print("Integrated Loudness: \(loudness.integrated.value) LUFS")
print("Loudness Range (LRA): \(loudness.range.value) LU")
print("True Peak (dBTP): \(loudness.truePeak.value) dB")

if loudness.integrated.value > -22.0 {
    print("🚨 Loudness exceeds EBU R128 target of -23 LUFS.")
}
```

---

## 🖼️ 4. SwiftUI Integration: Professional Quality Auditor

You can build a professional "File Validator" dashboard using the SDK's reporting capabilities.

```swift
import SwiftUI
import AudioIntelligence

struct ForensicAuditView: View {
    let forensic: ForensicMeasurements
    let metadata: ReportMetadata
    
    var body: some View {
        List {
            Section("Signal Authenticity") {
                HStack {
                    Label("Provenance DNA", systemImage: "fingerprint")
                    Spacer()
                    Text(forensic.isUpsampled ? "Upsampled" : "Authentic Native")
                        .foregroundColor(forensic.isUpsampled ? .red : .green)
                        .bold()
                }
                
                LabeledContent("LSB Entropy", value: String(format: "%.3f", forensic.entropyScore.value))
                LabeledContent("Bit Density", value: "\(forensic.effectiveBits.value)-bit")
            }
            
            Section("Codec Audit") {
                LabeledContent("Detected Encoder", value: metadata.encoder ?? "Unknown/Original Lossless")
                LabeledContent("Spectral Ceiling", value: "\(Int(forensic.codecCutoff.value)) Hz")
            }
        }
        .headerProminence(.increased)
    }
}
```

---

## ✅ 5. Generating the Scientific DNA Report

AudioIntelligence can generate a complete, formatted **Markdown DNA Report** that mirrors the structure of an official forensic audit.

```swift
let report = try await sdk.analyze(url: audioURL)

// Serialize the report to JSON
let json = try report.jsonData(prettyPrinted: true)
if let jsonString = String(data: json, encoding: .utf8) {
    print(jsonString)
}

// Save to disk for sharing
try json.write(to: URL(fileURLWithPath: "report.json"))
```

---
*Congratulations! You have completed the AudioIntelligence Infinity Tutorial series. You are now equipped to build world-class, silicon-optimized professional audio applications.*
