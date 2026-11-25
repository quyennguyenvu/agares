// swift-tools-version: 5.9
// 5.9 on purpose: Swift 5 language mode, which the AppKit and event-tap glue is written for.
import PackageDescription

let package = Package(
    name: "Agares",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "AgaresEngine"),
        .executableTarget(name: "Agares", dependencies: ["AgaresEngine"]),
        .testTarget(name: "AgaresEngineTests", dependencies: ["AgaresEngine"]),
    ]
)
