//
//  ScrcpyDeviceSource.swift
//  ScreenPresenter
//
//  Created by Sun on 2025/12/22.
//
//  Scrcpy 设备源
//  通过 scrcpy-server 获取 Android 设备的 H.264/H.265 码流
//  使用 VideoToolbox 进行硬件解码
//

import AppKit
import Combine
import CoreMedia
import CoreVideo
import Foundation
import Network
import VideoToolbox

// MARK: - Scrcpy 配置

/// Scrcpy 启动配置
struct ScrcpyConfiguration {
    /// 设备序列号
    var serial: String

    /// 最大尺寸限制（0 表示不限制）
    var maxSize: Int = 0

    /// 比特率 (bps)
    var bitrate: Int = 8_000_000

    /// 最大帧率
    var maxFps: Int = 60

    /// 是否显示触摸点
    var showTouches: Bool = false

    /// 是否关闭设备屏幕
    var turnScreenOff: Bool = false

    /// 是否保持唤醒
    var stayAwake: Bool = true

    /// 是否启用音频（Android 11+ 支持）
    var audioEnabled: Bool = false

    /// 音频编解码器
    var audioCodec: AudioCodec = .opus

    /// 音频比特率 (bps)
    var audioBitRate: Int = 128_000

    /// 视频编解码器
    var videoCodec: VideoCodec = .h264

    /// 窗口标题（用于 scrcpy 窗口模式）
    var windowTitle: String?

    /// 窗口置顶
    var alwaysOnTop: Bool = false

    /// 录屏文件路径
    var recordPath: String?

    /// 录制格式
    var recordFormat: RecordFormat = .mp4

    /// 视频编解码器枚举
    enum VideoCodec: String {
        case h264
        case h265

        var fourCC: CMVideoCodecType {
            switch self {
            case .h264: kCMVideoCodecType_H264
            case .h265: kCMVideoCodecType_HEVC
            }
        }
    }

    /// 音频编解码器枚举
    enum AudioCodec: String {
        case opus
        case aac
        case flac
        case raw
    }

    /// 录制格式枚举
    enum RecordFormat: String {
        case mp4
        case mkv
    }

    /// 构建命令行参数（用于原始流输出）
    func buildRawStreamArguments() -> [String] {
        var args: [String] = []

        args.append("-s")
        args.append(serial)

        if maxSize > 0 {
            args.append("--max-size=\(maxSize)")
        }

        args.append("--video-bit-rate=\(bitrate)")
        args.append("--max-fps=\(maxFps)")
        args.append("--video-codec=\(videoCodec.rawValue)")

        // 关键：不显示窗口，输出原始流
        // 注意: scrcpy 3.0 起已移除 --no-display，使用 --no-playback 替代
        args.append("--no-playback")

        // 音频配置
        if audioEnabled {
            // 启用音频捕获（Android 11+ 支持）
            args.append("--audio-codec=\(audioCodec.rawValue)")
            args.append("--audio-bit-rate=\(audioBitRate)")
        } else {
            args.append("--no-audio")
        }

        args.append("--no-control")

        // 视频源为显示器
        args.append("--video-source=display")

        if stayAwake {
            args.append("--stay-awake")
        }

        return args
    }

    /// 构建命令行参数（用于窗口显示模式）
    func buildWindowArguments() -> [String] {
        var args: [String] = []

        args.append("-s")
        args.append(serial)

        if !audioEnabled {
            args.append("--no-audio")
        }
        if stayAwake {
            args.append("--stay-awake")
        }
        if turnScreenOff {
            args.append("--turn-screen-off")
        }
        if maxSize > 0 {
            args.append("--max-size=\(maxSize)")
        }
        if maxFps > 0 {
            args.append("--max-fps=\(maxFps)")
        }
        if bitrate > 0 {
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

// MARK: - Scrcpy 设备源

/// Scrcpy 设备源实现
/// 通过直接与 scrcpy-server 通信获取原始 H.264/H.265 码流并使用 VideoToolbox 解码
final class ScrcpyDeviceSource: BaseDeviceSource {
    // MARK: - 配置

    /// 配置（在初始化时设置）
    private let configuration: ScrcpyConfiguration
    private let toolchainManager: ToolchainManager

    // MARK: - 组件

    /// ADB 服务
    private var adbService: AndroidADBService?

    /// 服务器启动器
    private var serverLauncher: ScrcpyServerLauncher?

    /// Socket 接收器
    private var socketAcceptor: ScrcpySocketAcceptor?

    /// 视频流解析器
    private var streamParser: ScrcpyVideoStreamParser?

    /// VideoToolbox 解码器
    private var decoder: VideoToolboxDecoder?

    // MARK: - 音频组件

    /// 音频流解析器
    private var audioStreamParser: ScrcpyAudioStreamParser?

    /// AAC 音频解码器
    private var aacDecoder: ScrcpyAudioDecoder?

    /// OPUS 音频解码器
    private var opusDecoder: ScrcpyOpusDecoder?

    /// RAW PCM 音频解码器
    private var rawDecoder: ScrcpyRAWDecoder?

    /// 当前音频编解码器类型
    private var currentAudioCodecId: UInt32?

    /// 音频播放器
    private var audioPlayer: AudioPlayer?

    /// 音频同步器
    private var audioSynchronizer: AudioSynchronizer?

    /// 音频是否启用（从偏好设置读取，控制播放而非捕获）
    var audioEnabled: Bool {
        get { UserPreferences.shared.androidAudioEnabled }
        set {
            UserPreferences.shared.androidAudioEnabled = newValue
            audioPlayer?.isMuted = !newValue
        }
    }

    /// 音量 (0.0 - 1.0)
    var audioVolume: Float {
        get { UserPreferences.shared.androidAudioVolume }
        set {
            UserPreferences.shared.androidAudioVolume = newValue
            audioPlayer?.volume = newValue
        }
    }

    /// 是否静音（由 audioEnabled 自动控制）
    var audioMuted: Bool {
        get { !audioEnabled }
        set { audioEnabled = !newValue }
    }

    // MARK: - 状态

    /// 服务器进程
    private var serverProcess: Process?

    /// 监控任务
    private var monitorTask: Task<Void, Never>?

    /// 帧管道（参照 scrcpy trait 模式设计）
    /// 实现: 解码线程 → FramePipeline → 主线程渲染
    private let framePipeline = FramePipeline()

    /// 最新的 CVPixelBuffer 存储（兼容旧接口）
    private let latestPixelBufferLock = NSLock()
    private var latestPixelBufferStorage: CVPixelBuffer?

    /// 最新的 CVPixelBuffer（供渲染使用）
    override var latestPixelBuffer: CVPixelBuffer? {
        latestPixelBufferLock.lock()
        defer { latestPixelBufferLock.unlock() }
        return latestPixelBufferStorage
    }

    /// 捕获回调开关（避免 stop/cleanup 后仍处理解码回调）
    private let captureGateLock = NSLock()
    private var isCaptureActive = false

    /// 帧回调（通过 FramePipeline 分发，已实现事件合并）
    var onFrame: ((CVPixelBuffer) -> Void)? {
        didSet {
            // 将回调注册到帧管道
            if let callback = onFrame {
                framePipeline.setFrameHandler { [weak self] pixelBuffer in
                    // 更新最新帧引用（线程安全）
                    self?.setLatestPixelBuffer(pixelBuffer)
                    // 调用外部回调
                    callback(pixelBuffer)
                }
            } else {
                framePipeline.setFrameHandler { _ in }
            }
        }
    }

    /// 当前端口
    private var currentPort: Int

    /// 帧管道统计任务
    private var pipelineStatsTask: Task<Void, Never>?

    // MARK: - 初始化

    init(device: AndroidDevice, toolchainManager: ToolchainManager, configuration: ScrcpyConfiguration? = nil) {
        // 使用传入的配置或从用户偏好设置构建配置
        var config = configuration ?? UserPreferences.shared.buildScrcpyConfiguration(serial: device.serial)
        config.serial = device.serial
        self.configuration = config
        self.toolchainManager = toolchainManager

        // 从用户偏好读取端口范围起始值作为初始端口
        currentPort = UserPreferences.shared.scrcpyPortRangeStart

        super.init(
            displayName: device.displayName,
            sourceType: .scrcpy
        )

        // 设置设备信息
        deviceInfo = GenericDeviceInfo(
            id: device.serial,
            name: device.displayName,
            model: device.model,
            platform: .android
        )

        AppLogger.device.info("创建 Scrcpy 设备源: \(device.displayName)")
    }

    deinit {
        deactivateCaptureCallbacks()
        monitorTask?.cancel()
    }

    // MARK: - 连接

    override func connect() async throws {
        AppLogger.connection.info("准备连接 Android 设备: \(configuration.serial), 当前状态: \(state)")

        guard state == .idle || state == .disconnected else {
            AppLogger.connection.warning("设备已连接或正在连接中，当前状态: \(state)")
            return
        }

        updateState(.connecting)
        AppLogger.connection.info("开始连接 Android 设备: \(configuration.serial)")

        // 获取工具链路径
        let (adbPath, scrcpyServerPath) = await MainActor.run {
            (
                toolchainManager.adbPath,
                toolchainManager.scrcpyServerPath
            )
        }

        guard let serverPath = scrcpyServerPath else {
            let error = DeviceSourceError.connectionFailed("scrcpy-server 未找到")
            AppLogger.connection.error("连接失败: scrcpy-server 未找到")
            updateState(.error(error))
            throw error
        }

        // 创建 ADB 服务
        adbService = await MainActor.run {
            AndroidADBService(
                adbPath: adbPath,
                deviceSerial: configuration.serial
            )
        }

        // 创建视频流解析器（使用标准协议模式）
        streamParser = ScrcpyVideoStreamParser(codecType: configuration.videoCodec.fourCC, useRawStream: false)

        // 设置 SPS 变化回调（分辨率变化时重建解码器）
        streamParser?.onSPSChanged = { [weak self] _ in
            self?.handleSPSChanged()
        }

        // 创建 VideoToolbox 解码器
        decoder = VideoToolboxDecoder(codecType: configuration.videoCodec.fourCC)
        attachDecoderCallback()

        // 获取 scrcpy 版本
        let scrcpyVersion = getScrcpyVersion()

        // 创建服务器启动器
        guard let adbService else {
            updateState(.disconnected)
            AppLogger.connection.error("❌ 缺少 adbService，无法启动 scrcpy: \(displayName)")
            return
        }

        serverLauncher = ScrcpyServerLauncher(
            adbService: adbService,
            serverLocalPath: serverPath,
            port: currentPort,
            scrcpyVersion: scrcpyVersion
        )

        updateState(.connected)
        AppLogger.connection.info("✅ 设备连接成功: \(displayName), 状态: \(state)")
    }

    override func disconnect() async {
        AppLogger.connection.info("断开连接: \(displayName), 当前状态: \(state)")

        monitorTask?.cancel()
        monitorTask = nil

        // stopCapture 会处理所有清理工作
        await stopCapture()

        // 清理组件
        adbService = nil
        serverLauncher = nil
        socketAcceptor = nil
        streamParser = nil
        decoder = nil
        setLatestPixelBuffer(nil)

        updateState(.disconnected)
    }

    // MARK: - 捕获

    override func startCapture() async throws {
        AppLogger.capture.info("开始捕获 Android 设备: \(displayName), 状态: \(state)")

        guard state == .connected || state == .paused else {
            AppLogger.capture.error("无法开始捕获: 设备未连接，当前状态: \(state)")
            throw DeviceSourceError.captureStartFailed(L10n.capture.deviceNotConnected)
        }

        do {
            guard adbService != nil else {
                throw DeviceSourceError.captureStartFailed("ADB 服务未初始化")
            }

            // 重新挂载解码回调（stop/cleanup 会清空）
            attachDecoderCallback()

            // 0. 唤醒设备（如果息屏）
            await wakeUpDeviceIfNeeded()

            // 1. 查找可用端口（支持与其他 scrcpy 共存）
            try await findAvailablePort()

            // 2. 清理之前可能残留的 ADB 端口转发
            await cleanupADBForwarding()

            // 3. 创建/重建 launcher（使用新端口）
            // 因为端口可能已经改变，需要重新创建 launcher
            await recreateLauncherIfNeeded()

            guard let launcher = serverLauncher else {
                throw DeviceSourceError.captureStartFailed("服务器启动器未初始化")
            }

            AppLogger.capture
                .debug("[Scrcpy] 启动参数: 端口=\(currentPort), scid=\(launcher.scid), socketName=\(launcher.socketName)")

            // 4. 推送 scrcpy-server 并设置端口转发
            try await launcher.prepareEnvironment(configuration: configuration)

            // 5. 创建并启动 Socket 监听器/连接器（必须在服务端启动前！）
            socketAcceptor = ScrcpySocketAcceptor(
                port: currentPort,
                connectionMode: launcher.connectionMode,
                audioEnabled: configuration.audioEnabled
            )

            // 设置视频数据接收回调
            socketAcceptor?.onDataReceived = { [weak self] data in
                autoreleasepool {
                    self?.handleReceivedData(data)
                }
            }

            // 设置音频数据接收回调（如果启用）
            if configuration.audioEnabled {
                AppLogger.capture.debug("[Scrcpy] 音频已启用，设置音频组件")
                setupAudioComponents()
                socketAcceptor?.onAudioDataReceived = { [weak self] data in
                    autoreleasepool {
                        self?.handleReceivedAudioData(data)
                    }
                }
            }

            // 4. 启动监听/连接
            try await socketAcceptor?.start()

            // 5. 提前启动帧管道（必须在数据开始接收之前！）
            framePipeline.start(size: CGSize(width: 1080, height: 1920))

            // 6. 提前设置状态为 capturing
            updateState(.capturing)
            setCaptureActive(true)

            // 7. 启动 scrcpy-server
            serverProcess = try await launcher.startServer(configuration: configuration)

            // 8. 等待视频连接建立
            try await socketAcceptor?.waitForVideoConnection(timeout: 10)

            AppLogger.capture.info("捕获已启动: \(displayName)")

            // 启动进程监控
            startProcessMonitoring()

            // 启动帧管道统计任务
            startPipelineStats()

        } catch {
            // 捕获失败时清理资源
            await cleanupAfterError()

            // 转换为用户友好的错误
            let scrcpyError = ScrcpyErrorHelper.mapError(error, port: currentPort)
            let captureError = DeviceSourceError.captureStartFailed(scrcpyError.fullDescription)

            AppLogger.capture.error("[Scrcpy] 启动失败: \(scrcpyError.fullDescription)")

            // 重要：错误后恢复到 connected 状态，而不是 error 状态
            // 这样用户可以重新尝试，而不需要重启应用
            updateState(.connected)

            throw captureError
        }
    }

    /// 创建或重建 ScrcpyServerLauncher
    /// 当端口改变时需要重建，因为 launcher 的端口在初始化时就固定了
    private func recreateLauncherIfNeeded() async {
        guard let adbService else { return }

        // 获取 scrcpy-server 路径（需要在 MainActor 上访问）
        let serverPath = await MainActor.run { toolchainManager.scrcpyServerPath }

        guard let serverPath else {
            AppLogger.capture.error("[ScrcpyDeviceSource] 无法获取 scrcpy-server 路径")
            return
        }

        // 获取 scrcpy 版本
        let scrcpyVersion = getScrcpyVersion()

        // 检查是否需要重建（端口改变，或者 launcher 不存在）
        if serverLauncher == nil {
            AppLogger.capture.info("[ScrcpyDeviceSource] 创建 ScrcpyServerLauncher (端口: \(currentPort))")
        } else {
            AppLogger.capture.info("[ScrcpyDeviceSource] 重建 ScrcpyServerLauncher (新端口: \(currentPort))")
        }

        serverLauncher = ScrcpyServerLauncher(
            adbService: adbService,
            serverLocalPath: serverPath,
            port: currentPort,
            scrcpyVersion: scrcpyVersion
        )
    }

    /// 唤醒设备（如果息屏）
    /// 通过 ADB 发送电源键事件，模拟 scrcpy 的 power_on 行为
    private func wakeUpDeviceIfNeeded() async {
        guard let adbService else { return }

        AppLogger.capture.info("[ScrcpyDeviceSource] 检测设备屏幕状态...")

        do {
            // 检测屏幕是否亮起
            // dumpsys power 输出包含 "mWakefulness=Awake" (亮屏) 或 "mWakefulness=Asleep" (息屏)
            let result = try await adbService.shell("dumpsys power | grep mWakefulness")

            let isScreenOn = result.stdout.contains("Awake")

            if isScreenOn {
                AppLogger.capture.info("[ScrcpyDeviceSource] 设备屏幕已亮起")
                return
            }

            AppLogger.capture.info("[ScrcpyDeviceSource] 设备息屏，发送电源键唤醒...")

            // 发送电源键事件唤醒设备 (keyevent 26 = KEYCODE_POWER)
            _ = try await adbService.shell("input keyevent 26")

            // 等待设备实际响应（参考 scrcpy 的 500ms 延迟）
            try await Task.sleep(nanoseconds: 500_000_000)

            AppLogger.capture.info("[ScrcpyDeviceSource] 设备已唤醒")

        } catch {
            // 唤醒失败不应阻止捕获，只记录警告
            AppLogger.capture.warning("[ScrcpyDeviceSource] 检测/唤醒设备失败: \(error.localizedDescription)")
        }
    }

    /// 查找可用端口（支持与其他 scrcpy 实例共存）
    /// 仿照 scrcpy 的行为：从配置的起始端口开始，如果被占用则尝试下一个端口
    /// 端口范围由偏好设置控制，默认 27183 - 27199（与 scrcpy 官方一致）
    private func findAvailablePort() async throws {
        let portRange = UserPreferences.shared.scrcpyPortRange

        for port in portRange {
            let available = ScrcpyErrorHelper.isPortAvailable(port)
            if available {
                currentPort = port
                AppLogger.capture.debug("[Scrcpy] 使用端口 \(port)")
                return
            }
        }

        // 所有端口都被占用
        throw ScrcpyError.portInUse(port: portRange.lowerBound)
    }

    /// 清理 ADB 端口转发（移除可能残留的转发规则）
    private func cleanupADBForwarding() async {
        guard let adbService else { return }

        AppLogger.capture.info("[ScrcpyDeviceSource] 清理残留的 ADB 端口转发...")

        // 移除与当前端口相关的 forward 和 reverse
        await adbService.removeForward(tcpPort: currentPort)
        // reverse 需要 socketName，但此时 launcher 可能还没初始化
        // 所以我们只清理 forward，reverse 由 launcher 在 stop() 时清理
    }

    /// 错误后清理资源
    private func cleanupAfterError() async {
        AppLogger.capture.info("[ScrcpyDeviceSource] 错误后清理资源...")

        // 先停掉回调，避免清理过程中仍处理帧
        deactivateCaptureCallbacks()

        // 停止帧管道
        stopPipelineStats()
        framePipeline.stop()

        // 清理 socket
        socketAcceptor?.stop()
        socketAcceptor = nil

        // 停止 launcher（会清理端口转发）
        await serverLauncher?.stop()

        // 终止服务器进程
        if let process = serverProcess, process.isRunning {
            process.terminate()
        }
        serverProcess = nil

        // 清理音频组件
        cleanupAudioComponents()

        // 重置解析器和解码器
        streamParser?.reset()
        decoder?.reset()
    }

    /// 重置连接（供外部调用，用于从错误状态恢复）
    func resetConnection() async {
        AppLogger.capture.info("[ScrcpyDeviceSource] 重置连接...")

        // 1. 彻底清理所有资源
        await cleanupAfterError()

        // 2. 清理 ADB 转发
        await cleanupADBForwarding()

        // 3. 尝试释放端口
        _ = await ScrcpyErrorHelper.tryReleasePort(currentPort)

        // 4. 重置状态
        if state != .disconnected {
            updateState(.connected)
        }

        AppLogger.capture.info("[ScrcpyDeviceSource] 连接已重置，可以重新开始捕获")
    }

    override func stopCapture() async {
        AppLogger.capture.info("停止捕获: \(displayName)")

        // 先停掉回调，避免清理过程中仍处理帧
        deactivateCaptureCallbacks()

        // 0. 停止帧管道统计任务
        stopPipelineStats()

        // 0.5. 停止帧管道
        framePipeline.stop()

        // 1. 停止 Socket 接收器
        socketAcceptor?.stop()
        socketAcceptor = nil

        // 2. 停止服务器启动器
        await serverLauncher?.stop()

        // 3. 终止服务器进程
        if let process = serverProcess, process.isRunning {
            process.terminate()
            process.waitUntilExit()
        }
        serverProcess = nil

        // 4. 重置解析器
        streamParser?.reset()

        // 5. 重置解码器
        decoder?.reset()

        // 6. 重置帧管道（清空旧帧）
        framePipeline.stop()

        // 7. 停止音频组件
        cleanupAudioComponents()

        if state == .capturing {
            updateState(.connected)
        }

        AppLogger.capture.info("捕获已停止: \(displayName)")
    }

    override func pauseCapture() {
        super.pauseCapture()
        // 暂停时不再处理解码回调
        if state == .paused {
            setCaptureActive(false)
        }
    }

    override func resumeCapture() {
        super.resumeCapture()
        // 恢复时重新允许处理解码回调
        if state == .capturing {
            setCaptureActive(true)
        }
    }

    // MARK: - 数据处理

    /// 过滤掉的非 VCL NAL 计数（用于诊断）
    private var filteredNonVCLCount = 0

    /// 端到端延迟统计
    private var frameReceiveTime: CFAbsoluteTime = 0
    private var frameDecodeCompleteTime: CFAbsoluteTime = 0
    private var totalE2ELatency: Double = 0
    private var maxE2ELatency: Double = 0
    private var e2eLatencyCount: Int = 0
    private var lastE2EStatsTime = CFAbsoluteTimeGetCurrent()

    /// 处理接收到的数据
    private func handleReceivedData(_ data: Data) {
        // 记录数据接收时间
        frameReceiveTime = CFAbsoluteTimeGetCurrent()

        guard let parser = streamParser, let decoder else { return }

        // 解析 NAL 单元
        let nalUnits = parser.append(data)

        for nalUnit in nalUnits {
            // 如果是参数集且解码器未初始化，尝试初始化
            if nalUnit.isParameterSet, !decoder.isReady {
                if parser.hasCompleteParameterSets {
                    initializeDecoderIfNeeded()
                }
                continue
            }

            // 过滤非 VCL NAL 单元（SEI/AUD/filler 等）
            // 这些单元不包含实际视频数据，不应送入解码器
            guard nalUnit.isVCL else {
                filteredNonVCLCount += 1
                // 每 100 个非 VCL NAL 记录一次日志（避免日志过多）
                if filteredNonVCLCount % 100 == 1 {
                    AppLogger.capture.debug("[Scrcpy] 过滤非 VCL NAL (type=\(nalUnit.type))，累计过滤: \(filteredNonVCLCount)")
                }
                continue
            }

            // 解码 VCL NAL 单元（实际视频帧数据）
            if decoder.isReady {
                decoder.decode(nalUnit: nalUnit)
            }
        }
    }

    /// 初始化解码器（如果需要）
    private func initializeDecoderIfNeeded() {
        guard let parser = streamParser, let decoder else { return }
        guard !decoder.isReady else { return }
        guard parser.hasCompleteParameterSets else { return }

        initializeDecoder()
    }

    /// 初始化解码器
    private func initializeDecoder() {
        guard let parser = streamParser, let decoder else { return }
        guard parser.hasCompleteParameterSets else { return }

        // 获取实际的编解码类型（可能从协议元数据更新）
        let codecType = parser.currentCodecType

        do {
            if codecType == kCMVideoCodecType_H264 {
                guard let sps = parser.sps, let pps = parser.pps else { return }
                try decoder.initializeH264(sps: sps, pps: pps)
            } else {
                guard let vps = parser.vps, let sps = parser.sps, let pps = parser.pps else { return }
                try decoder.initializeH265(vps: vps, sps: sps, pps: pps)
            }
            decoder.activateCallbacks()
            AppLogger.capture.info("✅ 解码器初始化成功（可能是旋转后重建）")
        } catch {
            AppLogger.capture.error("解码器初始化失败: \(error.localizedDescription)")
        }
    }

    /// 处理 SPS 变化（分辨率变化）
    /// 注意：只标记需要重建解码器，不立即重建
    /// 因为新的 PPS 可能还没到达，需要等待完整参数集
    private func handleSPSChanged() {
        AppLogger.capture.info("⚠️ 检测到 SPS 变化（设备旋转），标记解码器需要重建...")

        // 重置解码器（这会导致 isReady = false）
        decoder?.reset()

        // 重置帧管道（清空旧帧，避免显示旧的旋转前内容）
        framePipeline.stop()
        // 立即重新启动（使用当前尺寸或默认尺寸）
        framePipeline.start(size: captureSize != .zero ? captureSize : CGSize(width: 1080, height: 1920))

        AppLogger.capture.info("[旋转] 解码器已重置，等待新的完整参数集...")

        // 不在这里调用 initializeDecoder()
        // 等待 handleReceivedData 中收到新的参数集后自动重新初始化
        // 因为设备旋转时，scrcpy 会重新发送完整的 config packet (SPS + PPS)
    }

    /// 处理解码后的帧
    /// 使用双帧缓冲设计（与 scrcpy frame_buffer.c 一致）
    private func handleDecodedFrame(_ pixelBuffer: CVPixelBuffer) {
        guard canHandleFrames() else { return }

        // 计算端到端延迟（从数据接收到解码完成）
        let decodeCompleteTime = CFAbsoluteTimeGetCurrent()
        let e2eLatency = (decodeCompleteTime - frameReceiveTime) * 1000 // 转换为毫秒

        totalE2ELatency += e2eLatency
        maxE2ELatency = max(maxE2ELatency, e2eLatency)
        e2eLatencyCount += 1

        // 每 5 秒重置统计（保留内部统计逻辑，移除日志输出）
        let now = CFAbsoluteTimeGetCurrent()
        let elapsed = now - lastE2EStatsTime
        if elapsed >= 5.0 {
            // 重置统计
            lastE2EStatsTime = now
            totalE2ELatency = 0
            maxE2ELatency = 0
            e2eLatencyCount = 0
        }

        // 更新最新帧（兼容旧接口）
        setLatestPixelBuffer(pixelBuffer)

        // 更新捕获尺寸（这会触发 UI 刷新，包括 bezel 更新）
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let newSize = CGSize(width: width, height: height)

        // 检测尺寸变化（可能是旋转导致）
        if captureSize != newSize {
            let wasLandscape = captureSize.width > captureSize.height
            let isLandscape = width > height
            if wasLandscape != isLandscape {
                AppLogger.capture.info("[旋转] 检测到方向变化: \(wasLandscape ? "横屏" : "竖屏") → \(isLandscape ? "横屏" : "竖屏")")
                AppLogger.capture.info("[旋转] 新尺寸: \(width) x \(height)")
            }
        }

        updateCaptureSize(newSize)

        // 创建 CapturedFrame
        let frame = CapturedFrame(
            pixelBuffer: pixelBuffer,
            presentationTime: CMTime(value: Int64(CACurrentMediaTime() * 1_000_000), timescale: 1_000_000),
            size: newSize
        )
        emitFrame(frame)

        // 使用 FramePipeline 分发帧到主线程
        // FramePipeline 实现了 scrcpy 的事件合并机制：
        // - 如果上一帧还未被渲染，不发送新的主线程事件
        // - 主线程消费时总是获取最新帧
        // 这避免了主线程任务堆积的问题
        framePipeline.pushFrame(pixelBuffer)
    }

    // MARK: - 回调与状态保护

    private func setLatestPixelBuffer(_ pixelBuffer: CVPixelBuffer?) {
        latestPixelBufferLock.lock()
        latestPixelBufferStorage = pixelBuffer
        latestPixelBufferLock.unlock()
    }

    private func setCaptureActive(_ active: Bool) {
        captureGateLock.lock()
        isCaptureActive = active
        captureGateLock.unlock()
    }

    private func canHandleFrames() -> Bool {
        captureGateLock.lock()
        let active = isCaptureActive
        captureGateLock.unlock()
        return active
    }

    private func attachDecoderCallback() {
        decoder?.activateCallbacks()
        decoder?.onDecodedFrame = { [weak self] pixelBuffer in
            self?.handleDecodedFrame(pixelBuffer)
        }
    }

    private func deactivateCaptureCallbacks() {
        setCaptureActive(false)
        decoder?.stopAndDrain(clearCallback: true)
        setLatestPixelBuffer(nil)
    }

    // MARK: - 辅助方法

    // MARK: - 常量

    /// 内置 scrcpy-server 版本号
    private static let bundledScrcpyServerVersion = "4.0"

    /// 获取 scrcpy 版本
    /// 直接返回内置 scrcpy-server 的版本号
    private func getScrcpyVersion() -> String {
        Self.bundledScrcpyServerVersion
    }

    /// 启动进程监控
    private func startProcessMonitoring() {
        monitorTask = Task { [weak self] in
            guard let self, let serverProcess else { return }

            // 等待进程退出
            await withCheckedContinuation { continuation in
                serverProcess.terminationHandler = { _ in
                    continuation.resume()
                }
            }

            let exitCode = serverProcess.terminationStatus

            await MainActor.run { [weak self] in
                guard let self else { return }

                // 退出码 0 表示正常退出，15 (SIGTERM) 表示被主动终止（也是正常情况）
                let isNormalExit = exitCode == 0 || exitCode == 15 // SIGTERM

                if !isNormalExit, state != .disconnected {
                    AppLogger.connection.error("scrcpy-server 进程异常退出，退出码: \(exitCode)")
                    updateState(.error(.processTerminated(exitCode)))
                } else {
                    AppLogger.connection.info("scrcpy-server 进程正常退出")
                    if state == .capturing {
                        updateState(.connected)
                    }
                }
            }
        }
    }

    // MARK: - 帧缓冲统计

    /// 启动帧管道统计任务（生产环境已禁用日志输出）
    private func startPipelineStats() {
        // 保留任务结构以便后续调试使用，但不再输出日志
        pipelineStatsTask = nil
    }

    /// 停止帧管道统计任务
    private func stopPipelineStats() {
        pipelineStatsTask?.cancel()
        pipelineStatsTask = nil
    }

    // MARK: - 音频处理

    /// 设置音频组件
    private func setupAudioComponents() {
        // 创建音频流解析器
        audioStreamParser = ScrcpyAudioStreamParser()

        // [调试测试 10b] 测试 regulator.push
        audioStreamParser?.onCodecIdParsed = { [weak self] codecId in
            guard let self else { return }

            let codecName: String
            switch codecId {
            case ScrcpyAudioStreamParser.codecIdOpus:
                codecName = "opus"
                // 创建 OPUS 解码器
                opusDecoder = ScrcpyOpusDecoder()
                opusDecoder?.initialize(codecId: codecId)
            case ScrcpyAudioStreamParser.codecIdAAC:
                codecName = "aac"
            case ScrcpyAudioStreamParser.codecIdRAW:
                codecName = "raw"
            default:
                codecName = String(format: "0x%08x", codecId)
            }
            AppLogger.capture.debug("[音频] codec: \(codecName)")

            // 创建音频播放器
            audioPlayer = AudioPlayer()

            // 启用音频调节器
            audioPlayer?.enableRegulator(sampleRate: 48000, channels: 2, targetBufferingMs: 50)

            // 设置 onDecodedAudio 回调
            opusDecoder?.onDecodedAudio = { [weak self] pcmData, format in
                guard let self else { return }

                // 检查是否已初始化
                if audioPlayer?.isInitialized != true {
                    _ = audioPlayer?.initializeFromFormat(format)
                    audioPlayer?.start()
                }

                // 将数据推送到 regulator
                audioPlayer?.processPCMData(pcmData, format: format)
            }
        }

        // 实际调用解码 - 跳过 config 包
        audioStreamParser?.onAudioPacket = { [weak self] data, pts, isConfig, isKeyFrame in
            guard let self else { return }
            // Config 包不是音频数据，跳过
            if isConfig {
                return
            }
            opusDecoder?.decode(data, pts: pts, isKeyFrame: isKeyFrame)
        }
    }

    /// 音频处理队列（避免阻塞网络队列）
    private let audioProcessingQueue = DispatchQueue(label: "com.screenPresenter.audio.processing", qos: .userInitiated)

    /// 处理接收到的音频数据
    private func handleReceivedAudioData(_ data: Data) {
        // 将音频处理移到单独的队列，避免阻塞网络接收
        audioProcessingQueue.async { [weak self] in
            self?.audioStreamParser?.processData(data)
        }
    }

    /// 清理音频组件
    private func cleanupAudioComponents() {
        audioPlayer?.stop()
        audioPlayer?.reset()
        audioPlayer = nil

        aacDecoder?.cleanup()
        aacDecoder = nil

        opusDecoder?.cleanup()
        opusDecoder = nil

        rawDecoder?.cleanup()
        rawDecoder = nil

        currentAudioCodecId = nil

        // 清理音频同步器
        audioSynchronizer?.reset()
        audioSynchronizer = nil

        audioStreamParser?.reset()
        audioStreamParser = nil
    }
}
