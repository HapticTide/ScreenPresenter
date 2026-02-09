//
//  VideoToolboxDecoder.swift
//  ScreenPresenter
//
//  Created by Sun on 2025/12/24.
//
//  VideoToolbox 硬件解码器
//  使用 Apple VideoToolbox 进行 H.264/H.265 硬件加速解码
//

import CoreMedia
import CoreVideo
import Foundation
import QuartzCore
import VideoToolbox

// MARK: - 解码器状态

/// VideoToolbox 解码器状态
enum VideoToolboxDecoderState {
    case idle
    case ready
    case decoding
    case error(Error)
}

// MARK: - 解码器错误

/// VideoToolbox 解码器错误
enum VideoToolboxDecoderError: LocalizedError {
    case formatDescriptionCreationFailed(OSStatus)
    case sessionCreationFailed(OSStatus)
    case blockBufferCreationFailed(OSStatus)
    case sampleBufferCreationFailed(OSStatus)
    case decodeFailed(OSStatus)
    case missingParameterSets

    var errorDescription: String? {
        switch self {
        case let .formatDescriptionCreationFailed(status):
            "格式描述创建失败，错误码: \(status)"
        case let .sessionCreationFailed(status):
            "解码会话创建失败，错误码: \(status)"
        case let .blockBufferCreationFailed(status):
            "BlockBuffer 创建失败，错误码: \(status)"
        case let .sampleBufferCreationFailed(status):
            "SampleBuffer 创建失败，错误码: \(status)"
        case let .decodeFailed(status):
            "解码失败，错误码: \(status)"
        case .missingParameterSets:
            "缺少参数集（SPS/PPS）"
        }
    }
}

// MARK: - VideoToolbox 解码器

/// VideoToolbox 硬件解码器
/// 接收 AVCC 格式的编码数据，输出 CVPixelBuffer
final class VideoToolboxDecoder {
    // MARK: - 属性

    /// 编解码类型
    private let codecType: CMVideoCodecType

    /// 格式描述
    private var formatDescription: CMVideoFormatDescription?

    /// 解压缩会话
    private var decompressionSession: VTDecompressionSession?

    /// 当前状态
    private(set) var state: VideoToolboxDecoderState = .idle

    /// 解码队列
    private let decodeQueue = DispatchQueue(
        label: "com.screenPresenter.videoToolbox.decode",
        qos: .userInteractive
    )
    private static let decodeQueueKey = DispatchSpecificKey<Void>()

    /// 状态锁
    private let stateLock = NSLock()

    /// 解码后的帧回调（在 decodeQueue 上调用）
    var onDecodedFrame: ((CVPixelBuffer) -> Void)?

    /// 回调状态锁
    private let callbackStateLock = NSLock()

    /// 回调是否启用（用于停止期 fence）
    private var callbacksEnabled = true

    /// 回调代际令牌（用于丢弃停用前的回调）
    private var callbackToken: UInt64 = 0

    /// 解码统计
    private(set) var decodedFrameCount = 0
    private(set) var failedFrameCount = 0
    private(set) var droppedFrameCount = 0

    // MARK: - 丢帧策略

    /// 最大待解码帧数（超过此值将丢弃非关键帧）
    /// 提升阈值以避免过度丢帧，同时配合 VCL 过滤使用
    private let maxPendingFrames = 8

    /// 当前待解码帧计数
    private var pendingFrameCount = 0

    /// 待解码帧计数锁
    private let pendingLock = NSLock()

    /// 上次统计日志时间
    private var lastStatsLogTime = CFAbsoluteTimeGetCurrent()

    /// 统计周期内的解码帧数
    private var decodedInPeriod = 0

    /// 统计周期内的丢弃帧数
    private var droppedInPeriod = 0
    
    // MARK: - 调试统计
    
    /// 解码耗时累计
    private var totalDecodeTime: Double = 0
    
    /// 最大解码耗时
    private var maxDecodeTime: Double = 0
    
    /// 解码调用次数（周期内）
    private var decodeCallsInPeriod: Int = 0
    
    /// 解码成功回调时间统计
    private var callbackTimes: [Double] = []
    
    /// 上次解码完成时间
    private var lastDecodeCompleteTime = CFAbsoluteTimeGetCurrent()
    
    /// 最大解码完成间隔
    private var maxDecodeInterval: Double = 0
    
    /// 队列积压警告阈值
    private let queueWarningThreshold = 4

    // MARK: - 初始化

    /// 初始化解码器
    /// - Parameter codecType: 编解码类型（kCMVideoCodecType_H264 或 kCMVideoCodecType_HEVC）
    init(codecType: CMVideoCodecType) {
        self.codecType = codecType
        decodeQueue.setSpecific(key: Self.decodeQueueKey, value: ())
        AppLogger.capture.info("[VTDecoder] 初始化，编解码器: \(codecType == kCMVideoCodecType_H264 ? "H.264" : "H.265")")
    }

    deinit {
        invalidateSession()
        AppLogger.capture
            .info("[VTDecoder] 销毁，解码: \(decodedFrameCount), 失败: \(failedFrameCount), 丢弃: \(droppedFrameCount)")
    }

    // MARK: - 公开方法

    /// 使用 H.264 参数集初始化解码器
    /// - Parameters:
    ///   - sps: SPS 数据
    ///   - pps: PPS 数据
    func initializeH264(sps: Data, pps: Data) throws {
        AppLogger.capture.info("[VTDecoder] 使用 H.264 参数集初始化，SPS: \(sps.count)B, PPS: \(pps.count)B")

        guard let formatDesc = VideoFormatDescriptionFactory.createH264FormatDescription(sps: sps, pps: pps) else {
            AppLogger.capture.error("[VTDecoder] H.264 格式描述创建失败")
            throw VideoToolboxDecoderError.formatDescriptionCreationFailed(-1)
        }

        formatDescription = formatDesc
        try createDecompressionSession(formatDescription: formatDesc)

        updateState(.ready)
        AppLogger.capture.info("[VTDecoder] H.264 解码器初始化成功")
    }

    /// 使用 H.265 参数集初始化解码器
    /// - Parameters:
    ///   - vps: VPS 数据
    ///   - sps: SPS 数据
    ///   - pps: PPS 数据
    func initializeH265(vps: Data, sps: Data, pps: Data) throws {
        AppLogger.capture.info("[VTDecoder] 使用 H.265 参数集初始化，VPS: \(vps.count)B, SPS: \(sps.count)B, PPS: \(pps.count)B")

        guard let formatDesc = VideoFormatDescriptionFactory.createH265FormatDescription(vps: vps, sps: sps, pps: pps)
        else {
            throw VideoToolboxDecoderError.formatDescriptionCreationFailed(-1)
        }

        formatDescription = formatDesc
        try createDecompressionSession(formatDescription: formatDesc)

        updateState(.ready)
        AppLogger.capture.info("[VTDecoder] ✅ H.265 解码器初始化成功")
    }

    /// 解码 NAL 单元
    /// - Parameters:
    ///   - nalUnit: 解析后的 NAL 单元
    ///   - presentationTime: 显示时间（可选）
    func decode(nalUnit: ParsedNALUnit, presentationTime: CMTime? = nil) {
        // 跳过参数集
        guard !nalUnit.isParameterSet else { return }

        // 丢帧策略：如果待解码帧过多，丢弃非关键帧
        pendingLock.lock()
        let currentPending = pendingFrameCount
        pendingLock.unlock()

        if currentPending > maxPendingFrames, !nalUnit.isKeyFrame {
            droppedFrameCount += 1
            droppedInPeriod += 1
            return
        }

        pendingLock.lock()
        pendingFrameCount += 1
        pendingLock.unlock()

        decodeCallsInPeriod += 1

        // 定期重置统计（保留内部统计逻辑，移除日志输出）
        let now = CFAbsoluteTimeGetCurrent()
        if now - lastStatsLogTime >= 5.0 {
            // 重置周期统计
            lastStatsLogTime = now
            decodedInPeriod = 0
            droppedInPeriod = 0
            decodeCallsInPeriod = 0
            totalDecodeTime = 0
            maxDecodeTime = 0
            maxDecodeInterval = 0
        }

        decodeQueue.async { [weak self] in
            guard let self else { return }
            
            let decodeStartTime = CFAbsoluteTimeGetCurrent()
            
            defer {
                pendingLock.lock()
                pendingFrameCount -= 1
                pendingLock.unlock()
                
                // 统计解码耗时
                let decodeTime = (CFAbsoluteTimeGetCurrent() - decodeStartTime) * 1000
                totalDecodeTime += decodeTime
                maxDecodeTime = max(maxDecodeTime, decodeTime)
                
                // 统计解码间隔
                let interval = (CFAbsoluteTimeGetCurrent() - lastDecodeCompleteTime) * 1000
                maxDecodeInterval = max(maxDecodeInterval, interval)
                lastDecodeCompleteTime = CFAbsoluteTimeGetCurrent()
            }
            decodeNALUnitSync(nalUnit: nalUnit, presentationTime: presentationTime)
        }
    }

    /// 解码 AVCC 格式数据
    /// - Parameters:
    ///   - avccData: AVCC 格式的编码数据（4字节长度前缀 + NAL 数据）
    ///   - isKeyFrame: 是否为关键帧
    ///   - presentationTime: 显示时间（可选）
    func decode(avccData: Data, isKeyFrame: Bool, presentationTime: CMTime? = nil) {
        decodeQueue.async { [weak self] in
            // 使用 autoreleasepool 确保每帧解码过程中创建的临时对象及时释放
            // 避免在高频解码循环中 autorelease 对象堆积导致内存缓慢增长
            autoreleasepool {
                self?.decodeAVCCDataSync(avccData: avccData, isKeyFrame: isKeyFrame, presentationTime: presentationTime)
            }
        }
    }

    /// 刷新解码器（等待所有帧解码完成）
    func flush() {
        decodeQueueSync { [weak self] in
            guard let session = self?.decompressionSession else { return }
            VTDecompressionSessionWaitForAsynchronousFrames(session)
        }
    }

    /// 启用解码回调（用于恢复捕获）
    func activateCallbacks() {
        setCallbacksEnabled(true)
    }

    /// 停止期 fence：禁用回调并等待队列清空
    func stopAndDrain(clearCallback: Bool = false) {
        setCallbacksEnabled(false)
        if clearCallback {
            onDecodedFrame = nil
        }
        flush()
        // 确保 decodeQueue 中待执行任务已清空
        decodeQueueSync { }
    }

    /// 重置解码器
    func reset() {
        stopAndDrain()
        invalidateSession()
        formatDescription = nil
        decodedFrameCount = 0
        failedFrameCount = 0
        droppedFrameCount = 0
        decodedInPeriod = 0
        droppedInPeriod = 0
        lastStatsLogTime = CFAbsoluteTimeGetCurrent()
        pendingLock.lock()
        pendingFrameCount = 0
        pendingLock.unlock()
        updateState(.idle)
        AppLogger.capture.info("[VTDecoder] 已重置")
    }

    /// 解码器是否已就绪
    var isReady: Bool {
        if case .ready = state { return true }
        if case .decoding = state { return true }
        return false
    }

    // MARK: - 私有方法

    /// 更新状态
    private func updateState(_ newState: VideoToolboxDecoderState) {
        stateLock.lock()
        state = newState
        stateLock.unlock()
    }

    private func setCallbacksEnabled(_ enabled: Bool) {
        callbackStateLock.lock()
        callbacksEnabled = enabled
        callbackToken &+= 1
        callbackStateLock.unlock()
    }

    private func getCallbackState() -> (enabled: Bool, token: UInt64) {
        callbackStateLock.lock()
        let state = (callbacksEnabled, callbackToken)
        callbackStateLock.unlock()
        return state
    }

    private func decodeQueueSync(_ block: () -> Void) {
        if DispatchQueue.getSpecific(key: Self.decodeQueueKey) != nil {
            block()
        } else {
            decodeQueue.sync(execute: block)
        }
    }

    private func handleDecodedCallback(status: OSStatus, imageBuffer: CVImageBuffer?) {
        let state = getCallbackState()
        guard state.enabled else { return }

        if status != noErr || imageBuffer == nil {
            decodeQueue.async { [weak self] in
                guard let self else { return }
                let current = self.getCallbackState()
                guard current.enabled, current.token == state.token else { return }
                self.failedFrameCount += 1
            }
            return
        }

        guard let buffer = imageBuffer else { return }
        let retainedBufferRef = Unmanaged.passRetained(buffer).toOpaque()

        decodeQueue.async { [weak self] in
            let retainedBuffer = Unmanaged<CVImageBuffer>.fromOpaque(retainedBufferRef)
            let buffer = retainedBuffer.takeUnretainedValue()
            defer { retainedBuffer.release() }

            guard let self else { return }

            let current = self.getCallbackState()
            guard current.enabled, current.token == state.token else {
                return
            }

            self.decodedFrameCount += 1
            self.decodedInPeriod += 1
            self.onDecodedFrame?(buffer)
        }
    }

    /// 创建解压缩会话
    private func createDecompressionSession(formatDescription: CMFormatDescription) throws {
        // 先销毁旧的会话
        invalidateSession()

        // 输出配置
        let outputPixelBufferAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferMetalCompatibilityKey as String: true,
        ]

        // 创建回调
        var outputCallback = VTDecompressionOutputCallbackRecord(
            decompressionOutputCallback: { refcon, _, status, _, imageBuffer, _, _ in
                guard let refcon else { return }

                let decoder = Unmanaged<VideoToolboxDecoder>.fromOpaque(refcon).takeUnretainedValue()

                decoder.handleDecodedCallback(status: status, imageBuffer: imageBuffer)
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
            throw VideoToolboxDecoderError.sessionCreationFailed(status)
        }

        decompressionSession = session
        AppLogger.capture.info("[VTDecoder] 解压缩会话已创建")
    }

    /// 销毁解压缩会话
    private func invalidateSession() {
        if let session = decompressionSession {
            // 等待所有异步帧解码完成，避免回调访问已释放的内存
            VTDecompressionSessionWaitForAsynchronousFrames(session)
            VTDecompressionSessionInvalidate(session)
            decompressionSession = nil
            AppLogger.capture.info("[VTDecoder] 解压缩会话已销毁")
        }
    }

    /// 同步解码 NAL 单元
    private func decodeNALUnitSync(nalUnit: ParsedNALUnit, presentationTime: CMTime?) {
        // 转换为 AVCC 格式
        let avccData = AnnexBToAVCCConverter.convert(nalUnit.data)
        decodeAVCCDataSync(avccData: avccData, isKeyFrame: nalUnit.isKeyFrame, presentationTime: presentationTime)
    }

    /// 同步解码 AVCC 数据
    private func decodeAVCCDataSync(avccData: Data, isKeyFrame: Bool, presentationTime: CMTime?) {
        guard let session = decompressionSession, let formatDesc = formatDescription else {
            return
        }

        updateState(.decoding)

        // 创建 CMBlockBuffer
        var blockBuffer: CMBlockBuffer?

        let blockBufferStatus = avccData.withUnsafeBytes { buffer -> OSStatus in
            // 必须复制数据，因为 CMBlockBuffer 不拥有数据
            CMBlockBufferCreateWithMemoryBlock(
                allocator: kCFAllocatorDefault,
                memoryBlock: nil,
                blockLength: buffer.count,
                blockAllocator: kCFAllocatorDefault,
                customBlockSource: nil,
                offsetToData: 0,
                dataLength: buffer.count,
                flags: 0,
                blockBufferOut: &blockBuffer
            )
        }

        guard blockBufferStatus == kCMBlockBufferNoErr, let buffer = blockBuffer else {
            failedFrameCount += 1
            return
        }

        // 复制数据到 block buffer
        var didCopyBytes = false
        avccData.withUnsafeBytes { dataBuffer in
            guard let baseAddress = dataBuffer.baseAddress else { return }
            _ = CMBlockBufferReplaceDataBytes(
                with: baseAddress,
                blockBuffer: buffer,
                offsetIntoDestination: 0,
                dataLength: dataBuffer.count
            )
            didCopyBytes = true
        }
        guard didCopyBytes else {
            failedFrameCount += 1
            return
        }

        // 创建 CMSampleBuffer
        var sampleBuffer: CMSampleBuffer?
        let pts = presentationTime ?? CMTime(value: Int64(CACurrentMediaTime() * 1_000_000), timescale: 1_000_000)

        var timingInfo = CMSampleTimingInfo(
            duration: CMTime.invalid,
            presentationTimeStamp: pts,
            decodeTimeStamp: CMTime.invalid
        )

        var sampleSize = avccData.count
        let sampleBufferStatus = CMSampleBufferCreateReady(
            allocator: kCFAllocatorDefault,
            dataBuffer: buffer,
            formatDescription: formatDesc,
            sampleCount: 1,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timingInfo,
            sampleSizeEntryCount: 1,
            sampleSizeArray: &sampleSize,
            sampleBufferOut: &sampleBuffer
        )

        guard sampleBufferStatus == noErr, let sample = sampleBuffer else {
            failedFrameCount += 1
            return
        }

        // 设置关键帧标记
        if isKeyFrame {
            let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: true)
            if let attachments, CFArrayGetCount(attachments) > 0 {
                let dict = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0), to: CFMutableDictionary.self)
                CFDictionarySetValue(
                    dict,
                    Unmanaged.passUnretained(kCMSampleAttachmentKey_NotSync).toOpaque(),
                    Unmanaged.passUnretained(kCFBooleanFalse).toOpaque()
                )
            }
        }

        // 解码
        let decodeFlags: VTDecodeFrameFlags = [._EnableAsynchronousDecompression]
        var infoFlags: VTDecodeInfoFlags = []

        let decodeStatus = VTDecompressionSessionDecodeFrame(
            session,
            sampleBuffer: sample,
            flags: decodeFlags,
            frameRefcon: nil,
            infoFlagsOut: &infoFlags
        )

        if decodeStatus != noErr {
            failedFrameCount += 1
            AppLogger.capture.warning("[VTDecoder] 解码失败: \(decodeStatus)")
        }
    }
}
