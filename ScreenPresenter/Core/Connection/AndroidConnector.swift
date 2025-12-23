//
//  AndroidConnector.swift
//  ScreenPresenter
//
//  Created by Sun on 2025/12/22.
//
//  Android 连接器
//  管理 adb/scrcpy 连接与投屏流程
//

import AppKit
import Combine
import Foundation

// MARK: - 连接状态

enum AndroidConnectionState: Equatable {
    case disconnected
    case connecting
    case waitingForAuthorization // 等待用户在手机上授权
    case connected
    case error(String)

    var displayName: String {
        switch self {
        case .disconnected:
            "未连接"
        case .connecting:
            "连接中..."
        case .waitingForAuthorization:
            "等待授权"
        case .connected:
            "已连接"
        case let .error(message):
            "错误: \(message)"
        }
    }
}

// MARK: - scrcpy 配置

struct ScrcpyConfig {
    var noAudio: Bool = true // 不传输音频（减少延迟）
    var stayAwake: Bool = true // 保持设备唤醒
    var turnScreenOff: Bool = false // 关闭手机屏幕
    var maxSize: Int? // 最大分辨率
    var maxFps: Int? // 最大帧率
    var bitrate: String? // 码率，如 "8M"
    var windowTitle: String? // 窗口标题
    var alwaysOnTop: Bool = false // 窗口置顶

    // 录屏配置
    var recordPath: String? // 录制文件路径
    var recordFormat: RecordFormat = .mp4 // 录制格式

    enum RecordFormat: String {
        case mp4
        case mkv
    }

    /// 转换为命令行参数
    var arguments: [String] {
        var args: [String] = []

        if noAudio {
            args.append("--no-audio")
        }
        if stayAwake {
            args.append("--stay-awake")
        }
        if turnScreenOff {
            args.append("--turn-screen-off")
        }
        if let maxSize {
            args.append("--max-size=\(maxSize)")
        }
        if let maxFps {
            args.append("--max-fps=\(maxFps)")
        }
        if let bitrate {
            args.append("--video-bit-rate=\(bitrate)")
        }
        if let windowTitle {
            args.append("--window-title=\(windowTitle)")
        }
        if alwaysOnTop {
            args.append("--always-on-top")
        }
        if let recordPath {
            args.append("--record=\(recordPath)")
            args.append("--record-format=\(recordFormat.rawValue)")
        }

        return args
    }
}

// MARK: - Android 连接器

@MainActor
final class AndroidConnector: ObservableObject {
    // MARK: - 状态

    /// 当前连接状态
    @Published private(set) var connectionState: AndroidConnectionState = .disconnected

    /// 当前连接的设备
    @Published private(set) var connectedDevice: AndroidDevice?

    /// 是否正在录屏
    @Published private(set) var isRecording = false

    /// 当前录屏文件路径
    @Published private(set) var currentRecordingPath: String?

    /// scrcpy 进程 ID
    private var scrcpyProcessID: UUID?

    // MARK: - 依赖

    private let processRunner = ProcessRunner()
    private let toolchainManager: ToolchainManager
    private let deviceProvider: AndroidDeviceProvider

    // MARK: - 初始化

    init(deviceProvider: AndroidDeviceProvider, toolchainManager: ToolchainManager) {
        self.deviceProvider = deviceProvider
        self.toolchainManager = toolchainManager
    }

    // MARK: - 公开方法

    /// 连接到设备并启动投屏
    /// - Parameters:
    ///   - device: 目标设备
    ///   - config: scrcpy 配置
    func connect(to device: AndroidDevice, config: ScrcpyConfig = ScrcpyConfig()) async {
        // 检查设备状态
        guard device.state == .device else {
            if device.state == .unauthorized {
                connectionState = .waitingForAuthorization
                await waitForAuthorization(device: device, config: config)
            } else {
                connectionState = .error("设备状态异常: \(device.state.displayName)")
            }
            return
        }

        connectionState = .connecting

        // 启动 scrcpy
        await startScrcpy(for: device, config: config)
    }

    /// 断开连接
    func disconnect() {
        if let processID = scrcpyProcessID {
            processRunner.terminate(processID)
            scrcpyProcessID = nil
        }
        connectionState = .disconnected
        connectedDevice = nil
        isRecording = false
        currentRecordingPath = nil
    }

    /// 开始录屏（需要先连接）
    func startRecording() async {
        guard let device = connectedDevice, connectionState == .connected else { return }

        // 先断开当前连接
        disconnect()

        // 生成录屏文件路径
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestamp = dateFormatter.string(from: Date())

        let moviesURL = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first!
        let recordingDir = moviesURL.appendingPathComponent("ScreenPresenter", isDirectory: true)

        // 创建目录
        try? FileManager.default.createDirectory(at: recordingDir, withIntermediateDirectories: true)

        let filename = "\(device.displayName)_\(timestamp).mp4"
        let recordPath = recordingDir.appendingPathComponent(filename).path

        currentRecordingPath = recordPath

        // 使用录屏配置重新连接
        var config = ScrcpyConfig()
        config.recordPath = recordPath
        config.windowTitle = "🔴 录制中 - \(device.displayName)"

        isRecording = true
        await connect(to: device, config: config)
    }

    /// 停止录屏
    func stopRecording() {
        if isRecording {
            disconnect()

            // 打开录屏文件所在目录
            if let path = currentRecordingPath {
                let url = URL(fileURLWithPath: path).deletingLastPathComponent()
                NSWorkspace.shared.open(url)
            }
        }
    }

    // MARK: - 私有方法

    /// 等待用户授权
    private func waitForAuthorization(device: AndroidDevice, config: ScrcpyConfig) async {
        // 每 2 秒轮询一次，最多等待 60 秒
        let maxAttempts = 30
        var attempts = 0

        while attempts < maxAttempts {
            try? await Task.sleep(nanoseconds: 2_000_000_000)

            await deviceProvider.refreshDevices()

            if let updatedDevice = deviceProvider.device(for: device.serial) {
                if updatedDevice.state == .device {
                    // 已授权，开始连接
                    await startScrcpy(for: updatedDevice, config: config)
                    return
                } else if updatedDevice.state != .unauthorized {
                    // 设备状态变化（可能断开）
                    connectionState = .error("设备断开连接")
                    return
                }
            } else {
                // 设备消失
                connectionState = .error("设备已断开")
                return
            }

            attempts += 1
        }

        connectionState = .error("等待授权超时，请在手机上点击「允许 USB 调试」")
    }

    /// 启动 scrcpy
    private func startScrcpy(for device: AndroidDevice, config: ScrcpyConfig) async {
        // 构建参数
        var arguments = ["-s", device.serial]
        arguments.append(contentsOf: config.arguments)

        // 设置窗口标题
        var finalConfig = config
        if finalConfig.windowTitle == nil {
            finalConfig.windowTitle = device.displayName
            arguments.append("--window-title=\(device.displayName)")
        }

        do {
            let processID = try await processRunner.startBackground(
                toolchainManager.scrcpyPath,
                arguments: arguments,
                onOutput: { [weak self] output in
                    Task { @MainActor in
                        self?.handleScrcpyOutput(output)
                    }
                },
                onTermination: { [weak self] exitCode in
                    Task { @MainActor in
                        self?.handleScrcpyTermination(exitCode: exitCode)
                    }
                }
            )

            scrcpyProcessID = processID
            connectedDevice = device
            connectionState = .connected

        } catch {
            connectionState = .error("启动投屏失败: \(error.localizedDescription)")
        }
    }

    /// 处理 scrcpy 输出
    private func handleScrcpyOutput(_ output: String) {
        // 可以在这里解析 scrcpy 输出，检测错误等
        print("[scrcpy] \(output)")
    }

    /// 处理 scrcpy 终止
    private func handleScrcpyTermination(exitCode: Int32) {
        scrcpyProcessID = nil
        connectedDevice = nil

        if exitCode == 0 {
            connectionState = .disconnected
        } else {
            connectionState = .error("投屏意外终止 (退出码: \(exitCode))")
        }
    }
}

// MARK: - Wi-Fi 连接扩展

extension AndroidConnector {
    /// 通过 Wi-Fi 连接设备（需要先 USB 连接）
    /// - Parameters:
    ///   - device: 已通过 USB 连接的设备
    ///   - port: tcpip 端口，默认 5555
    func enableWifiConnection(for device: AndroidDevice, port: Int = 5555) async throws -> String {
        // 1. 启用 tcpip 模式
        let tcpipResult = try await processRunner.run(
            toolchainManager.adbPath,
            arguments: ["-s", device.serial, "tcpip", String(port)]
        )

        guard tcpipResult.isSuccess else {
            throw ProcessError.executionFailed(
                exitCode: tcpipResult.exitCode,
                stderr: tcpipResult.stderr
            )
        }

        // 等待设备重启 adb
        try await Task.sleep(nanoseconds: 2_000_000_000)

        // 2. 获取设备 IP 地址
        let ipResult = try await processRunner.run(
            toolchainManager.adbPath,
            arguments: ["-s", device.serial, "shell", "ip", "route"]
        )

        // 解析 IP 地址
        if let match = ipResult.stdout.firstMatch(of: /src (\d+\.\d+\.\d+\.\d+)/) {
            let ip = String(match.1)
            return "\(ip):\(port)"
        }

        throw ProcessError.executionFailed(
            exitCode: -1,
            stderr: "无法获取设备 IP 地址"
        )
    }

    /// 连接到 Wi-Fi 设备
    func connectWifi(address: String) async throws {
        let result = try await processRunner.run(
            toolchainManager.adbPath,
            arguments: ["connect", address]
        )

        if !result.isSuccess || result.stdout.contains("failed") {
            throw ProcessError.executionFailed(
                exitCode: result.exitCode,
                stderr: result.stdout + result.stderr
            )
        }
    }

    /// 断开 Wi-Fi 连接
    func disconnectWifi(address: String) async throws {
        _ = try await processRunner.run(
            toolchainManager.adbPath,
            arguments: ["disconnect", address]
        )
    }
}

// MARK: - 快捷操作扩展

extension AndroidConnector {
    /// 截图并保存
    func takeScreenshot() async {
        guard let device = connectedDevice else { return }

        // 生成文件名
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestamp = dateFormatter.string(from: Date())

        let picturesURL = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first!
        let screenshotDir = picturesURL.appendingPathComponent("ScreenPresenter", isDirectory: true)

        // 创建目录
        try? FileManager.default.createDirectory(at: screenshotDir, withIntermediateDirectories: true)

        let filename = "\(device.displayName)_\(timestamp).png"
        let savePath = screenshotDir.appendingPathComponent(filename).path

        do {
            // 在设备上截图
            _ = try await processRunner.run(
                toolchainManager.adbPath,
                arguments: ["-s", device.serial, "shell", "screencap", "-p", "/sdcard/screenshot.png"]
            )

            // 拉取到本地
            let result = try await processRunner.run(
                toolchainManager.adbPath,
                arguments: ["-s", device.serial, "pull", "/sdcard/screenshot.png", savePath]
            )

            if result.isSuccess {
                // 删除设备上的临时文件
                _ = try? await processRunner.run(
                    toolchainManager.adbPath,
                    arguments: ["-s", device.serial, "shell", "rm", "/sdcard/screenshot.png"]
                )

                // 打开截图所在目录
                NSWorkspace.shared.open(screenshotDir)
            }
        } catch {
            print("截图失败: \(error)")
        }
    }

    /// 发送按键事件
    func sendKeyEvent(_ keyCode: Int) async {
        guard let device = connectedDevice else { return }

        _ = try? await processRunner.run(
            toolchainManager.adbPath,
            arguments: ["-s", device.serial, "shell", "input", "keyevent", String(keyCode)]
        )
    }

    /// 返回键
    func pressBack() async {
        await sendKeyEvent(4) // KEYCODE_BACK
    }

    /// Home 键
    func pressHome() async {
        await sendKeyEvent(3) // KEYCODE_HOME
    }

    /// 最近任务键
    func pressRecents() async {
        await sendKeyEvent(187) // KEYCODE_APP_SWITCH
    }

    /// 音量加
    func volumeUp() async {
        await sendKeyEvent(24) // KEYCODE_VOLUME_UP
    }

    /// 音量减
    func volumeDown() async {
        await sendKeyEvent(25) // KEYCODE_VOLUME_DOWN
    }

    /// 旋转屏幕
    func rotateScreen() async {
        guard let device = connectedDevice else { return }

        // 获取当前旋转状态
        do {
            let result = try await processRunner.run(
                toolchainManager.adbPath,
                arguments: ["-s", device.serial, "shell", "settings", "get", "system", "user_rotation"]
            )

            let currentRotation = Int(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
            let newRotation = (currentRotation + 1) % 4

            // 先禁用自动旋转
            _ = try await processRunner.run(
                toolchainManager.adbPath,
                arguments: ["-s", device.serial, "shell", "settings", "put", "system", "accelerometer_rotation", "0"]
            )

            // 设置新的旋转角度
            _ = try await processRunner.run(
                toolchainManager.adbPath,
                arguments: [
                    "-s",
                    device.serial,
                    "shell",
                    "settings",
                    "put",
                    "system",
                    "user_rotation",
                    String(newRotation),
                ]
            )
        } catch {
            print("旋转屏幕失败: \(error)")
        }
    }

    /// 电源键（锁屏/唤醒）
    func pressPower() async {
        await sendKeyEvent(26) // KEYCODE_POWER
    }
}
