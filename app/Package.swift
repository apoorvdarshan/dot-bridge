// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "DotBridge",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(
            name: "DotBridge",
            path: "Sources/DotBridge",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
