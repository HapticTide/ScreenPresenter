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

    private var metalLayer: CAMetalLayer!
    private var renderer: MetalRenderer?
    private var displayLink: CVDisplayLink?

    // MARK: - 渲染队列

    /// 专用渲染队列（避免主线程渲染）
    private let renderQueue = DispatchQueue(label: "com.screenPresenter.render", qos: .userInteractive)

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

        metalLayer = layer as? CAMetalLayer
        if metalLayer == nil {
            metalLayer = CAMetalLayer()
            layer = metalLayer
        }

        metalLayer.device = MTLCreateSystemDefaultDevice()
        metalLayer.pixelFormat = .bgra8Unorm
        metalLayer.framebufferOnly = true
        metalLayer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2.0

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
        setupDisplayLink()

        AppLogger.rendering.info("开始渲染")
    }

    /// 停止渲染
    func stopRendering() {
        guard isRendering else { return }

        isRendering = false
        stopDisplayLink()

        AppLogger.rendering.info("停止渲染")
    }

    /// 手动触发一次渲染
    func renderOnce() {
        renderFrame()
    }

    // MARK: - Display Link

    private func setupDisplayLink() {
        var link: CVDisplayLink?
        CVDisplayLinkCreateWithActiveCGDisplays(&link)

        guard let displayLink = link else {
            AppLogger.rendering.error("无法创建 CVDisplayLink")
            return
        }

        // 设置输出回调
        let callback: CVDisplayLinkOutputCallback = { _, _, _, _, _, userInfo -> CVReturn in
            guard let userInfo else { return kCVReturnSuccess }
            let view = Unmanaged<MetalRenderView>.fromOpaque(userInfo).takeUnretainedValue()
            view.displayLinkCallback()
            return kCVReturnSuccess
        }

        let userInfo = Unmanaged.passUnretained(self).toOpaque()
        CVDisplayLinkSetOutputCallback(displayLink, callback, userInfo)

        // 设置当前显示
        if let screen = window?.screen {
            let displayID = screen
                .deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID ?? CGMainDisplayID()
            CVDisplayLinkSetCurrentCGDisplay(displayLink, displayID)
        }

        CVDisplayLinkStart(displayLink)
        self.displayLink = displayLink
    }

    private func stopDisplayLink() {
        if let displayLink {
            CVDisplayLinkStop(displayLink)
        }
        displayLink = nil
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

    /// 设置布局模式
    func setLayoutMode(_ mode: LayoutMode) {
        renderer?.layoutMode = mode
    }

    /// 设置是否交换位置
    func setSwapped(_ swapped: Bool) {
        renderer?.isSwapped = swapped
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
