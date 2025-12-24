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
        guard !isMonitoring else {
            AppLogger.device.debug("设备监控已在运行中")
            return
        }

        AppLogger.device.info("开始监控 Android 设备")
        isMonitoring = true
        lastError = nil

        monitoringTask = Task {
            await startAdbServer()

            while !Task.isCancelled, isMonitoring {
                await refreshDevices()
                try? await Task.sleep(nanoseconds: UInt64(pollingInterval * 1_000_000_000))
            }

            AppLogger.device.info("设备监控已停止")
        }
    }

    /// 停止监控
    func stopMonitoring() {
        AppLogger.device.info("停止监控 Android 设备")
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
                var newDevices = parseDevices(from: result.stdout)

                // 为已授权设备获取详细信息
                for i in newDevices.indices {
                    if newDevices[i].state == .device {
                        newDevices[i] = await enrichDeviceInfo(newDevices[i])
                    }
                }

                // 只在设备列表真正变化时更新
                if newDevices != devices {
                    AppLogger.device.info("Android 设备列表已更新: \(newDevices.count) 个设备")
                    for device in newDevices {
                        AppLogger.device
                            .info(
                                "  - \(device.serial): \(device.state.rawValue), 名称: \(device.displayName), Android \(device.androidVersion ?? "?")"
                            )
                    }
                    devices = newDevices
                }

                isAdbServerRunning = true
                lastError = nil
            } else {
                AppLogger.device.error("adb devices 命令失败: \(result.stderr)")
                lastError = "adb 命令执行失败: \(result.stderr)"
            }
        } catch {
            AppLogger.device.error("刷新设备列表失败: \(error.localizedDescription)")
            lastError = error.localizedDescription
            isAdbServerRunning = false
        }
    }

    /// 获取设备详细信息
    private func enrichDeviceInfo(_ device: AndroidDevice) async -> AndroidDevice {
        var enriched = device

        // 并行获取所有属性以提高效率
        async let brand = getDeviceProperty(device.serial, property: "ro.product.brand")
        async let marketName = getDeviceProperty(device.serial, property: "ro.product.marketname")
        async let androidVersion = getDeviceProperty(device.serial, property: "ro.build.version.release")
        async let sdkVersion = getDeviceProperty(device.serial, property: "ro.build.version.sdk")

        enriched.brand = await brand
        enriched.marketName = await marketName
        enriched.androidVersion = await androidVersion
        enriched.sdkVersion = await sdkVersion

        // 某些设备没有 marketname，尝试其他属性
        if enriched.marketName == nil || enriched.marketName?.isEmpty == true {
            enriched.marketName = await getDeviceProperty(device.serial, property: "ro.product.vendor.marketname")
        }
        if enriched.marketName == nil || enriched.marketName?.isEmpty == true {
            enriched.marketName = await getDeviceProperty(device.serial, property: "ro.config.marketing_name")
        }

        return enriched
    }

    /// 启动 adb 服务
    func startAdbServer() async {
        AppLogger.device.info("启动 adb 服务...")

        do {
            let result = try await processRunner.run(
                toolchainManager.adbPath,
                arguments: ["start-server"]
            )
            isAdbServerRunning = result.isSuccess

            if result.isSuccess {
                AppLogger.device.info("adb 服务已启动")
            } else {
                AppLogger.device.error("adb 服务启动失败: \(result.stderr)")
            }
        } catch {
            isAdbServerRunning = false
            lastError = L10n.adb.startFailed(error.localizedDescription)
            AppLogger.device.error("adb 服务启动异常: \(error.localizedDescription)")
        }
    }

    /// 停止 adb 服务
    func stopAdbServer() async {
        AppLogger.device.info("停止 adb 服务...")

        do {
            _ = try await processRunner.run(
                toolchainManager.adbPath,
                arguments: ["kill-server"]
            )
            isAdbServerRunning = false
            devices = []
            AppLogger.device.info("adb 服务已停止")
        } catch {
            lastError = L10n.adb.stopFailed(error.localizedDescription)
            AppLogger.device.error("停止 adb 服务失败: \(error.localizedDescription)")
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
