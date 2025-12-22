//
//  DemoConsoleApp.swift
//  DemoConsole
//
//  Created by Sun on 2025/12/22.
//
//  应用程序入口
//  配置主窗口和应用状态
//

import SwiftUI

@main
struct DemoConsoleApp: App {
    @StateObject private var appState = AppState()
    @ObservedObject private var preferences = UserPreferences.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .frame(minWidth: 800, minHeight: 600)
                .preferredColorScheme(preferences.themeMode.colorScheme)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }

        // 偏好设置独立窗口
        Settings {
            SettingsView()
                .preferredColorScheme(preferences.themeMode.colorScheme)
        }
    }
}

// MARK: - 全局应用状态

@MainActor
final class AppState: ObservableObject {
    /// 工具链管理器
    @Published var toolchainManager = ToolchainManager()

    /// Android 设备提供者
    @Published private(set) var androidDeviceProvider: AndroidDeviceProvider!

    /// Android 连接器
    @Published private(set) var androidConnector: AndroidConnector!

    /// iOS 设备提供者
    @Published private(set) var iosDeviceProvider = IOSDeviceProvider()

    /// 权限检查器
    @Published var permissionChecker = PermissionChecker()

    /// 当前选中的设备 ID
    @Published var selectedDeviceID: String?

    /// 是否显示首次启动检查清单
    @Published var showPermissionChecklist = false

    /// 是否正在初始化
    @Published var isInitializing = true

    // MARK: - 设备源（捕获）

    /// iOS 设备源
    @Published private(set) var iosDeviceSource: IOSDeviceSource?

    /// Android 设备源
    @Published private(set) var androidDeviceSource: ScrcpyDeviceSource?

    /// iOS 最新捕获帧
    @Published private(set) var iosLatestFrame: CapturedFrame?

    /// Android 最新捕获帧
    @Published private(set) var androidLatestFrame: CapturedFrame?

    // MARK: - 设备连接状态

    /// Android 是否已连接
    var androidConnected: Bool {
        !androidDeviceProvider.devices.isEmpty
    }

    /// Android 设备名称
    var androidDeviceName: String? {
        androidDeviceProvider.devices.first?.displayName
    }

    /// iOS 是否已连接
    var iosConnected: Bool {
        !iosDeviceProvider.devices.isEmpty
    }

    /// iOS 设备名称
    var iosDeviceName: String? {
        iosDeviceProvider.devices.first?.name
    }

    /// iOS 捕获中
    var iosCapturing: Bool {
        iosDeviceSource?.state == .capturing
    }

    /// Android 捕获中
    var androidCapturing: Bool {
        androidDeviceSource?.state == .capturing
    }

    // MARK: - 私有属性

    private var deviceObservationTask: Task<Void, Never>?

    init() {
        // 使用共享的 toolchainManager 初始化 androidDeviceProvider
        androidDeviceProvider = AndroidDeviceProvider(toolchainManager: toolchainManager)
        // 使用共享的 toolchainManager 和 androidDeviceProvider 初始化 androidConnector
        androidConnector = AndroidConnector(
            deviceProvider: androidDeviceProvider,
            toolchainManager: toolchainManager
        )

        Task {
            await initialize()
        }
    }

    /// 初始化应用
    private func initialize() async {
        // 检查是否首次启动
        let hasCompletedSetup = UserDefaults.standard.bool(forKey: "hasCompletedSetup")

        // 初始化工具链
        await toolchainManager.setup()

        // 检查权限
        await permissionChecker.checkAll()

        // 如果首次启动或权限不完整，显示检查清单
        if !hasCompletedSetup || !permissionChecker.allPermissionsGranted {
            showPermissionChecklist = true
        }

        isInitializing = false

        // 开始监控设备
        androidDeviceProvider.startMonitoring()
        iosDeviceProvider.startMonitoring()

        // 启动设备观察
        startDeviceObservation()
    }

    /// 标记设置完成
    func markSetupComplete() {
        UserDefaults.standard.set(true, forKey: "hasCompletedSetup")
        showPermissionChecklist = false
    }

    /// 刷新设备列表
    func refreshDevices() {
        Task {
            await androidDeviceProvider.refreshDevices()
        }
        iosDeviceProvider.refreshDevices()
    }

    // MARK: - 设备观察

    /// 启动设备观察，自动处理连接/断开
    private func startDeviceObservation() {
        deviceObservationTask?.cancel()
        deviceObservationTask = Task { [weak self] in
            guard let self else { return }

            // 定期检查设备状态变化
            while !Task.isCancelled {
                await checkAndUpdateDeviceSources()
                try? await Task.sleep(nanoseconds: 1_000_000_000) // 1秒
            }
        }
    }

    /// 检查并更新设备源
    private func checkAndUpdateDeviceSources() async {
        // 处理 iOS 设备
        await handleIOSDeviceChange()

        // 处理 Android 设备
        await handleAndroidDeviceChange()
    }

    /// 处理 iOS 设备变化
    private func handleIOSDeviceChange() async {
        let currentDevice = iosDeviceProvider.devices.first

        if let device = currentDevice {
            // 设备已连接
            if iosDeviceSource == nil || iosDeviceSource?.iosDevice.id != device.id {
                // 创建新的设备源
                await disconnectIOSDevice()
                await connectIOSDevice(device)
            }
        } else {
            // 设备已断开
            if iosDeviceSource != nil {
                await disconnectIOSDevice()
            }
        }
    }

    /// 处理 Android 设备变化
    private func handleAndroidDeviceChange() async {
        let currentDevice = androidDeviceProvider.devices.first

        if let device = currentDevice {
            // 设备已连接
            if androidDeviceSource == nil || androidDeviceSource?.deviceInfo?.id != device.serial {
                // 创建新的设备源
                await disconnectAndroidDevice()
                await connectAndroidDevice(device)
            }
        } else {
            // 设备已断开
            if androidDeviceSource != nil {
                await disconnectAndroidDevice()
            }
        }
    }

    // MARK: - iOS 设备管理

    /// 连接 iOS 设备并启动捕获
    private func connectIOSDevice(_ device: IOSDevice) async {
        AppLogger.device.info("开始连接 iOS 设备: \(device.name), ID: \(device.id)")

        let source = IOSDeviceSource(device: device)
        iosDeviceSource = source

        do {
            try await source.connect()
            AppLogger.device.info("iOS 设备已连接: \(device.name), 状态: \(source.state.displayText)")

            // 先订阅帧流（确保在 startCapture 之前订阅）
            subscribeToIOSFrames(source)

            // 自动启动捕获
            try await source.startCapture()
            AppLogger.capture.info("iOS 设备捕获已启动: \(device.name), 状态: \(source.state.displayText)")
        } catch {
            AppLogger.device.error("iOS 设备连接/捕获失败: \(error.localizedDescription)")
            // 保留 source 以便 UI 显示错误状态
        }
    }

    /// 断开 iOS 设备
    private func disconnectIOSDevice() async {
        guard let source = iosDeviceSource else { return }

        AppLogger.device.info("断开 iOS 设备: \(source.displayName)")

        await source.stopCapture()
        await source.disconnect()

        iosDeviceSource = nil
        iosLatestFrame = nil
    }

    /// 订阅 iOS 帧流
    private func subscribeToIOSFrames(_ source: IOSDeviceSource) {
        Task { [weak self] in
            for await frame in source.frameStream {
                await MainActor.run {
                    self?.iosLatestFrame = frame
                }
            }
        }
    }

    // MARK: - Android 设备管理

    /// 连接 Android 设备并启动捕获
    private func connectAndroidDevice(_ device: AndroidDevice) async {
        AppLogger.device.info("开始连接 Android 设备: \(device.displayName)")

        // 检查 scrcpy 是否可用
        guard toolchainManager.scrcpyStatus.isReady else {
            AppLogger.device.warning("scrcpy 未安装，无法捕获 Android 设备")
            return
        }

        let source = ScrcpyDeviceSource(device: device)
        androidDeviceSource = source

        do {
            try await source.connect()
            AppLogger.device.info("Android 设备已连接: \(device.displayName)")

            // 自动启动捕获
            try await source.startCapture()
            AppLogger.capture.info("Android 设备捕获已启动: \(device.displayName)")

            // 订阅帧流
            subscribeToAndroidFrames(source)
        } catch {
            AppLogger.device.error("Android 设备连接失败: \(error.localizedDescription)")
        }
    }

    /// 断开 Android 设备
    private func disconnectAndroidDevice() async {
        guard let source = androidDeviceSource else { return }

        AppLogger.device.info("断开 Android 设备: \(source.displayName)")

        await source.stopCapture()
        await source.disconnect()

        androidDeviceSource = nil
        androidLatestFrame = nil
    }

    /// 订阅 Android 帧流
    private func subscribeToAndroidFrames(_ source: ScrcpyDeviceSource) {
        Task { [weak self] in
            for await frame in source.frameStream {
                await MainActor.run {
                    self?.androidLatestFrame = frame
                }
            }
        }
    }

    // MARK: - 公开方法

    /// 手动启动 iOS 捕获
    func startIOSCapture() async {
        guard let source = iosDeviceSource else { return }
        do {
            try await source.startCapture()
        } catch {
            AppLogger.capture.error("启动 iOS 捕获失败: \(error.localizedDescription)")
        }
    }

    /// 手动停止 iOS 捕获
    func stopIOSCapture() async {
        guard let source = iosDeviceSource else { return }
        await source.stopCapture()
    }

    /// 手动启动 Android 捕获
    func startAndroidCapture() async {
        guard let source = androidDeviceSource else { return }
        do {
            try await source.startCapture()
        } catch {
            AppLogger.capture.error("启动 Android 捕获失败: \(error.localizedDescription)")
        }
    }

    /// 手动停止 Android 捕获
    func stopAndroidCapture() async {
        guard let source = androidDeviceSource else { return }
        await source.stopCapture()
    }
}
