// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ZipPaint",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "ZipPaint", path: "Sources/ZipPaint")
    ]
)
