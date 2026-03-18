// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Gump",
    platforms: [
        .macOS(.v15)
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0"),
    ],
    targets: [
        .executableTarget(
            name: "gump",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Sources/Gump",
            resources: [
                .copy("Resources/runner-boot.sh"),
            ]
        ),
        .testTarget(
            name: "GumpTests",
            dependencies: ["gump"],
            path: "Tests/GumpTests"
        ),
    ]
)
