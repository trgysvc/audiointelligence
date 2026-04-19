// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CLIExample",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(path: "../../") // Local dependency on parent SDK
    ],
    targets: [
        .executableTarget(
            name: "CLIExample",
            dependencies: [
                .product(name: "AudioIntelligence", package: "audiointelligence")
            ],
            path: "."
        )
    ]
)
