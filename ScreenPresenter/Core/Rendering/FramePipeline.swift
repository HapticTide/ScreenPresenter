//
//  FramePipeline.swift
//  ScreenPresenter
//
//  Created by Sun on 2026/1/5.
//
//  帧管道协议
//  参照 scrcpy 的 trait 模式设计，实现清晰的生产者-消费者模式
//
//  设计理念:
//  1. FrameSource: 帧生产者（解码器产出帧）
//  2. FrameSink: 帧消费者（渲染器接收帧）
//  3. FrameBuffer: 单帧缓冲，实现"最新帧优先"策略
//  4. 事件合并: 避免主线程任务堆积
//

import AVFoundation
import CoreVideo
import Foundation

// MARK: - 帧数据

/// 帧数据结构
struct VideoFrame {
    /// 像素缓冲区
    let pixelBuffer: CVPixelBuffer

    /// 呈现时间戳
    let presentationTime: CMTime

    /// 帧尺寸
    var size: CGSize {
        CGSize(
            width: CVPixelBufferGetWidth(pixelBuffer),
            height: CVPixelBufferGetHeight(pixelBuffer)
        )
    }

    /// 创建时间（用于延迟统计）
    let creationTime: CFAbsoluteTime

    init(pixelBuffer: CVPixelBuffer, presentationTime: CMTime = .zero) {
        self.pixelBuffer = pixelBuffer
        self.presentationTime = presentationTime
        creationTime = CFAbsoluteTimeGetCurrent()
    }
}

// MARK: - 帧消费者协议 (Frame Sink Trait)

/// 帧消费者协议
/// 能够接收和处理帧的组件应实现此协议
protocol FrameSink: AnyObject {
    /// 打开帧接收器
    /// - Parameter size: 初始帧尺寸
    /// - Returns: 是否成功打开
    func open(size: CGSize) -> Bool

    /// 关闭帧接收器
    func close()

    /// 推送帧
    /// - Parameter frame: 要处理的帧
    /// - Returns: 是否成功处理
    @discardableResult
    func push(_ frame: VideoFrame) -> Bool
}

// MARK: - 帧生产者协议 (Frame Source Trait)

/// 帧生产者协议
/// 能够产出帧的组件应实现此协议
protocol FrameSource: AnyObject {
    /// 注册的帧消费者
    var sinks: [FrameSink] { get }

    /// 添加帧消费者
    func addSink(_ sink: FrameSink)

    /// 移除帧消费者
    func removeSink(_ sink: FrameSink)

    /// 向所有消费者推送帧
    func pushToSinks(_ frame: VideoFrame) -> Bool
}

// MARK: - 帧生产者默认实现

/// 帧生产者基类
/// 管理多个帧消费者，实现广播分发
class BaseFrameSource: FrameSource {
    /// 最大消费者数量（与 scrcpy 一致）
    static let maxSinks = 2

    /// 注册的帧消费者
    private(set) var sinks: [FrameSink] = []

    /// 线程锁
    private let lock = NSLock()

    /// 添加帧消费者
    func addSink(_ sink: FrameSink) {
        lock.lock()
        defer { lock.unlock() }

        guard sinks.count < Self.maxSinks else {
            AppLogger.rendering.warning("帧消费者数量已达上限: \(Self.maxSinks)")
            return
        }

        sinks.append(sink)
        AppLogger.rendering.info("添加帧消费者，当前数量: \(sinks.count)")
    }

    /// 移除帧消费者
    func removeSink(_ sink: FrameSink) {
        lock.lock()
        defer { lock.unlock() }

        sinks.removeAll { $0 === sink }
        AppLogger.rendering.info("移除帧消费者，剩余数量: \(sinks.count)")
    }

    /// 向所有消费者推送帧
    @discardableResult
    func pushToSinks(_ frame: VideoFrame) -> Bool {
        lock.lock()
        let currentSinks = sinks
        lock.unlock()

        guard !currentSinks.isEmpty else {
            return true
        }

        for sink in currentSinks {
            if !sink.push(frame) {
                return false
            }
        }

        return true
    }

    /// 打开所有消费者
    func openSinks(size: CGSize) -> Bool {
        lock.lock()
        let currentSinks = sinks
        lock.unlock()

        for (index, sink) in currentSinks.enumerated() {
            if !sink.open(size: size) {
                // 关闭已打开的消费者
                for i in 0..<index {
                    currentSinks[i].close()
                }
                return false
            }
        }

        return true
    }

    /// 关闭所有消费者
    func closeSinks() {
        lock.lock()
        let currentSinks = sinks
        lock.unlock()

        for sink in currentSinks {
            sink.close()
        }
    }
}

// MARK: - 帧缓冲消费者

/// 带缓冲的帧消费者
/// 实现单帧缓冲 + 事件合并机制
/// 参照 scrcpy 的 frame_buffer.c + screen.c 设计
final class BufferedFrameSink: FrameSink {
    // MARK: - 类型定义

    /// 新帧可用回调
    typealias FrameAvailableCallback = () -> Void

    // MARK: - 属性

    /// 底层帧缓冲
    private let frameBuffer = FrameBuffer()

    /// 新帧可用时的回调（在解码线程调用）
    var onFrameAvailable: FrameAvailableCallback?

    /// 是否有待处理的渲染请求（事件合并标志）
    /// 使用 OSAtomicInt32 实现原子操作
    private var pendingEvent: Int32 = 0

    /// 是否已打开
    private var isOpen = false

    /// 当前帧尺寸
    private(set) var frameSize: CGSize = .zero

    // MARK: - 统计

    /// 被跳过的帧数
    private(set) var skippedFrameCount = 0

    /// 渲染的帧数
    private(set) var renderedFrameCount = 0

    // MARK: - FrameSink 协议实现

    func open(size: CGSize) -> Bool {
        frameSize = size
        isOpen = true
        frameBuffer.reset()
        skippedFrameCount = 0
        renderedFrameCount = 0
        AppLogger.rendering.info("BufferedFrameSink 已打开，尺寸: \(size)")
        return true
    }

    func close() {
        isOpen = false
        frameBuffer.reset()
        AppLogger.rendering.info("BufferedFrameSink 已关闭")
    }

    /// 推送新帧（由解码线程调用）
    @discardableResult
    func push(_ frame: VideoFrame) -> Bool {
        guard isOpen else { return false }

        // 推送到帧缓冲
        let previousSkipped = frameBuffer.push(frame.pixelBuffer)

        if previousSkipped {
            // 上一帧被跳过（未被消费）
            skippedFrameCount += 1

            // 关键：不发送新事件！
            // 已有一个事件在等待，它会消费最新帧
            // 这与 scrcpy 的 sc_screen_frame_sink_push 逻辑一致
            return true
        }

        // 使用原子操作检查是否已有待处理事件
        // 如果 pendingEvent 为 0，设置为 1 并返回 true（可以发送事件）
        // 如果 pendingEvent 为 1，返回 false（已有事件待处理）
        let shouldNotify = OSAtomicCompareAndSwap32(0, 1, &pendingEvent)

        if shouldNotify {
            // 通知有新帧可用
            onFrameAvailable?()
        }

        return true
    }

    // MARK: - 帧消费

    /// 消费当前帧（由渲染线程调用）
    /// - Returns: 最新的像素缓冲区，如果没有新帧则返回 nil
    func consume() -> CVPixelBuffer? {
        // 重置事件标志（允许下一个事件）
        OSAtomicCompareAndSwap32(1, 0, &pendingEvent)

        guard let pixelBuffer = frameBuffer.consume() else {
            return nil
        }

        renderedFrameCount += 1
        return pixelBuffer
    }

    /// 查看当前帧（不改变状态）
    func peek() -> CVPixelBuffer? {
        frameBuffer.peek()
    }

    /// 检查是否有新帧
    var hasNewFrame: Bool {
        frameBuffer.hasNewFrame
    }

    /// 获取统计信息
    func getStats() -> (skipped: Int, rendered: Int, skipRate: Double) {
        let total = skippedFrameCount + renderedFrameCount
        let skipRate = total > 0 ? Double(skippedFrameCount) / Double(total) : 0
        return (skippedFrameCount, renderedFrameCount, skipRate)
    }

    /// 重置统计
    func resetStats() {
        skippedFrameCount = 0
        renderedFrameCount = 0
    }
}

// MARK: - 渲染帧接收器

/// 渲染帧接收器
/// 实现 CVDisplayLink 驱动的渲染循环
/// 主动从 BufferedFrameSink 拉取帧，实现 vsync 同步
/// 注意：已改用共享的 DisplayLinkManager，避免多个 CVDisplayLink 同时运行
final class RenderFrameSink {
    // MARK: - 属性

    /// 帧源（BufferedFrameSink）
    private weak var frameSource: BufferedFrameSink?

    // 注意：displayLink 已移除，改用共享的 DisplayLinkManager

    /// 渲染回调
    var onRender: ((CVPixelBuffer) -> Void)?

    /// 是否正在渲染
    private(set) var isRendering = false

    /// 渲染队列
    /// 注意：从 .userInteractive 降级为 .userInitiated，降低 CPU 调度压力
    private let renderQueue = DispatchQueue(label: "com.screenPresenter.renderSink", qos: .userInitiated)

    /// 唯一标识符（用于 DisplayLinkManager 注册）
    private let displayLinkId: String = "RenderFrameSink-\(UUID().uuidString)"

    // MARK: - 初始化

    init(frameSource: BufferedFrameSink) {
        self.frameSource = frameSource
    }

    deinit {
        stopRendering()
    }

    // MARK: - 渲染控制

    /// 开始渲染
    func startRendering() {
        guard !isRendering else { return }
        isRendering = true
        // 使用共享的 DisplayLinkManager，避免多个 CVDisplayLink 同时运行
        DisplayLinkManager.shared.register(id: displayLinkId) { [weak self] in
            self?.displayLinkCallback()
        }
        AppLogger.rendering.info("RenderFrameSink 开始渲染 (使用共享 DisplayLinkManager)")
    }

    /// 停止渲染
    func stopRendering() {
        guard isRendering else { return }
        isRendering = false
        // 取消注册共享 DisplayLink
        DisplayLinkManager.shared.unregister(id: displayLinkId)
        AppLogger.rendering.info("RenderFrameSink 停止渲染")
    }

    // MARK: - Display Link 回调

    private func displayLinkCallback() {
        guard isRendering else { return }

        // 在渲染队列中执行，避免阻塞 DisplayLink 回调线程
        renderQueue.async { [weak self] in
            // 使用 autoreleasepool 确保每帧渲染过程中创建的临时对象及时释放
            // 避免在高频渲染循环中 autorelease 对象堆积导致内存缓慢增长
            autoreleasepool {
                self?.renderFrame()
            }
        }
    }

    private func renderFrame() {
        // 从帧源消费帧
        guard let pixelBuffer = frameSource?.consume() else {
            // 没有新帧，跳过本次 vsync
            return
        }

        // 直接在渲染队列调用回调
        // SingleDeviceRenderView 的 updateTexture 和 renderFrame 是线程安全的
        onRender?(pixelBuffer)
    }
}

// MARK: - 主线程帧分发器

/// 主线程帧分发器
/// 将帧事件安全地分发到主线程，支持事件合并
final class MainThreadFrameDispatcher {
    // MARK: - 属性

    /// 帧源
    private let frameSink: BufferedFrameSink

    /// 主线程帧处理回调
    var onFrame: ((CVPixelBuffer) -> Void)?

    /// 是否已设置
    private var isSetup = false

    // MARK: - 初始化

    init(frameSink: BufferedFrameSink) {
        self.frameSink = frameSink
    }

    // MARK: - 设置

    /// 设置分发器
    func setup() {
        guard !isSetup else { return }
        isSetup = true

        // 设置帧可用回调
        frameSink.onFrameAvailable = { [weak self] in
            self?.dispatchToMainThread()
        }

        AppLogger.rendering.info("MainThreadFrameDispatcher 已设置")
    }

    /// 停止分发
    func stop() {
        isSetup = false
        frameSink.onFrameAvailable = nil
        AppLogger.rendering.info("MainThreadFrameDispatcher 已停止")
    }

    // MARK: - 分发

    private func dispatchToMainThread() {
        DispatchQueue.main.async { [weak self] in
            guard let self, isSetup else { return }

            // 消费最新帧
            guard let pixelBuffer = frameSink.consume() else {
                return
            }

            // 回调处理
            onFrame?(pixelBuffer)
        }
    }
}

// MARK: - 帧管道

/// 渲染模式
enum FramePipelineRenderMode {
    /// 主线程事件驱动（默认，兼容性好）
    case mainThreadEvent
    /// CVDisplayLink 驱动（更流畅，独立于主线程）
    case displayLink
}

/// 帧管道
/// 组合 FrameSource 和 FrameSink，构建完整的帧传递链路
final class FramePipeline {
    // MARK: - 组件

    /// 带缓冲的帧消费者
    let bufferedSink: BufferedFrameSink

    /// 主线程分发器
    private let dispatcher: MainThreadFrameDispatcher

    /// CVDisplayLink 渲染器
    private let renderSink: RenderFrameSink

    /// 当前渲染模式
    private(set) var renderMode: FramePipelineRenderMode = .displayLink

    // MARK: - 状态

    /// 是否已启动
    private(set) var isRunning = false

    // MARK: - 初始化

    init(renderMode: FramePipelineRenderMode = .displayLink) {
        bufferedSink = BufferedFrameSink()
        dispatcher = MainThreadFrameDispatcher(frameSink: bufferedSink)
        renderSink = RenderFrameSink(frameSource: bufferedSink)
        self.renderMode = renderMode
    }

    // MARK: - 控制

    /// 启动管道
    func start(size: CGSize) {
        guard !isRunning else { return }

        _ = bufferedSink.open(size: size)

        switch renderMode {
        case .mainThreadEvent:
            dispatcher.setup()
            AppLogger.rendering.info("FramePipeline 已启动（主线程事件模式）")
        case .displayLink:
            renderSink.startRendering()
            AppLogger.rendering.info("FramePipeline 已启动（CVDisplayLink 模式）")
        }

        isRunning = true
    }

    /// 停止管道
    func stop() {
        guard isRunning else { return }

        switch renderMode {
        case .mainThreadEvent:
            dispatcher.stop()
        case .displayLink:
            renderSink.stopRendering()
        }

        bufferedSink.close()
        isRunning = false

        AppLogger.rendering.info("FramePipeline 已停止")
    }

    /// 推送帧（由解码线程调用）
    @discardableResult
    func pushFrame(_ pixelBuffer: CVPixelBuffer) -> Bool {
        guard isRunning else {
            return false
        }

        let frame = VideoFrame(pixelBuffer: pixelBuffer)
        return bufferedSink.push(frame)
    }

    /// 设置帧处理回调
    /// 根据渲染模式，回调可能在主线程（mainThreadEvent）或渲染队列（displayLink）中调用
    func setFrameHandler(_ handler: @escaping (CVPixelBuffer) -> Void) {
        switch renderMode {
        case .mainThreadEvent:
            dispatcher.onFrame = handler
        case .displayLink:
            renderSink.onRender = handler
        }
    }

    /// 获取统计信息
    func getStats() -> (skipped: Int, rendered: Int, skipRate: Double) {
        bufferedSink.getStats()
    }
}
