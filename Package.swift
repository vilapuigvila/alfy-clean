// swift-tools-version:5.5
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "alfy-clean",
    platforms: [
        .macOS(.v12),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "0.3.0"),
    ],
    targets: [
        .executableTarget(
            name: "alfy-clean",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Sources/alfy-clean"),
        .testTarget(
            name: "alfy-cleanTests",
            dependencies: ["alfy-clean"],
            path: "Tests/alfy-cleanTests"),
    ]
)
