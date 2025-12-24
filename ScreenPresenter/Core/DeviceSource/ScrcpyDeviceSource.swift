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

    /// 是否禁用音频
    var noAudio: Bool = true

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
        // 注意: scrcpy 3.x 已移除 --no-display，使用 --no-playback 替代
        args.append("--no-playback")
        args.append("--no-audio")
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

        if noAudio {
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
    // MARK: - 常量

    /// 默认端口
    private static let defaultPort = 27183

    // MARK: - 配置

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

    // MARK: - 状态

    /// 服务器进程
    private var serverProcess: Process?

    /// 监控任务
    private var monitorTask: Task<Void, Never>?

    /// 最新的 CVPixelBuffer 存储
    private var _latestPixelBuffer: CVPixelBuffer?

    /// 最新的 CVPixelBuffer（供渲染使用）
    override var latestPixelBuffer: CVPixelBuffer? { _latestPixelBuffer }

    /// 帧回调
    var onFrame: ((CVPixelBuffer) -> Void)?

    /// 当前端口
    private var currentPort: Int

    // MARK: - 初始化

    init(device: AndroidDevice, toolchainManager: ToolchainManager, configuration: ScrcpyConfiguration? = nil) {
        // 使用传入的配置或从用户偏好设置构建配置
        var config = configuration ?? UserPreferences.shared.buildScrcpyConfiguration(serial: device.serial)
        config.serial = device.serial
        self.configuration = config
        self.toolchainManager = toolchainManager

        // 从用户偏好读取端口配置
        currentPort = UserPreferences.shared.scrcpyPort

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
        let (adbPath, scrcpyServerPath, scrcpyReady) = await MainActor.run {
            (
                toolchainManager.adbPath,
                toolchainManager.scrcpyServerPath,
                toolchainManager.scrcpyStatus.isReady
            )
        }

        AppLogger.connection.info("scrcpy 状态: \(scrcpyReady ? "就绪" : "未就绪")")

        guard scrcpyReady else {
            let error = DeviceSourceError.connectionFailed("scrcpy 未安装")
            AppLogger.connection.error("连接失败: scrcpy 未安装")
            updateState(.error(error))
            throw error
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
        decoder?.onDecodedFrame = { [weak self] pixelBuffer in
            self?.handleDecodedFrame(pixelBuffer)
        }

        // 获取 scrcpy 版本
        let scrcpyVersion = await getScrcpyVersion()

        // 创建服务器启动器
        serverLauncher = ScrcpyServerLauncher(
            adbService: adbService!,
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
        _latestPixelBuffer = nil

        updateState(.disconnected)
    }

    // MARK: - 捕获

    override func startCapture() async throws {
        // 使用 print 确保日志可见
        print("🚀 [ScrcpyDeviceSource] startCapture 开始，设备: \(displayName), 状态: \(state)")
        AppLogger.capture.info("准备开始捕获 Android 设备: \(displayName), 当前状态: \(state)")

        guard state == .connected || state == .paused else {
            print("❌ [ScrcpyDeviceSource] 设备未连接，当前状态: \(state)")
            AppLogger.capture.error("无法开始捕获: 设备未连接，当前状态: \(state)")
            throw DeviceSourceError.captureStartFailed(L10n.capture.deviceNotConnected)
        }

        AppLogger.capture.info("开始捕获 Android 设备: \(displayName)")

        do {
            guard let launcher = serverLauncher else {
                print("❌ [ScrcpyDeviceSource] serverLauncher 未初始化")
                throw DeviceSourceError.captureStartFailed("服务器启动器未初始化")
            }

            // 1. 先推送 scrcpy-server 并设置端口转发
            print("🚀 [ScrcpyDeviceSource] 准备启动环境...")
            try await launcher.prepareEnvironment(configuration: configuration)
            print("✅ [ScrcpyDeviceSource] 环境准备完成，连接模式: \(launcher.connectionMode)")

            // 2. 创建并启动 Socket 监听器/连接器（必须在服务端启动前！）
            print("🔌 [ScrcpyDeviceSource] 创建 Socket 接收器...")
            socketAcceptor = ScrcpySocketAcceptor(
                port: currentPort,
                connectionMode: launcher.connectionMode
            )

            // 设置数据接收回调
            socketAcceptor?.onDataReceived = { [weak self] data in
                self?.handleReceivedData(data)
            }

            // 3. 启动监听/连接
            print("🔌 [ScrcpyDeviceSource] 启动 Socket 监听...")
            try await socketAcceptor?.start()
            print("✅ [ScrcpyDeviceSource] Socket 监听已启动")

            // 4. 提前设置状态为 capturing，以便接收到数据后立即处理
            // 这样解码后的帧不会因为状态检查而被丢弃
            updateState(.capturing)
            print("✅ [ScrcpyDeviceSource] 状态已更新为 capturing")

            // 5. 现在启动 scrcpy-server（它会连接到我们的监听端口）
            print("🚀 [ScrcpyDeviceSource] 启动 scrcpy-server...")
            serverProcess = try await launcher.startServer(configuration: configuration)
            print("✅ [ScrcpyDeviceSource] scrcpy-server 已启动")

            // 6. 等待视频连接建立
            print("⏳ [ScrcpyDeviceSource] 等待视频连接...")
            try await socketAcceptor?.waitForVideoConnection(timeout: 10)

            AppLogger.capture.info("捕获已启动: \(displayName)")

            // 启动进程监控
            startProcessMonitoring()

        } catch {
            let captureError = DeviceSourceError.captureStartFailed(error.localizedDescription)
            updateState(.error(captureError))
            throw captureError
        }
    }

    override func stopCapture() async {
        AppLogger.capture.info("停止捕获: \(displayName)")

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

        if state == .capturing {
            updateState(.connected)
        }

        AppLogger.capture.info("捕获已停止: \(displayName)")
    }

    // MARK: - 数据处理

    /// 接收到的数据计数（用于调试）
    private var receivedDataCount = 0
    private var receivedBytesTotal = 0

    /// 处理接收到的数据
    private func handleReceivedData(_ data: Data) {
        receivedDataCount += 1
        receivedBytesTotal += data.count

        // 每收到一定数量的数据包打印一次日志
        if receivedDataCount == 1 {
            print("📥 [ScrcpyDeviceSource] 首次收到数据: \(data.count) 字节")
        }
        if receivedDataCount % 100 == 0 {
            print("📥 [ScrcpyDeviceSource] 已收到 \(receivedDataCount) 个数据包，共 \(receivedBytesTotal) 字节")
        }

        guard let parser = streamParser, let decoder else {
            print("❌ [ScrcpyDeviceSource] parser 或 decoder 为 nil")
            return
        }

        // 解析 NAL 单元
        let nalUnits = parser.append(data)

        if receivedDataCount == 1 {
            print("📦 [ScrcpyDeviceSource] 首次解析得到 \(nalUnits.count) 个 NAL 单元")
        }

        for nalUnit in nalUnits {
            // 如果是参数集且解码器未初始化，尝试初始化
            if nalUnit.isParameterSet, !decoder.isReady {
                if parser.hasCompleteParameterSets {
                    initializeDecoderIfNeeded()
                }
                continue
            }

            // 解码非参数集 NAL 单元
            if decoder.isReady, !nalUnit.isParameterSet {
                decoder.decode(nalUnit: nalUnit)
            } else if !decoder.isReady, !nalUnit.isParameterSet {
                // 解码器未就绪，跳过非参数集帧
                if receivedDataCount <= 5 {
                    print("⏳ [ScrcpyDeviceSource] 解码器未就绪，跳过 NAL 类型: \(nalUnit.type)")
                }
            }
        }
    }

    /// 初始化解码器（如果需要）
    private func initializeDecoderIfNeeded() {
        guard let parser = streamParser, let decoder else {
            print("❌ [ScrcpyDeviceSource] initializeDecoderIfNeeded: parser 或 decoder 为 nil")
            return
        }
        guard !decoder.isReady else { return }
        guard parser.hasCompleteParameterSets else {
            print("⏳ [ScrcpyDeviceSource] 等待完整参数集...")
            return
        }

        print("🔧 [ScrcpyDeviceSource] 尝试初始化解码器，参数集: \(parser.parameterSetsDescription)")
        AppLogger.capture.info("尝试初始化解码器，参数集: \(parser.parameterSetsDescription)")

        initializeDecoder()
    }

    /// 初始化解码器
    private func initializeDecoder() {
        guard let parser = streamParser, let decoder else {
            print("❌ [ScrcpyDeviceSource] initializeDecoder: parser 或 decoder 为 nil")
            return
        }
        guard parser.hasCompleteParameterSets else {
            print("❌ [ScrcpyDeviceSource] initializeDecoder: 参数集不完整")
            return
        }

        // 获取实际的编解码类型（可能从协议元数据更新）
        let codecType = parser.currentCodecType
        print("🔧 [ScrcpyDeviceSource] 开始初始化解码器，codec: \(codecType == kCMVideoCodecType_H264 ? "H.264" : "H.265")")

        do {
            if codecType == kCMVideoCodecType_H264 {
                guard let sps = parser.sps, let pps = parser.pps else {
                    print("❌ [ScrcpyDeviceSource] H.264 参数集为 nil")
                    return
                }
                print("🔧 [ScrcpyDeviceSource] 调用 decoder.initializeH264(sps: \(sps.count)B, pps: \(pps.count)B)")
                try decoder.initializeH264(sps: sps, pps: pps)
            } else {
                guard let vps = parser.vps, let sps = parser.sps, let pps = parser.pps else {
                    print("❌ [ScrcpyDeviceSource] H.265 参数集为 nil")
                    return
                }
                print("🔧 [ScrcpyDeviceSource] 调用 decoder.initializeH265")
                try decoder.initializeH265(vps: vps, sps: sps, pps: pps)
            }
            print("✅ [ScrcpyDeviceSource] 解码器初始化成功！")
            AppLogger.capture.info("✅ 解码器初始化成功，协议信息: \(parser.protocolDescription)")
        } catch {
            print("❌ [ScrcpyDeviceSource] 解码器初始化失败: \(error)")
            AppLogger.capture.error("❌ 解码器初始化失败: \(error.localizedDescription)")
        }
    }

    /// 处理 SPS 变化（分辨率变化）
    private func handleSPSChanged() {
        AppLogger.capture.info("⚠️ 检测到 SPS 变化，重建解码器...")

        // 重置解码器
        decoder?.reset()

        // 重新初始化解码器
        initializeDecoder()
    }

    /// 处理解码后的帧
    private var decodedFrameCount = 0

    private func handleDecodedFrame(_ pixelBuffer: CVPixelBuffer) {
        decodedFrameCount += 1

        // 前几帧打印日志
        if decodedFrameCount <= 3 {
            print("🎬 [ScrcpyDeviceSource] 收到解码帧 #\(decodedFrameCount)，状态: \(state)")
        }

        guard state == .capturing else {
            if decodedFrameCount <= 3 {
                print("⚠️ [ScrcpyDeviceSource] 状态不是 capturing，丢弃帧")
            }
            return
        }

        // 更新最新帧
        _latestPixelBuffer = pixelBuffer

        // 更新捕获尺寸
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)

        if decodedFrameCount <= 3 {
            print("🎬 [ScrcpyDeviceSource] 帧尺寸: \(width)x\(height)")
        }

        updateCaptureSize(CGSize(width: width, height: height))

        // 创建 CapturedFrame
        let frame = CapturedFrame(
            pixelBuffer: pixelBuffer,
            presentationTime: CMTime(value: Int64(CACurrentMediaTime() * 1_000_000), timescale: 1_000_000),
            size: CGSize(width: width, height: height)
        )
        emitFrame(frame)

        // 回调通知
        DispatchQueue.main.async { [weak self] in
            self?.onFrame?(pixelBuffer)
        }
    }

    // MARK: - 辅助方法

    /// 获取 scrcpy 版本
    /// 优先从 scrcpy 可执行文件获取，失败时使用默认版本
    private func getScrcpyVersion() async -> String {
        let scrcpyPath = await MainActor.run { toolchainManager.scrcpyPath }

        AppLogger.process.info("获取 scrcpy 版本，路径: \(scrcpyPath)")

        do {
            let runner = await MainActor.run { ProcessRunner() }
            let result = try await runner.run(scrcpyPath, arguments: ["--version"])

            AppLogger.process.debug("scrcpy --version 输出: \(result.stdout.prefix(100))")

            // 解析版本号，格式如: "scrcpy 3.3.4 <https://...>"
            // 必须匹配完整的三段式版本号 (x.y.z)
            if let match = result.stdout.firstMatch(of: /scrcpy\s+(\d+\.\d+\.\d+)/) {
                let version = String(match.1)
                AppLogger.process.info("✅ 获取到 scrcpy 版本: \(version)")
                return version
            }

            // 尝试匹配两段式版本号 (x.y)
            if let match = result.stdout.firstMatch(of: /scrcpy\s+(\d+\.\d+)/) {
                let version = String(match.1)
                AppLogger.process.info("✅ 获取到 scrcpy 版本 (两段式): \(version)")
                return version
            }

            AppLogger.process.warning("无法从输出中解析版本号: \(result.stdout.prefix(200))")
        } catch {
            AppLogger.process.error("获取 scrcpy 版本失败: \(error.localizedDescription)")
        }

        // 默认返回与内置 scrcpy-server 匹配的版本号
        // 内置的 scrcpy-server 版本是 3.3.4
        let defaultVersion = "3.3.4"
        AppLogger.process.warning("⚠️ 使用默认版本号: \(defaultVersion)")
        return defaultVersion
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
}
