# AudioIntelligence Project Structure

A modular, Apple-Silicon-native package that separates the public facade from the DSP
implementation, the report schema, and the UI.

```text
AudioIntelligence/
├── Package.swift                 # SwiftPM manifest (swift-tools 6.3)
├── README.md · CHANGELOG.md · DEVLOG.md · CONTRIBUTING.md · CODE_OF_CONDUCT.md · LICENSE
│
├── Sources/
│   ├── AudioIntelligence/            # PUBLIC facade (the `AudioIntelligence` actor)
│   │   ├── AudioIntelligence.swift
│   │   └── Documentation.docc/       # DocC catalog
│   │
│   ├── AudioIntelligenceCore/        # DSP engine room
│   │   ├── Core/                     # Loading, caching, errors
│   │   ├── Feature/                  # All analysis engines (STFT, Loudness, Forensic, …)
│   │   ├── Effects/                  # HPSS, NMF, stem separation, manipulation
│   │   ├── Report/                   # AudioReport schema, Measured/Estimated, mapping, MarkdownRenderer
│   │   ├── Display/                  # Visualization data structures
│   │   ├── Models/                   # Public value types (AudioReport, AudioFeature)
│   │   └── Util/                     # DNAReportBuilder pipeline, DSP/ helpers, calibration, auditing
│   │
│   ├── AudioIntelligenceMetal/       # Optional Metal compute kernels (CPU fallback)
│   ├── AudioIntelligenceUI/          # SwiftUI components (MainDashboardView, SpectralLandscapeView…)
│   ├── AudioIntelligenceApp/         # Demo SwiftUI app target
│   └── AIBenchmark/                  # Performance & parity CLI (ArgumentParser)
│
├── Examples/                        # Standalone example executables
│   ├── CLIExample/                   # Minimal library usage
│   ├── InfinityAudit/                # Renders + persists an AudioReport (md + plist)
│   └── SQAMAuditTool/                # Batch SQAM audit utility
│
├── Tests/                           # Validation & unit suites (EBU/AES/librosa-parity/golden)
│
└── docs/                            # Technical manuals (this folder)
    ├── REPORT_SPECIFICATION.md       # The AudioReport schema & transport
    ├── Architecture.md · Engines.md · Forensics.md · Integration.md
    ├── AI_INTEGRATION_GUIDE.md · ScientificValidation.md · Calibration.md
    ├── FormatSupport.md · ErrorHandling.md · Migration_from_Librosa.md
    ├── ProjectStructure.md · RiskManagement.md
    └── Tutorials/
```

## Module responsibilities

1. **AudioIntelligence (public):** a thread-safe `actor` facade. `analyze(url:features:)` returns
   a typed `AudioReport`; the library writes no files.
2. **AudioIntelligenceCore (internal DSP):** the engines (under `Feature/`), the analysis
   pipeline (`Util/DNAReportBuilder`), and the report schema (`Report/`). High-precision Swift on
   Accelerate/vDSP.
3. **AudioIntelligenceMetal (hardware):** optional GPU kernels with a CPU fallback.
4. **AudioIntelligenceUI (interface):** SwiftUI views that consume `AudioReport`.

> Note: the analysis engines all live under `Core/Feature/` — there are no separate `Engines/`,
> `Forensic/`, or top-level `DSP/` directories. DSP helpers are under `Core/Util/DSP/`.
