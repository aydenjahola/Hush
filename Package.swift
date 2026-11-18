// swift-tools-version: 6.2
import PackageDescription

// Language features enabled on every target. Follow-ups, deliberately not enabled yet:
// InternalImportsByDefault and -strict-memory-safety (see .superpowers/w3-report.md).
let common: [SwiftSetting] = [
    .enableUpcomingFeature("ExistentialAny"),
    .enableUpcomingFeature("MemberImportVisibility"),
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
    .enableUpcomingFeature("InferIsolatedConformances"),
]
// HushUI and HushApp are main-actor code by default; HushCore (pure values) and HushAudio
// (realtime boundary) stay nonisolated by default.
let mainActorDefault = common + [.defaultIsolation(MainActor.self)]

let package = Package(
    name: "Hush",
    defaultLocalization: "en",
    platforms: [.macOS("26.0")],
    products: [
        .executable(name: "Hush", targets: ["HushApp"])
    ],
    targets: [
        .target(name: "HushCore", swiftSettings: common),
        .target(name: "HushAudio", dependencies: ["HushCore"], swiftSettings: common),
        .target(
            name: "HushUI",
            dependencies: ["HushCore", "HushAudio"],
            resources: [.process("Resources")],
            swiftSettings: mainActorDefault
        ),
        .executableTarget(
            name: "HushApp",
            dependencies: ["HushUI", "HushAudio", "HushCore"],
            swiftSettings: mainActorDefault
        ),
        // Test-only helper: plays a sine to a chosen device so integration tests can tap a real process.
        .executableTarget(name: "HushToneGenerator", swiftSettings: common),
        .testTarget(name: "HushCoreTests", dependencies: ["HushCore"], swiftSettings: common),
        .testTarget(name: "HushAudioTests", dependencies: ["HushAudio"], swiftSettings: common),
        .testTarget(
            name: "HushUITests",
            dependencies: ["HushUI", "HushAudio", "HushCore"],
            swiftSettings: mainActorDefault
        ),
        // Real Core Audio: skipped unless HUSH_INTEGRATION=1 (`make integration-test`).
        .testTarget(
            name: "HushIntegrationTests",
            dependencies: ["HushUI", "HushAudio", "HushCore"],
            swiftSettings: common
        ),
    ]
)
