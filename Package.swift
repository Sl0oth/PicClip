// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "PicClip",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(
            name: "PicClip",
            path: "Sources/PicClip",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
