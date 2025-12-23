//
//  MetalRenderer.swift
//  ScreenPresenter
//
//  Created by Sun on 2025/12/22.
//
//  Metal 渲染器
//  使用 CAMetalLayer 和 MTLTexture 进行高性能视频渲染
//

import AppKit
import CoreMedia
import CoreVideo
import Metal
import MetalKit
import QuartzCore

// MARK: - Metal 渲染器

final class MetalRenderer {
    // MARK: - Metal 核心对象

    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let pipelineState: MTLRenderPipelineState
    private var textureCache: CVMetalTextureCache?

    // MARK: - 渲染状态

    private var vertexBuffer: MTLBuffer?
    private let samplerState: MTLSamplerState

    // MARK: - 纹理

    private(set) var leftTexture: MTLTexture?
    private(set) var rightTexture: MTLTexture?

    // MARK: - 统计

    private(set) var leftFPS: Double = 0
    private(set) var rightFPS: Double = 0
    private var leftFrameTimestamps: [CFAbsoluteTime] = []
    private var rightFrameTimestamps: [CFAbsoluteTime] = []

    // MARK: - 布局

    var layoutMode: LayoutMode = .sideBySide
    var isSwapped: Bool = false

    // MARK: - 屏幕区域（用于渲染到设备边框内）

    /// 左侧/上方设备的屏幕区域（在视图坐标系中）
    var primaryScreenFrame: CGRect = .zero
    /// 右侧/下方设备的屏幕区域（在视图坐标系中）
    var secondaryScreenFrame: CGRect = .zero

    // MARK: - 初始化

    init?() {
        // 创建 Metal 设备
        guard let device = MTLCreateSystemDefaultDevice() else {
            AppLogger.rendering.error("无法创建 Metal 设备")
            return nil
        }
        self.device = device

        // 创建命令队列
        guard let commandQueue = device.makeCommandQueue() else {
            AppLogger.rendering.error("无法创建命令队列")
            return nil
        }
        self.commandQueue = commandQueue

        // 创建纹理缓存
        var cache: CVMetalTextureCache?
        let status = CVMetalTextureCacheCreate(
            kCFAllocatorDefault,
            nil,
            device,
            nil,
            &cache
        )
        guard status == kCVReturnSuccess, let textureCache = cache else {
            AppLogger.rendering.error("无法创建纹理缓存: \(status)")
            return nil
        }
        self.textureCache = textureCache

        // 创建渲染管线
        guard let pipelineState = MetalRenderer.createPipelineState(device: device) else {
            AppLogger.rendering.error("无法创建渲染管线")
            return nil
        }
        self.pipelineState = pipelineState

        // 创建采样器
        let samplerDescriptor = MTLSamplerDescriptor()
        samplerDescriptor.minFilter = .linear
        samplerDescriptor.magFilter = .linear
        samplerDescriptor.sAddressMode = .clampToEdge
        samplerDescriptor.tAddressMode = .clampToEdge

        guard let sampler = device.makeSamplerState(descriptor: samplerDescriptor) else {
            AppLogger.rendering.error("无法创建采样器")
            return nil
        }
        samplerState = sampler

        // 创建顶点缓冲区
        setupVertexBuffer()

        AppLogger.rendering.info("Metal 渲染器初始化成功")
    }

    // MARK: - 纹理更新

    /// 更新左侧纹理（从 CVPixelBuffer）
    func updateLeftTexture(from pixelBuffer: CVPixelBuffer) {
        leftTexture = createTexture(from: pixelBuffer)
        updateFPSStatistics(for: &leftFrameTimestamps, fps: &leftFPS)
    }

    /// 更新右侧纹理（从 CVPixelBuffer）
    func updateRightTexture(from pixelBuffer: CVPixelBuffer) {
        rightTexture = createTexture(from: pixelBuffer)
        updateFPSStatistics(for: &rightFrameTimestamps, fps: &rightFPS)
    }

    /// 从 CVPixelBuffer 创建 MTLTexture
    private func createTexture(from pixelBuffer: CVPixelBuffer) -> MTLTexture? {
        guard let cache = textureCache else { return nil }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)

        var cvTexture: CVMetalTexture?
        let status = CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault,
            cache,
            pixelBuffer,
            nil,
            .bgra8Unorm,
            width,
            height,
            0,
            &cvTexture
        )

        guard status == kCVReturnSuccess, let texture = cvTexture else {
            return nil
        }

        return CVMetalTextureGetTexture(texture)
    }

    // MARK: - 渲染

    /// 渲染到 CAMetalLayer
    func render(to layer: CAMetalLayer) {
        guard let drawable = layer.nextDrawable() else { return }
        guard let commandBuffer = commandQueue.makeCommandBuffer() else { return }

        let renderPassDescriptor = MTLRenderPassDescriptor()
        renderPassDescriptor.colorAttachments[0].texture = drawable.texture
        renderPassDescriptor.colorAttachments[0].loadAction = .clear
        renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 0.0)
        renderPassDescriptor.colorAttachments[0].storeAction = .store

        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
            return
        }

        encoder.setRenderPipelineState(pipelineState)
        encoder.setFragmentSamplerState(samplerState, index: 0)

        // 获取 drawable 尺寸
        let drawableSize = CGSize(
            width: CGFloat(drawable.texture.width),
            height: CGFloat(drawable.texture.height)
        )

        // 根据布局模式渲染
        switch layoutMode {
        case .sideBySide:
            renderSideBySide(encoder: encoder, drawableSize: drawableSize)
        case .topBottom:
            renderTopBottom(encoder: encoder, drawableSize: drawableSize)
        case .single:
            renderSingle(encoder: encoder, drawableSize: drawableSize)
        }

        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    // MARK: - 布局渲染

    /// 左右并排渲染
    private func renderSideBySide(encoder: MTLRenderCommandEncoder, drawableSize: CGSize) {
        // 确定左右纹理
        let (leftTex, rightTex) = isSwapped ? (rightTexture, leftTexture) : (leftTexture, rightTexture)

        // 渲染左侧（主屏幕区域）
        if let texture = leftTex {
            renderTextureInScreenFrame(
                texture,
                encoder: encoder,
                screenFrame: primaryScreenFrame,
                drawableSize: drawableSize
            )
        }

        // 渲染右侧（次屏幕区域）
        if let texture = rightTex {
            renderTextureInScreenFrame(
                texture,
                encoder: encoder,
                screenFrame: secondaryScreenFrame,
                drawableSize: drawableSize
            )
        }
    }

    /// 上下布局渲染
    private func renderTopBottom(encoder: MTLRenderCommandEncoder, drawableSize: CGSize) {
        // 确定上下纹理
        let (topTex, bottomTex) = isSwapped ? (rightTexture, leftTexture) : (leftTexture, rightTexture)

        // 渲染上方（主屏幕区域）
        if let texture = topTex {
            renderTextureInScreenFrame(
                texture,
                encoder: encoder,
                screenFrame: primaryScreenFrame,
                drawableSize: drawableSize
            )
        }

        // 渲染下方（次屏幕区域）
        if let texture = bottomTex {
            renderTextureInScreenFrame(
                texture,
                encoder: encoder,
                screenFrame: secondaryScreenFrame,
                drawableSize: drawableSize
            )
        }
    }

    /// 单视图渲染
    private func renderSingle(encoder: MTLRenderCommandEncoder, drawableSize: CGSize) {
        let texture = isSwapped ? rightTexture : leftTexture

        if let texture {
            renderTextureInScreenFrame(
                texture,
                encoder: encoder,
                screenFrame: primaryScreenFrame,
                drawableSize: drawableSize
            )
        }
    }

    /// 渲染纹理到指定的屏幕区域
    private func renderTextureInScreenFrame(
        _ texture: MTLTexture,
        encoder: MTLRenderCommandEncoder,
        screenFrame: CGRect,
        drawableSize: CGSize
    ) {
        guard screenFrame.width > 0, screenFrame.height > 0 else { return }

        // 计算视口比例（从视图坐标转换为 drawable 坐标）
        let viewWidth = drawableSize.width / (NSScreen.main?.backingScaleFactor ?? 2.0)
        let viewHeight = drawableSize.height / (NSScreen.main?.backingScaleFactor ?? 2.0)

        let scaleX = drawableSize.width / viewWidth
        let scaleY = drawableSize.height / viewHeight

        // Metal 坐标系原点在左下角，而 NSView 坐标系原点在左下角（但 Y 向上）
        // 所以需要翻转 Y 坐标
        let flippedY = viewHeight - screenFrame.maxY

        let viewport = MTLViewport(
            originX: Double(screenFrame.minX * scaleX),
            originY: Double(flippedY * scaleY),
            width: Double(screenFrame.width * scaleX),
            height: Double(screenFrame.height * scaleY),
            znear: 0,
            zfar: 1
        )

        renderTexture(
            texture,
            encoder: encoder,
            viewport: viewport,
            containerSize: screenFrame.size
        )
    }

    /// 渲染单个纹理（保持纵横比）
    private func renderTexture(
        _ texture: MTLTexture,
        encoder: MTLRenderCommandEncoder,
        viewport: MTLViewport,
        containerSize: CGSize
    ) {
        encoder.setViewport(viewport)

        // 计算保持纵横比的顶点
        let textureAspect = CGFloat(texture.width) / CGFloat(texture.height)
        let containerAspect = containerSize.width / containerSize.height

        var scaleX: Float = 1.0
        var scaleY: Float = 1.0

        if textureAspect > containerAspect {
            // 纹理更宽，以宽度为准
            scaleY = Float(containerAspect / textureAspect)
        } else {
            // 纹理更高，以高度为准
            scaleX = Float(textureAspect / containerAspect)
        }

        // 更新顶点数据
        let vertices: [Float] = [
            // 位置 (x, y)       // 纹理坐标 (u, v)
            -scaleX, -scaleY, 0.0, 1.0, // 左下
            scaleX, -scaleY, 1.0, 1.0, // 右下
            -scaleX, scaleY, 0.0, 0.0, // 左上
            scaleX, scaleY, 1.0, 0.0, // 右上
        ]

        encoder.setVertexBytes(vertices, length: vertices.count * MemoryLayout<Float>.size, index: 0)
        encoder.setFragmentTexture(texture, index: 0)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
    }

    // MARK: - 辅助方法

    private func setupVertexBuffer() {
        // 默认全屏四边形顶点
        let vertices: [Float] = [
            // 位置 (x, y)       // 纹理坐标 (u, v)
            -1.0, -1.0, 0.0, 1.0, // 左下
            1.0, -1.0, 1.0, 1.0, // 右下
            -1.0, 1.0, 0.0, 0.0, // 左上
            1.0, 1.0, 1.0, 0.0, // 右上
        ]

        vertexBuffer = device.makeBuffer(
            bytes: vertices,
            length: vertices.count * MemoryLayout<Float>.size,
            options: .storageModeShared
        )
    }

    private static func createPipelineState(device: MTLDevice) -> MTLRenderPipelineState? {
        // 创建着色器库
        guard let library = device.makeDefaultLibrary() ?? createShaderLibrary(device: device) else {
            AppLogger.rendering.error("无法创建着色器库")
            return nil
        }

        let vertexFunction = library.makeFunction(name: "vertexShader")
        let fragmentFunction = library.makeFunction(name: "fragmentShader")

        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertexFunction
        descriptor.fragmentFunction = fragmentFunction
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        // 启用 alpha 混合以支持透明背景
        descriptor.colorAttachments[0].isBlendingEnabled = true
        descriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        descriptor.colorAttachments[0].sourceAlphaBlendFactor = .one
        descriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha

        do {
            return try device.makeRenderPipelineState(descriptor: descriptor)
        } catch {
            AppLogger.rendering.error("创建渲染管线失败: \(error.localizedDescription)")
            return nil
        }
    }

    private static func createShaderLibrary(device: MTLDevice) -> MTLLibrary? {
        let shaderSource = """
        #include <metal_stdlib>
        using namespace metal;

        struct VertexOut {
            float4 position [[position]];
            float2 texCoord;
        };

        vertex VertexOut vertexShader(uint vertexID [[vertex_id]],
                                       constant float4 *vertices [[buffer(0)]]) {
            VertexOut out;
            float4 v = vertices[vertexID];
            out.position = float4(v.xy, 0.0, 1.0);
            out.texCoord = v.zw;
            return out;
        }

        fragment float4 fragmentShader(VertexOut in [[stage_in]],
                                        texture2d<float> texture [[texture(0)]],
                                        sampler textureSampler [[sampler(0)]]) {
            return texture.sample(textureSampler, in.texCoord);
        }
        """

        do {
            return try device.makeLibrary(source: shaderSource, options: nil)
        } catch {
            AppLogger.rendering.error("编译着色器失败: \(error.localizedDescription)")
            return nil
        }
    }

    private func updateFPSStatistics(for timestamps: inout [CFAbsoluteTime], fps: inout Double) {
        let now = CFAbsoluteTimeGetCurrent()
        timestamps.append(now)
        timestamps = timestamps.filter { now - $0 < 1.0 }
        fps = Double(timestamps.count)
    }

    // MARK: - 清理

    func clearTextures() {
        leftTexture = nil
        rightTexture = nil
        leftFPS = 0
        rightFPS = 0
        leftFrameTimestamps.removeAll()
        rightFrameTimestamps.removeAll()
    }
}

// MARK: - 布局模式

enum LayoutMode: String, CaseIterable {
    case sideBySide = "side_by_side"
    case topBottom = "top_bottom"
    case single

    var displayName: String {
        switch self {
        case .sideBySide: L10n.layout.sideBySide
        case .topBottom: L10n.layout.topBottom
        case .single: L10n.layout.single
        }
    }

    var icon: String {
        switch self {
        case .sideBySide: "rectangle.split.2x1"
        case .topBottom: "rectangle.split.1x2"
        case .single: "rectangle"
        }
    }
}
