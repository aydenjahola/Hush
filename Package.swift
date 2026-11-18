// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Hush",
    platforms: [.macOS("26.0")],
    products: [
        .executable(name: "Hush", targets: ["HushApp"]),
    ],
    targets: [
        .target(name: "HushCore"),
        .target(name: "HushAudio", dependencies: ["HushCore"]),
        .target(name: "HushUI", dependencies: ["HushCore", "HushAudio"]),
        .executableTarget(name: "HushApp", dependencies: ["HushUI", "HushAudio", "HushCore"]),
        // Test-only helper: plays a sine to a chosen device so integration tests can tap a real process.
        .executableTarget(name: "HushToneGenerator"),
        .testTarget(name: "HushCoreTests", dependencies: ["HushCore"]),
        .testTarget(name: "HushAudioTests", dependencies: ["HushAudio"]),
        .testTarget(name: "HushUITests", dependencies: ["HushUI", "HushAudio", "HushCore"]),
        // Real Core Audio: skipped unless HUSH_INTEGRATION=1 (`make integration-test`).
        .testTarget(name: "HushIntegrationTests", dependencies: ["HushUI", "HushAudio", "HushCore"]),
    ]
)
