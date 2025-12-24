// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "FBDeviceControlKit",
    platforms: [
        .macOS(.v12),
    ],
    products: [
        // 主要产品：Swift API
        .library(
            name: "FBDeviceControlKit",
            targets: ["FBDeviceControlKit"]
        ),
        // 底层 ObjC 模块（高级用户可直接使用）
        .library(
            name: "CFBDeviceControl",
            targets: ["CFBDeviceControl"]
        ),
    ],
    targets: [
        // MARK: - ObjC Targets

        // FBControlCore - 核心控制层
        .target(
            name: "CFBControlCore",
            dependencies: [],
            path: "Sources/CFBControlCore",
            publicHeadersPath: "include",
            cSettings: [
                .define("FB_DEVICE_CONTROL_SOURCES_COMPILED", to: "1"),
            ],
            linkerSettings: [
                .linkedFramework("Foundation"),
                .linkedFramework("CoreServices"),
            ]
        ),

        // FBDeviceControl - 设备控制层
        .target(
            name: "CFBDeviceControl",
            dependencies: ["CFBControlCore"],
            path: "Sources/CFBDeviceControl",
            publicHeadersPath: "include",
            cSettings: [
                .define("FB_DEVICE_CONTROL_SOURCES_COMPILED", to: "1"),
            ],
            linkerSettings: [
                .linkedFramework("Foundation"),
                .linkedFramework("CoreMedia"),
                .linkedFramework("AVFoundation"),
            ]
        ),

        // MARK: - Swift Target

        // FBDeviceControlKit - Swift API 层
        .target(
            name: "FBDeviceControlKit",
            dependencies: ["CFBDeviceControl"],
            path: "Sources/FBDeviceControlKit"
        ),
    ]
)
