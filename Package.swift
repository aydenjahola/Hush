// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Hush",
    platforms: [.macOS("26.0")],
    targets: [
        .target(name: "HushCore"),
        .testTarget(name: "HushCoreTests", dependencies: ["HushCore"]),
    ]
)
