//
//  IOSScreenMirrorActivator.swift
//  ScreenPresenter
//
//  Created by Sun on 2025/12/22.
//
//  iOS 屏幕镜像激活器
//  使用 CoreMediaIO 启用屏幕捕获设备
//
//  【核心职责】
//  1. 启用 CoreMediaIO DAL 设备（kCMIOHardwarePropertyAllowScreenCaptureDevices）
//  2. 这是 QuickTime 同款路径的关键步骤
//

import CoreMediaIO
import Foundation

// MARK: - iOS 屏幕镜像激活器

/// iOS 屏幕镜像激活器
/// 负责启用 CoreMediaIO DAL 设备以允许访问 iOS 屏幕捕获
final class IOSScreenMirrorActivator {
    // MARK: - 单例

    static let shared = IOSScreenMirrorActivator()

    // MARK: - 状态

    /// 是否已启用 DAL 设备
    private(set) var isDALEnabled = false

    /// 最后一次错误
    private(set) var lastError: String?

    // MARK: - 初始化

    private init() {}

    // MARK: - 公开方法

    /// 启用 CoreMediaIO DAL 设备（允许访问屏幕捕获设备）
    /// 这是使用 AVFoundation 捕获 iOS 屏幕的必要步骤
    @discardableResult
    func enableDALDevices() -> Bool {
        var prop = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyAllowScreenCaptureDevices),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )

        var allow: UInt32 = 1
        let result = CMIOObjectSetPropertyData(
            CMIOObjectID(kCMIOObjectSystemObject),
            &prop,
            0, nil,
            UInt32(MemoryLayout<UInt32>.size),
            &allow
        )

        if result == kCMIOHardwareNoError {
            isDALEnabled = true
            lastError = nil
            AppLogger.device.info("已启用 CoreMediaIO 屏幕捕获设备 (DAL)")
            return true
        } else {
            isDALEnabled = false
            lastError = L10n.iosScreenMirror.enableFailed(result)
            AppLogger.device.warning("启用 CoreMediaIO 屏幕捕获设备失败: \(result)")
            return false
        }
    }

    /// 检查 DAL 设备是否已启用
    func checkDALStatus() -> Bool {
        var prop = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyAllowScreenCaptureDevices),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )

        var allow: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)

        let result = CMIOObjectGetPropertyData(
            CMIOObjectID(kCMIOObjectSystemObject),
            &prop,
            0, nil,
            size,
            &size,
            &allow
        )

        if result == kCMIOHardwareNoError {
            isDALEnabled = allow != 0
            return isDALEnabled
        }

        return false
    }

    /// 激活 iOS 设备的屏幕镜像模式
    /// - Returns: 是否成功
    func activateScreenMirror() async -> Bool {
        AppLogger.device.info("尝试激活 iOS 屏幕镜像...")

        // 启用 DAL 设备
        let dalEnabled = enableDALDevices()

        if dalEnabled {
            // 等待设备枚举
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5秒
            AppLogger.device.info("屏幕镜像激活成功")
            return true
        }

        AppLogger.device.info("屏幕镜像激活失败")
        return false
    }
}
