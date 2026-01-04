//
//  ColorProfileManager.swift
//  ScreenPresenter
//
//  Created by Sun on 2026/1/4.
//
//  颜色配置管理器
//  负责 Profile 的 CRUD 操作和持久化存储
//

import Foundation
import Combine

// MARK: - 通知名称

extension Notification.Name {
    /// 颜色配置变更通知
    static let colorProfileDidChange = Notification.Name("colorProfileDidChange")

    /// 颜色补偿启用状态变更通知
    static let colorCompensationEnabledDidChange = Notification.Name("colorCompensationEnabledDidChange")
}

// MARK: - 颜色配置管理器

/// 颜色配置管理器
/// 单例模式，管理颜色补偿配置的 CRUD 和持久化
final class ColorProfileManager: ObservableObject {
    // MARK: - 单例

    static let shared = ColorProfileManager()

    // MARK: - UserDefaults Keys

    private enum Keys {
        static let enabled = "colorCompensation.enabled"
        static let currentProfile = "colorCompensation.currentProfile"
        static let customProfiles = "colorCompensation.customProfiles"
    }

    // MARK: - Published 属性

    /// 是否启用颜色补偿
    @Published var isEnabled: Bool {
        didSet {
            if oldValue != isEnabled {
                UserDefaults.standard.set(isEnabled, forKey: Keys.enabled)
                ColorCompensationFilter.shared.isEnabled = isEnabled
                NotificationCenter.default.post(name: .colorCompensationEnabledDidChange, object: isEnabled)
            }
        }
    }

    /// 当前配置
    @Published var currentProfile: ColorProfile {
        didSet {
            if oldValue != currentProfile {
                saveCurrentProfile()
                ColorCompensationFilter.shared.profile = currentProfile
                NotificationCenter.default.post(name: .colorProfileDidChange, object: currentProfile)
            }
        }
    }

    /// 自定义配置列表
    @Published var customProfiles: [ColorProfile] = []

    // MARK: - 预设配置

    /// 预设配置列表（只读）
    let presetProfiles: [ColorProfile] = [
        .neutral,
        .coldTV,
        .grayishTV,
        .oversaturatedTV
    ]

    // MARK: - 初始化

    private init() {
        // 加载启用状态
        isEnabled = UserDefaults.standard.bool(forKey: Keys.enabled)

        // 加载当前配置
        if let data = UserDefaults.standard.data(forKey: Keys.currentProfile),
           let profile = try? JSONDecoder().decode(ColorProfile.self, from: data) {
            currentProfile = profile
        } else {
            currentProfile = .neutral
        }

        // 加载自定义配置
        loadCustomProfiles()

        // 同步到滤镜
        ColorCompensationFilter.shared.isEnabled = isEnabled
        ColorCompensationFilter.shared.profile = currentProfile
    }

    // MARK: - Profile CRUD

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

    /// 选择预设配置
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

    /// 重置为中性配置
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
           let profiles = try? JSONDecoder().decode([ColorProfile].self, from: data) {
            customProfiles = profiles
        }
    }

    /// 保存自定义配置
    private func saveCustomProfiles() {
        if let data = try? JSONEncoder().encode(customProfiles) {
            UserDefaults.standard.set(data, forKey: Keys.customProfiles)
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
