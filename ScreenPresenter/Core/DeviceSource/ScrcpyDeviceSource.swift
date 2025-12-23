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

        args.append("--bit-rate=\(bitrate)")
        args.append("--max-fps=\(maxFps)")
        args.append("--video-codec=\(videoCodec.rawValue)")

        // 关键：不显示窗口，输出原始流
        args.append("--no-display")
        args.append("--no-audio")
        args.append("--no-control")

        // 输出到 stdout
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
/// 通过 scrcpy 获取原始 H.264/H.265 码流并使用 VideoToolbox 解码
final class ScrcpyDeviceSource: BaseDeviceSource {
    // MARK: - 属性

    private let configuration: ScrcpyConfiguration
    private var process: Process?
    private var decoder: VideoToolboxDecoder?
    private var monitorTask: Task<Void, Never>?
    private var readTask: Task<Void, Never>?

    private let toolchainManager: ToolchainManager

    /// 最新的 CVPixelBuffer 存储
    private var _latestPixelBuffer: CVPixelBuffer?

    /// 最新的 CVPixelBuffer（供渲染使用）
    override var latestPixelBuffer: CVPixelBuffer? { _latestPixelBuffer }

    /// 帧回调
    var onFrame: ((CVPixelBuffer) -> Void)?

    // MARK: - 初始化

    init(device: AndroidDevice, toolchainManager: ToolchainManager, configuration: ScrcpyConfiguration? = nil) {
        var config = configuration ?? ScrcpyConfiguration(serial: device.serial)
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
        guard state == .idle || state == .disconnected else {
            AppLogger.connection.warning("设备已连接或正在连接中")
            return
        }

        updateState(.connecting)
        AppLogger.connection.info("开始连接 Android 设备: \(configuration.serial)")

        // 检查 scrcpy 是否可用
        let scrcpyReady = await MainActor.run { toolchainManager.scrcpyStatus.isReady }
        guard scrcpyReady else {
            let error = DeviceSourceError.connectionFailed("scrcpy 未安装")
            updateState(.error(error))
            throw error
        }

        // 创建 VideoToolbox 解码器
        decoder = VideoToolboxDecoder(codecType: configuration.videoCodec.fourCC)
        decoder?.onDecodedFrame = { [weak self] pixelBuffer in
            self?.handleDecodedFrame(pixelBuffer)
        }

        updateState(.connected)
        AppLogger.connection.info("设备连接成功: \(displayName)")
    }

    override func disconnect() async {
        AppLogger.connection.info("断开连接: \(displayName)")

        monitorTask?.cancel()
        monitorTask = nil
        readTask?.cancel()
        readTask = nil

        await stopCapture()

        // 终止 scrcpy 进程
        if let process, process.isRunning {
            process.terminate()
            process.waitUntilExit()
        }
        process = nil

        // 清理解码器
        decoder = nil
        _latestPixelBuffer = nil

        updateState(.disconnected)
    }

    // MARK: - 捕获

    override func startCapture() async throws {
        guard state == .connected || state == .paused else {
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
        readTask?.cancel()
        readTask = nil

        // 终止 scrcpy 进程
        if let process, process.isRunning {
            process.terminate()
            process.waitUntilExit()
        }
        process = nil

        if state == .capturing {
            updateState(.connected)
        }

        AppLogger.capture.info("捕获已停止: \(displayName)")
    }

    // MARK: - Scrcpy 进程管理

    private func startScrcpyProcess() async throws {
        // 在主线程获取工具链路径
        let (scrcpyPath, adbPath, scrcpyServerPath) = await MainActor.run {
            (toolchainManager.scrcpyPath, toolchainManager.adbPath, toolchainManager.scrcpyServerPath)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: scrcpyPath)
        process.arguments = configuration.buildRawStreamArguments()

        // 设置环境变量（确保能找到 adb 和 scrcpy-server）
        var environment = ProcessInfo.processInfo.environment
        let adbDir = (adbPath as NSString).deletingLastPathComponent
        environment["PATH"] = "\(adbDir):/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
        environment["ADB"] = adbPath

        // 设置 scrcpy-server 路径（内置版本使用 portable 模式）
        if let serverPath = scrcpyServerPath {
            environment["SCRCPY_SERVER_PATH"] = serverPath
            AppLogger.process.info("使用 scrcpy-server: \(serverPath)")
        }

        process.environment = environment

        // 配置输出管道
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        AppLogger.process
            .info("启动 scrcpy: \(scrcpyPath) \(configuration.buildRawStreamArguments().joined(separator: " "))")

        try process.run()
        self.process = process

        // 启动视频流读取任务
        startVideoStreamReader(outputPipe: outputPipe)

        // 读取错误输出
        Task {
            for try await line in errorPipe.fileHandleForReading.bytes.lines {
                AppLogger.process.debug("[scrcpy stderr] \(line)")
            }
        }
    }

    /// 启动视频流读取
    private func startVideoStreamReader(outputPipe: Pipe) {
        readTask = Task { [weak self] in
            guard let self else { return }

            let fileHandle = outputPipe.fileHandleForReading

            // 读取视频流数据
            while !Task.isCancelled {
                do {
                    // 读取数据块
                    let data = fileHandle.availableData
                    if data.isEmpty {
                        try await Task.sleep(nanoseconds: 10_000_000) // 10ms
                        continue
                    }

                    // 送入解码器
                    await decoder?.decode(data: data)

                } catch {
                    if !Task.isCancelled {
                        AppLogger.capture.error("读取视频流失败: \(error.localizedDescription)")
                    }
                    break
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
            guard let self, let process else { return }

            // 等待进程退出
            await withCheckedContinuation { continuation in
                process.terminationHandler = { _ in
                    continuation.resume()
                }
            }

            let exitCode = process.terminationStatus

            await MainActor.run { [weak self] in
                guard let self else { return }

                if exitCode != 0, state != .disconnected {
                    AppLogger.connection.error("scrcpy 进程异常退出，退出码: \(exitCode)")
                    updateState(.error(.processTerminated(exitCode)))
                } else {
                    AppLogger.connection.info("scrcpy 进程正常退出")
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
    func decode(data: Data) async {
        // 解析 NAL 单元
        let nalUnits = nalParser.parse(data: data)

        for nalUnit in nalUnits {
            // 检查是否是参数集
            if nalUnit.isParameterSet {
                if !isInitialized {
                    // 尝试初始化解码器
                    if initializeDecoder(with: nalUnit) {
                        isInitialized = true
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

    /// 初始化解码器（使用参数集）
    private func initializeDecoder(with nalUnit: NALUnit) -> Bool {
        // 为简化实现，这里假设已经有了正确的参数集
        // 实际实现需要正确解析 SPS/PPS (H.264) 或 VPS/SPS/PPS (H.265)

        guard let sps = nalParser.sps, let pps = nalParser.pps else {
            return false
        }

        // 创建格式描述
        var formatDescription: CMFormatDescription?
        let status: OSStatus

        if codecType == kCMVideoCodecType_H264 {
            let parameterSetPointers: [UnsafePointer<UInt8>] = [
                sps.withUnsafeBytes { $0.baseAddress!.assumingMemoryBound(to: UInt8.self) },
                pps.withUnsafeBytes { $0.baseAddress!.assumingMemoryBound(to: UInt8.self) },
            ]
            let parameterSetSizes: [Int] = [sps.count, pps.count]

            status = CMVideoFormatDescriptionCreateFromH264ParameterSets(
                allocator: kCFAllocatorDefault,
                parameterSetCount: 2,
                parameterSetPointers: parameterSetPointers,
                parameterSetSizes: parameterSetSizes,
                nalUnitHeaderLength: 4,
                formatDescriptionOut: &formatDescription
            )
        } else {
            // H.265 需要 VPS
            guard let vps = nalParser.vps else { return false }

            let parameterSetPointers: [UnsafePointer<UInt8>] = [
                vps.withUnsafeBytes { $0.baseAddress!.assumingMemoryBound(to: UInt8.self) },
                sps.withUnsafeBytes { $0.baseAddress!.assumingMemoryBound(to: UInt8.self) },
                pps.withUnsafeBytes { $0.baseAddress!.assumingMemoryBound(to: UInt8.self) },
            ]
            let parameterSetSizes: [Int] = [vps.count, sps.count, pps.count]

            status = CMVideoFormatDescriptionCreateFromHEVCParameterSets(
                allocator: kCFAllocatorDefault,
                parameterSetCount: 3,
                parameterSetPointers: parameterSetPointers,
                parameterSetSizes: parameterSetSizes,
                nalUnitHeaderLength: 4,
                extensions: nil,
                formatDescriptionOut: &formatDescription
            )
        }

        guard status == noErr, let description = formatDescription else {
            AppLogger.capture.error("创建格式描述失败: \(status)")
            return false
        }

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
        var data = nalUnit.data

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
