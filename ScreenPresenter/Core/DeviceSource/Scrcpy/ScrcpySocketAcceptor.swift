//
//  ScrcpySocketAcceptor.swift
//  ScreenPresenter
//
//  Created by Sun on 2025/12/24.
//
//  Scrcpy Socket 接收器
//  使用 Network.framework 管理 TCP 连接
//

import Foundation
import Network

// MARK: - Socket 连接状态

/// Socket 连接状态
enum ScrcpySocketState {
    case idle
    case listening
    case connecting
    case connected
    case disconnected
    case error(Error)
}

// MARK: - Scrcpy Socket 接收器

/// Scrcpy Socket 接收器
/// 使用 Network.framework 管理 TCP 连接
/// 支持两种模式：
/// - reverse 模式：macOS 监听端口，等待 Android 设备连接
/// - forward 模式：macOS 主动连接到 adb forward 的端口
final class ScrcpySocketAcceptor {
    // MARK: - 属性

    /// 监听端口
    private let port: Int

    /// 连接模式
    private let connectionMode: ScrcpyConnectionMode

    /// NW Listener（reverse 模式使用）
    private var listener: NWListener?

    /// NW Connection（视频流连接）
    private var videoConnection: NWConnection?

    /// 连接队列
    private let queue = DispatchQueue(label: "com.screenPresenter.scrcpy.socket", qos: .userInteractive)

    /// 当前状态
    private(set) var state: ScrcpySocketState = .idle

    /// 已接收的连接数
    private var acceptedConnectionCount = 0

    /// 状态变更回调
    var onStateChange: ((ScrcpySocketState) -> Void)?

    /// 数据接收回调
    var onDataReceived: ((Data) -> Void)?

    // MARK: - 初始化

    /// 初始化接收器
    /// - Parameters:
    ///   - port: 监听/连接端口
    ///   - connectionMode: 连接模式
    init(port: Int, connectionMode: ScrcpyConnectionMode) {
        self.port = port
        self.connectionMode = connectionMode

        AppLogger.connection.info("[SocketAcceptor] 初始化，端口: \(port), 模式: \(connectionMode)")
    }

    deinit {
        stop()
    }

    // MARK: - 公开方法

    /// 启动连接
    /// reverse 模式：启动监听器等待连接
    /// forward 模式：主动连接到端口
    func start() async throws {
        AppLogger.connection.info("[SocketAcceptor] 启动连接，模式: \(connectionMode)")

        switch connectionMode {
        case .reverse:
            try await startListening()
        case .forward:
            try await connectToServer()
        }
    }

    /// 停止连接
    func stop() {
        AppLogger.connection.info("[SocketAcceptor] 停止连接")

        // 停止监听器
        listener?.cancel()
        listener = nil

        // 关闭连接
        videoConnection?.cancel()
        videoConnection = nil

        acceptedConnectionCount = 0
        updateState(.disconnected)
    }

    /// 等待视频连接建立
    /// - Parameter timeout: 超时时间（秒）
    func waitForVideoConnection(timeout: TimeInterval = 10) async throws {
        AppLogger.connection.info("[SocketAcceptor] 等待视频连接，模式: \(connectionMode), 端口: \(port), 超时: \(timeout)秒")

        let startTime = CFAbsoluteTimeGetCurrent()
        var lastLogTime = startTime

        while CFAbsoluteTimeGetCurrent() - startTime < timeout {
            if case .connected = state {
                let elapsed = CFAbsoluteTimeGetCurrent() - startTime
                AppLogger.connection.info("[SocketAcceptor] ✅ 视频连接已建立，耗时: \(String(format: "%.1f", elapsed))秒")
                return
            }

            if case let .error(error) = state {
                AppLogger.connection.error("[SocketAcceptor] ❌ 连接错误: \(error.localizedDescription)")
                throw error
            }

            // 每 2 秒输出一次等待日志
            let now = CFAbsoluteTimeGetCurrent()
            if now - lastLogTime >= 2 {
                let elapsed = now - startTime
                AppLogger.connection
                    .debug("[SocketAcceptor] 等待中... 已等待 \(String(format: "%.1f", elapsed))秒，当前状态: \(state)")
                lastLogTime = now
            }

            try await Task.sleep(nanoseconds: 100_000_000) // 100ms
        }

        let elapsed = CFAbsoluteTimeGetCurrent() - startTime
        AppLogger.connection.error("[SocketAcceptor] ❌ 连接超时！已等待 \(String(format: "%.1f", elapsed))秒，最终状态: \(state)")
        AppLogger.connection
            .error("[SocketAcceptor] 诊断信息 - 模式: \(connectionMode), 端口: \(port), 已接收连接数: \(acceptedConnectionCount)")
        throw ScrcpySocketError.connectionTimeout
    }

    // MARK: - 私有方法 - Reverse 模式

    /// 启动监听器（reverse 模式）
    private func startListening() async throws {
        AppLogger.connection.info("[SocketAcceptor] 启动 TCP 监听器，端口: \(port)")

        updateState(.listening)

        // 创建 TCP 参数
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true

        // 创建监听器
        guard let nwPort = NWEndpoint.Port(rawValue: UInt16(port)) else {
            throw ScrcpySocketError.invalidPort(port)
        }

        do {
            listener = try NWListener(using: parameters, on: nwPort)
        } catch {
            throw ScrcpySocketError.listenerCreationFailed(reason: error.localizedDescription)
        }

        // 设置状态处理
        listener?.stateUpdateHandler = { [weak self] state in
            self?.handleListenerState(state)
        }

        // 设置连接处理
        listener?.newConnectionHandler = { [weak self] connection in
            self?.handleNewConnection(connection)
        }

        // 启动监听
        listener?.start(queue: queue)

        AppLogger.connection.info("[SocketAcceptor] 监听器已启动")
    }

    /// 处理监听器状态变化
    private func handleListenerState(_ state: NWListener.State) {
        switch state {
        case .ready:
            AppLogger.connection.info("[SocketAcceptor] 监听器就绪")
        case let .failed(error):
            AppLogger.connection.error("[SocketAcceptor] 监听器失败: \(error.localizedDescription)")
            updateState(.error(ScrcpySocketError.listenerFailed(reason: error.localizedDescription)))
        case .cancelled:
            AppLogger.connection.info("[SocketAcceptor] 监听器已取消")
        default:
            break
        }
    }

    /// 处理新连接
    private func handleNewConnection(_ connection: NWConnection) {
        acceptedConnectionCount += 1

        // 第一个连接是视频流
        if acceptedConnectionCount == 1 {
            videoConnection = connection
            setupVideoConnection(connection)
        } else {
            // 后续连接（control/audio）忽略但需要接受以避免服务端阻塞
            AppLogger.connection.info("[SocketAcceptor] 忽略连接 #\(acceptedConnectionCount)（非视频流）")
            connection.cancel()
        }
    }

    // MARK: - 私有方法 - Forward 模式

    /// 连接到服务器（forward 模式）
    private func connectToServer() async throws {
        AppLogger.connection.info("[SocketAcceptor] 连接到 localhost:\(port)")

        updateState(.connecting)

        // 创建连接
        let host = NWEndpoint.Host("127.0.0.1")
        guard let nwPort = NWEndpoint.Port(rawValue: UInt16(port)) else {
            throw ScrcpySocketError.invalidPort(port)
        }

        let connection = NWConnection(host: host, port: nwPort, using: .tcp)
        videoConnection = connection

        // 使用 continuation 等待连接建立
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            // 使用 class 包装避免 Swift 6 并发警告
            final class ResumeGuard: @unchecked Sendable {
                var resumed = false
            }
            let guard_ = ResumeGuard()

            connection.stateUpdateHandler = { [weak self, guard_] state in
                guard !guard_.resumed else { return }

                switch state {
                case .ready:
                    guard_.resumed = true
                    self?.updateState(.connected)
                    AppLogger.connection.info("[SocketAcceptor] ✅ 连接已建立")
                    continuation.resume()

                case let .failed(error):
                    guard_.resumed = true
                    self?.updateState(.error(ScrcpySocketError.connectionFailed(reason: error.localizedDescription)))
                    AppLogger.connection.error("[SocketAcceptor] 连接失败: \(error.localizedDescription)")
                    continuation
                        .resume(throwing: ScrcpySocketError.connectionFailed(reason: error.localizedDescription))

                case .cancelled:
                    if !guard_.resumed {
                        guard_.resumed = true
                        continuation.resume(throwing: ScrcpySocketError.connectionCancelled)
                    }

                default:
                    break
                }
            }

            connection.start(queue: queue)
        }

        // 连接成功后开始接收数据
        startReceiving()
    }

    // MARK: - 视频连接处理

    /// 设置视频连接
    private func setupVideoConnection(_ connection: NWConnection) {
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                AppLogger.connection.info("[SocketAcceptor] ✅ 视频连接已就绪")
                self?.updateState(.connected)
                self?.startReceiving()

            case let .failed(error):
                AppLogger.connection.error("[SocketAcceptor] 视频连接失败: \(error.localizedDescription)")
                self?.updateState(.error(ScrcpySocketError.connectionFailed(reason: error.localizedDescription)))

            case .cancelled:
                AppLogger.connection.info("[SocketAcceptor] 视频连接已取消")
                self?.updateState(.disconnected)

            default:
                break
            }
        }

        connection.start(queue: queue)
    }

    /// 开始接收数据
    private func startReceiving() {
        guard let connection = videoConnection else { return }

        receiveData(on: connection)
    }

    /// 接收到的数据包计数（用于调试）
    private var receivedPacketCount = 0

    /// 递归接收数据
    private func receiveData(on connection: NWConnection) {
        connection
            .receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] content, _, isComplete, error in
                guard let self else { return }

                if let error {
                    AppLogger.connection.error("[SocketAcceptor] 接收数据错误: \(error.localizedDescription)")
                    updateState(.error(ScrcpySocketError.receiveError(reason: error.localizedDescription)))
                    return
                }

                if let data = content, !data.isEmpty {
                    onDataReceived?(data)
                }

                if isComplete {
                    updateState(.disconnected)
                    return
                }

                // 继续接收
                receiveData(on: connection)
            }
    }

    /// 更新状态
    private func updateState(_ newState: ScrcpySocketState) {
        state = newState
        DispatchQueue.main.async { [weak self] in
            self?.onStateChange?(newState)
        }
    }
}

// MARK: - Scrcpy Socket 错误

/// Scrcpy Socket 错误
enum ScrcpySocketError: LocalizedError {
    case invalidPort(Int)
    case listenerCreationFailed(reason: String)
    case listenerFailed(reason: String)
    case connectionFailed(reason: String)
    case connectionTimeout
    case connectionCancelled
    case receiveError(reason: String)

    var errorDescription: String? {
        switch self {
        case let .invalidPort(port):
            "无效端口: \(port)"
        case let .listenerCreationFailed(reason):
            "创建监听器失败: \(reason)"
        case let .listenerFailed(reason):
            "监听器错误: \(reason)"
        case let .connectionFailed(reason):
            "连接失败: \(reason)"
        case .connectionTimeout:
            "连接超时"
        case .connectionCancelled:
            "连接已取消"
        case let .receiveError(reason):
            "接收数据错误: \(reason)"
        }
    }
}
