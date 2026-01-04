//
//  UserPreferences.swift
//  ScreenPresenter
//
//  Created by Sun on 2025/12/22.
//
//  用户偏好设置
//  持久化存储用户的各项配置选项
//

import AppKit
import Foundation

// MARK: - Scrcpy 编解码器类型

/// Scrcpy 编解码器类型
enum ScrcpyCodecType: String, CaseIterable {
    case h264
    case h265

    var displayName: String {
        switch self {
        case .h264: "H.264"
        case .h265: "H.265 (HEVC)"
        }
    }
}

// MARK: - 用户偏好设置模型

/// 用户偏好设置
final class UserPreferences {
    // MARK: - Singleton

    static let shared = UserPreferences()

    // MARK: - Keys

    private enum Keys {
        static let iosOnLeft = "iosOnLeft"
        static let layoutMode = "layoutMode"
        static let appLanguage = "appLanguage"
        static let backgroundOpacity = "backgroundOpacity"
        static let showDeviceBezel = "showDeviceBezel"
        static let captureFrameRate = "captureFrameRate"
        static let scrcpyBitrate = "scrcpyBitrate"
        static let scrcpyMaxSize = "scrcpyMaxSize"
        static let scrcpyShowTouches = "scrcpyShowTouches"
        static let scrcpyPort = "scrcpyPort"
        static let scrcpyCodec = "scrcpyCodec"
        // 自定义路径
        static let customAdbPath = "customAdbPath"
        static let customScrcpyPath = "customScrcpyPath"
        static let customScrcpyServerPath = "customScrcpyServerPath"
        static let useCustomAdbPath = "useCustomAdbPath"
        static let useCustomScrcpyPath = "useCustomScrcpyPath"
        static let useCustomScrcpyServerPath = "useCustomScrcpyServerPath"
        // 电源管理
        static let preventAutoLockDuringCapture = "preventAutoLockDuringCapture"
    }

    // MARK: - UserDefaults

    private let defaults = UserDefaults.standard

    // MARK: - Layout Settings

    /// iOS 设备是否在左侧（默认 true：左 iOS | 右 Android）
    var iosOnLeft: Bool {
        get {
            // 如果从未设置过，默认为 true
            if defaults.object(forKey: Keys.iosOnLeft) == nil {
                return true
            }
            return defaults.bool(forKey: Keys.iosOnLeft)
        }
        set {
            defaults.set(newValue, forKey: Keys.iosOnLeft)
        }
    }

    /// 布局模式（默认 dual：双设备并排显示）
    var layoutMode: PreviewLayoutMode {
        get {
            guard
                let raw = defaults.string(forKey: Keys.layoutMode),
                let mode = PreviewLayoutMode(rawValue: raw)
            else {
                return .dual
            }
            return mode
        }
        set {
            defaults.set(newValue.rawValue, forKey: Keys.layoutMode)
            // 发送通知更新 UI
            NotificationCenter.default.post(name: .layoutModeDidChange, object: nil)
        }
    }

    // MARK: - Display Settings

    /// 应用语言
    var appLanguage: AppLanguage {
        get {
            guard
                let raw = defaults.string(forKey: Keys.appLanguage),
                let lang = AppLanguage(rawValue: raw)
            else {
                return .system
            }
            return lang
        }
        set {
            defaults.set(newValue.rawValue, forKey: Keys.appLanguage)
            LocalizationManager.shared.setLanguage(newValue)
        }
    }

    /// 背景透明度 (0.0 - 1.0)
    var backgroundOpacity: CGFloat {
        get {
            let value = defaults.double(forKey: Keys.backgroundOpacity)
            // 如果值为 0 且从未设置过，返回默认值 1.0
            if value == 0, defaults.object(forKey: Keys.backgroundOpacity) == nil {
                return 1.0
            }
            return CGFloat(value)
        }
        set {
            defaults.set(Double(newValue), forKey: Keys.backgroundOpacity)
        }
    }

    /// 获取背景色（固定黑色，透明度可调）
    var backgroundColor: NSColor {
        NSColor.black.withAlphaComponent(backgroundOpacity)
    }

    /// 是否显示设备边框（默认 true）
    var showDeviceBezel: Bool {
        get {
            // 如果从未设置过，默认为 true
            if defaults.object(forKey: Keys.showDeviceBezel) == nil {
                return true
            }
            return defaults.bool(forKey: Keys.showDeviceBezel)
        }
        set {
            defaults.set(newValue, forKey: Keys.showDeviceBezel)
            // 发送通知更新 UI
            NotificationCenter.default.post(name: .deviceBezelVisibilityDidChange, object: nil)
        }
    }

    // MARK: - Power Settings

    /// 捕获期间禁止自动锁屏（默认 true）
    var preventAutoLockDuringCapture: Bool {
        get {
            // 如果从未设置过，默认为 true（推荐在捕获时阻止休眠）
            if defaults.object(forKey: Keys.preventAutoLockDuringCapture) == nil {
                return true
            }
            return defaults.bool(forKey: Keys.preventAutoLockDuringCapture)
        }
        set {
            defaults.set(newValue, forKey: Keys.preventAutoLockDuringCapture)
            // 发送通知更新 UI 和协调器
            NotificationCenter.default.post(name: .preventAutoLockSettingDidChange, object: nil)
        }
    }

    // MARK: - Capture Settings

    /// 捕获帧率
    var captureFrameRate: Int {
        get {
            let value = defaults.integer(forKey: Keys.captureFrameRate)
            return value > 0 ? value : 60
        }
        set { defaults.set(newValue, forKey: Keys.captureFrameRate) }
    }

    // MARK: - scrcpy Settings

    /// 码率（Mbps）
    var scrcpyBitrate: Int {
        get {
            let value = defaults.integer(forKey: Keys.scrcpyBitrate)
            return value > 0 ? value : 8
        }
        set { defaults.set(newValue, forKey: Keys.scrcpyBitrate) }
    }

    /// 最大分辨率（0 表示不限制）
    var scrcpyMaxSize: Int {
        get {
            // 需要区分"未设置"和"设置为 0（不限制）"
            if defaults.object(forKey: Keys.scrcpyMaxSize) == nil {
                return 0 // 默认值
            }
            return defaults.integer(forKey: Keys.scrcpyMaxSize)
        }
        set { defaults.set(newValue, forKey: Keys.scrcpyMaxSize) }
    }

    /// 显示触摸点
    var scrcpyShowTouches: Bool {
        get { defaults.bool(forKey: Keys.scrcpyShowTouches) }
        set { defaults.set(newValue, forKey: Keys.scrcpyShowTouches) }
    }

    /// scrcpy 连接端口（默认 27183）
    var scrcpyPort: Int {
        get {
            let value = defaults.integer(forKey: Keys.scrcpyPort)
            return value > 0 ? value : 27183
        }
        set { defaults.set(newValue, forKey: Keys.scrcpyPort) }
    }

    /// scrcpy 编解码器（h264/h265，默认 h264）
    var scrcpyCodec: ScrcpyCodecType {
        get {
            guard
                let raw = defaults.string(forKey: Keys.scrcpyCodec),
                let codec = ScrcpyCodecType(rawValue: raw)
            else {
                return .h264
            }
            return codec
        }
        set { defaults.set(newValue.rawValue, forKey: Keys.scrcpyCodec) }
    }

    // MARK: - Custom Tool Paths

    /// 是否使用自定义 adb 路径
    var useCustomAdbPath: Bool {
        get { defaults.bool(forKey: Keys.useCustomAdbPath) }
        set { defaults.set(newValue, forKey: Keys.useCustomAdbPath) }
    }

    /// 自定义 adb 路径
    var customAdbPath: String? {
        get { defaults.string(forKey: Keys.customAdbPath) }
        set { defaults.set(newValue, forKey: Keys.customAdbPath) }
    }

    /// 是否使用自定义 scrcpy 路径
    var useCustomScrcpyPath: Bool {
        get { defaults.bool(forKey: Keys.useCustomScrcpyPath) }
        set { defaults.set(newValue, forKey: Keys.useCustomScrcpyPath) }
    }

    /// 自定义 scrcpy 路径
    var customScrcpyPath: String? {
        get { defaults.string(forKey: Keys.customScrcpyPath) }
        set { defaults.set(newValue, forKey: Keys.customScrcpyPath) }
    }

    /// 是否使用自定义 scrcpy-server 路径
    var useCustomScrcpyServerPath: Bool {
        get { defaults.bool(forKey: Keys.useCustomScrcpyServerPath) }
        set { defaults.set(newValue, forKey: Keys.useCustomScrcpyServerPath) }
    }

    /// 自定义 scrcpy-server 路径
    var customScrcpyServerPath: String? {
        get { defaults.string(forKey: Keys.customScrcpyServerPath) }
        set { defaults.set(newValue, forKey: Keys.customScrcpyServerPath) }
    }

    // MARK: - Private Init

    private init() {
        // 设置默认值
        registerDefaults()
    }

    private func registerDefaults() {
        defaults.register(defaults: [
            Keys.backgroundOpacity: 1.0,
            Keys.showDeviceBezel: true,
            Keys.captureFrameRate: 60,
            Keys.scrcpyBitrate: 8,
            Keys.scrcpyMaxSize: 0,
            Keys.scrcpyShowTouches: false,
            Keys.scrcpyPort: 27183,
            Keys.scrcpyCodec: ScrcpyCodecType.h264.rawValue,
        ])
    }

    // MARK: - scrcpy 配置生成

    /// 为特定设备构建 scrcpy 配置
    func buildScrcpyConfiguration(serial: String) -> ScrcpyConfiguration {
        let videoCodec: ScrcpyConfiguration.VideoCodec = switch scrcpyCodec {
        case .h264: .h264
        case .h265: .h265
        }

        return ScrcpyConfiguration(
            serial: serial,
            maxSize: scrcpyMaxSize,
            bitrate: scrcpyBitrate * 1_000_000,
            maxFps: captureFrameRate,
            showTouches: scrcpyShowTouches,
            stayAwake: true,
            videoCodec: videoCodec
        )
    }
}

// MARK: - NSColor Hex Extension

extension NSColor {
    /// 从十六进制字符串创建颜色
    convenience init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xf) * 17, (int & 0xf) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xff, int & 0xff)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xff, int >> 8 & 0xff, int & 0xff)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            red: CGFloat(r) / 255,
            green: CGFloat(g) / 255,
            blue: CGFloat(b) / 255,
            alpha: CGFloat(a) / 255
        )
    }

    /// 将颜色转换为十六进制字符串
    func toHex() -> String {
        guard let rgbColor = usingColorSpace(.sRGB) else {
            return "000000"
        }
        let r = Int(rgbColor.redComponent * 255)
        let g = Int(rgbColor.greenComponent * 255)
        let b = Int(rgbColor.blueComponent * 255)
        return String(format: "%02X%02X%02X", r, g, b)
    }
}
