// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "MarkdownKit",
    platforms: [
        .macOS(.v14),
        .iOS(.v15)
    ],
    products: [
        .library(
            name: "MarkdownKit",
            targets: ["MarkdownKit"]
        ),
    ],
    dependencies: [
        .package(path: "../MarkdownCore"),
    ],
    targets: [
        .target(
            name: "MarkdownKit",
            dependencies: ["MarkdownCore"],
            path: "Sources",
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency"),
            ]
        ),
    ]
)
