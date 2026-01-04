//
//  DeviceColorSettings.swift
//  ScreenPresenter
//
//  Created by Sun on 2026/1/4.
//
//  设备色彩补偿设置模型
//  支持按设备类型（iOS/Android）独立设置色彩补偿
//

import Foundation

// MARK: - 设备色彩设置模式

/// 设备色彩设置模式
/// 定义设备使用全局设置还是独立设置
enum DeviceColorMode: String, Codable, CaseIterable {
    /// 使用全局设置
    case useGlobal
    /// 使用独立设置
    case independent

    var displayName: String {
        switch self {
        case .useGlobal: L10n.colorCompensation.mode.useGlobal
        case .independent: L10n.colorCompensation.mode.independent
        }
    }
}

// MARK: - 设备色彩设置

/// 单个设备的色彩补偿设置
struct DeviceColorSettings: Codable, Equatable {
    /// 设置模式（全局/独立）
    var mode: DeviceColorMode = .useGlobal

    /// 是否启用色彩补偿（独立设置时使用）
    var isEnabled: Bool = false

    /// 当前配置 ID（独立设置时使用）
    var profileId: UUID?

    /// 当前配置数据（独立设置时使用）
    var profile: ColorProfile = .neutral

    // MARK: - 便捷方法

    /// 获取实际使用的配置
    /// - Parameters:
    ///   - globalEnabled: 全局启用状态
    ///   - globalProfile: 全局配置
    /// - Returns: 实际使用的配置和启用状态
    func effectiveSettings(globalEnabled: Bool, globalProfile: ColorProfile) -> (enabled: Bool, profile: ColorProfile) {
        switch mode {
        case .useGlobal:
            return (globalEnabled, globalProfile)
        case .independent:
            return (isEnabled, profile)
        }
    }
}

// MARK: - 所有设备的色彩设置

/// 所有设备的色彩设置容器
struct AllDeviceColorSettings: Codable, Equatable {
    /// iOS 设备设置
    var ios: DeviceColorSettings = DeviceColorSettings()

    /// Android 设备设置
    var android: DeviceColorSettings = DeviceColorSettings()

    // MARK: - 便捷访问

    /// 根据平台获取设置
    subscript(platform: DevicePlatform) -> DeviceColorSettings {
        get {
            switch platform {
            case .ios: return ios
            case .android: return android
            }
        }
        set {
            switch platform {
            case .ios: ios = newValue
            case .android: android = newValue
            }
        }
    }
}
