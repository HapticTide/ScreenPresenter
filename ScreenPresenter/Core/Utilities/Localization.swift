//
//  Localization.swift
//  ScreenPresenter
//
//  Created by Sun on 2025/12/23.
//
//  本地化支持
//  提供多语言切换功能
//

import Foundation

// MARK: - 语言选项

/// 应用支持的语言
enum AppLanguage: String, CaseIterable, Codable {
    case system // 跟随系统
    case en // English
    case zhHans = "zh-Hans" // 简体中文

    /// 显示名称（本地化）
    var displayName: String {
        switch self {
        case .system: L10n.language.system
        case .en: L10n.language.en
        case .zhHans: L10n.language.zhHans
        }
    }

    /// 原生名称（用于选择器显示）
    /// 注意：.system 使用本地化字符串，其他语言使用固定名称（方便用户识别）
    var nativeName: String {
        switch self {
        case .system: L10n.language.system // 跟随系统 / Follow System
        case .en: "English"
        case .zhHans: "简体中文"
        }
    }

    /// 对应的 Locale 标识符
    var localeIdentifier: String? {
        switch self {
        case .system: nil
        case .en: "en"
        case .zhHans: "zh-Hans"
        }
    }
}

// MARK: - 本地化管理器

/// 本地化管理器
final class LocalizationManager {
    // MARK: - 单例

    static let shared = LocalizationManager()

    // MARK: - 属性

    /// 当前使用的 Bundle
    private(set) var bundle: Bundle = .main

    /// 当前语言
    private(set) var currentLanguage: AppLanguage = .system

    /// 语言变更通知
    static let languageDidChangeNotification = Notification.Name("AppLanguageDidChange")

    // MARK: - 初始化

    private init() {
        loadSavedLanguage()
    }

    // MARK: - 公开方法

    /// 设置应用语言
    /// - Parameter language: 目标语言
    func setLanguage(_ language: AppLanguage) {
        currentLanguage = language
        UserDefaults.standard.set(language.rawValue, forKey: "AppLanguage")

        updateBundle(for: language)

        // 发送通知
        NotificationCenter.default.post(name: Self.languageDidChangeNotification, object: nil)

        AppLogger.app.info("语言已切换为: \(language.nativeName)")
    }

    /// 获取本地化字符串
    /// - Parameters:
    ///   - key: 本地化 key
    ///   - arguments: 格式化参数
    /// - Returns: 本地化后的字符串
    func localizedString(_ key: String, arguments: CVarArg...) -> String {
        let format = bundle.localizedString(forKey: key, value: nil, table: nil)
        if arguments.isEmpty {
            return format
        }
        return String(format: format, arguments: arguments)
    }

    // MARK: - 私有方法

    private func loadSavedLanguage() {
        if
            let savedValue = UserDefaults.standard.string(forKey: "AppLanguage"),
            let language = AppLanguage(rawValue: savedValue) {
            currentLanguage = language
            updateBundle(for: language)
        }
    }

    private func updateBundle(for language: AppLanguage) {
        if
            let identifier = language.localeIdentifier,
            let path = Bundle.main.path(forResource: identifier, ofType: "lproj"),
            let languageBundle = Bundle(path: path) {
            bundle = languageBundle
        } else {
            bundle = .main
        }
    }
}

// MARK: - String 扩展

extension String {
    /// 本地化字符串
    var localized: String {
        LocalizationManager.shared.localizedString(self)
    }

    /// 带参数的本地化字符串
    func localized(_ arguments: CVarArg...) -> String {
        let format = LocalizationManager.shared.bundle.localizedString(forKey: self, value: nil, table: nil)
        return String(format: format, arguments: arguments)
    }
}

// MARK: - L10n 命名空间

/// 本地化字符串命名空间
/// 使用方式: L10n.common.ok
enum L10n {
    // MARK: - App

    enum app {
        static var name: String { "app.name".localized }
        static var description: String { "app.description".localized }
    }

    // MARK: - Common

    enum common {
        static var ok: String { "common.ok".localized }
        static var cancel: String { "common.cancel".localized }
        static var close: String { "common.close".localized }
        static var copy: String { "common.copy".localized }
        static var refresh: String { "common.refresh".localized }
        static var install: String { "common.install".localized }
        static var version: String { "common.version".localized }
        static var status: String { "common.status".localized }
        static var error: String { "common.error".localized }
        static var unknown: String { "common.unknown".localized }
        static var checking: String { "common.checking".localized }
        static var loading: String { "common.loading".localized }
    }

    // MARK: - Menu

    enum menu {
        static var about: String { "menu.about".localized }
        static var preferences: String { "menu.preferences".localized }
        static var services: String { "menu.services".localized }
        static var hide: String { "menu.hide".localized }
        static var hideOthers: String { "menu.hideOthers".localized }
        static var showAll: String { "menu.showAll".localized }
        static var quit: String { "menu.quit".localized }
        static var checkForUpdates: String { "menu.checkForUpdates".localized }
        static var device: String { "menu.device".localized }
        static var refreshDevices: String { "menu.refreshDevices".localized }
        static var exportLogs: String { "menu.exportLogs".localized }
        static var close: String { "menu.close".localized }
        static var view: String { "menu.view".localized }
        static var colorCompensation: String { "menu.colorCompensation".localized }
        static var toggleDeviceBezel: String { "menu.toggleDeviceBezel".localized }
        static var togglePreventSleep: String { "menu.togglePreventSleep".localized }
        static var window: String { "menu.window".localized }
        static var minimize: String { "menu.minimize".localized }
        static var zoom: String { "menu.zoom".localized }
        static var bringAllToFront: String { "menu.bringAllToFront".localized }
        static var help: String { "menu.help".localized }
    }

    // MARK: - Window

    enum window {
        static var preferences: String { "window.preferences".localized }
        static var main: String { "window.main".localized }
    }

    // MARK: - Device

    enum device {
        static var connected: String { "device.connected".localized }
        static var disconnected: String { "device.disconnected".localized }
        static var connecting: String { "device.connecting".localized }
        static var capturing: String { "device.capturing".localized }
        static var waitingAuth: String { "device.waitingAuth".localized }
        static var idle: String { "device.idle".localized }
        static var paused: String { "device.paused".localized }
        static func error(_ msg: String) -> String { "device.error".localized(msg) }
    }

    // MARK: - Platform

    enum platform {
        static var ios: String { "platform.ios".localized }
        static var android: String { "platform.android".localized }
    }

    // MARK: - Overlay

    enum overlay {
        static var disconnected: String { "overlay.disconnected".localized }
        static var clickToStart: String { "overlay.clickToStart".localized }
        static func fps(_ value: Int) -> String { "overlay.fps".localized(value) }
    }

    // MARK: - Status Bar

    enum statusBar {
        static var waitingDevice: String { "statusBar.waitingDevice".localized }
        static func ios(_ status: String) -> String { "statusBar.ios".localized(status) }
        static func android(_ status: String) -> String { "statusBar.android".localized(status) }
    }

    // MARK: - Layout

    enum layout {
        static var sideBySide: String { "layout.sideBySide".localized }
        static var dual: String { "layout.dual".localized }
        static var leftOnly: String { "layout.leftOnly".localized }
        static var rightOnly: String { "layout.rightOnly".localized }
    }

    // MARK: - Theme

    enum theme {
        static var system: String { "theme.system".localized }
        static var light: String { "theme.light".localized }
        static var dark: String { "theme.dark".localized }
    }

    // MARK: - Language

    enum language {
        static var system: String { "language.system".localized }
        static var en: String { "language.en".localized }
        static var zhHans: String { "language.zhHans".localized }
    }

    // MARK: - Preferences

    enum prefs {
        enum tab {
            static var general: String { "prefs.tab.general".localized }
            static var capture: String { "prefs.tab.capture".localized }
            static var scrcpy: String { "prefs.tab.scrcpy".localized }
            static var permissions: String { "prefs.tab.permissions".localized }
            static var toolchain: String { "prefs.tab.toolchain".localized }
            static var about: String { "prefs.tab.about".localized }
        }

        enum section {
            static var language: String { "prefs.section.language".localized }
            static var appearance: String { "prefs.section.appearance".localized }
            static var layout: String { "prefs.section.layout".localized }
            static var frameRate: String { "prefs.section.frameRate".localized }
            static var audio: String { "prefs.section.audio".localized }
            static var iosAudio: String { "prefs.section.iosAudio".localized }
            static var androidAudio: String { "prefs.section.androidAudio".localized }
            static var android: String { "prefs.section.android".localized }
            static var video: String { "prefs.section.video".localized }
            static var display: String { "prefs.section.display".localized }
            static var advanced: String { "prefs.section.advanced".localized }
            static var systemPermissions: String { "prefs.section.systemPermissions".localized }
            static var iosPermissions: String { "prefs.section.iosPermissions".localized }
            static var androidPermissions: String { "prefs.section.androidPermissions".localized }
            static var androidToolchain: String { "prefs.section.androidToolchain".localized }
        }

        enum general {
            static var displaySettings: String { "prefs.general.displaySettings".localized }
            static var autoStartCapture: String { "prefs.general.autoStartCapture".localized }
            static var showFPS: String { "prefs.general.showFPS".localized }
            static var language: String { "prefs.general.language".localized }
            static var languageNote: String { "prefs.general.languageNote".localized }
        }

        enum appearance {
            static var backgroundOpacity: String { "prefs.appearance.backgroundOpacity".localized }
            static var showDeviceBezel: String { "prefs.appearance.showDeviceBezel".localized }
        }

        enum power {
            static var sectionTitle: String { "prefs.power.sectionTitle".localized }
            static var preventAutoLock: String { "prefs.power.preventAutoLock".localized }
            static var preventAutoLockHelp: String { "prefs.power.preventAutoLockHelp".localized }
        }

        enum colorCompensationPref {
            static var sectionTitle: String { "prefs.colorCompensation.sectionTitle".localized }
            static var enableSwitch: String { "prefs.colorCompensation.enable".localized }
            static var openPanel: String { "prefs.colorCompensation.openPanel".localized }
            static var description: String { "prefs.colorCompensation.description".localized }
        }

        enum layoutPref {
            static var devicePosition: String { "prefs.layout.devicePosition".localized }
            static var iosOnLeft: String { "prefs.layout.iosOnLeft".localized }
            static var androidOnLeft: String { "prefs.layout.androidOnLeft".localized }
        }

        enum capturePref {
            static var frameRate: String { "prefs.capture.frameRate".localized }
            static var frameRateNote: String { "prefs.capture.frameRateNote".localized }
        }

        enum audioPref {
            static var enableCapture: String { "prefs.audio.enableCapture".localized }
            static var volume: String { "prefs.audio.volume".localized }
            static var iosNote: String { "prefs.audio.iosNote".localized }
            static var androidNote: String { "prefs.audio.androidNote".localized }
            static var codec: String { "prefs.audio.codec".localized }
        }

        enum scrcpyPref {
            static var bitrate: String { "prefs.scrcpy.bitrate".localized }
            static var maxSize: String { "prefs.scrcpy.maxSize".localized }
            static var maxSizeNote: String { "prefs.scrcpy.maxSizeNote".localized }
            static var showTouches: String { "prefs.scrcpy.showTouches".localized }
            static var advancedNote: String { "prefs.scrcpy.advancedNote".localized }
            static var github: String { "prefs.scrcpy.github".localized }
            static var noLimit: String { "prefs.scrcpy.noLimit".localized }
            static func pixels(_ n: Int) -> String { "prefs.scrcpy.pixels".localized(n) }
            static func mbps(_ n: Int) -> String { "prefs.scrcpy.mbps".localized(n) }
            static var portRange: String { "prefs.scrcpy.portRange".localized }
            static var codec: String { "prefs.scrcpy.codec".localized }
        }

        enum toolchain {
            static var title: String { "prefs.toolchain.title".localized }
            static func adb(_ status: String) -> String { "prefs.toolchain.adb".localized(status) }
            static func scrcpy(_ status: String) -> String { "prefs.toolchain.scrcpy".localized(status) }
            static var refresh: String { "prefs.toolchain.refresh".localized }
            static var refreshStatus: String { "prefs.toolchain.refreshStatus".localized }
            static var installScrcpy: String { "prefs.toolchain.installScrcpy".localized }
            static var notInstalled: String { "prefs.toolchain.notInstalled".localized }
            static var installing: String { "prefs.toolchain.installing".localized }
            static var adbDesc: String { "prefs.toolchain.adbDesc".localized }
            static var scrcpyDesc: String { "prefs.toolchain.scrcpyDesc".localized }
            static var scrcpyServerDesc: String { "prefs.toolchain.scrcpyServerDesc".localized }
            static func bundled(_ version: String) -> String { "toolchain.bundled".localized(version) }
            static var notFoundAdb: String { "toolchain.notFound.adb".localized }
            static var notFoundScrcpy: String { "toolchain.notFound.scrcpy".localized }
            static var installHomebrew: String { "toolchain.installHomebrew".localized }
            static var installFailed: String { "toolchain.installFailed".localized }
            // 自定义路径
            static var useCustomPath: String { "prefs.toolchain.useCustomPath".localized }
            static var pathPlaceholder: String { "prefs.toolchain.pathPlaceholder".localized }
            static var browse: String { "prefs.toolchain.browse".localized }
            static func selectTool(_ name: String) -> String { "prefs.toolchain.selectTool".localized(name) }
            static var pathValid: String { "prefs.toolchain.pathValid".localized }
            static var pathNotFound: String { "prefs.toolchain.pathNotFound".localized }
            static var pathIsDirectory: String { "prefs.toolchain.pathIsDirectory".localized }
            static var pathNotExecutable: String { "prefs.toolchain.pathNotExecutable".localized }
        }

        enum about {
            static func version(_ v: String) -> String { "prefs.about.version".localized(v) }
        }
    }

    // MARK: - Toolchain (顶级)

    enum toolchain {
        static var installScrcpyHint: String { "toolchain.installScrcpyHint".localized }
        static var installScrcpyButton: String { "toolchain.installScrcpyButton".localized }
    }

    // MARK: - Android

    enum android {
        enum state {
            static var device: String { "android.state.device".localized }
            static var unauthorized: String { "android.state.unauthorized".localized }
            static var offline: String { "android.state.offline".localized }
            static var noPermissions: String { "android.state.noPermissions".localized }
            static var unknown: String { "android.state.unknown".localized }
        }

        enum hint {
            static var unauthorized: String { "android.hint.unauthorized".localized }
            static var offline: String { "android.hint.offline".localized }
            static var noPermissions: String { "android.hint.noPermissions".localized }
            static var unknown: String { "android.hint.unknown".localized }
        }

        enum connection {
            static var authTimeout: String { "android.authTimeout".localized }
            static func mirrorStartFailed(_ error: String) -> String { "android.mirrorStartFailed".localized(error) }
            static func mirrorTerminated(_ code: Int32) -> String { "android.mirrorTerminated".localized(code) }
            static var cannotGetIp: String { "android.cannotGetIp".localized }
        }
    }

    // MARK: - iOS

    enum ios {
        enum hint {
            static var trust: String { "ios.hint.trust".localized }
            static func occupied(_ app: String) -> String { "ios.hint.occupied".localized(app) }
            static var occupiedUnknown: String { "ios.hint.occupiedUnknown".localized }
            static var locked: String { "ios.hint.locked".localized }
            static var otherApp: String { "ios.hint.otherApp".localized }
        }
    }

    // MARK: - Errors

    enum error {
        static func connectionFailed(_ reason: String) -> String { "error.connectionFailed".localized(reason) }
        static var permissionDenied: String { "error.permissionDenied".localized }
        static var windowNotFound: String { "error.windowNotFound".localized }
        static func captureStartFailed(_ reason: String) -> String { "error.captureStartFailed".localized(reason) }
        static var captureInterrupted: String { "error.captureInterrupted".localized }
        static func processTerminated(_ code: Int32) -> String { "error.processTerminated".localized(code) }
        static var timeout: String { "error.timeout".localized }
        static func noDevice(_ platform: String) -> String { "error.noDevice".localized(platform) }
        static func startCaptureFailed(_ platform: String, _ error: String) -> String {
            "error.startCaptureFailed".localized(platform, error)
        }
    }

    // MARK: - Toolbar

    enum toolbar {
        static var refresh: String { "toolbar.refresh".localized }
        static var refreshing: String { "toolbar.refreshing".localized }
        static var refreshComplete: String { "toolbar.refreshComplete".localized }
        static var deviceInfoRefreshed: String { "toolbar.deviceInfoRefreshed".localized }
        static var swap: String { "toolbar.swap".localized }
        static var preferences: String { "toolbar.preferences".localized }
        static var swapTooltip: String { "toolbar.swap.tooltip".localized }
        static var refreshTooltip: String { "toolbar.refresh.tooltip".localized }
        static var preferencesTooltip: String { "toolbar.preferences.tooltip".localized }
        static var toggleBezel: String { "toolbar.toggleBezel".localized }
        static var toggleBezelTooltip: String { "toolbar.toggleBezel.tooltip".localized }
        static var showBezel: String { "toolbar.showBezel".localized }
        static var hideBezel: String { "toolbar.hideBezel".localized }
        static var layoutMode: String { "toolbar.layoutMode".localized }
        static var layoutModeTooltip: String { "toolbar.layoutMode.tooltip".localized }
        static var preventSleep: String { "toolbar.preventSleep".localized }
        static var preventSleepTooltip: String { "toolbar.preventSleep.tooltip".localized }
        static var preventSleepOn: String { "toolbar.preventSleep.on".localized }
        static var preventSleepOff: String { "toolbar.preventSleep.off".localized }
    }

    // MARK: - Toast

    enum toast {
        static var exportLogsSuccess: String { "toast.exportLogsSuccess".localized }
        static func exportLogsFailed(_ error: String) -> String {
            String(format: "toast.exportLogsFailed".localized, error)
        }
    }

    // MARK: - Permission

    enum permission {
        static var unknown: String { "permission.unknown".localized }
        static var checking: String { "permission.checking".localized }
        static var granted: String { "permission.granted".localized }
        static var denied: String { "permission.denied".localized }
        static var notDetermined: String { "permission.notDetermined".localized }
        static var screenRecordingName: String { "permission.screenRecording.name".localized }
        static var screenRecordingDesc: String { "permission.screenRecording.desc".localized }
        static var cameraName: String { "permission.camera.name".localized }
        static var cameraDesc: String { "permission.camera.desc".localized }
        static var openSystemPrefs: String { "permission.openSystemPrefs".localized }
        // 撤销权限
        static var revoke: String { "permission.revoke".localized }
        static var revokeTitle: String { "permission.revokeTitle".localized }
        static var revokeScreenRecordingHint: String { "permission.revokeScreenRecordingHint".localized }
        static var revokeCameraHint: String { "permission.revokeCameraHint".localized }
        static var revokeNote: String { "permission.revokeNote".localized }
    }

    // MARK: - Background

    enum background {
        static var followTheme: String { "background.followTheme".localized }
        static var custom: String { "background.custom".localized }
    }

    // MARK: - Connection

    enum connection {
        static var notConnected: String { "connection.notConnected".localized }
        static var connecting: String { "connection.connecting".localized }
        static var waitingAuth: String { "connection.waitingAuth".localized }
        static var connected: String { "connection.connected".localized }
        static func error(_ msg: String) -> String { "connection.error".localized(msg) }
        static func abnormalState(_ state: String) -> String { "connection.abnormalState".localized(state) }
        static var disconnected: String { "connection.disconnected".localized }
    }

    // MARK: - Overlay UI

    enum overlayUI {
        static var startCapture: String { "overlay.startCapture".localized }
        static var stop: String { "overlay.stop".localized }
        static func captureStopped(_ platform: String) -> String { "overlay.captureStopped".localized(platform) }
        static var connectDevice: String { "overlay.connectDevice".localized }
        static var connectIOS: String { "overlay.connectIOS".localized }
        static var connectAndroid: String { "overlay.connectAndroid".localized }
        static var waitingConnection: String { "overlay.waitingConnection".localized }
        static var waitingForIPhone: String { "overlay.waitingForIPhone".localized }
        static var waitingForAndroid: String { "overlay.waitingForAndroid".localized }
        static var deviceReady: String { "overlay.deviceReady".localized }
        static var deviceDetected: String { "overlay.deviceDetected".localized }
        static var captureIOSHint: String { "overlay.captureIOSHint".localized }
        static var captureAndroidHint: String { "overlay.captureAndroidHint".localized }
        static func toolNotInstalled(_ tool: String) -> String { "overlay.toolNotInstalled".localized(tool) }
        static func needInstall(_ tool: String) -> String { "overlay.needInstall".localized(tool) }
        static func installTool(_ tool: String) -> String { "overlay.installTool".localized(tool) }
    }

    // MARK: - Device Info

    enum deviceInfo {
        static var unknownModel: String { "deviceInfo.unknownModel".localized }
        static var unknownVersion: String { "deviceInfo.unknownVersion".localized }
        static var unknown: String { "deviceInfo.unknown".localized }
    }

    // MARK: - Process

    enum process {
        static func notFound(_ path: String) -> String { "process.notFound".localized(path) }
        static func failed(_ code: Int32, _ stderr: String) -> String { "process.failed".localized(code, stderr) }
        static var timeout: String { "process.timeout".localized }
        static var cancelled: String { "process.cancelled".localized }
    }

    // MARK: - ADB

    enum adb {
        static func startFailed(_ error: String) -> String { "adb.startFailed".localized(error) }
        static func stopFailed(_ error: String) -> String { "adb.stopFailed".localized(error) }
    }

    // MARK: - Capture

    enum capture {
        static var deviceNotConnected: String { "capture.deviceNotConnected".localized }
        static var sessionNotInitialized: String { "capture.sessionNotInitialized".localized }
        static func cannotGetDevice(_ id: String) -> String { "capture.cannotGetDevice".localized(id) }
        static var cannotAddInput: String { "capture.cannotAddInput".localized }
        static func inputFailed(_ error: String) -> String { "capture.inputFailed".localized(error) }
        static func deviceNotReady(_ name: String) -> String { "capture.deviceNotReady".localized(name) }
        static var cannotAddOutput: String { "capture.cannotAddOutput".localized }
    }

    // MARK: - iOS Screen Mirror

    enum iosScreenMirror {
        static func enableFailed(_ code: Int32) -> String { "ios.enableFailed".localized(code) }
    }

    // MARK: - iOS Device Type

    enum iosDeviceType {
        static var unknown: String { "ios.deviceType.unknown".localized }
    }

    // MARK: - Installation Log

    enum install {
        static var checkingHomebrew: String { "install.checkingHomebrew".localized }
        static var homebrewNotFound: String { "install.homebrewNotFound".localized }
        static var installHomebrewPrompt: String { "install.installHomebrewPrompt".localized }
        static func homebrewFound(_ path: String) -> String { "install.homebrewFound".localized(path) }
        static var startInstall: String { "install.startInstall".localized }
        static var installSuccess: String { "install.installSuccess".localized }
        static func installFailed(_ error: String) -> String { "install.installFailed".localized(error) }
        static var verifyingInstall: String { "install.verifyingInstall".localized }
    }

    // MARK: - Color Compensation

    enum colorCompensation {
        static var title: String { "color.compensation.title".localized }
        static var enabled: String { "color.compensation.enabled".localized }
        static var presetLabel: String { "color.compensation.preset".localized }
        static var compare: String { "color.compensation.compare".localized }
        static var compareCompensated: String { "color.compensation.compare.compensated".localized }
        static var compareOriginal: String { "color.compensation.compare.original".localized }
        static var reset: String { "color.compensation.reset".localized }
        static var savePreset: String { "color.compensation.savePreset".localized }
        static var deletePreset: String { "color.compensation.deletePreset".localized }
        static var customPresets: String { "color.compensation.customPresets".localized }
        static var savePresetTitle: String { "color.compensation.savePresetTitle".localized }
        static var savePresetMessage: String { "color.compensation.savePresetMessage".localized }
        static var savePresetPlaceholder: String { "color.compensation.savePresetPlaceholder".localized }
        static var presetNameExists: String { "color.compensation.presetNameExists".localized }

        // 设备选择相关
        static var deviceSelector: String { "color.compensation.deviceSelector".localized }
        static var globalSettings: String { "color.compensation.globalSettings".localized }
        static var iosSettings: String { "color.compensation.iosSettings".localized }
        static var androidSettings: String { "color.compensation.androidSettings".localized }

        enum mode {
            static var useGlobal: String { "color.mode.useGlobal".localized }
            static var independent: String { "color.mode.independent".localized }
        }

        enum section {
            static var enable: String { "color.section.enable".localized }
            static var preset: String { "color.section.preset".localized }
            static var brightness: String { "color.section.brightness".localized }
            static var color: String { "color.section.color".localized }
            static var actions: String { "color.section.actions".localized }
            static var deviceMode: String { "color.section.deviceMode".localized }
        }

        enum params {
            static var blackLift: String { "color.params.blackLift".localized }
            static var whiteClip: String { "color.params.whiteClip".localized }
            static var highlightRollOff: String { "color.params.highlightRollOff".localized }
            static var temperature: String { "color.params.temperature".localized }
            static var tint: String { "color.params.tint".localized }
            static var saturation: String { "color.params.saturation".localized }
        }

        enum preset {
            static var neutral: String { "color.preset.neutral".localized }
            static var coldTV: String { "color.preset.coldTV".localized }
            static var grayishTV: String { "color.preset.grayishTV".localized }
            static var oversaturatedTV: String { "color.preset.oversaturatedTV".localized }
        }
    }
}
