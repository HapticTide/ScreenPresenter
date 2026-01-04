//
//  ColorProfile.swift
//  ScreenPresenter
//
//  Created by Sun on 2026/1/4.
//
//  颜色补偿配置模型
//  定义电视端预补偿的所有参数
//

import Foundation

// MARK: - 颜色补偿配置

/// 颜色补偿配置
/// 用于描述一套电视对应的预补偿参数
struct ColorProfile: Codable, Equatable, Identifiable {
    // MARK: - 标识

    /// 唯一标识符
    var id: UUID = .init()

    /// 配置名称
    var name: String = "Default"

    /// 是否为预设配置（只读）
    var isPreset: Bool = false

    // MARK: - 亮度曲线参数

    /// Gamma 值
    /// 范围: 0.5 ~ 2.0, 默认 1.0
    /// - < 1.0: 提亮中间调
    /// - > 1.0: 压暗中间调
    var gamma: Float = 1.0

    /// 黑位提升
    /// 范围: -0.1 ~ 0.1, 默认 0.0
    /// 正值提升暗部细节，负值加深黑色
    var blackLift: Float = 0.0

    /// 白点裁切
    /// 范围: 0.9 ~ 1.1, 默认 1.0
    /// < 1.0: 压缩高光，> 1.0: 扩展高光
    var whiteClip: Float = 1.0

    /// 高光滚降系数
    /// 范围: 0.0 ~ 0.5, 默认 0.0
    /// 柔化高光过渡，防止高光过曝
    var highlightRollOff: Float = 0.0

    // MARK: - 色彩参数

    /// 色温偏移
    /// 范围: -1.0(冷/蓝) ~ 1.0(暖/黄), 默认 0.0
    var temperature: Float = 0.0

    /// 色调偏移
    /// 范围: -1.0(绿) ~ 1.0(品红), 默认 0.0
    var tint: Float = 0.0

    /// 饱和度
    /// 范围: 0.0 ~ 2.0, 默认 1.0
    /// 0.0 = 灰度，1.0 = 原始，> 1.0 = 增强
    var saturation: Float = 1.0

    // MARK: - 参数范围

    /// 参数范围定义
    enum Range {
        static let gamma: ClosedRange<Float> = 0.5 ... 2.0
        static let blackLift: ClosedRange<Float> = -0.1 ... 0.1
        static let whiteClip: ClosedRange<Float> = 0.9 ... 1.1
        static let highlightRollOff: ClosedRange<Float> = 0.0 ... 0.5
        static let temperature: ClosedRange<Float> = -1.0 ... 1.0
        static let tint: ClosedRange<Float> = -1.0 ... 1.0
        static let saturation: ClosedRange<Float> = 0.0 ... 2.0
    }

    // MARK: - 预设

    /// 中性预设（无补偿）
    static let neutral: ColorProfile = {
        var profile = ColorProfile(name: L10n.colorCompensation.preset.neutral)
        profile.isPreset = true
        return profile
    }()

    /// 偏冷电视预设
    /// 电视偏蓝，需要增加暖色补偿
    static var coldTV: ColorProfile {
        var profile = ColorProfile(name: L10n.colorCompensation.preset.coldTV)
        profile.isPreset = true
        profile.temperature = 0.15 // 增加暖色
        profile.tint = 0.02 // 轻微偏品红
        return profile
    }

    /// 发灰电视预设
    /// 电视对比度低、颜色发灰，需要增强对比度和饱和度
    static var grayishTV: ColorProfile {
        var profile = ColorProfile(name: L10n.colorCompensation.preset.grayishTV)
        profile.isPreset = true
        profile.gamma = 0.95 // 轻微提亮
        profile.blackLift = -0.02 // 加深黑色
        profile.saturation = 1.15 // 增强饱和度
        return profile
    }

    /// 过饱和电视预设
    /// 电视颜色过于鲜艳，需要降低饱和度
    static var oversaturatedTV: ColorProfile {
        var profile = ColorProfile(name: L10n.colorCompensation.preset.oversaturatedTV)
        profile.isPreset = true
        profile.saturation = 0.85 // 降低饱和度
        return profile
    }

    /// 所有内置预设
    static var builtInPresets: [ColorProfile] {
        [.neutral, .coldTV, .grayishTV, .oversaturatedTV]
    }

    // MARK: - 验证

    /// 验证参数是否在有效范围内
    var isValid: Bool {
        Range.gamma.contains(gamma) &&
            Range.blackLift.contains(blackLift) &&
            Range.whiteClip.contains(whiteClip) &&
            Range.highlightRollOff.contains(highlightRollOff) &&
            Range.temperature.contains(temperature) &&
            Range.tint.contains(tint) &&
            Range.saturation.contains(saturation)
    }

    /// 将参数钳位到有效范围
    mutating func clampToValidRange() {
        gamma = gamma.clamped(to: Range.gamma)
        blackLift = blackLift.clamped(to: Range.blackLift)
        whiteClip = whiteClip.clamped(to: Range.whiteClip)
        highlightRollOff = highlightRollOff.clamped(to: Range.highlightRollOff)
        temperature = temperature.clamped(to: Range.temperature)
        tint = tint.clamped(to: Range.tint)
        saturation = saturation.clamped(to: Range.saturation)
    }

    /// 重置为默认值
    mutating func reset() {
        gamma = 1.0
        blackLift = 0.0
        whiteClip = 1.0
        highlightRollOff = 0.0
        temperature = 0.0
        tint = 0.0
        saturation = 1.0
    }

    /// 是否为默认值（未做任何调整）
    var isDefault: Bool {
        gamma == 1.0 &&
            blackLift == 0.0 &&
            whiteClip == 1.0 &&
            highlightRollOff == 0.0 &&
            temperature == 0.0 &&
            tint == 0.0 &&
            saturation == 1.0
    }
}

// MARK: - Float 扩展

private extension Float {
    func clamped(to range: ClosedRange<Float>) -> Float {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
