// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "MarkdownCore",
    platforms: [
        .macOS(.v14),
        .iOS(.v15)
    ],
    products: [
        .library(
            name: "MarkdownCore",
            targets: ["MarkdownCore"]
        ),
    ],
    targets: [
        .target(
            name: "MarkdownCore",
            path: "Sources",
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency"),
            ]
        ),

        .testTarget(
            name: "MarkdownCoreTests",
            dependencies: ["MarkdownCore"],
            path: "Tests",
            resources: [
                .process("Files"),
            ]
        ),
    ]
)
