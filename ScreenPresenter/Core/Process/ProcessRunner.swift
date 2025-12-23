//
//  ProcessRunner.swift
//  ScreenPresenter
//
//  Created by Sun on 2025/12/22.
//
//  进程运行器
//  封装外部命令执行和输出处理
//

import Combine
import Foundation

// MARK: - 进程执行结果

struct ProcessResult {
    let exitCode: Int32
    let stdout: String
    let stderr: String

    var isSuccess: Bool { exitCode == 0 }
}

// MARK: - 进程执行错误

enum ProcessError: LocalizedError {
    case executableNotFound(String)
    case executionFailed(exitCode: Int32, stderr: String)
    case timeout
    case cancelled

    var errorDescription: String? {
        switch self {
        case let .executableNotFound(path):
            "找不到可执行文件: \(path)"
        case let .executionFailed(exitCode, stderr):
            "执行失败 (退出码: \(exitCode)): \(stderr)"
        case .timeout:
            "执行超时"
        case .cancelled:
            "执行已取消"
        }
    }
}

// MARK: - 进程执行器

@MainActor
final class ProcessRunner: ObservableObject {
    /// 运行中的进程
    @Published private(set) var runningProcesses: [UUID: Process] = [:]

    /// 执行命令并等待结果
    /// - Parameters:
    ///   - executable: 可执行文件路径
    ///   - arguments: 命令参数
    ///   - timeout: 超时时间（秒）
    /// - Returns: 执行结果
    func run(
        _ executable: String,
        arguments: [String] = [],
        timeout: TimeInterval = 30
    ) async throws -> ProcessResult {
        // 检查可执行文件是否存在
        guard FileManager.default.fileExists(atPath: executable) else {
            throw ProcessError.executableNotFound(executable)
        }

        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        // 设置环境变量 - 保留原有 PATH 并追加常用路径
        var environment = ProcessInfo.processInfo.environment
        let existingPath = environment["PATH"] ?? ""
        let additionalPaths = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
        if existingPath.isEmpty {
            environment["PATH"] = additionalPaths
        } else {
            environment["PATH"] = "\(additionalPaths):\(existingPath)"
        }
        // 确保 HOME 环境变量设置正确
        if environment["HOME"] == nil {
            environment["HOME"] = NSHomeDirectory()
        }
        process.environment = environment

        let processID = UUID()

        // 在启动进程前就设置好数据读取
        // 使用 availableData 在后台线程读取，避免死锁
        var stdoutData = Data()
        var stderrData = Data()

        let stdoutHandle = stdoutPipe.fileHandleForReading
        let stderrHandle = stderrPipe.fileHandleForReading

        // 启动进程
        try process.run()

        _ = await MainActor.run {
            self.runningProcesses[processID] = process
        }

        // 使用 Task 异步读取数据
        async let stdoutTask: Data = Task.detached {
            stdoutHandle.readDataToEndOfFile()
        }.value

        async let stderrTask: Data = Task.detached {
            stderrHandle.readDataToEndOfFile()
        }.value

        // 超时处理
        let timeoutTask = Task {
            try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            if process.isRunning {
                process.terminate()
            }
        }

        // 等待进程结束
        process.waitUntilExit()
        timeoutTask.cancel()

        // 获取输出数据
        stdoutData = await stdoutTask
        stderrData = await stderrTask

        let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
        let stderr = String(data: stderrData, encoding: .utf8) ?? ""

        _ = await MainActor.run {
            self.runningProcesses.removeValue(forKey: processID)
        }

        return ProcessResult(
            exitCode: process.terminationStatus,
            stdout: stdout,
            stderr: stderr
        )
    }

    /// 启动后台进程（不等待结果）
    /// - Parameters:
    ///   - executable: 可执行文件路径
    ///   - arguments: 命令参数
    ///   - onOutput: 输出回调
    ///   - onTermination: 终止回调
    /// - Returns: 进程 ID
    func startBackground(
        _ executable: String,
        arguments: [String] = [],
        onOutput: ((String) -> Void)? = nil,
        onTermination: ((Int32) -> Void)? = nil
    ) async throws -> UUID {
        guard FileManager.default.fileExists(atPath: executable) else {
            throw ProcessError.executableNotFound(executable)
        }

        let process = Process()
        let stdoutPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = stdoutPipe
        process.standardError = stdoutPipe

        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = "/usr/local/bin:/usr/bin:/bin:/opt/homebrew/bin"
        process.environment = environment

        let processID = UUID()

        // 输出监听
        if let onOutput {
            stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if let output = String(data: data, encoding: .utf8), !output.isEmpty {
                    onOutput(output)
                }
            }
        }

        // 终止处理
        process.terminationHandler = { [weak self] process in
            stdoutPipe.fileHandleForReading.readabilityHandler = nil

            Task { @MainActor in
                self?.runningProcesses.removeValue(forKey: processID)
            }

            onTermination?(process.terminationStatus)
        }

        try process.run()
        runningProcesses[processID] = process

        return processID
    }

    /// 终止指定进程
    func terminate(_ processID: UUID) {
        runningProcesses[processID]?.terminate()
        runningProcesses.removeValue(forKey: processID)
    }

    /// 终止所有进程
    func terminateAll() {
        for (_, process) in runningProcesses {
            process.terminate()
        }
        runningProcesses.removeAll()
    }
}

// MARK: - 便捷扩展

extension ProcessRunner {
    /// 执行 shell 命令（不加载用户配置）
    func shell(_ command: String, timeout: TimeInterval = 30) async throws -> ProcessResult {
        try await run("/bin/zsh", arguments: ["-c", command], timeout: timeout)
    }

    /// 执行 shell 命令（使用登录 shell，加载完整 PATH）
    func loginShell(_ command: String, timeout: TimeInterval = 30) async throws -> ProcessResult {
        try await run("/bin/zsh", arguments: ["-l", "-c", command], timeout: timeout)
    }

    /// 启动后台 shell 命令（使用登录 shell 以获取完整 PATH）
    /// - Parameters:
    ///   - command: shell 命令
    ///   - onOutput: 输出回调
    ///   - onTermination: 终止回调
    /// - Returns: 进程 ID
    func startBackgroundShell(
        _ command: String,
        onOutput: ((String) -> Void)? = nil,
        onTermination: ((Int32) -> Void)? = nil
    ) async throws -> UUID {
        let process = Process()
        let stdoutPipe = Pipe()

        // 使用 zsh 的登录 shell (-l) 来获取完整的环境变量（包括 Homebrew 路径）
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-l", "-c", command]
        process.standardOutput = stdoutPipe
        process.standardError = stdoutPipe

        let processID = UUID()

        // 输出监听
        if let onOutput {
            stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if let output = String(data: data, encoding: .utf8), !output.isEmpty {
                    onOutput(output)
                }
            }
        }

        // 终止处理
        process.terminationHandler = { [weak self] process in
            stdoutPipe.fileHandleForReading.readabilityHandler = nil

            Task { @MainActor in
                self?.runningProcesses.removeValue(forKey: processID)
            }

            onTermination?(process.terminationStatus)
        }

        try process.run()
        runningProcesses[processID] = process

        return processID
    }

    // MARK: - Static Helpers

    /// 查找可执行文件路径
    /// - Parameter name: 可执行文件名称
    /// - Returns: 完整路径，如果未找到则返回 nil
    nonisolated static func findExecutable(_ name: String) -> String? {
        // 常见的可执行文件路径
        let searchPaths = [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin",
        ]

        for path in searchPaths {
            let fullPath = (path as NSString).appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: fullPath) {
                return fullPath
            }
        }

        return nil
    }
}
