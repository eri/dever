// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Dever",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Dever",
            path: "Sources/Dever",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
