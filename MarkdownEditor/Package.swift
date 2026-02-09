// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "MarkdownEditor",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "MarkdownEditor", targets: ["MarkdownEditor"]),
    ],
    dependencies: [
        .package(path: "../MarkdownKit"),
        .package(path: "../MarkdownPreview"),
    ],
    targets: [
        .target(
            name: "AppKitControls",
            dependencies: ["AppKitExtensions"],
            path: "Sources/Modules/AppKitControls"
        ),
        .target(
            name: "AppKitExtensions",
            path: "Sources/Modules/AppKitExtensions"
        ),
        .target(
            name: "DiffKit",
            path: "Sources/Modules/DiffKit",
            resources: [.process("Resources")]
        ),
        .target(
            name: "FileVersion",
            dependencies: ["AppKitControls", "MarkdownKit", "DiffKit"],
            path: "Sources/Modules/FileVersion"
        ),
        .target(
            name: "FontPicker",
            dependencies: ["AppKitExtensions"],
            path: "Sources/Modules/FontPicker"
        ),
        .target(
            name: "Previewer",
            dependencies: ["AppKitExtensions", "MarkdownKit"],
            path: "Sources/Modules/Previewer",
            resources: [.process("Resources")]
        ),
        .target(
            name: "SettingsUI",
            dependencies: ["AppKitExtensions"],
            path: "Sources/Modules/SettingsUI"
        ),
        .target(
            name: "Statistics",
            dependencies: ["AppKitExtensions", "MarkdownKit"],
            path: "Sources/Modules/Statistics"
        ),
        .target(
            name: "TextBundle",
            path: "Sources/Modules/TextBundle"
        ),
        .target(
            name: "TextCompletion",
            path: "Sources/Modules/TextCompletion"
        ),

        // MARK: - 主 Target（MarkdownEditor 源码 + 胶水层）

        .target(
            name: "MarkdownEditor",
            dependencies: [
                "MarkdownKit",
                "MarkdownPreview",
                "AppKitControls",
                "AppKitExtensions",
                "DiffKit",
                "FileVersion",
                "FontPicker",
                "Previewer",
                "SettingsUI",
                "Statistics",
                "TextBundle",
                "TextCompletion",
            ],
            path: "Sources/MarkdownEditor",
            resources: [
                .copy("Resources/Editor"),
            ],
            swiftSettings: [
                .swiftLanguageMode(.v5),
            ]
        ),
    ]
)
