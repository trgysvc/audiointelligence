// swift-tools-version: 6.0
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
        )
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-atomics.git", from: "1.1.0"),
    ],
    targets: [
        // Public API Layer
        .target(
            name: "AudioIntelligence",
            dependencies: [
                "AudioIntelligenceCore",
                .product(name: "Atomics", package: "swift-atomics")
            ],
            path: "Sources/AudioIntelligence"
        ),
        
        // Private Implementation Layer
        .target(
            name: "AudioIntelligenceCore",
            path: "Sources/AudioIntelligenceCore"
        ),

        // Optional Metal Layer
        .target(
            name: "AudioIntelligenceMetal",
            path: "Sources/AudioIntelligenceMetal"
        ),

        // Hello World Example CLI
        .executableTarget(
            name: "CLIExample",
            dependencies: ["AudioIntelligence"],
            path: "Examples/CLIExample"
        ),

        // Tests
        .testTarget(
            name: "AudioIntelligenceTests",
            dependencies: ["AudioIntelligence"],
            path: "Tests/AudioIntelligenceTests"
        )
    ]
)
