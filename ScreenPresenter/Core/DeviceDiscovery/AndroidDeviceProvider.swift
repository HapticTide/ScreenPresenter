//
//  AndroidDeviceProvider.swift
//  ScreenPresenter
//
//  Created by Sun on 2025/12/22.
//
//  Android 设备提供者
//  通过 adb 扫描并管理 Android 设备列表
//

import Combine
import Foundation

// MARK: - Android 设备提供者

@MainActor
final class AndroidDeviceProvider: ObservableObject {
    // MARK: - 状态

    /// 已发现的设备列表
    @Published private(set) var devices: [AndroidDevice] = []

    /// 是否正在监控
    @Published private(set) var isMonitoring = false

    /// 最后一次错误
    @Published private(set) var lastError: String?

    /// adb 服务是否运行中
    @Published private(set) var isAdbServerRunning = false

    // MARK: - 私有属性

    private let processRunner = ProcessRunner()
    private var monitoringTask: Task<Void, Never>?
    private let toolchainManager: ToolchainManager

    /// 轮询间隔（秒）
    private let pollingInterval: TimeInterval = 2.0

    // MARK: - 生命周期

    init(toolchainManager: ToolchainManager) {
        self.toolchainManager = toolchainManager
    }

    deinit {
        monitoringTask?.cancel()
    }

    // MARK: - 公开方法

    /// 开始监控设备
    func startMonitoring() {
        guard !isMonitoring else { return }

        isMonitoring = true
        lastError = nil

        monitoringTask = Task {
            await startAdbServer()

            while !Task.isCancelled, isMonitoring {
                await refreshDevices()
                try? await Task.sleep(nanoseconds: UInt64(pollingInterval * 1_000_000_000))
            }
        }
    }

    /// 停止监控
    func stopMonitoring() {
        isMonitoring = false
        monitoringTask?.cancel()
        monitoringTask = nil
    }

    /// 手动刷新设备列表
    func refreshDevices() async {
        do {
            let result = try await processRunner.run(
                toolchainManager.adbPath,
                arguments: ["devices", "-l"]
            )

            if result.isSuccess {
                let newDevices = parseDevices(from: result.stdout)

                // 只在设备列表真正变化时更新
                if newDevices != devices {
                    devices = newDevices
                }

                isAdbServerRunning = true
                lastError = nil
            } else {
                lastError = "adb 命令执行失败: \(result.stderr)"
            }
        } catch {
            lastError = error.localizedDescription
            isAdbServerRunning = false
        }
    }

    /// 启动 adb 服务
    func startAdbServer() async {
        do {
            let result = try await processRunner.run(
                toolchainManager.adbPath,
                arguments: ["start-server"]
            )
            isAdbServerRunning = result.isSuccess
        } catch {
            isAdbServerRunning = false
            lastError = L10n.adb.startFailed(error.localizedDescription)
        }
    }

    /// 停止 adb 服务
    func stopAdbServer() async {
        do {
            _ = try await processRunner.run(
                toolchainManager.adbPath,
                arguments: ["kill-server"]
            )
            isAdbServerRunning = false
            devices = []
        } catch {
            lastError = L10n.adb.stopFailed(error.localizedDescription)
        }
    }

    /// 获取特定设备
    func device(for serial: String) -> AndroidDevice? {
        devices.first { $0.serial == serial }
    }

    // MARK: - 私有方法

    /// 解析 adb devices -l 输出
    private func parseDevices(from output: String) -> [AndroidDevice] {
        output
            .components(separatedBy: .newlines)
            .compactMap { AndroidDevice.parse(from: $0) }
    }
}

// MARK: - 设备操作扩展

extension AndroidDeviceProvider {
    /// 获取设备属性
    func getDeviceProperty(_ serial: String, property: String) async -> String? {
        do {
            let result = try await processRunner.run(
                toolchainManager.adbPath,
                arguments: ["-s", serial, "shell", "getprop", property]
            )
            if result.isSuccess {
                return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        } catch {
            // 忽略
        }
        return nil
    }

    /// 获取设备品牌
    func getDeviceBrand(_ serial: String) async -> String? {
        await getDeviceProperty(serial, property: "ro.product.brand")
    }

    /// 获取 Android 版本
    func getAndroidVersion(_ serial: String) async -> String? {
        await getDeviceProperty(serial, property: "ro.build.version.release")
    }
}
