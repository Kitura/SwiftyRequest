// swift-tools-version:4.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "TestServer",
    dependencies: [
        // Dependencies declare other packages that this package depends on.
        .package(url: "https://github.com/Kitura/Kitura.git", from: "2.6.0"),
        .package(url: "https://github.com/Kitura/FileKit.git", .upToNextMinor(from: "0.0.0")),
        .package(url: "https://github.com/Kitura/HeliumLogger.git", from: "1.8.0"),
        .package(url: "https://github.com/Kitura/Swift-JWT.git", from: "3.1.0"),
    ],
    targets: [
        // Targets are the basic building blocks of a package. A target can define a module or a test suite.
        // Targets can depend on other targets in this package, and on products in packages which this package depends on.
        .target(
            name: "TestServer",
            dependencies: ["Kitura", "FileKit", "HeliumLogger", "SwiftJWT"]),
    ]
)
