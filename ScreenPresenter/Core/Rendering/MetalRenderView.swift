//
//  MetalRenderView.swift
//  ScreenPresenter
//
//  Created by Sun on 2025/12/22.
//
//  Metal 渲染视图
//  使用 CAMetalLayer 作为渲染表面的 NSView
//

import AppKit
import CoreVideo
import Metal
import QuartzCore

// MARK: - Metal 渲染视图

final class MetalRenderView: NSView {
    // MARK: - Metal 组件

    private var metalLayer: CAMetalLayer?
    private var renderer: MetalRenderer?
    // 注意：displayLink 已移除，改用共享的 DisplayLinkManager

    // MARK: - 渲染队列

    /// 专用渲染队列（避免主线程渲染）
    /// 注意：从 .userInteractive 降级为 .userInitiated，降低 CPU 调度压力
    private let renderQueue = DispatchQueue(label: "com.screenPresenter.render", qos: .userInitiated)

    // MARK: - 状态

    private(set) var isRendering = false
    private let renderLock = NSLock()

    // MARK: - 回调

    var onRenderFrame: (() -> Void)?

    // MARK: - 初始化

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupMetal()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupMetal()
    }

    deinit {
        stopRendering()
    }

    // MARK: - 视图生命周期

    override func makeBackingLayer() -> CALayer {
        let layer = CAMetalLayer()
        layer.device = MTLCreateSystemDefaultDevice()
        layer.pixelFormat = .bgra8Unorm
        layer.framebufferOnly = true
        layer.isOpaque = false
        layer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2.0
        return layer
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        metalLayer?.contentsScale = window?.backingScaleFactor ?? 2.0
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()

        if window != nil {
            metalLayer?.contentsScale = window?.backingScaleFactor ?? 2.0
            updateDrawableSize()
        }
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updateDrawableSize()
    }

    override func setBoundsSize(_ newSize: NSSize) {
        super.setBoundsSize(newSize)
        updateDrawableSize()
    }

    // MARK: - 设置

    private func setupMetal() {
        wantsLayer = true
        layerContentsRedrawPolicy = .duringViewResize

        let resolvedLayer = (layer as? CAMetalLayer) ?? CAMetalLayer()
        metalLayer = resolvedLayer
        layer = resolvedLayer

        resolvedLayer.device = MTLCreateSystemDefaultDevice()
        resolvedLayer.pixelFormat = .bgra8Unorm
        resolvedLayer.framebufferOnly = true
        resolvedLayer.isOpaque = false
        resolvedLayer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2.0

        // 创建渲染器
        renderer = MetalRenderer()

        AppLogger.rendering.info("Metal 渲染视图已初始化")
    }

    private func updateDrawableSize() {
        guard let metalLayer else { return }

        let scale = window?.backingScaleFactor ?? 2.0
        let size = CGSize(
            width: bounds.width * scale,
            height: bounds.height * scale
        )

        if size.width > 0, size.height > 0 {
            metalLayer.drawableSize = size
        }
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

        AppLogger.rendering.info("开始渲染 (使用共享 DisplayLinkManager)")
    }

    /// 停止渲染
    func stopRendering() {
        guard isRendering else { return }

        isRendering = false
        // 取消注册共享 DisplayLink
        DisplayLinkManager.shared.unregister(id: displayLinkId)

        AppLogger.rendering.info("停止渲染")
    }

    /// 手动触发一次渲染
    func renderOnce() {
        renderFrame()
    }

    // MARK: - Display Link

    /// 唯一标识符（用于 DisplayLinkManager 注册）
    private var displayLinkId: String {
        "MetalRenderView-\(ObjectIdentifier(self).hashValue)"
    }

    private func displayLinkCallback() {
        renderLock.lock()
        defer { renderLock.unlock() }

        guard isRendering else { return }

        // 在专用渲染队列执行渲染，避免阻塞主线程
        renderQueue.async { [weak self] in
            self?.renderFrame()
        }
    }

    // MARK: - 渲染

    private func renderFrame() {
        guard let renderer, let metalLayer else { return }

        // 通知外部获取新帧（可能需要在主线程执行）
        if let callback = onRenderFrame {
            DispatchQueue.main.async {
                callback()
            }
        }

        // 在渲染队列执行 Metal 渲染（线程安全）
        renderer.render(to: metalLayer)
    }

    // MARK: - 纹理更新

    /// 更新左侧纹理
    func updateLeftTexture(from pixelBuffer: CVPixelBuffer) {
        renderer?.updateLeftTexture(from: pixelBuffer)
    }

    /// 更新右侧纹理
    func updateRightTexture(from pixelBuffer: CVPixelBuffer) {
        renderer?.updateRightTexture(from: pixelBuffer)
    }

    /// 清除所有纹理
    func clearTextures() {
        renderer?.clearTextures()
    }

    // MARK: - 布局

    /// 设置是否交换位置
    func setSwapped(_ swapped: Bool) {
        renderer?.isSwapped = swapped
        needsDisplay = true
        AppLogger.rendering.info("交换状态已切换: \(swapped)")
    }

    /// 设置主屏幕区域（用于渲染左侧/上方设备）
    func setPrimaryScreenFrame(_ frame: CGRect) {
        renderer?.primaryScreenFrame = frame
    }

    /// 设置次屏幕区域（用于渲染右侧/下方设备）
    func setSecondaryScreenFrame(_ frame: CGRect) {
        renderer?.secondaryScreenFrame = frame
    }

    /// 设置主屏幕圆角半径（用于渲染左侧/上方设备）
    func setPrimaryScreenCornerRadius(_ radius: CGFloat) {
        renderer?.primaryScreenCornerRadius = radius
    }

    /// 设置次屏幕圆角半径（用于渲染右侧/下方设备）
    func setSecondaryScreenCornerRadius(_ radius: CGFloat) {
        renderer?.secondaryScreenCornerRadius = radius
    }

    // MARK: - 统计

    /// 左侧帧率
    var leftFPS: Double {
        renderer?.leftFPS ?? 0
    }

    /// 右侧帧率
    var rightFPS: Double {
        renderer?.rightFPS ?? 0
    }
}
