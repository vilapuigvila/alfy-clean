// swift-tools-version:5.5
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "avp",
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "0.3.0"),
        .package(url: "https://github.com/qiuzhifei/swift-commands", from: "0.6.0")
    ],
    targets: [
        .executableTarget(
            name: "avp",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "Commands", package: "swift-commands")
            ],
            path: "Sources/spm",
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "avpTests",
            dependencies: ["avp"],
            path: "Tests/spmTests"
        ),
    ]
)
