//
//  AndroidADBService.swift
//  ScreenPresenter
//
//  Created by Sun on 2025/12/24.
//
//  Android ADB 命令服务
//  封装 adb 命令执行，提供结构化接口
//

import Foundation

// MARK: - ADB 命令结果

/// ADB 命令执行结果
struct ADBResult {
    let exitCode: Int32
    let stdout: String
    let stderr: String
    let duration: TimeInterval

    var isSuccess: Bool { exitCode == 0 }
}

// MARK: - ADB 错误

/// ADB 执行错误
enum ADBError: LocalizedError {
    case executableNotFound
    case deviceNotFound(serial: String)
    case commandFailed(command: String, exitCode: Int32, stderr: String)
    case timeout(command: String)
    case connectionFailed(reason: String)

    var errorDescription: String? {
        switch self {
        case .executableNotFound:
            "adb 可执行文件未找到"
        case let .deviceNotFound(serial):
            "设备未找到: \(serial)"
        case let .commandFailed(command, exitCode, stderr):
            "命令失败 [\(command)]: 退出码 \(exitCode), \(stderr)"
        case let .timeout(command):
            "命令超时: \(command)"
        case let .connectionFailed(reason):
            "连接失败: \(reason)"
        }
    }
}

// MARK: - Android ADB 服务

/// Android ADB 命令服务
/// 提供对 adb 命令的封装，支持指定设备执行
final class AndroidADBService {
    // MARK: - 属性

    /// adb 可执行文件路径
    private let adbPath: String

    /// 设备序列号
    private let deviceSerial: String

    /// 进程执行器
    private let processRunner: ProcessRunner

    /// 命令执行超时时间（秒）
    private let timeout: TimeInterval

    // MARK: - 初始化

    @MainActor
    init(
        adbPath: String,
        deviceSerial: String,
        processRunner: ProcessRunner? = nil,
        timeout: TimeInterval = 30
    ) {
        self.adbPath = adbPath
        self.deviceSerial = deviceSerial
        self.processRunner = processRunner ?? ProcessRunner()
        self.timeout = timeout
    }

    // MARK: - 公开方法

    /// 执行 adb 命令
    /// - Parameters:
    ///   - arguments: 命令参数（不包含 -s serial）
    ///   - logCommand: 是否记录命令日志
    /// - Returns: 执行结果
    @MainActor
    func execute(_ arguments: [String], logCommand: Bool = true) async throws -> ADBResult {
        let startTime = CFAbsoluteTimeGetCurrent()

        // 构建完整参数：-s <serial> <arguments>
        var fullArgs = ["-s", deviceSerial]
        fullArgs.append(contentsOf: arguments)

        let commandDescription = "adb \(fullArgs.joined(separator: " "))"

        if logCommand {
            AppLogger.process.info("[ADB] 执行: \(commandDescription)")
        }

        do {
            let result = try await processRunner.run(adbPath, arguments: fullArgs, timeout: timeout)
            let duration = CFAbsoluteTimeGetCurrent() - startTime

            let adbResult = ADBResult(
                exitCode: result.exitCode,
                stdout: result.stdout,
                stderr: result.stderr,
                duration: duration
            )

            if logCommand {
                if result.isSuccess {
                    AppLogger.process.info("[ADB] 成功 (\(String(format: "%.1f", duration * 1000))ms)")
                } else {
                    AppLogger.process.warning("[ADB] 失败: 退出码 \(result.exitCode), stderr: \(result.stderr)")
                }
            }

            return adbResult
        } catch {
            let duration = CFAbsoluteTimeGetCurrent() - startTime
            AppLogger.process
                .error("[ADB] 执行异常 (\(String(format: "%.1f", duration * 1000))ms): \(error.localizedDescription)")
            throw error
        }
    }

    /// 推送文件到设备
    /// - Parameters:
    ///   - localPath: 本地文件路径
    ///   - remotePath: 设备上的目标路径
    @MainActor
    func push(local localPath: String, remote remotePath: String) async throws {
        AppLogger.process.info("[ADB] push: \(localPath) -> \(remotePath)")

        let result = try await execute(["push", localPath, remotePath])

        if !result.isSuccess {
            throw ADBError.commandFailed(
                command: "push",
                exitCode: result.exitCode,
                stderr: result.stderr
            )
        }

        AppLogger.process.info("[ADB] push 成功，耗时: \(String(format: "%.1f", result.duration * 1000))ms")
    }

    /// 设置 adb reverse（设备连接到 macOS 监听端口）
    /// - Parameters:
    ///   - localAbstract: 设备上的 Unix 域套接字名称
    ///   - tcpPort: macOS 上的 TCP 端口
    @MainActor
    func reverse(localAbstract: String, tcpPort: Int) async throws {
        AppLogger.process.info("[ADB] reverse: localabstract:\(localAbstract) -> tcp:\(tcpPort)")

        let result = try await execute([
            "reverse",
            "localabstract:\(localAbstract)",
            "tcp:\(tcpPort)",
        ])

        if !result.isSuccess {
            throw ADBError.commandFailed(
                command: "reverse",
                exitCode: result.exitCode,
                stderr: result.stderr
            )
        }

        AppLogger.process.info("[ADB] reverse 设置成功")
    }

    /// 移除 adb reverse
    /// - Parameter localAbstract: 设备上的 Unix 域套接字名称
    @MainActor
    func removeReverse(localAbstract: String) async {
        AppLogger.process.info("[ADB] remove reverse: localabstract:\(localAbstract)")

        do {
            _ = try await execute(["reverse", "--remove", "localabstract:\(localAbstract)"], logCommand: false)
            AppLogger.process.info("[ADB] reverse 已移除")
        } catch {
            AppLogger.process.warning("[ADB] 移除 reverse 失败: \(error.localizedDescription)")
        }
    }

    /// 移除所有 adb reverse
    @MainActor
    func removeAllReverse() async {
        AppLogger.process.info("[ADB] remove all reverse")

        do {
            _ = try await execute(["reverse", "--remove-all"], logCommand: false)
            AppLogger.process.info("[ADB] 所有 reverse 已移除")
        } catch {
            AppLogger.process.warning("[ADB] 移除所有 reverse 失败: \(error.localizedDescription)")
        }
    }

    /// 设置 adb forward（macOS 连接到设备端口）
    /// - Parameters:
    ///   - tcpPort: macOS 上的 TCP 端口
    ///   - localAbstract: 设备上的 Unix 域套接字名称
    @MainActor
    func forward(tcpPort: Int, localAbstract: String) async throws {
        AppLogger.process.info("[ADB] forward: tcp:\(tcpPort) -> localabstract:\(localAbstract)")

        let result = try await execute([
            "forward",
            "tcp:\(tcpPort)",
            "localabstract:\(localAbstract)",
        ])

        if !result.isSuccess {
            throw ADBError.commandFailed(
                command: "forward",
                exitCode: result.exitCode,
                stderr: result.stderr
            )
        }

        AppLogger.process.info("[ADB] forward 设置成功")
    }

    /// 移除 adb forward
    /// - Parameter tcpPort: macOS 上的 TCP 端口
    @MainActor
    func removeForward(tcpPort: Int) async {
        AppLogger.process.info("[ADB] remove forward: tcp:\(tcpPort)")

        do {
            _ = try await execute(["forward", "--remove", "tcp:\(tcpPort)"], logCommand: false)
            AppLogger.process.info("[ADB] forward 已移除")
        } catch {
            AppLogger.process.warning("[ADB] 移除 forward 失败: \(error.localizedDescription)")
        }
    }

    /// 移除所有 adb forward
    @MainActor
    func removeAllForward() async {
        AppLogger.process.info("[ADB] remove all forward")

        do {
            _ = try await execute(["forward", "--remove-all"], logCommand: false)
            AppLogger.process.info("[ADB] 所有 forward 已移除")
        } catch {
            AppLogger.process.warning("[ADB] 移除所有 forward 失败: \(error.localizedDescription)")
        }
    }

    /// 执行 shell 命令
    /// - Parameter command: shell 命令
    /// - Returns: 执行结果
    @MainActor
    func shell(_ command: String) async throws -> ADBResult {
        try await execute(["shell", command])
    }

    /// 启动 scrcpy-server 进程（后台运行，不等待结束）
    /// - Parameters:
    ///   - serverPath: 设备上 scrcpy-server 的路径
    ///   - arguments: 服务器参数列表
    /// - Returns: 启动的进程
    func startServer(serverPath: String, arguments: [String]) throws -> Process {
        let shellCommand =
            "CLASSPATH=\(serverPath) app_process / com.genymobile.scrcpy.Server \(arguments.joined(separator: " "))"

        print("🚀 [ADB] 启动 scrcpy-server")
        print("📋 [ADB] Shell命令: \(shellCommand)")
        print("📋 [ADB] ADB路径: \(adbPath)")
        print("📋 [ADB] 设备序列号: \(deviceSerial)")
        AppLogger.process.info("[ADB] 启动 scrcpy-server: \(shellCommand)")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: adbPath)
        process.arguments = ["-s", deviceSerial, "shell", shellCommand]

        // 同时捕获 stdout 和 stderr，scrcpy-server 的输出可能在任一流上
        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe // 合并到同一个 pipe

        try process.run()

        print("✅ [ADB] scrcpy-server 进程已启动，PID: \(process.processIdentifier)")
        AppLogger.process.info("[ADB] scrcpy-server 进程已启动，PID: \(process.processIdentifier)")

        // 异步读取所有输出
        Task {
            print("📖 [ADB] 开始读取 scrcpy-server 输出...")
            for try await line in outputPipe.fileHandleForReading.bytes.lines {
                // 使用 print 确保输出可见
                print("📺 [scrcpy-server] \(line)")
                // 根据内容判断日志级别
                if line.contains("ERROR") || line.contains("Exception") || line.contains("error") {
                    AppLogger.process.error("[scrcpy-server] \(line)")
                } else if line.contains("WARN") || line.contains("warning") {
                    AppLogger.process.warning("[scrcpy-server] \(line)")
                } else {
                    AppLogger.process.info("[scrcpy-server] \(line)")
                }
            }
            print("📕 [scrcpy-server] 输出流已关闭")
            AppLogger.process.info("[scrcpy-server] 输出流已关闭")
        }

        return process
    }

    /// 终止 scrcpy-server（如果正在运行）
    @MainActor
    func killScrcpyServerIfNeeded() async {
        AppLogger.process.info("[ADB] 检查并终止 scrcpy-server...")

        do {
            // 查找并终止 scrcpy-server 进程
            let result = try await shell("pkill -f 'app_process.*scrcpy' 2>/dev/null || true")
            if result.isSuccess {
                AppLogger.process.info("[ADB] scrcpy-server 已终止（如果存在）")
            }
        } catch {
            AppLogger.process.warning("[ADB] 终止 scrcpy-server 失败: \(error.localizedDescription)")
        }
    }

    // MARK: - 设备信息

    /// 获取设备属性
    /// - Parameter property: 属性名称
    /// - Returns: 属性值
    @MainActor
    func getProperty(_ property: String) async -> String? {
        do {
            let result = try await shell("getprop \(property)")
            if result.isSuccess {
                return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        } catch {
            // 忽略错误
        }
        return nil
    }

    /// 获取设备型号
    @MainActor
    func getDeviceModel() async -> String? {
        await getProperty("ro.product.model")
    }

    /// 获取 Android 版本
    @MainActor
    func getAndroidVersion() async -> String? {
        await getProperty("ro.build.version.release")
    }

    /// 获取设备品牌
    @MainActor
    func getDeviceBrand() async -> String? {
        await getProperty("ro.product.brand")
    }

    // MARK: - 设备列表

    /// 列出已连接的 Android 设备
    /// - Returns: 设备列表
    /// - Note: 此方法不使用 -s 参数，因为需要列出所有设备
    @MainActor
    func listDevices() async throws -> [AndroidDevice] {
        AppLogger.process.info("[ADB] 列出设备...")

        let startTime = CFAbsoluteTimeGetCurrent()

        let result = try await processRunner.run(adbPath, arguments: ["devices", "-l"], timeout: timeout)
        let duration = CFAbsoluteTimeGetCurrent() - startTime

        guard result.isSuccess else {
            AppLogger.process.error("[ADB] 列出设备失败: \(result.stderr)")
            throw ADBError.commandFailed(
                command: "devices",
                exitCode: result.exitCode,
                stderr: result.stderr
            )
        }

        let devices = parseDevicesOutput(result.stdout)
        AppLogger.process.info("[ADB] 找到 \(devices.count) 个设备 (\(String(format: "%.1f", duration * 1000))ms)")

        return devices
    }

    /// 解析 adb devices -l 输出
    private func parseDevicesOutput(_ output: String) -> [AndroidDevice] {
        output
            .components(separatedBy: .newlines)
            .compactMap { AndroidDevice.parse(from: $0) }
    }
}
