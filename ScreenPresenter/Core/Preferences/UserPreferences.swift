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

// MARK: - 用户偏好设置模型

/// 用户偏好设置
final class UserPreferences {
    // MARK: - Singleton

    static let shared = UserPreferences()

    // MARK: - Keys

    private enum Keys {
        static let defaultLayout = "defaultLayout"
        static let autoReconnect = "autoReconnect"
        static let reconnectDelay = "reconnectDelay"
        static let maxReconnectAttempts = "maxReconnectAttempts"
        static let appLanguage = "appLanguage"
        static let backgroundOpacity = "backgroundOpacity"
        static let captureFrameRate = "captureFrameRate"
        static let scrcpyBitrate = "scrcpyBitrate"
        static let scrcpyMaxSize = "scrcpyMaxSize"
        static let scrcpyShowTouches = "scrcpyShowTouches"
    }

    // MARK: - UserDefaults

    private let defaults = UserDefaults.standard

    // MARK: - Layout Settings

    /// 默认布局样式
    var defaultLayout: LayoutMode {
        get {
            guard
                let raw = defaults.string(forKey: Keys.defaultLayout),
                let mode = LayoutMode(rawValue: raw) else {
                return .sideBySide
            }
            return mode
        }
        set {
            defaults.set(newValue.rawValue, forKey: Keys.defaultLayout)
        }
    }

    // MARK: - Connection Settings

    /// 是否自动重连
    var autoReconnect: Bool {
        get { defaults.bool(forKey: Keys.autoReconnect) }
        set { defaults.set(newValue, forKey: Keys.autoReconnect) }
    }

    /// 重连延迟（秒）
    var reconnectDelay: Double {
        get {
            let value = defaults.double(forKey: Keys.reconnectDelay)
            return value > 0 ? value : 3.0
        }
        set { defaults.set(newValue, forKey: Keys.reconnectDelay) }
    }

    /// 最大重连次数
    var maxReconnectAttempts: Int {
        get {
            let value = defaults.integer(forKey: Keys.maxReconnectAttempts)
            return value > 0 ? value : 5
        }
        set { defaults.set(newValue, forKey: Keys.maxReconnectAttempts) }
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

    /// 最大分辨率
    var scrcpyMaxSize: Int {
        get {
            let value = defaults.integer(forKey: Keys.scrcpyMaxSize)
            return value > 0 ? value : 1920
        }
        set { defaults.set(newValue, forKey: Keys.scrcpyMaxSize) }
    }

    /// 显示触摸点
    var scrcpyShowTouches: Bool {
        get { defaults.bool(forKey: Keys.scrcpyShowTouches) }
        set { defaults.set(newValue, forKey: Keys.scrcpyShowTouches) }
    }

    // MARK: - Private Init

    private init() {
        // 设置默认值
        registerDefaults()
    }

    private func registerDefaults() {
        defaults.register(defaults: [
            Keys.autoReconnect: true,
            Keys.reconnectDelay: 3.0,
            Keys.maxReconnectAttempts: 5,
            Keys.backgroundOpacity: 1.0,
            Keys.captureFrameRate: 60,
            Keys.scrcpyBitrate: 8,
            Keys.scrcpyMaxSize: 1920,
            Keys.scrcpyShowTouches: false,
        ])
    }

    // MARK: - scrcpy 配置生成

    /// 为特定设备构建 scrcpy 配置
    func buildScrcpyConfiguration(serial: String) -> ScrcpyConfiguration {
        ScrcpyConfiguration(
            serial: serial,
            maxSize: scrcpyMaxSize,
            bitrate: scrcpyBitrate * 1_000_000,
            maxFps: captureFrameRate,
            showTouches: scrcpyShowTouches,
            stayAwake: true
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
