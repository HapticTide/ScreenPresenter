//
//  ColorProfileManager.swift
//  ScreenPresenter
//
//  Created by Sun on 2026/1/4.
//
//  颜色配置管理器
//  负责 Profile 的 CRUD 操作和持久化存储
//  支持全局设置和按设备类型（iOS/Android）独立设置
//

import Combine
import Foundation

// MARK: - 通知名称

extension Notification.Name {
    /// 颜色配置变更通知
    static let colorProfileDidChange = Notification.Name("colorProfileDidChange")

    /// 颜色补偿启用状态变更通知
    static let colorCompensationEnabledDidChange = Notification.Name("colorCompensationEnabledDidChange")

    /// 设备色彩设置变更通知
    static let deviceColorSettingsDidChange = Notification.Name("deviceColorSettingsDidChange")
}

// MARK: - 颜色配置管理器

/// 颜色配置管理器
/// 单例模式，管理颜色补偿配置的 CRUD 和持久化
/// 支持全局设置和按设备类型独立设置
final class ColorProfileManager: ObservableObject {
    // MARK: - 单例

    static let shared = ColorProfileManager()

    // MARK: - UserDefaults Keys

    private enum Keys {
        static let enabled = "colorCompensation.enabled"
        static let currentProfile = "colorCompensation.currentProfile"
        static let customProfiles = "colorCompensation.customProfiles"
        static let deviceSettings = "colorCompensation.deviceSettings"
    }

    // MARK: - Published 属性（全局设置）

    /// 是否启用颜色补偿（全局）
    @Published var isEnabled: Bool {
        didSet {
            if oldValue != isEnabled {
                UserDefaults.standard.set(isEnabled, forKey: Keys.enabled)
                syncFiltersForAllDevices()
                NotificationCenter.default.post(name: .colorCompensationEnabledDidChange, object: isEnabled)
            }
        }
    }

    /// 当前配置（全局）
    @Published var currentProfile: ColorProfile {
        didSet {
            if oldValue != currentProfile {
                saveCurrentProfile()
                syncFiltersForAllDevices()
                NotificationCenter.default.post(name: .colorProfileDidChange, object: currentProfile)
            }
        }
    }

    /// 自定义配置列表
    @Published var customProfiles: [ColorProfile] = []

    /// 设备独立设置
    @Published var deviceSettings: AllDeviceColorSettings {
        didSet {
            if oldValue != deviceSettings {
                saveDeviceSettings()
                syncFiltersForAllDevices()
                NotificationCenter.default.post(name: .deviceColorSettingsDidChange, object: deviceSettings)
            }
        }
    }

    // MARK: - 设备滤镜实例

    /// iOS 设备的滤镜
    let iosFilter = ColorCompensationFilter()

    /// Android 设备的滤镜
    let androidFilter = ColorCompensationFilter()

    // MARK: - 预设配置

    /// 预设配置列表（只读）
    let presetProfiles: [ColorProfile] = [
        .neutral,
        .coldTV,
        .grayishTV,
        .oversaturatedTV,
    ]

    // MARK: - 初始化

    private init() {
        // 先初始化所有存储属性的默认值
        // 加载启用状态
        isEnabled = UserDefaults.standard.bool(forKey: Keys.enabled)

        // 加载当前配置
        if let data = UserDefaults.standard.data(forKey: Keys.currentProfile),
           let profile = try? JSONDecoder().decode(ColorProfile.self, from: data)
        {
            currentProfile = profile
        } else {
            currentProfile = .neutral
        }

        // 加载设备独立设置（在调用任何方法之前）
        if let data = UserDefaults.standard.data(forKey: Keys.deviceSettings),
           let settings = try? JSONDecoder().decode(AllDeviceColorSettings.self, from: data)
        {
            deviceSettings = settings
        } else {
            deviceSettings = AllDeviceColorSettings()
        }

        // 现在所有存储属性已初始化，可以安全调用方法
        // 加载自定义配置
        loadCustomProfiles()

        // 同步滤镜状态
        syncFiltersForAllDevices()
    }

    // MARK: - 设备滤镜访问

    /// 获取指定平台的滤镜
    func filter(for platform: DevicePlatform) -> ColorCompensationFilter {
        switch platform {
        case .ios: return iosFilter
        case .android: return androidFilter
        }
    }

    /// 同步所有设备滤镜的状态
    private func syncFiltersForAllDevices() {
        syncFilter(for: .ios)
        syncFilter(for: .android)
    }

    /// 同步指定设备的滤镜状态
    private func syncFilter(for platform: DevicePlatform) {
        let settings = deviceSettings[platform]
        let filter = filter(for: platform)
        let (enabled, profile) = settings.effectiveSettings(globalEnabled: isEnabled, globalProfile: currentProfile)

        filter.isEnabled = enabled
        filter.profile = profile
    }

    // MARK: - 设备独立设置

    /// 获取指定平台的设置
    func settings(for platform: DevicePlatform) -> DeviceColorSettings {
        deviceSettings[platform]
    }

    /// 更新指定平台的设置模式
    func setMode(_ mode: DeviceColorMode, for platform: DevicePlatform) {
        var settings = deviceSettings
        settings[platform].mode = mode
        deviceSettings = settings
    }

    /// 更新指定平台的启用状态（独立模式）
    func setEnabled(_ enabled: Bool, for platform: DevicePlatform) {
        var settings = deviceSettings
        settings[platform].isEnabled = enabled
        deviceSettings = settings
    }

    /// 更新指定平台的配置（独立模式）
    func setProfile(_ profile: ColorProfile, for platform: DevicePlatform) {
        var settings = deviceSettings
        settings[platform].profile = profile
        settings[platform].profileId = profile.id
        deviceSettings = settings
    }

    /// 调整指定平台的参数
    func adjustParameter(for platform: DevicePlatform, keyPath: WritableKeyPath<ColorProfile, Float>, value: Float) {
        var settings = deviceSettings
        settings[platform].profile[keyPath: keyPath] = value
        deviceSettings = settings
    }

    // MARK: - Profile CRUD（全局）

    /// 添加自定义配置
    /// - Parameter profile: 配置
    func addCustomProfile(_ profile: ColorProfile) {
        guard !profile.isPreset else { return }
        customProfiles.append(profile)
        saveCustomProfiles()
    }

    /// 更新自定义配置
    /// - Parameters:
    ///   - profile: 新配置
    ///   - index: 索引
    func updateCustomProfile(_ profile: ColorProfile, at index: Int) {
        guard index >= 0, index < customProfiles.count else { return }
        customProfiles[index] = profile
        saveCustomProfiles()

        // 如果更新的是当前配置，同步更新
        if currentProfile.name == profile.name {
            currentProfile = profile
        }
    }

    /// 删除自定义配置
    /// - Parameter index: 索引
    func deleteCustomProfile(at index: Int) {
        guard index >= 0, index < customProfiles.count else { return }
        let profile = customProfiles[index]
        customProfiles.remove(at: index)
        saveCustomProfiles()

        // 如果删除的是当前配置，切换到中性
        if currentProfile.name == profile.name {
            currentProfile = .neutral
        }
    }

    /// 选择预设配置（全局）
    /// - Parameter preset: 预设配置
    func selectPreset(_ preset: ColorProfile) {
        currentProfile = preset
    }

    /// 创建新自定义配置（基于当前配置）
    /// - Parameter name: 名称
    /// - Returns: 新配置
    @discardableResult
    func createCustomProfile(name: String) -> ColorProfile {
        var profile = currentProfile
        profile.name = name
        profile.isPreset = false
        addCustomProfile(profile)
        currentProfile = profile
        return profile
    }

    /// 重置为中性配置（全局）
    func resetToNeutral() {
        currentProfile = .neutral
    }

    // MARK: - 持久化

    /// 保存当前配置
    private func saveCurrentProfile() {
        if let data = try? JSONEncoder().encode(currentProfile) {
            UserDefaults.standard.set(data, forKey: Keys.currentProfile)
        }
    }

    /// 加载自定义配置
    private func loadCustomProfiles() {
        if let data = UserDefaults.standard.data(forKey: Keys.customProfiles),
           let profiles = try? JSONDecoder().decode([ColorProfile].self, from: data)
        {
            customProfiles = profiles
        }
    }

    /// 保存自定义配置
    private func saveCustomProfiles() {
        if let data = try? JSONEncoder().encode(customProfiles) {
            UserDefaults.standard.set(data, forKey: Keys.customProfiles)
        }
    }

    /// 保存设备独立设置
    private func saveDeviceSettings() {
        if let data = try? JSONEncoder().encode(deviceSettings) {
            UserDefaults.standard.set(data, forKey: Keys.deviceSettings)
        }
    }

    // MARK: - 辅助方法

    /// 所有可用配置（预设 + 自定义）
    var allProfiles: [ColorProfile] {
        presetProfiles + customProfiles
    }

    /// 根据名称查找配置
    /// - Parameter name: 名称
    /// - Returns: 配置
    func findProfile(byName name: String) -> ColorProfile? {
        allProfiles.first { $0.name == name }
    }

    /// 获取指定平台的实际生效设置
    func effectiveSettings(for platform: DevicePlatform) -> (enabled: Bool, profile: ColorProfile) {
        let settings = deviceSettings[platform]
        return settings.effectiveSettings(globalEnabled: isEnabled, globalProfile: currentProfile)
    }
}


// MARK: - 扩展：参数调整

extension ColorProfileManager {
    /// 调整 gamma
    func adjustGamma(_ value: Float) {
        var profile = currentProfile
        profile.gamma = value
        currentProfile = profile
    }

    /// 调整黑位提升
    func adjustBlackLift(_ value: Float) {
        var profile = currentProfile
        profile.blackLift = value
        currentProfile = profile
    }

    /// 调整白位裁切
    func adjustWhiteClip(_ value: Float) {
        var profile = currentProfile
        profile.whiteClip = value
        currentProfile = profile
    }

    /// 调整高光柔化
    func adjustHighlightRollOff(_ value: Float) {
        var profile = currentProfile
        profile.highlightRollOff = value
        currentProfile = profile
    }

    /// 调整色温
    func adjustTemperature(_ value: Float) {
        var profile = currentProfile
        profile.temperature = value
        currentProfile = profile
    }

    /// 调整色调
    func adjustTint(_ value: Float) {
        var profile = currentProfile
        profile.tint = value
        currentProfile = profile
    }

    /// 调整饱和度
    func adjustSaturation(_ value: Float) {
        var profile = currentProfile
        profile.saturation = value
        currentProfile = profile
    }
}
