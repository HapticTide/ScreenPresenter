//
//  IOSDeviceSource.swift
//  ScreenPresenter
//
//  Created by Sun on 2025/12/24.
//
//  iOS 设备源
//  使用 CoreMediaIO + AVFoundation 捕获 USB 连接的 iPhone/iPad 屏幕
//  这是 QuickTime 同款路径，稳定可靠
//

@preconcurrency import AVFoundation
import Combine
import CoreMedia
import CoreVideo
import Foundation
import os.lock

// MARK: - iOS 设备源

final class IOSDeviceSource: BaseDeviceSource, @unchecked Sendable {
    // MARK: - 属性

    /// 关联的 iOS 设备
    let iosDevice: IOSDevice

    /// 是否支持音频
    override var supportsAudio: Bool { true }

    /// 最新的 CVPixelBuffer（仅用于获取尺寸信息，不长期持有）
    override var latestPixelBuffer: CVPixelBuffer? { nil }

    // MARK: - 私有属性

    private var captureSession: AVCaptureSession?
    private var videoOutput: AVCaptureVideoDataOutput?
    private var audioOutput: AVCaptureAudioDataOutput?
    private let captureQueue = DispatchQueue(label: "com.screenPresenter.ios.capture", qos: .userInteractive)
    /// 注意：从 .userInteractive 降级为 .default，音频有缓冲可以稍微延迟
    private let audioQueue = DispatchQueue(label: "com.screenPresenter.ios.audio", qos: .default)

    /// 视频输出代理
    private var videoDelegate: VideoCaptureDelegate?

    /// 音频输出代理
    private var audioDelegate: AudioCaptureDelegate?

    /// 音频播放器
    private var audioPlayer: AudioPlayer?

    /// 是否正在捕获（使用线程安全的原子操作）
    private let capturingLock = OSAllocatedUnfairLock(initialState: false)

    /// 帧回调
    var onFrame: ((CVPixelBuffer) -> Void)?

    // MARK: - 帧背压保护

    /// 待处理帧计数（原子操作）
    private var pendingFrameCount: Int32 = 0

    /// 最大待处理帧数（超过此值将丢弃帧）
    private let maxPendingFrames: Int32 = 4

    /// 已丢弃帧计数
    private var droppedFrameCount: Int = 0

    /// 上次丢帧警告时间
    private var lastDropWarningTime: CFAbsoluteTime = 0

    // MARK: - 会话健康检查

    /// 会话启动时间（用于检测长时间运行）
    private var sessionStartTime: Date?

    /// 会话健康检查定时器
    private var sessionHealthTimer: Timer?

    /// 最大会话持续时间（15 分钟后建议重建）
    private let maxSessionDuration: TimeInterval = 15 * 60

    /// 自适应帧率更新定时器
    private var adaptiveFPSTimer: Timer?

    // MARK: - 音频控制

    /// 是否启用音频（从偏好设置读取）
    var isAudioEnabled: Bool {
        get { UserPreferences.shared.iosAudioEnabled }
        set {
            UserPreferences.shared.iosAudioEnabled = newValue
            updateAudioPlayback()
        }
    }

    /// 音量 (0.0 - 1.0)
    var audioVolume: Float {
        get { UserPreferences.shared.iosAudioVolume }
        set {
            UserPreferences.shared.iosAudioVolume = newValue
            audioPlayer?.volume = newValue
        }
    }

    // MARK: - 初始化

    init(device: IOSDevice) {
        iosDevice = device

        let deviceInfo = GenericDeviceInfo(
            id: device.id,
            name: device.name,
            model: device.modelID,
            platform: .ios
        )

        super.init(
            displayName: device.name,
            sourceType: .quicktime
        )

        self.deviceInfo = deviceInfo

        AppLogger.device.info("创建 iOS 设备源: \(device.name)")
    }

    // MARK: - DeviceSource 实现

    override func connect() async throws {
        guard state == .idle || state == .disconnected else {
            AppLogger.connection.warning("iOS 设备已连接或正在连接中")
            return
        }

        updateState(.connecting)
        AppLogger.connection.info("开始连接 iOS 设备: \(iosDevice.name)")

        do {
            // 1. 确保 CoreMediaIO 已启用屏幕捕获设备（使用全局单例）
            if !IOSScreenMirrorActivator.shared.isDALEnabled {
                IOSScreenMirrorActivator.shared.enableDALDevices()
            }

            // 2. 创建捕获会话
            try await setupCaptureSession()

            updateState(.connected)
            AppLogger.connection.info("iOS 设备已连接: \(iosDevice.name)")
        } catch {
            let deviceError = DeviceSourceError.connectionFailed(error.localizedDescription)
            updateState(.error(deviceError))
            throw deviceError
        }
    }

    override func disconnect() async {
        AppLogger.connection.info("断开 iOS 设备: \(iosDevice.name)")

        await stopCapture()

        // 移除通知监听
        NotificationCenter.default.removeObserver(self)

        // 清理音频
        audioPlayer?.stop()
        audioPlayer = nil

        captureSession?.stopRunning()
        captureSession = nil
        videoOutput = nil
        audioOutput = nil
        videoDelegate = nil
        audioDelegate = nil
        onFrame = nil

        lastCaptureSize = .zero

        updateState(.disconnected)
    }

    override func startCapture() async throws {
        guard state == .connected || state == .paused else {
            throw DeviceSourceError.captureStartFailed(L10n.capture.deviceNotConnected)
        }

        guard let session = captureSession else {
            throw DeviceSourceError.captureStartFailed(L10n.capture.sessionNotInitialized)
        }

        AppLogger.capture.info("开始捕获 iOS 设备: \(iosDevice.name)")

        // ⚠️ 重要：在启动会话之前设置标志，避免竞态条件
        capturingLock.withLock { $0 = true }
        lastCaptureSize = .zero // 重置尺寸以便重新检测

        // 在后台线程启动会话
        await withCheckedContinuation { continuation in
            captureQueue.async { [weak self] in
                guard let self else {
                    continuation.resume()
                    return
                }

                if !session.isRunning {
                    session.startRunning()
                }

                DispatchQueue.main.async {
                    self.updateState(.capturing)

                    // 启动会话健康检查
                    self.startSessionHealthCheck()

                    // 启动自适应帧率更新
                    self.startAdaptiveFPSUpdate()

                    continuation.resume()
                }
            }
        }

        AppLogger.capture.info("iOS 捕获已启动: \(iosDevice.name)")
    }

    override func stopCapture() async {
        // 停止健康检查定时器
        stopSessionHealthCheck()

        // 停止自适应帧率更新
        stopAdaptiveFPSUpdate()

        let wasCapturing = capturingLock.withLock { current -> Bool in
            let was = current
            current = false
            return was
        }
        guard wasCapturing else { return }

        await withCheckedContinuation { continuation in
            captureQueue.async { [weak self] in
                self?.captureSession?.stopRunning()

                DispatchQueue.main.async {
                    if self?.state == .capturing {
                        self?.updateState(.connected)
                    }
                    continuation.resume()
                }
            }
        }

        AppLogger.capture.info("iOS 捕获已停止: \(iosDevice.name)")
    }

    // MARK: - 捕获会话设置

    private func setupCaptureSession() async throws {
        AppLogger.capture.info("开始配置捕获会话，设备ID: \(iosDevice.id), avUniqueID: \(iosDevice.avUniqueID)")

        // 获取 AVCaptureDevice（使用 avUniqueID）
        guard let captureDevice = iosDevice.getAVCaptureDevice() else {
            AppLogger.capture.error("无法获取捕获设备: \(iosDevice.avUniqueID)")
            throw DeviceSourceError.connectionFailed(L10n.capture.cannotGetDevice(iosDevice.id))
        }

        AppLogger.capture.info("找到捕获设备: \(captureDevice.localizedName), 模型: \(captureDevice.modelID)")

        // 检测设备是否被其他应用占用（如 QuickTime）
        if captureDevice.isInUseByAnotherApplication {
            AppLogger.capture.warning("设备被其他应用占用: \(captureDevice.localizedName)")
            throw DeviceSourceError.deviceInUse("QuickTime")
        }

        let session = AVCaptureSession()
        session.sessionPreset = .high

        // 配置捕获帧率
        configureFrameRate(for: captureDevice)

        // 添加视频输入
        do {
            let videoInput = try AVCaptureDeviceInput(device: captureDevice)
            guard session.canAddInput(videoInput) else {
                AppLogger.capture.error("无法添加视频输入到会话")
                throw DeviceSourceError.connectionFailed(L10n.capture.cannotAddInput)
            }
            session.addInput(videoInput)
            AppLogger.capture.info("视频输入已添加")
        } catch {
            AppLogger.capture.error("创建视频输入失败: \(error.localizedDescription)")

            // 检测常见错误并提供更有用的提示
            let errorMessage = error.localizedDescription
            if errorMessage.contains("无法使用") || errorMessage.contains("Cannot use") {
                // "无法使用 XXX" 通常是因为 iPhone 未解锁或未信任
                throw DeviceSourceError.connectionFailed(L10n.capture.deviceNotReady(iosDevice.name))
            } else {
                throw DeviceSourceError.connectionFailed(L10n.capture.inputFailed(errorMessage))
            }
        }

        // 添加视频输出
        let videoOutput = AVCaptureVideoDataOutput()
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        ]
        videoOutput.alwaysDiscardsLateVideoFrames = true

        // 创建视频代理
        let delegate = VideoCaptureDelegate { [weak self] sampleBuffer in
            self?.handleVideoSampleBuffer(sampleBuffer)
        }
        videoOutput.setSampleBufferDelegate(delegate, queue: captureQueue)
        AppLogger.capture.info("✅ 视频代理已设置到输出")

        guard session.canAddOutput(videoOutput) else {
            AppLogger.capture.error("❌ 无法添加视频输出到会话")
            throw DeviceSourceError.connectionFailed(L10n.capture.cannotAddOutput)
        }
        session.addOutput(videoOutput)
        AppLogger.capture.info("✅ 视频输出已添加到会话")

        // 添加音频输入和输出
        setupAudioCapture(for: session, videoDevice: captureDevice)

        captureSession = session
        self.videoOutput = videoOutput
        videoDelegate = delegate

        AppLogger.capture.info("iOS 捕获会话已配置: \(iosDevice.name)")
    }

    // MARK: - 音频捕获设置

    /// 设置音频捕获
    /// iOS 设备通过 CoreMediaIO 暴露时，通常是 muxed 类型（同时包含视频和音频）
    ///
    /// 注意：由于 iOS 系统限制，当设备被用于屏幕投射时，音频会被系统"占用"
    /// 即使不添加音频输出，iPhone 也会静音。因此我们始终捕获音频，
    /// 通过 isAudioEnabled 控制是否在 Mac 上播放。
    private func setupAudioCapture(for session: AVCaptureSession, videoDevice: AVCaptureDevice) {
        // iOS 设备通过 CoreMediaIO 暴露时，通常是 muxed 类型（同时包含视频和音频）
        // 检查是否支持 muxed 或 audio
        let supportsMuxed = videoDevice.hasMediaType(.muxed)
        let supportsAudio = videoDevice.hasMediaType(.audio)

        AppLogger.capture.info("[Audio] 设备音频支持: muxed=\(supportsMuxed), audio=\(supportsAudio)")

        guard supportsMuxed || supportsAudio else {
            AppLogger.capture.info("[Audio] 设备不支持音频捕获")
            return
        }

        // 直接添加音频输出到会话
        // 对于 muxed 设备，音频和视频共享同一个输入，但可以有独立的输出
        let audioOutput = AVCaptureAudioDataOutput()
        let audioDelegate = AudioCaptureDelegate { [weak self] sampleBuffer in
            self?.handleAudioSampleBuffer(sampleBuffer)
        }
        audioOutput.setSampleBufferDelegate(audioDelegate, queue: audioQueue)

        guard session.canAddOutput(audioOutput) else {
            AppLogger.capture.warning("[Audio] 无法添加音频输出到会话")
            return
        }

        session.addOutput(audioOutput)
        self.audioOutput = audioOutput
        self.audioDelegate = audioDelegate

        // 创建音频播放器
        audioPlayer = AudioPlayer()
        audioPlayer?.volume = audioVolume
        audioPlayer?.isMuted = !isAudioEnabled

        AppLogger.capture.info("[Audio] ✅ 音频捕获已启用, 播放状态: \(isAudioEnabled ? "开启" : "静音")")
    }

    // MARK: - 音频处理

    /// 音频采样计数（用于日志）
    private var audioSampleCount = 0

    /// 处理音频采样缓冲
    private func handleAudioSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        // 检查捕获状态
        let isCapturing = capturingLock.withLock { $0 }
        guard isCapturing, isAudioEnabled else { return }

        // 使用 autoreleasepool 避免内存累积
        autoreleasepool {
            audioPlayer?.processSampleBuffer(sampleBuffer)
        }
    }

    /// 更新音频播放状态
    private func updateAudioPlayback() {
        audioPlayer?.isMuted = !isAudioEnabled
    }

    // MARK: - 帧处理

    /// 上一次的捕获尺寸（用于检测旋转）
    private var lastCaptureSize: CGSize = .zero

    private func handleVideoSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        // 检查捕获状态（使用线程安全的原子读取）
        let isCapturing = capturingLock.withLock { $0 }
        guard isCapturing else { return }

        // 帧背压检测：如果待处理帧过多，丢弃当前帧
        let currentPending = OSAtomicIncrement32(&pendingFrameCount)

        if currentPending > maxPendingFrames {
            // 帧积压过多，丢弃当前帧以防止内存和资源耗尽
            OSAtomicDecrement32(&pendingFrameCount)
            droppedFrameCount += 1

            // 每 5 秒最多输出一次警告，避免日志刷屏
            let now = CFAbsoluteTimeGetCurrent()
            if now - lastDropWarningTime >= 5.0 {
                AppLogger.capture.warning("[iOS] 帧背压过高，已丢弃 \(droppedFrameCount) 帧，当前积压: \(currentPending)")
                lastDropWarningTime = now
            }
            return
        }

        // 使用 defer 确保帧处理完成后减少计数
        defer { OSAtomicDecrement32(&pendingFrameCount) }

        // 获取 CVPixelBuffer
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }

        // 获取当前帧尺寸
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let currentSize = CGSize(width: CGFloat(width), height: CGFloat(height))

        // 检测尺寸变化（包括旋转）
        if currentSize != lastCaptureSize {
            let wasLandscape = lastCaptureSize.width > lastCaptureSize.height
            let isLandscape = currentSize.width > currentSize.height

            if lastCaptureSize != .zero, wasLandscape != isLandscape {
                AppLogger.capture.info("[iOS 旋转] 检测到方向变化: \(wasLandscape ? "横屏" : "竖屏") → \(isLandscape ? "横屏" : "竖屏")")
            }

            lastCaptureSize = currentSize
            updateCaptureSize(currentSize)
            AppLogger.capture.info("iOS 捕获分辨率: \(width)x\(height)")
        }

        // 创建 CapturedFrame 并发送
        let frame = CapturedFrame(sourceID: id, sampleBuffer: sampleBuffer)
        emitFrame(frame)

        // 直接回调通知渲染视图
        onFrame?(pixelBuffer)
    }

    // MARK: - 帧率配置

    /// 配置设备帧率
    /// - Parameter device: AVCaptureDevice 实例
    private func configureFrameRate(for device: AVCaptureDevice) {
        let targetFps = UserPreferences.shared.captureFrameRate
        let targetDuration = CMTime(value: 1, timescale: CMTimeScale(targetFps))

        // 查找支持目标帧率的格式
        // iOS 设备通过 CoreMediaIO 暴露时，格式支持可能有限
        // 我们尝试设置帧率，如果失败则使用默认值
        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }

            // 检查当前格式是否支持目标帧率
            let format = device.activeFormat
            var bestFrameRateRange: AVFrameRateRange?

            for range in format.videoSupportedFrameRateRanges {
                // 检查目标帧率是否在支持范围内
                if range.minFrameRate <= Double(targetFps) && Double(targetFps) <= range.maxFrameRate {
                    bestFrameRateRange = range
                    break
                }

                // 否则找到最接近的范围
                if bestFrameRateRange == nil || range.maxFrameRate > bestFrameRateRange!.maxFrameRate {
                    bestFrameRateRange = range
                }
            }

            if let range = bestFrameRateRange {
                // 目标帧率在支持范围内，直接设置
                if range.minFrameRate <= Double(targetFps), Double(targetFps) <= range.maxFrameRate {
                    device.activeVideoMinFrameDuration = targetDuration
                    device.activeVideoMaxFrameDuration = targetDuration
                    AppLogger.capture.info("iOS 帧率已配置: \(targetFps) fps")
                } else {
                    // 目标帧率超出支持范围，使用最大支持帧率
                    let maxSupportedFps = Int(range.maxFrameRate)
                    let actualDuration = CMTime(value: 1, timescale: CMTimeScale(maxSupportedFps))
                    device.activeVideoMinFrameDuration = actualDuration
                    device.activeVideoMaxFrameDuration = actualDuration
                    AppLogger.capture.info("iOS 帧率已配置: \(maxSupportedFps) fps（目标 \(targetFps) fps 不支持）")
                }
            } else {
                AppLogger.capture.warning("无法获取帧率支持范围，使用设备默认帧率")
            }
        } catch {
            AppLogger.capture.warning("无法配置 iOS 帧率: \(error.localizedDescription)")
        }
    }

    // MARK: - 会话健康检查

    /// 启动会话健康检查
    private func startSessionHealthCheck() {
        sessionStartTime = Date()

        // 停止已有的定时器
        sessionHealthTimer?.invalidate()

        // 每 60 秒检查一次会话健康状态
        sessionHealthTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.checkSessionHealth()
        }

        AppLogger.capture.info("[SessionHealth] 会话健康检查已启动")
    }

    /// 停止会话健康检查
    private func stopSessionHealthCheck() {
        sessionHealthTimer?.invalidate()
        sessionHealthTimer = nil
        sessionStartTime = nil
    }

    /// 检查会话健康状态
    private func checkSessionHealth() {
        guard let startTime = sessionStartTime else { return }

        let duration = Date().timeIntervalSince(startTime)
        let durationMinutes = Int(duration / 60)

        // 超过最大持续时间，发送警告
        if duration > maxSessionDuration {
            AppLogger.capture.warning("[SessionHealth] 会话已运行 \(durationMinutes) 分钟，建议重建以避免潜在问题")

            // 发送通知，由上层决定是否重建
            NotificationCenter.default.post(
                name: .iosSessionNeedsRebuild,
                object: self,
                userInfo: [
                    "deviceName": iosDevice.name,
                    "durationMinutes": durationMinutes,
                ]
            )
        } else {
            AppLogger.capture.debug("[SessionHealth] 会话健康，已运行 \(durationMinutes) 分钟")
        }
    }

    // MARK: - 自适应帧率（可选功能，默认禁用）

    /// 启动自适应帧率更新
    /// 注意：AdaptiveFrameRateController 默认禁用，此方法仅启动定时器
    /// 需要手动调用 AdaptiveFrameRateController.shared.enable() 才会生效
    private func startAdaptiveFPSUpdate() {
        // 停止已有的定时器
        adaptiveFPSTimer?.invalidate()

        // 每 5 秒更新一次自适应帧率（仅在启用时生效）
        adaptiveFPSTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            guard self != nil else { return }

            // 更新自适应帧率控制器（内部会检查是否启用）
            AdaptiveFrameRateController.shared.update()
        }

        // 注意：自适应帧率默认禁用，不输出启动日志避免混淆
    }

    /// 停止自适应帧率更新
    private func stopAdaptiveFPSUpdate() {
        adaptiveFPSTimer?.invalidate()
        adaptiveFPSTimer = nil

        // 重置自适应帧率控制器
        AdaptiveFrameRateController.shared.reset()
    }
}

// MARK: - 通知名称

extension Notification.Name {
    /// iOS 会话需要重建的通知
    /// UserInfo 包含：
    /// - deviceName: String - 设备名称
    /// - durationMinutes: Int - 已运行分钟数
    static let iosSessionNeedsRebuild = Notification.Name("com.screenPresenter.iosSessionNeedsRebuild")
}

// MARK: - 视频捕获代理

private final class VideoCaptureDelegate: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    private let handler: (CMSampleBuffer) -> Void

    init(handler: @escaping (CMSampleBuffer) -> Void) {
        self.handler = handler
        super.init()
    }

    func captureOutput(
        _: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from _: AVCaptureConnection
    ) {
        handler(sampleBuffer)
    }
}

// MARK: - 音频捕获代理

private final class AudioCaptureDelegate: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate {
    private let handler: (CMSampleBuffer) -> Void

    init(handler: @escaping (CMSampleBuffer) -> Void) {
        self.handler = handler
        super.init()
    }

    func captureOutput(
        _: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from _: AVCaptureConnection
    ) {
        handler(sampleBuffer)
    }
}
