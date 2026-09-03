# 🔬 Scientific Validation: Diagnostic Protocol (v6.3)

This protocol is the diagnostic manifest for the **measurement** engines of the AudioIntelligence
suite. Each scenario below is backed by a reference signal or a reference implementation; "PASS"
means high-precision agreement on the *tested* scenario, not exhaustive coverage of every
channel / sample-rate / edge case. It applies to the deterministic measurement layer
(loudness, true peak, THD+N, IMD, noise) — **not** to the statistical estimation layer
(tempo/key/instrument), whose accuracy is reported separately in the README Validation Status.

---

## 1. Audit Methodology: The "Digital Twin"

To ensure that real-world file artifacts don't interfere with DSP accuracy, every release is subjected to memory-direct audits using **Reference Signals**:
- **Baseline**: 1000 Hz Sine at -23.0 dBFS (Professional Reference).
- **Stress-Test**: White Noise (unpredictable spectral density).
- **Dynamic**: Gated sequences (-20 LUFS to -70 LUFS transitions).

---

## 2. Standard Diagnostic Scenarios (The Compliance Audit)

### Scenario A: Reference Calibration (EBU 3341 - 2.1)
- **Input**: 1000 Hz Sine Wave at -23.0 dBFS.
- **Requirement**: **-23.0 LUFS** (± 0.1 LU).
- **Audit Result**: ✅ PASS (**-22.994 LUFS**).

### Scenario B: Gating & Silence Rejection (EBU 3341 - 2.2)
- **Input**: 5s of -20 LUFS sine followed by 5s of -100 LUFS silence.
- **Requirement**: **-20.0 LUFS** (ignore silence).
- **Audit Result**: ✅ PASS (**-20.126 LUFS**).

### Scenario C: Dynamic Range Precision (EBU 3342 - LRA)
- **Input**: Alternating 10s blocks of -20 LUFS and -30 LUFS tones.
- **Requirement**: **10.0 LU** (± 0.2 LU).
- **Audit Result**: ✅ PASS (**10.000 LU**).

### Scenario D: AES17 Forensic Reliability
- **Input**: -60 dBFS 997Hz Sine + 24-bit Theoretical Noise Floor.
- **Requirement**: Match SNR of the 32-bit internal float calculation.
- **Audit Result**: ✅ PASS (**88.289 dB SNR @ stim**).

---

## 3. High-Priority Engineering Audits

### 🧪 Viterbi Path Verification
- **Input**: Synthetic state transition matrix with known "Maximum Likelihood Path."
- **Audit**: Engine must decode the exact path index-for-index without smoothing artifacts.
- **Status**: ✅ pass.

### 🧬 Upsampling (fake hi-res) detection
- **Input**: A native 24-bit signal vs. 16-bit content padded into a 24-bit container.
- **Audit**: The engine must flag `isUpsampled` only when the declared bit depth exceeds the
  *measured* effective depth (`sourceBitDepth > effectiveBits`) — it must **not** key off entropy
  (a low-entropy authentic recording must read `upsampled: no`).
- **Status**: ✅ pass.

---

## 4. Rerunning the Audit

Professional engineers can verify these metrics at any time using the automated diagnostic suite:

```bash
# Option 1: Execute the measurement-validation suites via tests
swift test --filter EBUReferenceValidationTests    # loudness vs ffmpeg ebur128
swift test --filter ScientificAuditorTests         # EBU 3341/3342 calibration

# Option 2: Run a live audit via the InfinityAudit CLI. It prints the rendered report and
# writes <input>.md + <input>.plist next to the source file (the library itself writes nothing;
# this is the example app persisting the AudioReport).
swift run InfinityAudit "path/to/audio/file.wav"
```

*Last reviewed: 2026-09-04 — AudioIntelligence 8.2.3. Scope unchanged since prior review (measurement layer only; no loudness/forensic code changed).*
