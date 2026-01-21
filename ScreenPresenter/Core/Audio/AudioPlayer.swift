//
//  AudioPlayer.swift
//  ScreenPresenter
//
//  Created by Sun on 2026/1/6.
//
//  音频播放器
//  用于播放从设备捕获的音频流
//  支持音量控制、静音功能和缓冲调节
//

import AVFoundation
import CoreMedia
import Foundation

// MARK: - 音频播放器

/// 音频播放器
/// 使用 AVAudioEngine 播放从设备捕获的音频采样
/// 支持两种模式：
/// 1. 推送模式（直接调度缓冲区）- 简单但可能有抖动
/// 2. 拉取模式（通过 AudioRegulator）- 更平滑的播放体验
final class AudioPlayer {
    // MARK: - 常量

    /// 拉取模式缓冲区大小（帧数）
    /// 10ms @ 48kHz = 480 samples
    private static let pullBufferFrameCount: AVAudioFrameCount = 480

    // MARK: - 属性

    /// 音频引擎
    private var audioEngine: AVAudioEngine?

    /// 播放节点
    private var playerNode: AVAudioPlayerNode?

    /// 混音节点（用于音量控制）
    private var mixerNode: AVAudioMixerNode?

    /// 音频格式（输入格式，来自设备）
    private var audioFormat: AVAudioFormat?

    /// 播放格式（输出格式，用于 AVAudioEngine，始终为 Float32 non-interleaved）
    private var playbackFormat: AVAudioFormat?

    /// 音频格式转换器（当输入格式不是 Float32 时使用）
    private var audioConverter: AVAudioConverter?

    /// 是否正在播放
    private(set) var isPlaying = false

    /// 是否已初始化
    private(set) var isInitialized = false

    /// 音量 (0.0 - 1.0)
    var volume: Float = 1.0 {
        didSet {
            mixerNode?.outputVolume = isMuted ? 0 : volume
        }
    }

    /// 是否静音
    var isMuted: Bool = false {
        didSet {
            mixerNode?.outputVolume = isMuted ? 0 : volume
        }
    }

    /// 音频队列（用于缓冲）
    /// 注意：从 .userInteractive 降级为 .default，音频有缓冲可以稍微延迟
    private var audioQueue = DispatchQueue(label: "com.screenPresenter.audioPlayer", qos: .default)

    /// 缓冲区计数（用于调试）
    private var bufferCount = 0

    // MARK: - 音频调节器

    /// 音频调节器（可选，启用后使用拉取模式）
    private var audioRegulator: AudioRegulator?

    /// 是否使用拉取模式
    private var usePullMode = false

    /// 拉取定时器
    private var pullTimer: DispatchSourceTimer?

    /// 拉取模式的输出格式
    private var pullOutputFormat: AVAudioFormat?

    // MARK: - 初始化

    init() {}

    deinit {
        stop()
    }

    // MARK: - 公开方法

    /// 从 CMSampleBuffer 初始化音频格式
    /// - Parameter sampleBuffer: 包含音频格式信息的采样缓冲
    /// - Returns: 是否成功初始化
    @discardableResult
    func initializeFromSampleBuffer(_ sampleBuffer: CMSampleBuffer) -> Bool {
        guard !isInitialized else { return true }

        guard let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer) else {
            AppLogger.capture.error("[AudioPlayer] 无法获取格式描述")
            return false
        }

        // 获取 AudioStreamBasicDescription
        guard let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription) else {
            AppLogger.capture.error("[AudioPlayer] 无法获取 AudioStreamBasicDescription")
            return false
        }

        // 创建 AVAudioFormat（输入格式）
        guard let inputFormat = AVAudioFormat(streamDescription: asbd) else {
            AppLogger.capture.error("[AudioPlayer] 无法创建 AVAudioFormat")
            return false
        }

        audioFormat = inputFormat

        // 打印详细的格式信息用于调试
        let formatFlags = asbd.pointee.mFormatFlags
        let isFloat = (formatFlags & kAudioFormatFlagIsFloat) != 0
        let isSignedInt = (formatFlags & kAudioFormatFlagIsSignedInteger) != 0
        let bitsPerChannel = asbd.pointee.mBitsPerChannel

        AppLogger.capture.info("""
        [AudioPlayer] 输入格式详情:
        - 采样率: \(inputFormat.sampleRate)Hz
        - 声道数: \(inputFormat.channelCount)
        - 位深: \(bitsPerChannel) bits
        - 是否浮点: \(isFloat)
        - 是否有符号整数: \(isSignedInt)
        - 是否交错: \(inputFormat.isInterleaved)
        """)

        // 创建播放格式（始终使用 Float32 non-interleaved，AVAudioEngine 最佳兼容格式）
        guard
            let outputFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: inputFormat.sampleRate,
                channels: inputFormat.channelCount,
                interleaved: false
            ) else {
            AppLogger.capture.error("[AudioPlayer] 无法创建输出格式")
            return false
        }

        playbackFormat = outputFormat

        // 如果输入格式不是 Float32，创建转换器
        if !isFloat || bitsPerChannel != 32 || inputFormat.isInterleaved {
            guard let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
                AppLogger.capture.error("[AudioPlayer] 无法创建音频格式转换器")
                return false
            }
            audioConverter = converter
            AppLogger.capture
                .info("[AudioPlayer] 已创建格式转换器: \(bitsPerChannel)bit \(isFloat ? "Float" : "Int") -> 32bit Float")
        }

        // 设置音频引擎（使用 Float32 non-interleaved 格式）
        setupAudioEngine(format: outputFormat)

        isInitialized = true
        AppLogger.capture
            .info("[AudioPlayer] 已初始化，播放格式: \(outputFormat.sampleRate)Hz, \(outputFormat.channelCount)ch, Float32")

        return true
    }

    /// 启动播放
    func start() {
        guard isInitialized, !isPlaying else { return }

        do {
            try audioEngine?.start()
            playerNode?.play()
            isPlaying = true

            // 如果启用了调节器，启动拉取模式
            if usePullMode {
                startPullMode()
            }

            AppLogger.capture.info("[AudioPlayer] 开始播放 (模式: \(usePullMode ? "拉取" : "推送"))")
        } catch {
            AppLogger.capture.error("[AudioPlayer] 启动失败: \(error.localizedDescription)")
        }
    }

    /// 停止播放
    func stop() {
        guard isPlaying else { return }

        // 停止拉取定时器
        stopPullTimer()

        playerNode?.stop()
        audioEngine?.stop()
        isPlaying = false
        bufferCount = 0
        AppLogger.capture.info("[AudioPlayer] 停止播放")
    }

    /// 重置播放器
    func reset() {
        stop()

        // 重置调节器
        audioRegulator?.reset()

        audioEngine = nil
        playerNode = nil
        mixerNode = nil
        audioFormat = nil
        playbackFormat = nil
        audioConverter = nil
        isInitialized = false

        AppLogger.capture.info("[AudioPlayer] 已重置")
    }

    /// 处理音频采样缓冲
    /// - Parameter sampleBuffer: 从设备捕获的音频采样
    func processSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        // 确保已初始化
        if !isInitialized {
            if !initializeFromSampleBuffer(sampleBuffer) {
                return
            }
            start()
        }

        guard isPlaying, let playerNode, let playbackFormat else { return }

        // 使用 autoreleasepool 避免内存累积
        autoreleasepool {
            // 将 CMSampleBuffer 转换为 AVAudioPCMBuffer（带格式转换）
            guard let pcmBuffer = createPCMBufferFromSampleBuffer(sampleBuffer, outputFormat: playbackFormat) else {
                return
            }

            // 调度缓冲区播放
            playerNode.scheduleBuffer(pcmBuffer, completionHandler: nil)

            bufferCount += 1
        }
    }

    /// 从 AVAudioFormat 初始化播放器
    /// - Parameter format: 音频格式
    /// - Returns: 是否成功初始化
    @discardableResult
    func initializeFromFormat(_ format: AVAudioFormat) -> Bool {
        guard !isInitialized else { return true }

        // 保存原始格式（可能是 interleaved）
        audioFormat = format

        // 创建 AVAudioEngine 使用的 non-interleaved 格式
        // AVAudioEngine 默认需要 non-interleaved 格式
        let engineFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: format.sampleRate,
            channels: format.channelCount,
            interleaved: false
        )

        guard let engineFormat else {
            AppLogger.capture.error("[AudioPlayer] 无法创建 non-interleaved 格式")
            return false
        }

        // 设置音频引擎（使用 non-interleaved 格式）
        setupAudioEngine(format: engineFormat)

        isInitialized = true
        AppLogger.capture.info("[AudioPlayer] 已初始化，采样率: \(format.sampleRate)Hz, 声道: \(format.channelCount)")

        return true
    }

    /// 处理 PCM 数据
    /// - Parameters:
    ///   - data: PCM 音频数据（Float32 格式，interleaved）
    ///   - format: 音频格式
    func processPCMData(_ data: Data, format: AVAudioFormat) {
        // 确保已初始化
        if !isInitialized {
            if !initializeFromFormat(format) {
                return
            }
            start()
        }

        guard isPlaying, let playerNode else {
            return
        }

        // 如果使用拉取模式，将数据推送到调节器
        if usePullMode, let regulator = audioRegulator {
            regulator.push(data)
            return
        }

        // 推送模式：直接调度缓冲区
        autoreleasepool {
            // 将 interleaved Data 转换为 non-interleaved AVAudioPCMBuffer
            guard let pcmBuffer = createPCMBuffer(from: data, inputFormat: format) else {
                return
            }

            // 调度缓冲区播放
            playerNode.scheduleBuffer(pcmBuffer, completionHandler: nil)
            bufferCount += 1
        }
    }

    // MARK: - 拉取模式（AudioRegulator 集成）

    /// 启用音频调节器（拉取模式）
    /// - Parameters:
    ///   - sampleRate: 采样率
    ///   - channels: 声道数
    ///   - targetBufferingMs: 目标缓冲时长（毫秒）
    func enableRegulator(sampleRate: Int = 48000, channels: Int = 2, targetBufferingMs: Int = 50) {
        audioRegulator = AudioRegulator(
            targetBufferingMs: targetBufferingMs,
            sampleRate: sampleRate,
            channels: channels
        )
        usePullMode = true

        // 创建拉取模式的输出格式
        pullOutputFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Double(sampleRate),
            channels: AVAudioChannelCount(channels),
            interleaved: false
        )

        AppLogger.capture.info("[AudioPlayer] 已启用音频调节器，目标缓冲: \(targetBufferingMs)ms")
    }

    /// 禁用音频调节器
    func disableRegulator() {
        stopPullTimer()
        audioRegulator?.reset()
        audioRegulator = nil
        usePullMode = false
        pullOutputFormat = nil

        AppLogger.capture.info("[AudioPlayer] 已禁用音频调节器")
    }

    /// 启动拉取模式播放
    private func startPullMode() {
        guard usePullMode, let regulator = audioRegulator, let format = pullOutputFormat else {
            return
        }

        // 停止现有的定时器
        stopPullTimer()

        // 创建定时器，周期性拉取数据
        // 10ms 周期 @ 48kHz = 480 samples
        let sampleRate = Int(format.sampleRate)
        let channels = Int(format.channelCount)
        let samplesPerPeriod = sampleRate / 100 // 10ms
        let intervalMs = 10

        let timer = DispatchSource.makeTimerSource(queue: audioQueue)
        timer.schedule(deadline: .now(), repeating: .milliseconds(intervalMs))

        timer.setEventHandler { [weak self] in
            self?.pullAndScheduleAudio(
                regulator: regulator,
                format: format,
                sampleCount: samplesPerPeriod,
                channels: channels
            )
        }

        timer.resume()
        pullTimer = timer

        AppLogger.capture.info("[AudioPlayer] 拉取模式已启动，周期: \(intervalMs)ms, 每次 \(samplesPerPeriod) 样本")
    }

    /// 停止拉取定时器
    private func stopPullTimer() {
        pullTimer?.cancel()
        pullTimer = nil
    }

    /// 拉取音频数据并调度播放
    private func pullAndScheduleAudio(
        regulator: AudioRegulator,
        format: AVAudioFormat,
        sampleCount: Int,
        channels: Int
    ) {
        guard isPlaying, let playerNode else { return }

        // 从调节器拉取数据
        let samples = regulator.pull(sampleCount: sampleCount)

        // 如果没有数据，跳过（静音）
        if samples.isEmpty {
            return
        }

        // 转换为 AVAudioPCMBuffer
        guard
            let pcmBuffer = createPCMBuffer(
                fromInterleavedSamples: samples,
                format: format,
                channels: channels
            ) else {
            return
        }

        // 调度播放
        playerNode.scheduleBuffer(pcmBuffer, completionHandler: nil)
    }

    /// 从 interleaved Float 样本创建 non-interleaved PCM 缓冲区
    private func createPCMBuffer(
        fromInterleavedSamples samples: [Float],
        format: AVAudioFormat,
        channels: Int
    ) -> AVAudioPCMBuffer? {
        let frameCount = samples.count / channels
        guard frameCount > 0 else { return nil }

        guard
            let pcmBuffer = AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: AVAudioFrameCount(frameCount)
            ) else {
            return nil
        }
        pcmBuffer.frameLength = AVAudioFrameCount(frameCount)

        // 分离声道：interleaved -> non-interleaved
        for channel in 0..<channels {
            guard let channelData = pcmBuffer.floatChannelData?[channel] else { continue }
            for frame in 0..<frameCount {
                channelData[frame] = samples[frame * channels + channel]
            }
        }

        return pcmBuffer
    }

    // MARK: - 私有方法

    private func setupAudioEngine(format: AVAudioFormat) {
        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        let mixer = AVAudioMixerNode()

        engine.attach(player)
        engine.attach(mixer)

        // 连接节点：player -> mixer -> output
        // 使用指定的格式连接 player 到 mixer
        engine.connect(player, to: mixer, format: format)

        // 连接 mixer 到 output 时使用 nil 格式，让 AVAudioEngine 自动处理格式转换
        // 这可以避免格式不兼容的问题
        engine.connect(mixer, to: engine.outputNode, format: nil)

        // 设置音量
        mixer.outputVolume = isMuted ? 0 : volume

        audioEngine = engine
        playerNode = player
        mixerNode = mixer
    }

    /// 从 CMSampleBuffer 创建 PCM 缓冲区（带格式转换）
    /// 支持 Int16/Int32/Float32 输入，统一输出为 Float32 non-interleaved
    /// - Parameters:
    ///   - sampleBuffer: 输入的音频采样缓冲
    ///   - outputFormat: 输出格式（Float32 non-interleaved）
    /// - Returns: 转换后的 PCM 缓冲区
    private func createPCMBufferFromSampleBuffer(
        _ sampleBuffer: CMSampleBuffer,
        outputFormat: AVAudioFormat
    ) -> AVAudioPCMBuffer? {
        // 获取采样数量
        let numSamples = CMSampleBufferGetNumSamples(sampleBuffer)
        guard numSamples > 0 else { return nil }

        // 获取音频数据
        guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else {
            return nil
        }

        var length = 0
        var dataPointer: UnsafeMutablePointer<Int8>?

        let status = CMBlockBufferGetDataPointer(
            blockBuffer,
            atOffset: 0,
            lengthAtOffsetOut: nil,
            totalLengthOut: &length,
            dataPointerOut: &dataPointer
        )

        guard status == kCMBlockBufferNoErr, let data = dataPointer else {
            return nil
        }

        // 如果有转换器，使用转换器进行格式转换
        if let converter = audioConverter, let inputFormat = audioFormat {
            return convertAudioData(
                data: data,
                length: length,
                inputFormat: inputFormat,
                outputFormat: outputFormat,
                frameCount: numSamples,
                converter: converter
            )
        }

        // 没有转换器意味着输入已经是 Float32 格式，直接创建 buffer
        guard
            let pcmBuffer = AVAudioPCMBuffer(
                pcmFormat: outputFormat,
                frameCapacity: AVAudioFrameCount(numSamples)
            ) else {
            return nil
        }
        pcmBuffer.frameLength = AVAudioFrameCount(numSamples)

        // 直接复制 Float32 数据（需要处理 interleaved -> non-interleaved）
        let channelCount = Int(outputFormat.channelCount)
        let srcPtr = UnsafeRawPointer(data).assumingMemoryBound(to: Float.self)

        if let inputFormat = audioFormat, inputFormat.isInterleaved {
            // 输入是 interleaved，需要分离声道
            for channel in 0..<channelCount {
                guard let channelData = pcmBuffer.floatChannelData?[channel] else { continue }
                for frame in 0..<numSamples {
                    channelData[frame] = srcPtr[frame * channelCount + channel]
                }
            }
        } else {
            // 输入已经是 non-interleaved
            for channel in 0..<channelCount {
                guard let channelData = pcmBuffer.floatChannelData?[channel] else { continue }
                let srcChannel = srcPtr.advanced(by: channel * numSamples)
                memcpy(channelData, srcChannel, numSamples * MemoryLayout<Float>.size)
            }
        }

        return pcmBuffer
    }

    /// 使用 AVAudioConverter 进行音频格式转换
    /// - Parameters:
    ///   - data: 原始音频数据指针
    ///   - length: 数据长度
    ///   - inputFormat: 输入格式
    ///   - outputFormat: 输出格式
    ///   - frameCount: 帧数
    ///   - converter: 音频转换器
    /// - Returns: 转换后的 PCM 缓冲区
    private func convertAudioData(
        data: UnsafeMutablePointer<Int8>,
        length: Int,
        inputFormat: AVAudioFormat,
        outputFormat: AVAudioFormat,
        frameCount: Int,
        converter: AVAudioConverter
    ) -> AVAudioPCMBuffer? {
        // 创建输入缓冲区
        guard
            let inputBuffer = AVAudioPCMBuffer(
                pcmFormat: inputFormat,
                frameCapacity: AVAudioFrameCount(frameCount)
            ) else {
            return nil
        }
        inputBuffer.frameLength = AVAudioFrameCount(frameCount)

        // 复制数据到输入缓冲区
        let channelCount = Int(inputFormat.channelCount)
        if inputFormat.isInterleaved {
            // 交错格式：数据按 [L0 R0 L1 R1 ...] 排列
            if inputFormat.commonFormat == .pcmFormatInt16 {
                if let channelData = inputBuffer.int16ChannelData?[0] {
                    memcpy(channelData, data, length)
                }
            } else if inputFormat.commonFormat == .pcmFormatInt32 {
                if let channelData = inputBuffer.int32ChannelData?[0] {
                    memcpy(channelData, data, length)
                }
            } else if inputFormat.commonFormat == .pcmFormatFloat32 {
                if let channelData = inputBuffer.floatChannelData?[0] {
                    memcpy(channelData, data, length)
                }
            }
        } else {
            // 非交错格式：每个声道的数据连续存储
            let bytesPerSample = Int(inputFormat.streamDescription.pointee.mBytesPerFrame) / channelCount
            let samplesPerChannel = frameCount

            for channel in 0..<channelCount {
                let srcOffset = channel * samplesPerChannel * bytesPerSample
                if inputFormat.commonFormat == .pcmFormatInt16 {
                    if let channelData = inputBuffer.int16ChannelData?[channel] {
                        memcpy(channelData, data.advanced(by: srcOffset), samplesPerChannel * bytesPerSample)
                    }
                } else if inputFormat.commonFormat == .pcmFormatInt32 {
                    if let channelData = inputBuffer.int32ChannelData?[channel] {
                        memcpy(channelData, data.advanced(by: srcOffset), samplesPerChannel * bytesPerSample)
                    }
                } else if inputFormat.commonFormat == .pcmFormatFloat32 {
                    if let channelData = inputBuffer.floatChannelData?[channel] {
                        memcpy(channelData, data.advanced(by: srcOffset), samplesPerChannel * bytesPerSample)
                    }
                }
            }
        }

        // 创建输出缓冲区
        guard
            let outputBuffer = AVAudioPCMBuffer(
                pcmFormat: outputFormat,
                frameCapacity: AVAudioFrameCount(frameCount)
            ) else {
            return nil
        }

        // 执行格式转换
        var error: NSError?
        let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
            outStatus.pointee = .haveData
            return inputBuffer
        }

        let conversionStatus = converter.convert(to: outputBuffer, error: &error, withInputFrom: inputBlock)

        if conversionStatus == .error {
            AppLogger.capture.error("[AudioPlayer] 音频格式转换失败: \(error?.localizedDescription ?? "未知错误")")
            return nil
        }

        return outputBuffer
    }

    // MARK: - 旧方法（保留给其他可能的调用者，但 iOS 不再使用）

    private func createPCMBuffer(from sampleBuffer: CMSampleBuffer, format: AVAudioFormat) -> AVAudioPCMBuffer? {
        // 获取采样数量
        let numSamples = CMSampleBufferGetNumSamples(sampleBuffer)
        guard numSamples > 0 else { return nil }

        // 创建 PCM 缓冲区
        guard let pcmBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(numSamples)) else {
            return nil
        }
        pcmBuffer.frameLength = AVAudioFrameCount(numSamples)

        // 获取音频数据
        guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else {
            return nil
        }

        var length = 0
        var dataPointer: UnsafeMutablePointer<Int8>?

        let status = CMBlockBufferGetDataPointer(
            blockBuffer,
            atOffset: 0,
            lengthAtOffsetOut: nil,
            totalLengthOut: &length,
            dataPointerOut: &dataPointer
        )

        guard status == kCMBlockBufferNoErr, let data = dataPointer else {
            return nil
        }

        // 根据格式复制数据
        if format.isInterleaved {
            // 交错格式：直接复制
            if let channelData = pcmBuffer.floatChannelData?[0] {
                memcpy(channelData, data, length)
            } else if let channelData = pcmBuffer.int16ChannelData?[0] {
                memcpy(channelData, data, length)
            } else if let channelData = pcmBuffer.int32ChannelData?[0] {
                memcpy(channelData, data, length)
            }
        } else {
            // 非交错格式：分别复制每个声道
            let bytesPerFrame = Int(format.streamDescription.pointee.mBytesPerFrame)
            let channelCount = Int(format.channelCount)
            let framesPerChannel = length / bytesPerFrame / channelCount

            for channel in 0..<channelCount {
                if let channelData = pcmBuffer.floatChannelData?[channel] {
                    let sourceOffset = channel * framesPerChannel * MemoryLayout<Float>.size
                    memcpy(channelData, data.advanced(by: sourceOffset), framesPerChannel * MemoryLayout<Float>.size)
                }
            }
        }

        return pcmBuffer
    }

    /// 从 Data 创建 PCM 缓冲区
    /// 输入是 interleaved Float32 数据，输出是 non-interleaved AVAudioPCMBuffer
    private func createPCMBuffer(from data: Data, inputFormat: AVAudioFormat) -> AVAudioPCMBuffer? {
        let channelCount = Int(inputFormat.channelCount)
        let bytesPerSample = 4 // Float32 = 4 bytes
        let bytesPerFrame = bytesPerSample * channelCount

        let frameCount = data.count / bytesPerFrame
        guard frameCount > 0 else {
            return nil
        }

        // 创建 non-interleaved 格式的 PCM 缓冲区
        guard
            let outputFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: inputFormat.sampleRate,
                channels: AVAudioChannelCount(channelCount),
                interleaved: false
            ) else {
            return nil
        }

        guard let pcmBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: AVAudioFrameCount(frameCount))
        else {
            return nil
        }
        pcmBuffer.frameLength = AVAudioFrameCount(frameCount)

        // 从 interleaved 转换为 non-interleaved
        data.withUnsafeBytes { ptr in
            guard let srcBase = ptr.baseAddress else { return }
            let srcPtr = srcBase.assumingMemoryBound(to: Float.self)

            // 分离声道数据
            // 输入：[L0 R0 L1 R1 L2 R2 ...]
            // 输出：channel[0] = [L0 L1 L2 ...], channel[1] = [R0 R1 R2 ...]
            for channel in 0..<channelCount {
                guard let channelData = pcmBuffer.floatChannelData?[channel] else { continue }
                for frame in 0..<frameCount {
                    channelData[frame] = srcPtr[frame * channelCount + channel]
                }
            }
        }

        return pcmBuffer
    }
}
