// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "DrawThingsStudio",
    platforms: [.macOS(.v26)],
    targets: [
        .executableTarget(
            name: "DrawThingsStudio",
            path: "Sources/DrawThingsStudio",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
