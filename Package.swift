// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Hush",
    platforms: [.macOS("26.0")],
    targets: [
        .target(name: "HushCore"),
        .target(name: "HushAudio", dependencies: ["HushCore"]),
        .target(name: "HushUI", dependencies: ["HushCore", "HushAudio"]),
        .testTarget(name: "HushCoreTests", dependencies: ["HushCore"]),
        .testTarget(name: "HushAudioTests", dependencies: ["HushAudio"]),
        .testTarget(name: "HushUITests", dependencies: ["HushUI", "HushAudio", "HushCore"]),
    ]
)
