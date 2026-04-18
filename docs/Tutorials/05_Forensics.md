# Tutorial 05: Scientific Forensics & Auditing

AudioIntelligence isn't just for features; it's a **Truth Engine**. For forensic investigators, mastering engineers, and quality assurance teams, the **Forensic Engine** provides conclusive evidence of a signal's origin and integrity.

---

## 🕵️ 1. Detecting Fake Hi-Res (Entropy Analysis)

The most common "forgery" in digital audio is upsampling a 16-bit (CD) file to 24-bit (Hi-Res). This adds no dynamic range but inflates the file size.

### The Science
- **Authentic 24-bit**: Significant thermal noise and micro-details in the lower 8 bits (Least Significant Bits).
- **Upsampled 16-bit**: Zero entropy (all zeros or static padding) in the lower 8 bits.

```swift
let results = try await sdk.analyze(url: audioURL, features: [.forensic])
let forensic = results.rawAnalysis.forensic

if forensic.isUpsampled {
    print("⚠️ FAKE HI-RES detected.")
    print("Effective Resolution: 16-bit")
    print("Shannon Entropy: \(forensic.lsbEntropy) (Expected > 0.8)")
}
```

---

## 📦 2. Codec Signature & Cutoff Detection

Every lossy codec (MP3, AAC, Vorbis) leaves a "Spectral Bracketing" signature. If a WAV file exhibits a brick-wall cutoff at 16kHz, we can mathematically prove it was previously an MP3.

```swift
let report = try await sdk.analyze(url: audioURL)

if let signature = report.rawAnalysis.forensic.detectedSourceCodec {
    print("Historical Provenance: \(signature)")
    print("Cutoff Frequency: \(report.rawAnalysis.forensic.cutoffFrequency) Hz")
}
```

---

## ⚖️ 3. EBU R128 Metering Compliance

For professional distribution, meeting the -23 LUFS (Integrated) loudness standard is mandatory. Our `MasteringEngine` is calibrated against **EBU Tech 3341** test vectors with ±0.1 LU precision.

```swift
let mastering = report.rawAnalysis.mastering

print("Integrated Loudness: \(mastering.integratedLUFS) LUFS")
print("Loudness Range (LRA): \(mastering.lra) LU")
print("True Peak (dBTP): \(mastering.truePeak) dB")

if mastering.integratedLUFS > -22.0 {
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
    let forensic: ForensicResult
    
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
                
                LabeledContent("LSB Entropy", value: String(format: "%.3f", forensic.lsbEntropy))
                LabeledContent("Bit Density", value: "\(forensic.activeBits)-bit")
            }
            
            Section("Codec Audit") {
                LabeledContent("Detected History", value: forensic.detectedSourceCodec ?? "Original Lossless")
                LabeledContent("Spectral Ceiling", value: "\(Int(forensic.cutoffFrequency)) Hz")
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

// Access the human-readable forensic report
let auditText = report.reportText
print(auditText)

// Save to disk for sharing
try auditText.write(to: report.reportPath, atomically: true, encoding: .utf8)
```

---
*Congratulations! You have completed the AudioIntelligence Infinity Tutorial series. You are now equipped to build world-class, silicon-optimized professional audio applications.*
