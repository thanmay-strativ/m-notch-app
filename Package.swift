// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MNotch",
    platforms: [.macOS(.v15)],
    targets: [
        .target(name: "MNotchCore"),
        .executableTarget(name: "MNotch", dependencies: ["MNotchCore"]),
        .testTarget(name: "MNotchCoreTests", dependencies: ["MNotchCore"]),
    ]
)
