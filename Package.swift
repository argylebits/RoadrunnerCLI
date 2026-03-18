// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Roadrunner",
    platforms: [
        .macOS(.v15)
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0"),
        .package(url: "https://github.com/argylebits/swift-version-plugin", from: "1.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "roadrunner",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Sources/Roadrunner",
            exclude: ["Resources/runner-boot.sh"],
            plugins: [
                .plugin(name: "VersionPlugin", package: "swift-version-plugin"),
            ]
        ),
        .testTarget(
            name: "RoadrunnerTests",
            dependencies: ["roadrunner"],
            path: "Tests/RoadrunnerTests"
        ),
    ]
)
