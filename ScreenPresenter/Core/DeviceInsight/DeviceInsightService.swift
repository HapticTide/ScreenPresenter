//
//  DeviceInsightService.swift
//  ScreenPresenter
//
//  Created by Sun on 2025/12/22.
//
//  设备感知服务
//  使用 MobileDevice.framework 获取 iOS 设备详细信息
//
//  【重要】MobileDevice.framework 是增强层，不是核心依赖：
//  - 可用时提供：设备名称、型号、系统版本、信任状态、占用状态
//  - 不可用时：返回降级结果，不影响主捕获流程
//  - 绝不能因为 MobileDevice 失败而阻止 CMIO+AVFoundation 工作
//

import AppKit
import Foundation

// MARK: - 设备信息结构

/// iOS 设备详细信息（来自 MobileDevice.framework）
struct IOSDeviceInsight {
    /// 设备 UDID
    let udid: String

    /// 用户设置的设备名称
    let deviceName: String

    /// 设备型号标识符（如 iPhone14,2）
    let modelIdentifier: String

    /// 设备型号名称（如 iPhone 13 Pro）
    let modelName: String

    /// iOS 版本
    let systemVersion: String

    /// 是否已信任（配对）
    let isTrusted: Bool

    /// 是否被其他应用占用（QuickTime/Xcode 等）
    let isOccupied: Bool

    /// 占用状态描述
    let occupiedBy: String?

    /// 连接类型（USB/WiFi）
    let connectionType: ConnectionType

    enum ConnectionType: String {
        case usb = "USB"
        case wifi = "WiFi"
        case unknown
    }

    /// 降级结果（当 MobileDevice 不可用时使用）
    static func degraded(udid: String, reason: String) -> IOSDeviceInsight {
        AppLogger.device.warning("设备信息降级: \(reason)")
        return IOSDeviceInsight(
            udid: udid,
            deviceName: "iOS 设备",
            modelIdentifier: "unknown",
            modelName: L10n.deviceInfo.unknownModel,
            systemVersion: L10n.deviceInfo.unknownVersion,
            isTrusted: true, // 假设已信任，让主流程继续
            isOccupied: false,
            occupiedBy: nil,
            connectionType: .usb
        )
    }
}

// MARK: - 设备感知服务

/// 设备感知服务
/// 提供 iOS 设备的详细信息，作为增强层使用
final class DeviceInsightService {
    // MARK: - 单例

    static let shared = DeviceInsightService()

    // MARK: - 状态

    /// MobileDevice.framework 是否可用
    private(set) var isMobileDeviceAvailable: Bool = false

    /// 服务初始化错误
    private(set) var initializationError: String?

    // MARK: - 私有属性

    private var mobileDeviceHandle: UnsafeMutableRawPointer?

    // MARK: - 初始化

    private init() {
        setupMobileDevice()
    }

    // MARK: - 设置

    private func setupMobileDevice() {
        // 尝试动态加载 MobileDevice.framework
        let frameworkPath = "/System/Library/PrivateFrameworks/MobileDevice.framework/MobileDevice"

        guard let handle = dlopen(frameworkPath, RTLD_NOW) else {
            let error = String(cString: dlerror())
            initializationError = L10n.mobileDevice.loadFailed(error)
            AppLogger.device.warning("MobileDevice.framework 不可用: \(error)")
            isMobileDeviceAvailable = false
            return
        }

        mobileDeviceHandle = handle
        isMobileDeviceAvailable = true
        AppLogger.device.info("MobileDevice.framework 已加载")
    }

    // MARK: - 公开方法

    /// 获取设备详细信息
    /// - Parameter udid: 设备 UDID（从 AVFoundation 获取的设备 ID）
    /// - Returns: 设备详细信息（可能是降级结果）
    func getDeviceInsight(for udid: String) -> IOSDeviceInsight {
        guard isMobileDeviceAvailable else {
            return .degraded(udid: udid, reason: initializationError ?? "MobileDevice 不可用")
        }

        // 尝试获取设备信息
        do {
            return try fetchDeviceInfo(udid: udid)
        } catch {
            return .degraded(udid: udid, reason: error.localizedDescription)
        }
    }

    /// 检查设备是否已信任
    /// - Parameter udid: 设备 UDID
    /// - Returns: 信任状态（不确定时返回 true 以不阻塞流程）
    func isDeviceTrusted(udid: String) -> Bool {
        guard isMobileDeviceAvailable else { return true }

        // 简化实现：假设已信任
        // 实际实现需要调用 MobileDevice API
        return true
    }

    /// 检查设备是否被占用
    /// - Parameter udid: 设备 UDID
    /// - Returns: (是否被占用, 占用者描述)
    func checkDeviceOccupation(udid: String) -> (isOccupied: Bool, occupiedBy: String?) {
        guard isMobileDeviceAvailable else { return (false, nil) }

        // 检查是否有其他进程正在使用设备
        // 常见占用者：QuickTime Player、Xcode、Instruments

        // 简化实现：检查是否有相关进程在运行
        let occupyingProcesses = ["QuickTime Player", "Xcode", "Instruments"]
        let workspace = NSWorkspace.shared

        for processName in occupyingProcesses {
            if workspace.runningApplications.contains(where: { $0.localizedName == processName }) {
                // 注意：这只是检查进程是否运行，不代表一定占用了当前设备
                AppLogger.device.info("检测到可能占用设备的应用: \(processName)")
            }
        }

        return (false, nil)
    }

    /// 获取用户提示文案
    /// - Parameter insight: 设备信息
    /// - Returns: 用户提示文案（如果有问题需要提示）
    func getUserPrompt(for insight: IOSDeviceInsight) -> String? {
        if !insight.isTrusted {
            return L10n.ios.hint.trust
        }

        if insight.isOccupied, let occupiedBy = insight.occupiedBy {
            return L10n.ios.hint.occupied(occupiedBy)
        }

        return nil
    }

    // MARK: - 私有方法

    private func fetchDeviceInfo(udid: String) throws -> IOSDeviceInsight {
        // 实际的 MobileDevice API 调用
        // 这里提供简化实现，返回基本信息

        // 由于 MobileDevice.framework 是私有框架，API 不稳定
        // 这里使用降级策略，返回从 AVFoundation 能获取的信息

        AppLogger.device.info("获取设备信息: \(udid)")

        // 简化实现：返回基本信息
        return IOSDeviceInsight(
            udid: udid,
            deviceName: "iOS 设备",
            modelIdentifier: "unknown",
            modelName: "iPhone/iPad",
            systemVersion: L10n.deviceInfo.unknown,
            isTrusted: true,
            isOccupied: false,
            occupiedBy: nil,
            connectionType: .usb
        )
    }

    // MARK: - 清理

    deinit {
        if let handle = mobileDeviceHandle {
            dlclose(handle)
        }
    }
}

// MARK: - 设备型号映射

extension DeviceInsightService {
    /// 将型号标识符转换为用户友好的名称
    static func modelName(for identifier: String) -> String {
        let modelMap: [String: String] = [
            // iPhone 15 系列
            "iPhone16,1": "iPhone 15 Pro",
            "iPhone16,2": "iPhone 15 Pro Max",
            "iPhone15,4": "iPhone 15",
            "iPhone15,5": "iPhone 15 Plus",

            // iPhone 14 系列
            "iPhone15,2": "iPhone 14 Pro",
            "iPhone15,3": "iPhone 14 Pro Max",
            "iPhone14,7": "iPhone 14",
            "iPhone14,8": "iPhone 14 Plus",

            // iPhone 13 系列
            "iPhone14,2": "iPhone 13 Pro",
            "iPhone14,3": "iPhone 13 Pro Max",
            "iPhone14,4": "iPhone 13 mini",
            "iPhone14,5": "iPhone 13",

            // iPhone 12 系列
            "iPhone13,1": "iPhone 12 mini",
            "iPhone13,2": "iPhone 12",
            "iPhone13,3": "iPhone 12 Pro",
            "iPhone13,4": "iPhone 12 Pro Max",

            // iPad Pro
            "iPad14,5": "iPad Pro 12.9-inch (6th gen)",
            "iPad14,6": "iPad Pro 12.9-inch (6th gen)",
            "iPad14,3": "iPad Pro 11-inch (4th gen)",
            "iPad14,4": "iPad Pro 11-inch (4th gen)",

            // 更多设备...
        ]

        return modelMap[identifier] ?? identifier
    }
}
