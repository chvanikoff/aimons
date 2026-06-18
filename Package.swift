// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AIMon",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "AIMonCore"),
        .executableTarget(
            name: "AIMon",
            dependencies: ["AIMonCore"]
        ),
        .testTarget(
            name: "AIMonCoreTests",
            dependencies: ["AIMonCore"]
        ),
    ]
)
