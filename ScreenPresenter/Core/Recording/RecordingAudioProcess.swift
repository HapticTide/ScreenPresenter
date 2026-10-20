//
//  RecordingAudioProcess.swift
//  ScreenPresenter
//
//  Created by Tank on 2026/07/18.
//

import AppKit
import Foundation

// MARK: - Helper 通信协议

enum RecordingAudioHelperErrorCode: String, Equatable {
    case noDevice
    case permissionDenied
    case unavailable
}

enum RecordingAudioProcessProtocol {
    static let outputFlag = "--output"
    static let controlDirectoryFlag = "--control-directory"
    static let ownerPIDFlag = "--owner-pid"
    static let readyFileName = "ready"
    static let errorFileName = "error"
    static let stopFileName = "stop"

    enum Handshake: Equatable {
        case ready(startedAt: Date)
        case error(code: RecordingAudioHelperErrorCode, message: String)
    }

    static func helperArguments(outputURL: URL, controlDirectoryURL: URL, ownerPID: Int32) -> [String] {
        [
            outputFlag,
            outputURL.path,
            controlDirectoryFlag,
            controlDirectoryURL.path,
            ownerPIDFlag,
            String(ownerPID)
        ]
    }

    static func parseHandshake(
        _ line: String,
        legacyStartedAt: @autoclosure () -> Date = Date()
    ) -> Handshake? {
        let value = line.trimmingCharacters(in: .newlines)

        // 兼容已经由 LaunchServices 缓存或残留运行的旧版 Helper。
        // 旧版只写入 `READY`，如果主 App 仅接受带时间戳的新格式，录制会永久停在 starting，
        // 用户点击停止后也会把尚未确认成功的会话目录当作启动残片清理掉。
        if value == "READY" {
            return .ready(startedAt: legacyStartedAt())
        }

        let readyComponents = value.split(separator: "\t", omittingEmptySubsequences: false)
        if readyComponents.count == 2,
            readyComponents[0] == "READY",
            let milliseconds = Int64(readyComponents[1]) {
            return .ready(
                startedAt: Date(timeIntervalSince1970: TimeInterval(milliseconds) / 1_000)
            )
        }

        let components = value.split(separator: "\t", maxSplits: 2, omittingEmptySubsequences: false)
        guard
            components.count == 3,
            components[0] == "ERROR",
            let code = RecordingAudioHelperErrorCode(rawValue: String(components[1]))
        else {
            return nil
        }
        return .error(code: code, message: String(components[2]))
    }
}

// MARK: - 主进程录音控制器

enum RecordingAudioProcessError: LocalizedError {
    case executableUnavailable
    case invalidHandshake
    case handshakeTimedOut
    case helperFailed(code: RecordingAudioHelperErrorCode, message: String)
    case helperExited

    var errorDescription: String? {
        switch self {
        case .executableUnavailable:
            "找不到独立麦克风录音 Helper"
        case .invalidHandshake:
            "录音 Helper 启动响应无效"
        case .handshakeTimedOut:
            "录音 Helper 启动超时"
        case let .helperFailed(_, message):
            message
        case .helperExited:
            "录音 Helper 异常退出"
        }
    }
}

/// 主 App 只负责启动和停止独立 Helper，自身不链接任何麦克风采集逻辑。
///
/// 必须通过 LaunchServices 启动 Helper，不能使用 `Process` 创建子进程。
/// macOS 会把子进程的隐私权限归因到父 App，即使子进程拥有不同 Bundle ID；
/// LaunchServices 启动的独立 App 才会以 AudioHelper 自己的身份申请和持有麦克风权限。
final class RecordingAudioProcess {
    private let application: NSRunningApplication
    private let controlDirectoryURL: URL
    private let onUnexpectedTermination: @Sendable (Error) -> Void

    private var isStopping = false
    private var terminationMonitor: Task<Void, Never>?

    private init(
        application: NSRunningApplication,
        controlDirectoryURL: URL,
        onUnexpectedTermination: @escaping @Sendable (Error) -> Void
    ) {
        self.application = application
        self.controlDirectoryURL = controlDirectoryURL
        self.onUnexpectedTermination = onUnexpectedTermination
    }

    static func start(
        outputURL: URL,
        onLaunched: (RecordingAudioProcess) -> Void,
        onUnexpectedTermination: @escaping @Sendable (Error) -> Void
    ) async throws -> (process: RecordingAudioProcess, startedAt: Date) {
        let helperApplicationURL = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Helpers/ScreenPresenterAudioHelper.app")
        let helperExecutableURL = helperApplicationURL
            .appendingPathComponent("Contents/MacOS/ScreenPresenterAudioHelper")
        guard FileManager.default.isExecutableFile(atPath: helperExecutableURL.path) else {
            throw RecordingAudioProcessError.executableUnavailable
        }

        let controlDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScreenPresenterAudioHelper", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: controlDirectoryURL,
            withIntermediateDirectories: true
        )

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.arguments = RecordingAudioProcessProtocol.helperArguments(
            outputURL: outputURL,
            controlDirectoryURL: controlDirectoryURL,
            ownerPID: ProcessInfo.processInfo.processIdentifier
        )
        configuration.activates = false
        configuration.addsToRecentItems = false
        configuration.createsNewApplicationInstance = true

        let application: NSRunningApplication
        do {
            application = try await openApplication(
                at: helperApplicationURL,
                configuration: configuration
            )
        } catch {
            try? FileManager.default.removeItem(at: controlDirectoryURL)
            throw error
        }

        let controller = RecordingAudioProcess(
            application: application,
            controlDirectoryURL: controlDirectoryURL,
            onUnexpectedTermination: onUnexpectedTermination
        )
        onLaunched(controller)

        switch try await controller.waitForHandshake() {
        case let .ready(startedAt):
            controller.startTerminationMonitoring()
            return (controller, startedAt)
        case let .error(code, message):
            controller.cancel()
            throw RecordingAudioProcessError.helperFailed(code: code, message: message)
        case nil:
            controller.cancel()
            throw RecordingAudioProcessError.invalidHandshake
        }
    }

    func stop() async {
        guard !isStopping else { return }
        isStopping = true
        terminationMonitor?.cancel()
        terminationMonitor = nil

        let stopURL = controlDirectoryURL.appendingPathComponent(
            RecordingAudioProcessProtocol.stopFileName
        )
        do {
            try Data().write(to: stopURL, options: .atomic)
        } catch {
            _ = application.terminate()
        }

        // 正常情况下 Helper 会在完成 M4A 收尾后自行退出。设置超时仅用于防止异常状态
        // 永久阻塞主 App；超时后先请求退出，仍无响应才强制终止。
        if !(await waitUntilTerminated(maxAttempts: 100)) {
            _ = application.terminate()
            if !(await waitUntilTerminated(maxAttempts: 20)) {
                _ = application.forceTerminate()
                _ = await waitUntilTerminated(maxAttempts: 20)
            }
        }

        cleanupControlDirectory()
    }

    func cancel() {
        isStopping = true
        terminationMonitor?.cancel()
        terminationMonitor = nil
        if !application.isTerminated {
            _ = application.forceTerminate()
        }
        cleanupControlDirectory()
    }

    private static func openApplication(
        at applicationURL: URL,
        configuration: NSWorkspace.OpenConfiguration
    ) async throws -> NSRunningApplication {
        try await withCheckedThrowingContinuation { continuation in
            NSWorkspace.shared.openApplication(
                at: applicationURL,
                configuration: configuration
            ) { application, error in
                if let application {
                    continuation.resume(returning: application)
                } else {
                    continuation.resume(
                        throwing: error ?? RecordingAudioProcessError.executableUnavailable
                    )
                }
            }
        }
    }

    private func waitForHandshake() async throws -> RecordingAudioProcessProtocol.Handshake? {
        let readyURL = controlDirectoryURL.appendingPathComponent(
            RecordingAudioProcessProtocol.readyFileName
        )
        let errorURL = controlDirectoryURL.appendingPathComponent(
            RecordingAudioProcessProtocol.errorFileName
        )
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(10))

        while !Task.isCancelled {
            if let handshake = readHandshake(readyURL: readyURL, errorURL: errorURL) {
                return handshake
            }

            // Helper 写入 ERROR 后会立即退出。必须在观察到进程终止后再读取一次，
            // 否则可能把 permissionDenied/noDevice 错报为 invalidHandshake。
            guard !application.isTerminated else {
                return readHandshake(readyURL: readyURL, errorURL: errorURL)
            }
            guard clock.now < deadline else {
                cancel()
                throw RecordingAudioProcessError.handshakeTimedOut
            }

            do {
                try await Task.sleep(nanoseconds: 100_000_000)
            } catch {
                return readHandshake(readyURL: readyURL, errorURL: errorURL)
            }
        }
        return readHandshake(readyURL: readyURL, errorURL: errorURL)
    }

    private func readHandshake(readyURL: URL, errorURL: URL) -> RecordingAudioProcessProtocol.Handshake? {
        for url in [readyURL, errorURL] {
            guard let data = try? Data(contentsOf: url),
                  let value = String(data: data, encoding: .utf8),
                  let handshake = RecordingAudioProcessProtocol.parseHandshake(value) else {
                continue
            }
            return handshake
        }
        return nil
    }

    private func startTerminationMonitoring() {
        terminationMonitor = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled, !application.isTerminated {
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
            guard !Task.isCancelled, !isStopping else { return }
            onUnexpectedTermination(RecordingAudioProcessError.helperExited)
        }
    }

    private func waitUntilTerminated(maxAttempts: Int) async -> Bool {
        for _ in 0..<maxAttempts {
            if application.isTerminated {
                return true
            }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        return application.isTerminated
    }

    private func cleanupControlDirectory() {
        try? FileManager.default.removeItem(at: controlDirectoryURL)
    }
}
