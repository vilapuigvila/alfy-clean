// swift-tools-version:5.5
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "avp",
    platforms: [
        .macOS(.v12),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "0.3.0"),
    ],
    targets: [
        .executableTarget(
            name: "avp",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Sources/spm",
            exclude: ["Resources/Scripts/buildWithTimingSummary.sh"]),
        .testTarget(
            name: "avpTests",
            dependencies: ["avp"],
            path: "Tests/spmTests"),
    ]
)
