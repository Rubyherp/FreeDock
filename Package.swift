// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FreeDock",
    platforms: [.macOS(.v12)],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "FreeDock"
        ),
        .testTarget(
            name: "FreeDockTests",
            dependencies: ["FreeDock"]
        )
    ]
)
