//
//  PermissionChecker.swift
//  ScreenPresenter
//
//  Created by Sun on 2025/12/22.
//
//  权限检查器
//  检测和请求屏幕录制等系统权限
//

import AppKit
import Foundation
import ScreenCaptureKit

// MARK: - 权限状态

enum PermissionStatus: Equatable {
    case unknown
    case checking
    case granted
    case denied
    case notDetermined

    var displayName: String {
        switch self {
        case .unknown:
            "未知"
        case .checking:
            "检查中..."
        case .granted:
            "已授权"
        case .denied:
            "已拒绝"
        case .notDetermined:
            "未设置"
        }
    }

    var icon: String {
        switch self {
        case .granted:
            "checkmark.circle.fill"
        case .denied:
            "xmark.circle.fill"
        case .notDetermined:
            "questionmark.circle"
        default:
            "circle"
        }
    }

    var iconColor: String {
        switch self {
        case .granted:
            "green"
        case .denied:
            "red"
        case .notDetermined:
            "orange"
        default:
            "gray"
        }
    }
}

// MARK: - 权限项

struct PermissionItem: Identifiable {
    let id: String
    let name: String
    let description: String
    var status: PermissionStatus
    let isRequired: Bool
    let settingsURL: URL?
}

// MARK: - 权限检查器

@MainActor
final class PermissionChecker {
    // MARK: - 状态

    /// 屏幕录制权限
    private(set) var screenRecordingStatus: PermissionStatus = .unknown

    /// 是否所有必需权限都已授予
    var allPermissionsGranted: Bool {
        true // 权限为可选
    }

    /// 权限列表
    var permissions: [PermissionItem] {
        [
            PermissionItem(
                id: "screenRecording",
                name: "屏幕录制",
                description: "用于捕获 Android 设备投屏画面（仅备用方案需要）",
                status: screenRecordingStatus,
                isRequired: false,
                settingsURL: URL(
                    string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
                )
            ),
        ]
    }

    // MARK: - 公开方法

    /// 检查所有权限
    func checkAll() async {
        await checkScreenRecordingPermission()
    }

    /// 检查屏幕录制权限
    func checkScreenRecordingPermission() async {
        screenRecordingStatus = .checking

        // 使用 CGPreflightScreenCaptureAccess 检查当前权限状态
        let hasAccess = CGPreflightScreenCaptureAccess()

        if hasAccess {
            screenRecordingStatus = .granted
        } else {
            screenRecordingStatus = .denied
        }
    }

    /// 请求屏幕录制权限
    func requestScreenRecordingPermission() async -> Bool {
        let result = CGRequestScreenCaptureAccess()
        await checkScreenRecordingPermission()
        return result
    }

    /// 打开系统偏好设置
    func openSystemPreferences(for permissionID: String) {
        if
            let permission = permissions.first(where: { $0.id == permissionID }),
            let url = permission.settingsURL {
            NSWorkspace.shared.open(url)
        }
    }

    /// 打开隐私设置
    func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy") {
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: - 工具检查扩展

extension PermissionChecker {
    /// 检查工具链状态
    func checkToolchain(manager: ToolchainManager) -> [ToolchainCheckItem] {
        [
            ToolchainCheckItem(
                name: "adb",
                description: "Android 调试工具",
                status: manager.adbStatus,
                isRequired: true
            ),
            ToolchainCheckItem(
                name: "scrcpy",
                description: "Android 投屏工具",
                status: manager.scrcpyStatus,
                isRequired: true
            ),
        ]
    }
}

// MARK: - 工具链检查项

struct ToolchainCheckItem: Identifiable {
    let name: String
    let description: String
    let status: ToolchainStatus
    let isRequired: Bool

    var id: String { name }

    var statusIcon: String {
        switch status {
        case .installed:
            "checkmark.circle.fill"
        case .installing:
            "arrow.down.circle"
        case .notInstalled:
            "xmark.circle"
        case .error:
            "exclamationmark.circle.fill"
        }
    }

    var statusColor: String {
        switch status {
        case .installed:
            "green"
        case .installing:
            "blue"
        case .notInstalled:
            "orange"
        case .error:
            "red"
        }
    }
}
