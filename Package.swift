// swift-tools-version:6.4
import PackageDescription

let package = Package(
    name: "GitGrail",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "GrailCore"),
        .executableTarget(name: "GitGrail", dependencies: ["GrailCore"]),
        .testTarget(name: "GrailCoreTests", dependencies: ["GrailCore"]),
    ]
)
