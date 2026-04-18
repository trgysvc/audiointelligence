# AudioIntelligence Project Structure (v6.3 Infinity)

The project follows a modular, silicon-native architecture designed for high-performance DSP on ARM processors, separating public Facade APIs from low-level Implementation engines.

```text
AudioIntelligence/
├── Package.swift               # Swift Package Manager Manifest
├── README.md                   # Global Entry Point (English)
│
├── Sources/
│   ├── AudioIntelligence/      # Public API Layer (Facade)
│   │   ├── AudioIntelligence.swift # Main entry point for developers
│   │   └── Models/             # Shared data models for results
│   │
│   ├── AudioIntelligenceCore/  # Discrete Implementation Layer
│   │   ├── Core/               # Infrastructure (Caching, Errors, Registry)
│   │   ├── Engines/            # Core analysis engines (STFT, Viterbi, NMF, etc.)
│   │   ├── Forensic/           # Bit-depth entropy and provenance tracking
│   │   ├── Models/             # Internal DNA data models
│   │   └── DSP/                # vDSP and Accelerate utility helpers
│   │
│   ├── AudioIntelligenceMetal/ # Hardware-accelerated DSP kernels
│   │   └── MetalEngine.swift   # GPU execution and memory management
│   │
│   └── AudioIntelligenceUI/    # Reusable SwiftUI Engineering Components
│
├── AIBenchmark/                # Professional Parity & Performance CLI
│   └── Sources/                # Benchmark implementation (Swift/ArgumentParser)
│
├── Examples/                   # Ready-to-use sample applications
│   ├── CLIExample/             # Simple library usage example
│   └── InfinityAudit/          # Professional forensic auditor & DNA reporter
│
├── Tests/                      # Unit and integration test suites
│   └── ScientificValidationTests.swift # EBU/AES17 Validation
│
├── docs/                       # Comprehensive Technical Manuals
│   ├── Architecture.md         # Deep dive into Silicon-native design
│   ├── Engines.md              # Technical manual for all DSP engines
│   ├── Forensics.md            # The science of audio provenance
│   ├── Integration.md          # SPM and Concurrency guide
│   ├── Calibration.md          # Official EBU/Scientific Verification Data
│   └── ScientificValidation.md # Real-time audit diagnostic manifest
│
└── LICENSE                     # Apache 2.0 License
```

## Modular Design Philosophy

1. **AudioIntelligence (Public)**: A zero-friction, async/await friendly API for mainstream app development.
2. **AudioIntelligenceCore (Internal)**: The DSP "Engine Room." High-precision implementation using vDSP and AMX.
3. **AudioIntelligenceMetal (Hardware)**: Direct GPU/ANE acceleration for massive batch processing.
4. **AudioIntelligenceUI (Interface)**: Premium visualization components (Spectrograms, Meters, DNA Maps).
5. **InfinityAudit (Auditing)**: External CLI for mathematical integrity validation and forensic reporting.
