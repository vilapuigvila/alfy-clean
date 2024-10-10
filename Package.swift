// swift-tools-version:5.5
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "avp",
    platforms: [
        .macOS(.v10_15)
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "0.3.0"),
        .package(url: "https://github.com/qiuzhifei/swift-commands", from: "0.6.0"),
        .package(url: "https://github.com/vapor/jwt-kit.git", from: "4.0.0"),
        .package(url: "https://github.com/Kitura/Swift-JWT.git", from: "4.0.0")
    ],
    targets: [
        .executableTarget(
            name: "avp",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "Commands", package: "swift-commands"),
                .product(name: "JWTKit", package: "jwt-kit"),
                .product(name: "SwiftJWT", package: "Swift-JWT"),
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
