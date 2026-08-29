// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "AudioIntelligence",
    platforms: [
        .macOS(.v15),
        .iOS(.v18)
    ],
    products: [
        .library(
            name: "AudioIntelligence",
            targets: ["AudioIntelligence"]
        ),
        .executable(
            name: "CLIExample",
            targets: ["CLIExample"]
        ),
        .executable(
            name: "InfinityAudit",
            targets: ["InfinityAudit"]
        ),
        .executable(
            name: "AudioIntelligenceApp",
            targets: ["AudioIntelligenceApp"]
        ),
        .executable(
            name: "AIBenchmark",
            targets: ["AIBenchmark"]
        ),
        .executable(
            name: "SQAMAuditTool",
            targets: ["SQAMAuditTool"]
        ),
        .executable(
            name: "ReliabilityAudit",
            targets: ["ReliabilityAudit"]
        ),
        .executable(
            name: "PrototypeTrainer",
            targets: ["PrototypeTrainer"]
        ),
        .library(
            name: "AudioIntelligenceUI",
            targets: ["AudioIntelligenceUI"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-atomics.git", from: "1.1.0"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.2.0"),
        // Documentation only (build-time plugin; not linked into the library).
        .package(url: "https://github.com/apple/swift-docc-plugin", from: "1.3.0"),
    ],
    targets: [
        // ---------------------------------------------------------------------
        // 1. PUBLIC SDK LAYER: The clean facade for developers.
        // ---------------------------------------------------------------------
        .target(
            name: "AudioIntelligence",
            dependencies: [
                "AudioIntelligenceCore",
                "AudioIntelligenceMetal",
                .product(name: "Atomics", package: "swift-atomics")
            ],
            path: "Sources/AudioIntelligence",
            resources: [
                .process("Resources")
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        
        // ---------------------------------------------------------------------
        // 2. MODULAR CORE LAYER: The high-performance DSP engine (v6.3 Infinity).
        // Includes: Core, Feature, Effects, Display, and Util sub-modules.
        // ---------------------------------------------------------------------
        .target(
            name: "AudioIntelligenceCore",
            dependencies: [
                "AudioIntelligenceMetal"
            ],
            path: "Sources/AudioIntelligenceCore",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),

        // ---------------------------------------------------------------------
        // 3. HARDWARE ACCELERATION: Optional Metal compute kernels.
        // ---------------------------------------------------------------------
        .target(
            name: "AudioIntelligenceMetal",
            path: "Sources/AudioIntelligenceMetal",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        
        // ---------------------------------------------------------------------
        // 4. UI COMPONENTS: Metal-accelerated visualization for SwiftUI.
        // ---------------------------------------------------------------------
        .target(
            name: "AudioIntelligenceUI",
            dependencies: ["AudioIntelligence"],
            path: "Sources/AudioIntelligenceUI",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),

        // ---------------------------------------------------------------------
        // 5. APPLICATIONS & BENCHMARKS: Verification and tools.
        // ---------------------------------------------------------------------
        .executableTarget(
            name: "AudioIntelligenceApp",
            dependencies: ["AudioIntelligenceUI"],
            path: "Sources/AudioIntelligenceApp",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),

        .executableTarget(
            name: "CLIExample",
            dependencies: ["AudioIntelligence"],
            path: "Examples/CLIExample"
        ),
        
        .executableTarget(
            name: "InfinityAudit",
            dependencies: ["AudioIntelligence"],
            path: "Examples/InfinityAudit"
        ),
        
        .executableTarget(
            name: "SQAMAuditTool",
            dependencies: ["AudioIntelligence"],
            path: "Examples/SQAMAuditTool"
        ),

        // Comprehensive real-data reliability scorecard — every engine with a real ground-
        // truth dataset, run in one pass, tracked over time. Not part of `swift test` (runs
        // over thousands of real files; too slow for the normal test loop). See
        // `Examples/ReliabilityAudit/README.md`.
        .executableTarget(
            name: "ReliabilityAudit",
            dependencies: ["AudioIntelligence", "AudioIntelligenceCore", "AudioIntelligenceMetal"],
            path: "Examples/ReliabilityAudit",
            exclude: ["reliability_report.json", "history.jsonl", "README.md"]
        ),
        
        // One-off tool: computes InstrumentEngine's 6 coarse-class prototype fingerprints
        // (centroid range, flatness ceiling, mean MFCC) from real OpenMIC-2018 training data,
        // replacing the original hand-typed placeholder values. Not part of `swift test` —
        // run manually to regenerate the constants when the training methodology changes.
        // See DEVLOG Phase 16.
        .executableTarget(
            name: "PrototypeTrainer",
            dependencies: ["AudioIntelligence", "AudioIntelligenceCore", "AudioIntelligenceMetal"],
            path: "Examples/PrototypeTrainer"
        ),

        .executableTarget(
            name: "AIBenchmark",
            dependencies: [
                "AudioIntelligence",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            path: "Sources/AIBenchmark",
            exclude: ["README.md"]
        ),
        // Scripts are standalone and should not be part of the main build target
//        .executableTarget(
//            name: "DownloadsAudit",
//            dependencies: ["AudioIntelligenceCore"],
//            path: "scripts",
//            sources: ["downloads_audit.swift"]
//        ),
        // ---------------------------------------------------------------------
        // 6. SCIENTIFIC VALIDATION: EBU/AES test suites.
        // ---------------------------------------------------------------------
        .testTarget(
            name: "AudioIntelligenceTests",
            dependencies: ["AudioIntelligence"],
            path: "Tests",
            resources: [
                .copy("Resources")
            ]
        )
    ]
)
