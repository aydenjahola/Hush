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
        .testTarget(name: "HushCoreTests", dependencies: ["HushCore"]),
        .testTarget(name: "HushAudioTests", dependencies: ["HushAudio"]),
        .testTarget(name: "HushUITests", dependencies: ["HushUI", "HushAudio", "HushCore"]),
    ]
)
