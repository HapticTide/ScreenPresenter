//
//  ScrcpyDeviceSource.swift
//  ScreenPresenter
//
//  Created by Sun on 2025/12/22.
//
//  Scrcpy 设备源
//  通过 scrcpy 获取 Android 设备的 H.264/H.265 码流
//  使用 VideoToolbox 进行硬件解码
//

import AppKit
import Combine
import CoreMedia
import CoreVideo
import Darwin
import Foundation
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

    /// scrcpy-server 在设备上的路径
    private static let serverDevicePath = "/data/local/tmp/scrcpy-server.jar"

    /// 本地监听端口基址
    private static let basePort = 27183

    // MARK: - 属性

    private let configuration: ScrcpyConfiguration
    private var serverProcess: Process?
    private var decoder: VideoToolboxDecoder?
    private var monitorTask: Task<Void, Never>?
    private var readTask: Task<Void, Never>?
    private var videoSocket: FileHandle?

    /// 当前使用的端口
    private var currentPort: Int = 0

    /// 生成的 scid（用于标识客户端）
    private var scid: UInt32 = 0

    private let toolchainManager: ToolchainManager

    /// 最新的 CVPixelBuffer 存储
    private var _latestPixelBuffer: CVPixelBuffer?

    /// 最新的 CVPixelBuffer（供渲染使用）
    override var latestPixelBuffer: CVPixelBuffer? { _latestPixelBuffer }

    /// 帧回调
    var onFrame: ((CVPixelBuffer) -> Void)?

    // MARK: - 初始化

    init(device: AndroidDevice, toolchainManager: ToolchainManager, configuration: ScrcpyConfiguration? = nil) {
        // 使用传入的配置或从用户偏好设置构建配置
        var config = configuration ?? UserPreferences.shared.buildScrcpyConfiguration(serial: device.serial)
        config.serial = device.serial
        self.configuration = config
        self.toolchainManager = toolchainManager

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
        readTask?.cancel()
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

        // 检查 scrcpy 是否可用
        let scrcpyReady = await MainActor.run { toolchainManager.scrcpyStatus.isReady }
        AppLogger.connection.info("scrcpy 状态: \(scrcpyReady ? "就绪" : "未就绪")")

        guard scrcpyReady else {
            let error = DeviceSourceError.connectionFailed("scrcpy 未安装")
            AppLogger.connection.error("连接失败: scrcpy 未安装")
            updateState(.error(error))
            throw error
        }

        // 创建 VideoToolbox 解码器
        AppLogger.connection.info("创建 VideoToolbox 解码器，编解码器: \(configuration.videoCodec.rawValue)")
        decoder = VideoToolboxDecoder(codecType: configuration.videoCodec.fourCC)
        decoder?.onDecodedFrame = { [weak self] pixelBuffer in
            self?.handleDecodedFrame(pixelBuffer)
        }

        updateState(.connected)
        AppLogger.connection.info("✅ 设备连接成功: \(displayName), 状态: \(state)")
    }

    override func disconnect() async {
        AppLogger.connection.info("断开连接: \(displayName), 当前状态: \(state)")

        monitorTask?.cancel()
        monitorTask = nil

        // stopCapture 会处理 readTask、socket、serverProcess 和 adb forward
        await stopCapture()

        // 清理解码器
        decoder = nil
        _latestPixelBuffer = nil

        updateState(.disconnected)
    }

    // MARK: - 捕获

    override func startCapture() async throws {
        AppLogger.capture.info("准备开始捕获 Android 设备: \(displayName), 当前状态: \(state)")

        guard state == .connected || state == .paused else {
            AppLogger.capture.error("无法开始捕获: 设备未连接，当前状态: \(state)")
            throw DeviceSourceError.captureStartFailed(L10n.capture.deviceNotConnected)
        }

        AppLogger.capture.info("开始捕获 Android 设备: \(displayName)")

        do {
            // 启动 scrcpy 进程
            try await startScrcpyProcess()

            updateState(.capturing)
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

        // 1. 先取消读取任务
        readTask?.cancel()

        // 2. 关闭 socket 的读取端，这会使 availableData 返回空数据而不是崩溃
        if let socket = videoSocket {
            let fd = socket.fileDescriptor
            if fd >= 0 {
                // shutdown 读取端，让 availableData 安全返回
                Darwin.shutdown(fd, SHUT_RD)
            }
        }

        // 3. 等待读取任务结束（最多等待 1 秒）
        if let task = readTask {
            _ = await Task {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }.value
            task.cancel()
        }
        readTask = nil

        // 4. 现在可以安全关闭 socket
        try? videoSocket?.close()
        videoSocket = nil

        // 5. 终止 scrcpy-server 进程
        if let serverProcess, serverProcess.isRunning {
            serverProcess.terminate()
            serverProcess.waitUntilExit()
        }
        serverProcess = nil

        // 6. 移除 adb 端口转发
        await removeAdbForward()

        if state == .capturing {
            updateState(.connected)
        }

        AppLogger.capture.info("捕获已停止: \(displayName)")
    }

    // MARK: - Scrcpy Server 管理

    /// 启动 scrcpy-server 并建立连接
    private func startScrcpyProcess() async throws {
        let (adbPath, scrcpyServerPath) = await MainActor.run {
            (toolchainManager.adbPath, toolchainManager.scrcpyServerPath)
        }

        AppLogger.process.info("adb 路径: \(adbPath)")
        AppLogger.process.info("scrcpy-server 路径: \(scrcpyServerPath ?? "未找到")")

        guard let serverPath = scrcpyServerPath else {
            AppLogger.process.error("scrcpy-server 未找到，无法启动")
            throw DeviceSourceError.captureStartFailed("scrcpy-server 未找到")
        }

        // 1. 推送 scrcpy-server 到设备
        try await pushServerToDevice(adbPath: adbPath, serverPath: serverPath)

        // 2. 设置 adb 端口转发
        try await setupAdbForward(adbPath: adbPath)

        // 3. 启动 scrcpy-server
        try await startServer(adbPath: adbPath)

        // 4. 连接到视频流
        try await connectToVideoStream()

        // 5. 启动视频流读取
        startVideoStreamReader()
    }

    /// 推送 scrcpy-server 到设备
    private func pushServerToDevice(adbPath: String, serverPath: String) async throws {
        AppLogger.process.info("推送 scrcpy-server 到设备...")

        let result = try await runProcess(
            adbPath,
            arguments: ["-s", configuration.serial, "push", serverPath, Self.serverDevicePath]
        )

        if !result.isSuccess {
            throw DeviceSourceError.captureStartFailed("推送 scrcpy-server 失败: \(result.stderr)")
        }

        AppLogger.process.info("scrcpy-server 已推送到设备")
    }

    /// 设置 adb 端口转发
    private func setupAdbForward(adbPath: String) async throws {
        // 生成随机 scid（限制在 Java Integer 安全范围内）
        scid = UInt32.random(in: 10_000_000..<100_000_000)
        currentPort = Self.basePort

        AppLogger.process.info("设置 adb 端口转发，scid: \(scid)")

        let result = try await runProcess(
            adbPath,
            arguments: [
                "-s", configuration.serial,
                "forward",
                "tcp:\(currentPort)",
                "localabstract:scrcpy_\(scid)",
            ]
        )

        if !result.isSuccess {
            throw DeviceSourceError.captureStartFailed("设置端口转发失败: \(result.stderr)")
        }

        AppLogger.process.info("端口转发已设置: tcp:\(currentPort) -> localabstract:scrcpy_\(scid)")
    }

    /// 移除 adb 端口转发
    private func removeAdbForward() async {
        guard currentPort > 0 else { return }

        let adbPath = await MainActor.run { toolchainManager.adbPath }

        do {
            _ = try await runProcess(
                adbPath,
                arguments: ["-s", configuration.serial, "forward", "--remove", "tcp:\(currentPort)"]
            )
            AppLogger.process.info("已移除端口转发")
        } catch {
            AppLogger.process.warning("移除端口转发失败: \(error.localizedDescription)")
        }
    }

    /// 在主线程执行进程（辅助方法）
    @MainActor
    private func runProcess(_ executable: String, arguments: [String]) async throws -> ProcessResult {
        let runner = ProcessRunner()
        return try await runner.run(executable, arguments: arguments)
    }

    /// 启动 scrcpy-server
    private func startServer(adbPath: String) async throws {
        // 获取 scrcpy 版本（用于服务端验证）
        let scrcpyVersion = await getScrcpyVersion()
        AppLogger.process.info("scrcpy 版本: \(scrcpyVersion)")

        // 构建服务端参数
        var serverArgs: [String] = [
            scrcpyVersion,
            "scid=\(scid)",
            "log_level=info",
            "audio=false",
            "control=false",
            "tunnel_forward=true",
            "send_device_meta=false",
            "send_frame_meta=false",
            "send_dummy_byte=false",
            "send_codec_meta=false",
            "raw_stream=true",
        ]

        if configuration.maxSize > 0 {
            serverArgs.append("max_size=\(configuration.maxSize)")
        }
        if configuration.maxFps > 0 {
            serverArgs.append("max_fps=\(configuration.maxFps)")
        }
        if configuration.bitrate > 0 {
            serverArgs.append("video_bit_rate=\(configuration.bitrate)")
        }
        serverArgs.append("video_codec=\(configuration.videoCodec.rawValue)")

        let shellCommand = "CLASSPATH=\(Self.serverDevicePath) app_process / com.genymobile.scrcpy.Server \(serverArgs.joined(separator: " "))"

        AppLogger.process.info("启动 scrcpy-server: \(shellCommand)")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: adbPath)
        process.arguments = ["-s", configuration.serial, "shell", shellCommand]

        let errorPipe = Pipe()
        process.standardError = errorPipe
        process.standardOutput = Pipe() // 忽略 stdout

        try process.run()
        serverProcess = process

        // 读取错误输出（提高日志级别以便调试）
        Task {
            for try await line in errorPipe.fileHandleForReading.bytes.lines {
                AppLogger.process.info("[scrcpy-server] \(line)")
            }
        }

        // 等待一小段时间让服务端启动
        try await Task.sleep(nanoseconds: 800_000_000) // 800ms

        // 检查进程是否还在运行
        guard process.isRunning else {
            let exitCode = process.terminationStatus
            throw DeviceSourceError.captureStartFailed("scrcpy-server 启动失败，退出码: \(exitCode)")
        }
    }

    /// 获取 scrcpy 版本
    private func getScrcpyVersion() async -> String {
        let scrcpyPath = await MainActor.run { toolchainManager.scrcpyPath }

        do {
            let result = try await runProcess(scrcpyPath, arguments: ["--version"])
            // 解析版本号，格式如: "scrcpy 3.3.4 <https://...>"
            if let match = result.stdout.firstMatch(of: /scrcpy\s+(\d+\.\d+(?:\.\d+)?)/) {
                return String(match.1)
            }
        } catch {
            AppLogger.process.warning("获取 scrcpy 版本失败: \(error.localizedDescription)")
        }

        // 默认返回一个版本号
        return "3.3.4"
    }

    /// 连接到视频流
    private func connectToVideoStream() async throws {
        AppLogger.process.info("连接到视频流，端口: \(currentPort)")

        // 创建 TCP 连接
        var hints = addrinfo()
        hints.ai_family = AF_INET
        hints.ai_socktype = SOCK_STREAM

        var result: UnsafeMutablePointer<addrinfo>?
        let status = getaddrinfo("127.0.0.1", String(currentPort), &hints, &result)

        guard status == 0, let addrInfo = result else {
            throw DeviceSourceError.captureStartFailed("无法解析地址")
        }

        defer { freeaddrinfo(result) }

        let sock = Darwin.socket(addrInfo.pointee.ai_family, addrInfo.pointee.ai_socktype, addrInfo.pointee.ai_protocol)
        guard sock >= 0 else {
            throw DeviceSourceError.captureStartFailed("无法创建 socket")
        }

        // 尝试连接，最多重试 5 次
        var connected = false
        for attempt in 1...5 {
            let connectResult = Darwin.connect(sock, addrInfo.pointee.ai_addr, addrInfo.pointee.ai_addrlen)
            if connectResult == 0 {
                connected = true
                break
            }

            AppLogger.process.debug("连接尝试 \(attempt) 失败，等待后重试...")
            try await Task.sleep(nanoseconds: 200_000_000) // 200ms
        }

        guard connected else {
            Darwin.close(sock)
            throw DeviceSourceError.captureStartFailed("无法连接到 scrcpy-server")
        }

        videoSocket = FileHandle(fileDescriptor: sock, closeOnDealloc: true)
        AppLogger.process.info("已连接到视频流")
    }

    /// 启动视频流读取
    private func startVideoStreamReader() {
        guard let videoSocket else {
            AppLogger.capture.error("视频 socket 未初始化")
            return
        }

        // 保存 socket 的本地引用，避免在循环中访问可能被置空的属性
        let socket = videoSocket

        readTask = Task { [weak self] in
            guard let self else { return }

            AppLogger.capture.info("开始读取视频流...")
            var totalBytesRead = 0
            var readCount = 0

            // 读取视频流数据
            while !Task.isCancelled {
                // 使用 readabilityHandler 或直接读取
                // FileHandle.availableData 在 socket 关闭时会抛出异常
                // 我们通过检查 Task.isCancelled 来提前退出
                autoreleasepool {
                    let data = socket.availableData

                    guard !data.isEmpty else {
                        // 空数据表示连接已关闭
                        return
                    }

                    totalBytesRead += data.count
                    readCount += 1

                    // 前几次读取打印详细日志
                    if readCount <= 5 {
                        AppLogger.capture.info("读取数据块 #\(readCount): \(data.count) 字节")
                        if data.count > 0 {
                            let preview = data.prefix(min(32, data.count)).map { String(format: "%02x", $0) }
                                .joined(separator: " ")
                            AppLogger.capture.info("数据预览: \(preview)")
                        }
                    }

                    // 送入解码器（在专用解码队列异步执行）
                    self.decoder?.decode(data: data)
                }

                // 检查是否应该退出
                if Task.isCancelled {
                    break
                }
            }

            AppLogger.capture.info("视频流读取任务结束，共读取 \(totalBytesRead) 字节，\(readCount) 次")

            // 流结束后更新状态
            await MainActor.run { [weak self] in
                guard let self else { return }
                if state == .capturing {
                    updateState(.error(.captureInterrupted))
                }
            }
        }
    }

    /// 处理解码后的帧
    private func handleDecodedFrame(_ pixelBuffer: CVPixelBuffer) {
        guard state == .capturing else { return }

        // 更新最新帧
        _latestPixelBuffer = pixelBuffer

        // 更新捕获尺寸
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        updateCaptureSize(CGSize(width: width, height: height))

        // 创建 CapturedFrame
        let frame = CapturedFrame(
            pixelBuffer: pixelBuffer,
            presentationTime: CMTime(value: Int64(CACurrentMediaTime() * 1000), timescale: 1000),
            size: CGSize(width: width, height: height)
        )
        emitFrame(frame)

        // 回调通知
        onFrame?(pixelBuffer)
    }

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

// MARK: - VideoToolbox 解码器

/// VideoToolbox 硬件解码器
private final class VideoToolboxDecoder {
    private var formatDescription: CMVideoFormatDescription?
    private var decompressionSession: VTDecompressionSession?
    private let codecType: CMVideoCodecType

    /// 解码后的帧回调
    var onDecodedFrame: ((CVPixelBuffer) -> Void)?

    /// NAL 单元解析器
    private var nalParser: NALUnitParser

    /// 是否已初始化
    private var isInitialized = false

    /// 专用解码队列（高优先级，确保低延迟解码）
    private let decodeQueue = DispatchQueue(
        label: "com.screenPresenter.android.decode",
        qos: .userInteractive
    )

    /// 用于保护解码器状态的锁
    private let decoderLock = NSLock()

    init(codecType: CMVideoCodecType) {
        self.codecType = codecType
        nalParser = NALUnitParser(codecType: codecType)
    }

    deinit {
        if let session = decompressionSession {
            VTDecompressionSessionInvalidate(session)
        }
    }

    /// 解码数据
    /// 将数据送入专用解码队列进行异步解码
    private var decodeCallCount = 0

    func decode(data: Data) {
        decodeQueue.async { [weak self] in
            guard let self else { return }

            decoderLock.lock()
            defer { decoderLock.unlock() }

            decodeCallCount += 1
            if decodeCallCount <= 10 {
                AppLogger.capture.info("[解码器] 收到数据 #\(decodeCallCount): \(data.count) 字节")
            }

            // 解析 NAL 单元
            let nalUnits = nalParser.parse(data: data)

            if decodeCallCount <= 10 {
                AppLogger.capture.info("[解码器] 解析出 \(nalUnits.count) 个 NAL 单元")
            }

            for nalUnit in nalUnits {
                if decodeCallCount <= 10 {
                    AppLogger.capture
                        .info(
                            "[解码器] NAL 类型: \(nalUnit.type), 是参数集: \(nalUnit.isParameterSet), 大小: \(nalUnit.data.count)"
                        )
                }

                // 检查是否是参数集
                if nalUnit.isParameterSet {
                    if !isInitialized {
                        AppLogger.capture.info("[解码器] 尝试初始化解码器...")
                        // 尝试初始化解码器
                        if initializeDecoder(with: nalUnit) {
                            isInitialized = true
                            AppLogger.capture.info("[解码器] ✅ 解码器初始化成功！")
                        }
                    }
                    continue
                }

                // 解码视频帧
                if isInitialized {
                    decodeNALUnit(nalUnit)
                }
            }
        }
    }

    /// 初始化解码器（使用参数集）
    private func initializeDecoder(with nalUnit: NALUnit) -> Bool {
        // 为简化实现，这里假设已经有了正确的参数集
        // 实际实现需要正确解析 SPS/PPS (H.264) 或 VPS/SPS/PPS (H.265)

        guard let sps = nalParser.sps, let pps = nalParser.pps else {
            AppLogger.capture.info("等待 SPS/PPS 参数集... (当前 SPS: \(nalParser.sps != nil), PPS: \(nalParser.pps != nil))")
            return false
        }

        AppLogger.capture.info("✅ 收到完整参数集 - SPS: \(sps.count) 字节, PPS: \(pps.count) 字节")
        AppLogger.capture
            .info("SPS: \(sps.map { String(format: "%02x", $0) }.joined(separator: " "))")
        AppLogger.capture
            .info("PPS: \(pps.map { String(format: "%02x", $0) }.joined(separator: " "))")
        AppLogger.capture.info("开始创建 H.264 格式描述...")

        // 创建格式描述
        var formatDescription: CMFormatDescription?
        let status: OSStatus

        if codecType == kCMVideoCodecType_H264 {
            // 使用 contiguousBytes 确保数据连续，并在闭包内完成所有操作
            status = sps.withUnsafeBytes { spsBuffer in
                pps.withUnsafeBytes { ppsBuffer in
                    let parameterSetPointers: [UnsafePointer<UInt8>] = [
                        spsBuffer.baseAddress!.assumingMemoryBound(to: UInt8.self),
                        ppsBuffer.baseAddress!.assumingMemoryBound(to: UInt8.self),
                    ]
                    let parameterSetSizes: [Int] = [sps.count, pps.count]

                    return CMVideoFormatDescriptionCreateFromH264ParameterSets(
                        allocator: kCFAllocatorDefault,
                        parameterSetCount: 2,
                        parameterSetPointers: parameterSetPointers,
                        parameterSetSizes: parameterSetSizes,
                        nalUnitHeaderLength: 4,
                        formatDescriptionOut: &formatDescription
                    )
                }
            }
        } else {
            // H.265 需要 VPS
            guard let vps = nalParser.vps else {
                AppLogger.capture.debug("等待 VPS 参数集...")
                return false
            }

            AppLogger.capture.info("收到 VPS: \(vps.count) 字节")

            status = vps.withUnsafeBytes { vpsBuffer in
                sps.withUnsafeBytes { spsBuffer in
                    pps.withUnsafeBytes { ppsBuffer in
                        let parameterSetPointers: [UnsafePointer<UInt8>] = [
                            vpsBuffer.baseAddress!.assumingMemoryBound(to: UInt8.self),
                            spsBuffer.baseAddress!.assumingMemoryBound(to: UInt8.self),
                            ppsBuffer.baseAddress!.assumingMemoryBound(to: UInt8.self),
                        ]
                        let parameterSetSizes: [Int] = [vps.count, sps.count, pps.count]

                        return CMVideoFormatDescriptionCreateFromHEVCParameterSets(
                            allocator: kCFAllocatorDefault,
                            parameterSetCount: 3,
                            parameterSetPointers: parameterSetPointers,
                            parameterSetSizes: parameterSetSizes,
                            nalUnitHeaderLength: 4,
                            extensions: nil,
                            formatDescriptionOut: &formatDescription
                        )
                    }
                }
            }
        }

        AppLogger.capture.info("CMVideoFormatDescriptionCreate 返回状态: \(status)")

        guard status == noErr, let description = formatDescription else {
            AppLogger.capture.error("❌ 创建格式描述失败，错误码: \(status)")
            return false
        }

        AppLogger.capture.info("✅ 格式描述创建成功")

        self.formatDescription = description

        // 创建解压缩会话
        return createDecompressionSession(formatDescription: description)
    }

    /// 创建解压缩会话
    private func createDecompressionSession(formatDescription: CMFormatDescription) -> Bool {
        // 输出配置
        let outputPixelBufferAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferMetalCompatibilityKey as String: true,
        ]

        // 创建回调
        var outputCallback = VTDecompressionOutputCallbackRecord(
            decompressionOutputCallback: { refcon, _, status, _, imageBuffer, _, _ in
                guard status == noErr, let imageBuffer else { return }

                let decoder = Unmanaged<VideoToolboxDecoder>.fromOpaque(refcon!).takeUnretainedValue()
                decoder.onDecodedFrame?(imageBuffer)
            },
            decompressionOutputRefCon: Unmanaged.passUnretained(self).toOpaque()
        )

        var session: VTDecompressionSession?
        let status = VTDecompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            formatDescription: formatDescription,
            decoderSpecification: nil,
            imageBufferAttributes: outputPixelBufferAttributes as CFDictionary,
            outputCallback: &outputCallback,
            decompressionSessionOut: &session
        )

        guard status == noErr, let session else {
            AppLogger.capture.error("创建解压缩会话失败: \(status)")
            return false
        }

        decompressionSession = session
        AppLogger.capture.info("VideoToolbox 解码器已初始化")
        return true
    }

    /// 解码 NAL 单元
    private func decodeNALUnit(_ nalUnit: NALUnit) {
        guard let session = decompressionSession, let formatDescription else { return }

        // 创建 CMBlockBuffer
        var blockBuffer: CMBlockBuffer?
        let data = nalUnit.data

        // 添加 NAL 长度前缀（4字节大端序）
        var length = UInt32(data.count).bigEndian
        var nalData = Data(bytes: &length, count: 4)
        nalData.append(data)

        let status = nalData.withUnsafeMutableBytes { buffer -> OSStatus in
            CMBlockBufferCreateWithMemoryBlock(
                allocator: kCFAllocatorDefault,
                memoryBlock: buffer.baseAddress,
                blockLength: buffer.count,
                blockAllocator: kCFAllocatorNull,
                customBlockSource: nil,
                offsetToData: 0,
                dataLength: buffer.count,
                flags: 0,
                blockBufferOut: &blockBuffer
            )
        }

        guard status == kCMBlockBufferNoErr, let buffer = blockBuffer else {
            return
        }

        // 创建 CMSampleBuffer
        var sampleBuffer: CMSampleBuffer?
        var timingInfo = CMSampleTimingInfo(
            duration: CMTime.invalid,
            presentationTimeStamp: CMTime(value: Int64(CACurrentMediaTime() * 1000), timescale: 1000),
            decodeTimeStamp: CMTime.invalid
        )

        CMSampleBufferCreateReady(
            allocator: kCFAllocatorDefault,
            dataBuffer: buffer,
            formatDescription: formatDescription,
            sampleCount: 1,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timingInfo,
            sampleSizeEntryCount: 0,
            sampleSizeArray: nil,
            sampleBufferOut: &sampleBuffer
        )

        guard let sample = sampleBuffer else { return }

        // 解码
        VTDecompressionSessionDecodeFrame(
            session,
            sampleBuffer: sample,
            flags: [._EnableAsynchronousDecompression],
            frameRefcon: nil,
            infoFlagsOut: nil
        )
    }
}

// MARK: - NAL 单元解析器

/// NAL 单元
private struct NALUnit {
    let type: UInt8
    let data: Data
    let isParameterSet: Bool
}

/// NAL 单元解析器
private final class NALUnitParser {
    private let codecType: CMVideoCodecType
    private var buffer = Data()

    /// 参数集
    var vps: Data? // H.265 only
    var sps: Data?
    var pps: Data?

    init(codecType: CMVideoCodecType) {
        self.codecType = codecType
    }

    /// 解析数据，返回 NAL 单元列表
    func parse(data: Data) -> [NALUnit] {
        buffer.append(data)

        var nalUnits: [NALUnit] = []
        var searchStart = 0

        // 查找起始码 (0x00 0x00 0x00 0x01 或 0x00 0x00 0x01)
        while searchStart < buffer.count - 4 {
            var startCodeLength = 0
            var foundStartCode = false

            // 检查 4 字节起始码
            if
                buffer[searchStart] == 0x00,
                buffer[searchStart + 1] == 0x00,
                buffer[searchStart + 2] == 0x00,
                buffer[searchStart + 3] == 0x01 {
                startCodeLength = 4
                foundStartCode = true
            }
            // 检查 3 字节起始码
            else if
                buffer[searchStart] == 0x00,
                buffer[searchStart + 1] == 0x00,
                buffer[searchStart + 2] == 0x01 {
                startCodeLength = 3
                foundStartCode = true
            }

            if foundStartCode {
                // 查找下一个起始码
                var nextStartCode = searchStart + startCodeLength
                while nextStartCode < buffer.count - 3 {
                    if
                        buffer[nextStartCode] == 0x00,
                        buffer[nextStartCode + 1] == 0x00,
                        buffer[nextStartCode + 2] == 0x01 ||
                        (buffer[nextStartCode + 2] == 0x00 && nextStartCode + 3 < buffer
                            .count && buffer[nextStartCode + 3] == 0x01) {
                        break
                    }
                    nextStartCode += 1
                }

                if nextStartCode >= buffer.count - 3 {
                    // 没有找到下一个起始码，保留当前数据等待更多数据
                    break
                }

                // 提取 NAL 单元数据
                let nalData = buffer.subdata(in: (searchStart + startCodeLength)..<nextStartCode)
                if let nalUnit = parseNALUnit(data: nalData) {
                    nalUnits.append(nalUnit)
                }

                searchStart = nextStartCode
            } else {
                searchStart += 1
            }
        }

        // 移除已处理的数据
        if searchStart > 0 {
            buffer.removeSubrange(0..<searchStart)
        }

        return nalUnits
    }

    /// 解析单个 NAL 单元
    private func parseNALUnit(data: Data) -> NALUnit? {
        guard !data.isEmpty else { return nil }

        let nalType: UInt8
        let isParameterSet: Bool

        if codecType == kCMVideoCodecType_H264 {
            // H.264: NAL type 在第一个字节的低 5 位
            nalType = data[0] & 0x1f

            switch nalType {
            case 7: // SPS
                sps = data
                isParameterSet = true
            case 8: // PPS
                pps = data
                isParameterSet = true
            default:
                isParameterSet = false
            }
        } else {
            // H.265: NAL type 在第一个字节的位 6-1
            nalType = (data[0] >> 1) & 0x3f

            switch nalType {
            case 32: // VPS
                vps = data
                isParameterSet = true
            case 33: // SPS
                sps = data
                isParameterSet = true
            case 34: // PPS
                pps = data
                isParameterSet = true
            default:
                isParameterSet = false
            }
        }

        return NALUnit(type: nalType, data: data, isParameterSet: isParameterSet)
    }
}
