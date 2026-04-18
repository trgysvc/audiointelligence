// swift-tools-version: 6.3.0
import PackageDescription

let package = Package(
    name: "AudioIntelligence",
    platforms: [
        .macOS(.v14),
        .iOS(.v17)
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
        .library(
            name: "AudioIntelligenceUI",
            targets: ["AudioIntelligenceUI"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-atomics.git", from: "1.1.0"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.2.0"),
    ],
    targets: [
        // ---------------------------------------------------------------------
        // 1. PUBLIC SDK LAYER: The clean facade for developers.
        // ---------------------------------------------------------------------
        .target(
            name: "AudioIntelligence",
            dependencies: [
                "AudioIntelligenceCore",
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
        // 2. MODULAR CORE LAYER: The high-performance DSP engine (v6.1 Infinity).
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
            name: "AIBenchmark",
            dependencies: [
                "AudioIntelligence",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            path: "Sources/AIBenchmark",
            exclude: ["README.md"]
        ),
        
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
