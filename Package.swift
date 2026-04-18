// swift-tools-version: 6.3.0
import PackageDescription

let package = Package(
    name: "AudioIntelligence",
    platforms: [
        .macOS(.v13),
        .iOS(.v16)
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
        // Public API Layer
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
                .enableUpcomingFeature("StrictConcurrency")
            ]
        ),
        
        // Private Implementation Layer
        .target(
            name: "AudioIntelligenceCore",
            dependencies: [
                "AudioIntelligenceMetal"
            ],
            path: "Sources/AudioIntelligenceCore",
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ]
        ),

        // Optional Metal Layer
        .target(
            name: "AudioIntelligenceMetal",
            path: "Sources/AudioIntelligenceMetal",
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ]
        ),
        
        // Reusable UI Component Layer (SDK Friendly)
        .target(
            name: "AudioIntelligenceUI",
            dependencies: ["AudioIntelligence"],
            path: "Sources/AudioIntelligenceUI",
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ]
        ),

        // Premium Standalone Application (macOS)
        .executableTarget(
            name: "AudioIntelligenceApp",
            dependencies: ["AudioIntelligenceUI"],
            path: "Sources/AudioIntelligenceApp",
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ]
        ),

        // Hello World Example CLI
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
        
        // Scientific Validation Tests
        .testTarget(
            name: "AudioIntelligenceTests",
            dependencies: ["AudioIntelligence"],
            path: "Tests"
        )
    ]
)
