# 📊 AIBenchmark CLI

The professional auditing tool for the AudioIntelligence SDK.

## 🚀 Overview
`AIBenchmark` is designed to verify the mathematical parity and performance efficiency of the AudioIntelligence engines against industry-standard reference models.

## 🛠 Usage

### Basic Analysis
Measure execution time and BPM accuracy for a single file:
```bash
swift run AIBenchmark path/to/audio.wav
```

### Reference Parity Audit
Provide a ground-truth report (a binary-plist `AudioReport`, e.g. saved from a known-good run)
to compare tempo and key against it:
```bash
swift run AIBenchmark path/to/audio.wav --ref-primary ground_truth.plist
```

## 📈 Benchmark Metrics
- **Execution time** for a full analysis.
- **Tempo / key parity** against the reference `AudioReport` (BPM delta, key match).

## 📄 License
Released as part of the AudioIntelligence Suite under Apache 2.0.
