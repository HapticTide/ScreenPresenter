// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "MarkdownPreview",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "MarkdownPreview", targets: ["MarkdownPreview"]),
    ],
    targets: [
        .target(
            name: "MarkdownPreview",
            path: "Sources/MarkdownPreview",
            resources: [
                .copy("Resources/Preview"),
            ],
            swiftSettings: [
                .swiftLanguageMode(.v5),
            ]
        ),
    ]
)
