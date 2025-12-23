//
//  DeviceSource.swift
//  ScreenPresenter
//
//  Created by Sun on 2025/12/22.
//
//  设备源协议
//  统一 iOS/Android 设备的捕获接口
//

import AppKit
import Combine
import CoreMedia
import CoreVideo
import Foundation

/// 设备平台
enum DevicePlatform: String {
    case ios = "iOS"
    case android = "Android"
}

// MARK: - 设备源类型

/// 设备源类型
enum DeviceSourceType: String, CaseIterable, Identifiable {
    case scrcpy // Android scrcpy 投屏
    case quicktime // iOS QuickTime 有线投屏

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .scrcpy: "scrcpy"
        case .quicktime: "QuickTime"
        }
    }

    var icon: String {
        switch self {
        case .scrcpy: "rectangle.portrait"
        case .quicktime: "iphone"
        }
    }

    var platform: DevicePlatform {
        switch self {
        case .scrcpy: .android
        case .quicktime: .ios
        }
    }
}

// MARK: - 设备源状态

/// 设备源状态
enum DeviceSourceState: Equatable {
    case idle // 空闲
    case connecting // 连接中
    case connected // 已连接
    case capturing // 捕获中
    case paused // 已暂停
    case error(DeviceSourceError) // 错误
    case disconnected // 已断开

    var isActive: Bool {
        switch self {
        case .connected, .capturing, .paused:
            true
        default:
            false
        }
    }

    var displayText: String {
        switch self {
        case .idle: L10n.device.idle
        case .connecting: L10n.device.connecting
        case .connected: L10n.device.connected
        case .capturing: L10n.device.capturing
        case .paused: L10n.device.paused
        case let .error(error): L10n.device.error(error.localizedDescription)
        case .disconnected: L10n.device.disconnected
        }
    }
}

/// 设备源错误
enum DeviceSourceError: Error, Equatable {
    case connectionFailed(String)
    case permissionDenied
    case windowNotFound
    case captureStartFailed(String)
    case processTerminated(Int32)
    case timeout
    case deviceInUse(String) // 设备被其他应用占用
    case unknown(String)

    var localizedDescription: String {
        switch self {
        case let .connectionFailed(reason):
            L10n.error.connectionFailed(reason)
        case .permissionDenied:
            L10n.error.permissionDenied
        case .windowNotFound:
            L10n.error.windowNotFound
        case let .captureStartFailed(reason):
            L10n.error.captureStartFailed(reason)
        case let .processTerminated(code):
            L10n.error.processTerminated(code)
        case .timeout:
            L10n.error.timeout
        case let .deviceInUse(app):
            L10n.ios.hint.occupied(app)
        case let .unknown(message):
            message
        }
    }
}

// MARK: - 设备信息

/// 设备信息协议
protocol DeviceInfo {
    var id: String { get }
    var name: String { get }
    var model: String? { get }
    var platform: DevicePlatform { get }
}

/// 通用设备信息结构
struct GenericDeviceInfo: DeviceInfo, Identifiable, Hashable {
    let id: String
    let name: String
    let model: String?
    let platform: DevicePlatform
    var additionalInfo: [String: String] = [:]

    init(id: String, name: String, model: String? = nil, platform: DevicePlatform) {
        self.id = id
        self.name = name
        self.model = model
        self.platform = platform
    }
}

// MARK: - 设备源协议

/// 设备源协议 - 所有设备捕获源的统一接口
protocol DeviceSource: AnyObject {
    // MARK: - 属性

    /// 唯一标识符
    var id: UUID { get }

    /// 显示名称
    var displayName: String { get }

    /// 设备源类型
    var sourceType: DeviceSourceType { get }

    /// 当前状态
    var state: DeviceSourceState { get }

    /// 关联的设备信息
    var deviceInfo: DeviceInfo? { get }

    /// 捕获尺寸
    var captureSize: CGSize { get }

    /// 当前帧率
    var frameRate: Double { get }

    /// 是否支持音频
    var supportsAudio: Bool { get }

    /// 最新的 CVPixelBuffer
    var latestPixelBuffer: CVPixelBuffer? { get }

    // MARK: - 连接控制

    /// 启动连接
    func connect() async throws

    /// 断开连接
    func disconnect() async

    /// 重新连接
    func reconnect() async throws

    // MARK: - 捕获控制

    /// 开始捕获
    func startCapture() async throws

    /// 停止捕获
    func stopCapture() async

    /// 暂停捕获
    func pauseCapture()

    /// 恢复捕获
    func resumeCapture()

    // MARK: - 帧数据

    /// 帧数据流
    var frameStream: AsyncStream<CapturedFrame> { get }

    /// 最新一帧图像
    var latestFrame: CapturedFrame? { get }
}

// MARK: - 设备源基类

/// 设备源基类 - 提供通用实现
class BaseDeviceSource: NSObject, DeviceSource {
    // MARK: - Properties

    private(set) var state: DeviceSourceState = .idle
    private(set) var captureSize: CGSize = .zero
    private(set) var frameRate: Double = 0
    private(set) var latestFrame: CapturedFrame?

    /// 最新的 CVPixelBuffer（子类需要维护）
    var latestPixelBuffer: CVPixelBuffer? { nil }

    // MARK: - Properties

    let id: UUID
    let displayName: String
    let sourceType: DeviceSourceType
    var deviceInfo: DeviceInfo?

    var supportsAudio: Bool { false }

    // MARK: - Frame Stream

    private var frameContinuation: AsyncStream<CapturedFrame>.Continuation?

    lazy var frameStream: AsyncStream<CapturedFrame> = AsyncStream { [weak self] continuation in
        self?.frameContinuation = continuation
    }

    // MARK: - Internal Properties

    var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    init(id: UUID = UUID(), displayName: String, sourceType: DeviceSourceType) {
        self.id = id
        self.displayName = displayName
        self.sourceType = sourceType

        AppLogger.device.info("创建设备源: \(displayName) (\(sourceType.rawValue))")
    }

    deinit {
        frameContinuation?.finish()
        AppLogger.device.info("销毁设备源: \(displayName)")
    }

    // MARK: - State Management

    func updateState(_ newState: DeviceSourceState) {
        let oldState = state
        state = newState
        AppLogger.device.info("设备源状态变更: \(oldState.displayText) -> \(newState.displayText)")
    }

    /// 更新捕获尺寸
    func updateCaptureSize(_ size: CGSize) {
        captureSize = size
    }

    // MARK: - Frame Handling

    func emitFrame(_ frame: CapturedFrame) {
        latestFrame = frame
        frameContinuation?.yield(frame)

        // 更新帧率统计
        updateFrameRateStatistics()
    }

    private var frameTimestamps: [CFAbsoluteTime] = []

    private func updateFrameRateStatistics() {
        let now = CFAbsoluteTimeGetCurrent()
        frameTimestamps.append(now)

        // 保留最近1秒的帧时间戳
        frameTimestamps = frameTimestamps.filter { now - $0 < 1.0 }

        // 计算帧率
        frameRate = Double(frameTimestamps.count)
    }

    // MARK: - Default Implementations (子类需要覆盖)

    func connect() async throws {
        fatalError("子类必须实现 connect()")
    }

    func disconnect() async {
        fatalError("子类必须实现 disconnect()")
    }

    func reconnect() async throws {
        await disconnect()
        try await connect()
    }

    func startCapture() async throws {
        fatalError("Subclass must implement startCapture()")
    }

    func stopCapture() async {
        fatalError("Subclass must implement stopCapture()")
    }

    func pauseCapture() {
        guard state == .capturing else { return }
        updateState(.paused)
        AppLogger.capture.info("捕获已暂停: \(displayName)")
    }

    func resumeCapture() {
        guard state == .paused else { return }
        updateState(.capturing)
        AppLogger.capture.info("捕获已恢复: \(displayName)")
    }
}
