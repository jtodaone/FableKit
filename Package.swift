// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "FableKit",
    platforms: [.visionOS(.v2), .macOS(.v14)],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "FableKit",
            targets: ["FableKit"]),
    ],
    dependencies: [
//        .package(url: "https://github.com/apple/swift-collections.git", .upToNextMinor(from: "1.1.0"))
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "FableKit",
            dependencies: [
//                .product(name: "DequeModule", package: "swift-collections")
            ]
        ),
        .testTarget(
            name: "FableKitTests",
            dependencies: ["FableKit"]
        ),
    ]
)
