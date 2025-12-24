//
//  AppState.swift
//  ScreenPresenter
//
//  Created by Sun on 2025/12/22.
//
//  全局应用状态
//  管理设备、捕获和渲染状态
//

import AppKit
import AVFoundation
import Combine
import CoreMedia
import Foundation

// MARK: - 全局应用状态

@MainActor
final class AppState {
    // MARK: - 单例

    static let shared = AppState()

    // MARK: - 状态

    /// 工具链管理器
    private(set) var toolchainManager = ToolchainManager()

    /// iOS 设备提供者
    private(set) var iosDeviceProvider = IOSDeviceProvider()

    /// Android 设备提供者
    private(set) var androidDeviceProvider: AndroidDeviceProvider!

    /// iOS 设备源
    private(set) var iosDeviceSource: IOSDeviceSource?

    /// Android 设备源
    private(set) var androidDeviceSource: ScrcpyDeviceSource?

    /// 是否正在初始化
    private(set) var isInitializing = true

    // MARK: - 发布者

    let stateChangedPublisher = PassthroughSubject<Void, Never>()

    // MARK: - 私有属性

    private var deviceObservationTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    // MARK: - 初始化

    private init() {
        androidDeviceProvider = AndroidDeviceProvider(toolchainManager: toolchainManager)
        setupDeviceProvidersObservation()
    }

    /// 监听设备提供者的变化
    private func setupDeviceProvidersObservation() {
        // 监听 iOS 设备列表变化（包括状态变化）
        iosDeviceProvider.$devices
            .dropFirst() // 跳过初始值
            .sink { [weak self] _ in
                self?.stateChangedPublisher.send()
            }
            .store(in: &cancellables)

        // 监听 Android 设备列表变化
        androidDeviceProvider.$devices
            .dropFirst()
            .sink { [weak self] _ in
                self?.stateChangedPublisher.send()
            }
            .store(in: &cancellables)
    }

    // MARK: - 公开方法

    /// 初始化应用
    func initialize() async {
        AppLogger.app.info("开始初始化应用")

        // 初始化工具链
        await toolchainManager.setup()

        // 开始监控设备
        iosDeviceProvider.startMonitoring()
        androidDeviceProvider.startMonitoring()

        // 启动设备观察
        startDeviceObservation()

        isInitializing = false
        stateChangedPublisher.send()

        AppLogger.app.info("应用初始化完成")
    }

    /// 清理资源
    func cleanup() async {
        AppLogger.app.info("开始清理资源")

        deviceObservationTask?.cancel()

        // 断开所有设备
        if let source = iosDeviceSource {
            await source.stopCapture()
            await source.disconnect()
        }

        if let source = androidDeviceSource {
            await source.stopCapture()
            await source.disconnect()
        }

        // 停止监控
        iosDeviceProvider.stopMonitoring()
        androidDeviceProvider.stopMonitoring()

        AppLogger.app.info("资源清理完成")
    }

    /// 刷新设备
    func refreshDevices() async {
        iosDeviceProvider.refreshDevices()
        await androidDeviceProvider.refreshDevices()
        stateChangedPublisher.send()
    }

    // MARK: - iOS 设备控制

    /// 启动 iOS 捕获
    func startIOSCapture() async throws {
        guard let source = iosDeviceSource else {
            if let device = iosDeviceProvider.devices.first {
                let newSource = IOSDeviceSource(device: device)
                iosDeviceSource = newSource
                try await newSource.connect()
                try await newSource.startCapture()
            } else {
                throw DeviceSourceError.connectionFailed(L10n.error.noDevice(L10n.platform.ios))
            }
            return
        }

        if source.state == .idle || source.state == .disconnected {
            try await source.connect()
        }

        try await source.startCapture()
        stateChangedPublisher.send()
    }

    /// 停止 iOS 捕获
    func stopIOSCapture() async {
        guard let source = iosDeviceSource else { return }
        await source.stopCapture()
        stateChangedPublisher.send()
    }

    // MARK: - Android 设备控制

    /// 启动 Android 捕获
    func startAndroidCapture() async throws {
        guard let source = androidDeviceSource else {
            if let device = androidDeviceProvider.devices.first {
                let newSource = ScrcpyDeviceSource(
                    device: device,
                    toolchainManager: toolchainManager
                )
                androidDeviceSource = newSource
                try await newSource.connect()
                try await newSource.startCapture()
            } else {
                throw DeviceSourceError.connectionFailed(L10n.error.noDevice(L10n.platform.android))
            }
            return
        }

        if source.state == .idle || source.state == .disconnected {
            try await source.connect()
        }

        try await source.startCapture()
        stateChangedPublisher.send()
    }

    /// 停止 Android 捕获
    func stopAndroidCapture() async {
        guard let source = androidDeviceSource else { return }
        await source.stopCapture()
        stateChangedPublisher.send()
    }

    // MARK: - 私有方法

    /// 启动设备观察
    private func startDeviceObservation() {
        deviceObservationTask?.cancel()
        deviceObservationTask = Task { [weak self] in
            guard let self else { return }

            while !Task.isCancelled {
                await checkAndUpdateDeviceSources()
                try? await Task.sleep(nanoseconds: 1_000_000_000) // 1秒
            }
        }
    }

    /// 检查并更新设备源
    private func checkAndUpdateDeviceSources() async {
        // 处理 iOS 设备变化
        await handleIOSDeviceChange()

        // 处理 Android 设备变化
        await handleAndroidDeviceChange()
    }

    /// 处理 iOS 设备变化
    private func handleIOSDeviceChange() async {
        let currentDevice = iosDeviceProvider.devices.first

        if let device = currentDevice {
            // 设备已连接
            // 使用 avUniqueID 比较设备（保持不变），而不是 id（可能从 avUniqueID 变成真实 UDID）
            // 这样当设备信息被 enriched() 增强时，不会错误地停止正在运行的捕获
            if iosDeviceSource == nil || iosDeviceSource?.iosDevice.avUniqueID != device.avUniqueID {
                // 断开旧设备
                if let oldSource = iosDeviceSource {
                    await oldSource.stopCapture()
                    await oldSource.disconnect()
                }

                // 创建新设备源（不自动捕获）
                let source = IOSDeviceSource(device: device)
                iosDeviceSource = source

                // 使用增强的设备信息记录日志
                var logMessage = "iOS 设备已连接: \(device.displayName)"
                if let modelName = device.displayModelName {
                    logMessage += " (\(modelName))"
                }
                AppLogger.device.info("\(logMessage)")

                // 如果有用户提示，单独记录
                if let prompt = device.userPrompt {
                    AppLogger.device.warning("iOS 设备状态: \(prompt)")
                }

                stateChangedPublisher.send()
            }
        } else {
            // 设备已断开
            if let source = iosDeviceSource {
                await source.stopCapture()
                await source.disconnect()
                iosDeviceSource = nil

                AppLogger.device.info("iOS 设备已断开")
                stateChangedPublisher.send()
            }
        }
    }

    /// 处理 Android 设备变化
    private func handleAndroidDeviceChange() async {
        let currentDevice = androidDeviceProvider.devices.first

        if let device = currentDevice {
            // 设备已连接
            if androidDeviceSource == nil || androidDeviceSource?.deviceInfo?.id != device.serial {
                // 断开旧设备
                if let oldSource = androidDeviceSource {
                    await oldSource.stopCapture()
                    await oldSource.disconnect()
                }

                // 创建新设备源（不自动捕获）
                let source = ScrcpyDeviceSource(
                    device: device,
                    toolchainManager: toolchainManager
                )
                androidDeviceSource = source

                AppLogger.device.info("Android 设备已连接: \(device.displayName)")
                stateChangedPublisher.send()
            }
        } else {
            // 设备已断开
            if let source = androidDeviceSource {
                await source.stopCapture()
                await source.disconnect()
                androidDeviceSource = nil

                AppLogger.device.info("Android 设备已断开")
                stateChangedPublisher.send()
            }
        }
    }

    // MARK: - 计算属性

    /// 当前 iOS 设备（用于获取完整设备信息）
    var currentIOSDevice: IOSDevice? {
        iosDeviceProvider.devices.first
    }

    /// iOS 是否已连接
    var iosConnected: Bool {
        currentIOSDevice != nil
    }

    /// iOS 设备名称（优先使用 FBDeviceControl 增强的名称）
    var iosDeviceName: String? {
        currentIOSDevice?.displayName
    }

    /// iOS 设备型号名称
    var iosDeviceModelName: String? {
        currentIOSDevice?.displayModelName
    }

    /// iOS 设备用户提示（信任状态、占用状态等）
    var iosDeviceUserPrompt: String? {
        currentIOSDevice?.userPrompt
    }

    /// iOS 是否正在捕获
    var iosCapturing: Bool {
        iosDeviceSource?.state == .capturing
    }

    /// Android 是否已连接
    var androidConnected: Bool {
        !androidDeviceProvider.devices.isEmpty
    }

    /// 当前 Android 设备
    var currentAndroidDevice: AndroidDevice? {
        androidDeviceProvider.devices.first
    }

    /// Android 设备名称
    var androidDeviceName: String? {
        currentAndroidDevice?.displayName
    }

    /// Android 设备型号名称
    var androidDeviceModelName: String? {
        currentAndroidDevice?.displayModelName
    }

    /// Android 系统版本
    var androidDeviceSystemVersion: String? {
        currentAndroidDevice?.displaySystemVersion
    }

    /// Android 设备状态
    var androidDeviceState: AndroidDeviceState? {
        currentAndroidDevice?.state
    }

    /// Android 设备用户提示（授权状态等）
    var androidDeviceUserPrompt: String? {
        currentAndroidDevice?.state.actionHint
    }

    /// Android 设备是否可捕获（已授权）
    var androidDeviceReady: Bool {
        currentAndroidDevice?.state == .device
    }

    /// Android 是否正在捕获
    var androidCapturing: Bool {
        androidDeviceSource?.state == .capturing
    }
}
