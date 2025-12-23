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
        AppLogger.device.info("刷新设备列表")
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
            if iosDeviceSource == nil || iosDeviceSource?.iosDevice.id != device.id {
                // 断开旧设备
                if let oldSource = iosDeviceSource {
                    await oldSource.stopCapture()
                    await oldSource.disconnect()
                }

                // 创建新设备源（不自动捕获）
                let source = IOSDeviceSource(device: device)
                iosDeviceSource = source

                AppLogger.device.info("iOS 设备已连接: \(device.name)")
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

    /// iOS 是否已连接
    var iosConnected: Bool {
        !iosDeviceProvider.devices.isEmpty
    }

    /// iOS 设备名称
    var iosDeviceName: String? {
        iosDeviceProvider.devices.first?.name
    }

    /// iOS 是否正在捕获
    var iosCapturing: Bool {
        iosDeviceSource?.state == .capturing
    }

    /// Android 是否已连接
    var androidConnected: Bool {
        !androidDeviceProvider.devices.isEmpty
    }

    /// Android 设备名称
    var androidDeviceName: String? {
        androidDeviceProvider.devices.first?.displayName
    }

    /// Android 是否正在捕获
    var androidCapturing: Bool {
        androidDeviceSource?.state == .capturing
    }
}
