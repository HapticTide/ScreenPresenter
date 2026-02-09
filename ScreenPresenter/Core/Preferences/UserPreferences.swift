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
import MarkdownEditor

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
        static let scrcpyPortRangeStart = "scrcpyPortRangeStart"
        static let scrcpyPortRangeEnd = "scrcpyPortRangeEnd"
        static let scrcpyCodec = "scrcpyCodec"
        // 自定义路径
        static let customAdbPath = "customAdbPath"
        static let customScrcpyServerPath = "customScrcpyServerPath"
        static let useCustomAdbPath = "useCustomAdbPath"
        static let useCustomScrcpyServerPath = "useCustomScrcpyServerPath"
        // 电源管理
        static let preventAutoLockDuringCapture = "preventAutoLockDuringCapture"
        // 音频设置
        static let iosAudioEnabled = "iosAudioEnabled"
        static let iosAudioVolume = "iosAudioVolume"
        static let androidAudioEnabled = "androidAudioEnabled"
        static let androidAudioVolume = "androidAudioVolume"
        static let androidAudioCodec = "androidAudioCodec"
        // Markdown 编辑器
        static let markdownEditorVisible = "markdownEditorVisible"
        static let markdownEditorPosition = "markdownEditorPosition"
        static let markdownThemeMode = "markdownThemeMode"
        static let markdownLastFilePath = "markdownLastFilePath"
        static let recentMarkdownFiles = "recentMarkdownFiles"
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

    /// scrcpy 端口范围起始（默认 27183，与 scrcpy 官方一致）
    var scrcpyPortRangeStart: Int {
        get {
            let value = defaults.integer(forKey: Keys.scrcpyPortRangeStart)
            return value > 0 ? value : 27183
        }
        set { defaults.set(newValue, forKey: Keys.scrcpyPortRangeStart) }
    }

    /// scrcpy 端口范围结束（默认 27199，支持最多 17 个并发连接）
    var scrcpyPortRangeEnd: Int {
        get {
            let value = defaults.integer(forKey: Keys.scrcpyPortRangeEnd)
            return value > 0 ? value : 27199
        }
        set { defaults.set(newValue, forKey: Keys.scrcpyPortRangeEnd) }
    }

    /// 端口范围（便捷属性）
    var scrcpyPortRange: ClosedRange<Int> {
        let start = scrcpyPortRangeStart
        let end = scrcpyPortRangeEnd
        // 确保 start <= end
        return min(start, end)...max(start, end)
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

    // MARK: - Audio Settings

    /// iOS 音频是否启用（默认 true）
    var iosAudioEnabled: Bool {
        get {
            if defaults.object(forKey: Keys.iosAudioEnabled) == nil {
                return true
            }
            return defaults.bool(forKey: Keys.iosAudioEnabled)
        }
        set {
            defaults.set(newValue, forKey: Keys.iosAudioEnabled)
            NotificationCenter.default.post(name: .audioSettingsDidChange, object: nil, userInfo: ["platform": "ios"])
        }
    }

    /// iOS 音频音量 (0.0 - 1.0，默认 1.0)
    var iosAudioVolume: Float {
        get {
            let value = defaults.float(forKey: Keys.iosAudioVolume)
            if value == 0, defaults.object(forKey: Keys.iosAudioVolume) == nil {
                return 1.0
            }
            return value
        }
        set {
            defaults.set(newValue, forKey: Keys.iosAudioVolume)
            NotificationCenter.default.post(name: .audioSettingsDidChange, object: nil, userInfo: ["platform": "ios"])
        }
    }

    /// Android 音频是否启用（默认 false，需要用户手动启用）
    var androidAudioEnabled: Bool {
        get {
            if defaults.object(forKey: Keys.androidAudioEnabled) == nil {
                return false
            }
            return defaults.bool(forKey: Keys.androidAudioEnabled)
        }
        set {
            defaults.set(newValue, forKey: Keys.androidAudioEnabled)
            NotificationCenter.default.post(
                name: .audioSettingsDidChange,
                object: nil,
                userInfo: ["platform": "android"]
            )
        }
    }

    /// Android 音频音量 (0.0 - 1.0，默认 1.0)
    var androidAudioVolume: Float {
        get {
            let value = defaults.float(forKey: Keys.androidAudioVolume)
            if value == 0, defaults.object(forKey: Keys.androidAudioVolume) == nil {
                return 1.0
            }
            return value
        }
        set {
            defaults.set(newValue, forKey: Keys.androidAudioVolume)
            NotificationCenter.default.post(
                name: .audioSettingsDidChange,
                object: nil,
                userInfo: ["platform": "android"]
            )
        }
    }

    /// Android 音频编解码器（默认 opus）
    var androidAudioCodec: ScrcpyConfiguration.AudioCodec {
        get {
            guard
                let rawValue = defaults.string(forKey: Keys.androidAudioCodec),
                let codec = ScrcpyConfiguration.AudioCodec(rawValue: rawValue) else {
                return .opus
            }
            return codec
        }
        set {
            defaults.set(newValue.rawValue, forKey: Keys.androidAudioCodec)
            NotificationCenter.default.post(
                name: .audioSettingsDidChange,
                object: nil,
                userInfo: ["platform": "android", "codec": newValue.rawValue]
            )
        }
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
            Keys.scrcpyPortRangeStart: 27183,
            Keys.scrcpyPortRangeEnd: 27199,
            Keys.scrcpyCodec: ScrcpyCodecType.h264.rawValue,
            Keys.iosAudioEnabled: true,
            Keys.iosAudioVolume: 1.0,
            Keys.androidAudioEnabled: false,
            Keys.androidAudioVolume: 1.0,
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
            audioEnabled: androidAudioEnabled, // 从用户偏好读取音频开关
            audioCodec: androidAudioCodec,
            videoCodec: videoCodec
        )
    }

    // MARK: - Markdown Editor Settings

    /// Markdown 编辑器是否可见（默认 false）
    var markdownEditorVisible: Bool {
        get { defaults.bool(forKey: Keys.markdownEditorVisible) }
        set {
            defaults.set(newValue, forKey: Keys.markdownEditorVisible)
            NotificationCenter.default.post(name: .markdownEditorVisibilityDidChange, object: nil)
        }
    }

    /// Markdown 编辑器位置（默认 center）
    var markdownEditorPosition: MarkdownEditorPosition {
        get {
            guard
                let raw = defaults.string(forKey: Keys.markdownEditorPosition),
                let position = MarkdownEditorPosition(rawValue: raw)
            else {
                return .center
            }
            return position
        }
        set {
            defaults.set(newValue.rawValue, forKey: Keys.markdownEditorPosition)
            NotificationCenter.default.post(name: .markdownEditorPositionDidChange, object: nil)
        }
    }

    /// Markdown 编辑器主题模式（默认跟随系统）
    var markdownThemeMode: MarkdownEditorThemeMode {
        get {
            guard
                let raw = defaults.string(forKey: Keys.markdownThemeMode),
                let mode = MarkdownEditorThemeMode(rawValue: raw)
            else {
                return .system
            }
            return mode
        }
        set {
            defaults.set(newValue.rawValue, forKey: Keys.markdownThemeMode)
        }
    }

    /// 上次打开的 Markdown 文件路径
    var markdownLastFilePath: String? {
        get { defaults.string(forKey: Keys.markdownLastFilePath) }
        set { defaults.set(newValue, forKey: Keys.markdownLastFilePath) }
    }

    /// 最近打开的 Markdown 文件列表（最多保留 10 个）
    var recentMarkdownFiles: [String] {
        get { defaults.stringArray(forKey: Keys.recentMarkdownFiles) ?? [] }
        set {
            // 最多保留 10 个
            let trimmed = Array(newValue.prefix(10))
            defaults.set(trimmed, forKey: Keys.recentMarkdownFiles)
        }
    }

    /// 添加文件到最近使用列表
    func addRecentMarkdownFile(_ path: String) {
        var files = recentMarkdownFiles
        // 如果已存在，先移除
        files.removeAll { $0 == path }
        // 添加到开头
        files.insert(path, at: 0)
        // 保存
        recentMarkdownFiles = files
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
