//
//  SingleDeviceRenderView.swift
//  ScreenPresenter
//
//  Created by Sun on 2025/12/23.
//
//  单设备 Metal 渲染视图
//  嵌入到 DeviceBezelView 的 screenContentView 中，画面跟随设备边框动画
//

import AppKit
import CoreVideo
import Metal
import QuartzCore

// MARK: - 单设备渲染视图

final class SingleDeviceRenderView: NSView {
    // MARK: - Metal 组件

    private var metalLayer: CAMetalLayer?
    private var device: MTLDevice?
    private var commandQueue: MTLCommandQueue?
    private var pipelineState: MTLRenderPipelineState?
    private var textureCache: CVMetalTextureCache?
    private var samplerState: MTLSamplerState?

    // MARK: - 颜色补偿

    private var lutSamplerState: MTLSamplerState?

    /// 颜色补偿滤镜（可外部注入，支持按设备独立设置）
    var colorFilter: ColorCompensationFilter?

    // MARK: - 纹理（保持对 CVMetalTexture 的强引用，防止 MTLTexture 失效）

    private var currentCVTexture: CVMetalTexture?
    private var currentTexture: MTLTexture?
    private let textureLock = NSLock()

    // MARK: - 渲染状态

    private(set) var isRendering = false
    /// 注意：从 .userInteractive 降级为 .userInitiated，降低 CPU 调度压力
    private let renderQueue = DispatchQueue(label: "com.screenPresenter.singleRender", qos: .userInitiated)

    /// 标记是否有新帧需要渲染
    private var needsRender = false

    // MARK: - 配置

    /// 屏幕圆角半径（使用系统的连续曲率圆角）
    var cornerRadius: CGFloat = 0 {
        didSet {
            metalLayer?.cornerRadius = cornerRadius
            metalLayer?.cornerCurve = .continuous
        }
    }

    // MARK: - 统计

    private var frameTimestamps: [CFAbsoluteTime] = []
    private var _fps: Double = 0
    private let fpsLock = NSLock()

    /// 当前 FPS（线程安全）
    var fps: Double {
        get {
            fpsLock.lock()
            defer { fpsLock.unlock() }
            return _fps
        }
        set {
            fpsLock.lock()
            _fps = newValue
            fpsLock.unlock()
        }
    }

    // MARK: - 调试统计

    /// 渲染次数（周期内）
    private var renderCountInPeriod: Int = 0

    /// 纹理更新次数（周期内）
    private var textureUpdateCountInPeriod: Int = 0

    /// 上次统计时间
    private var lastRenderStatsTime = CFAbsoluteTimeGetCurrent()

    /// 渲染耗时累计
    private var totalRenderTime: Double = 0

    /// 最大渲染耗时
    private var maxRenderTime: Double = 0

    /// 纹理更新耗时累计
    private var totalTextureUpdateTime: Double = 0

    /// 最大纹理更新耗时
    private var maxTextureUpdateTime: Double = 0

    /// 纹理更新间隔
    private var lastTextureUpdateTime = CFAbsoluteTimeGetCurrent()

    /// 最大纹理更新间隔
    private var maxTextureUpdateInterval: Double = 0

    // MARK: - 纹理缓存刷新优化

    /// 纹理缓存刷新计数器
    private var textureFlushCounter: Int = 0

    /// 纹理缓存刷新间隔（每 N 帧刷新一次）
    /// 从每帧刷新改为每 30 帧刷新，大幅降低 CPU 开销
    private let textureFlushInterval: Int = 30

    // MARK: - 资源监控

    /// 帧索引（用于资源监控的丢帧计算）
    private var frameIndex: Int = 0

    /// 资源监控丢帧计数
    private var resourceDroppedFrameCount: Int = 0

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
        // 清理纹理缓存
        if let cache = textureCache {
            CVMetalTextureCacheFlush(cache, 0)
        }
    }

    // MARK: - 视图生命周期

    override func makeBackingLayer() -> CALayer {
        let layer = CAMetalLayer()
        layer.device = MTLCreateSystemDefaultDevice()
        layer.pixelFormat = .bgra8Unorm
        layer.framebufferOnly = true
        layer.isOpaque = false
        layer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2.0
        // 禁用 vsync 等待，允许帧立即呈现
        // 这可以减少延迟，但可能导致撕裂（在投屏场景中可接受）
        layer.presentsWithTransaction = false
        // 允许 triple buffering 以提高吞吐量
        layer.maximumDrawableCount = 3
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
        // 尺寸变化时需要重新渲染
        scheduleRender()
    }

    override func setBoundsSize(_ newSize: NSSize) {
        super.setBoundsSize(newSize)
        updateDrawableSize()
        scheduleRender()
    }

    // MARK: - 设置

    private func setupMetal() {
        // 强制使用 layer-backed 视图
        wantsLayer = true

        // 创建并设置 CAMetalLayer
        let metal = CAMetalLayer()
        layer = metal
        metalLayer = metal

        guard let device = MTLCreateSystemDefaultDevice() else {
            AppLogger.rendering.error("无法创建 Metal 设备")
            return
        }
        self.device = device

        metal.device = device
        metal.pixelFormat = .bgra8Unorm
        metal.framebufferOnly = true
        metal.isOpaque = false
        metal.contentsScale = NSScreen.main?.backingScaleFactor ?? 2.0
        metal.masksToBounds = true

        // 创建命令队列
        guard let commandQueue = device.makeCommandQueue() else {
            AppLogger.rendering.error("无法创建命令队列")
            return
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
        guard status == kCVReturnSuccess else {
            AppLogger.rendering.error("无法创建纹理缓存: \(status)")
            return
        }
        textureCache = cache

        // 创建渲染管线
        guard let pipelineState = createPipelineState(device: device) else {
            AppLogger.rendering.error("无法创建渲染管线")
            return
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
            return
        }
        samplerState = sampler

        // 创建 LUT 采样器
        let lutSamplerDescriptor = ColorCompensationFilter.createLUTSamplerDescriptor()
        lutSamplerState = device.makeSamplerState(descriptor: lutSamplerDescriptor)
        samplerState = sampler

        AppLogger.rendering.info("SingleDeviceRenderView Metal 初始化成功")
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

    func startRendering() {
        guard !isRendering else { return }
        isRendering = true
    }

    func stopRendering() {
        guard isRendering else { return }
        isRendering = false
    }

    // MARK: - 按需渲染

    private func scheduleRender() {
        guard isRendering else { return }
        needsRender = true
        renderQueue.async { [weak self] in
            // 使用 autoreleasepool 确保每帧渲染过程中创建的临时对象及时释放
            autoreleasepool {
                self?.renderIfNeeded()
            }
        }
    }

    private func renderIfNeeded() {
        guard needsRender else { return }
        needsRender = false
        renderFrame()
    }

    // MARK: - 纹理更新

    func updateTexture(from pixelBuffer: CVPixelBuffer) {
        let updateStartTime = CFAbsoluteTimeGetCurrent()

        guard isRendering, let cache = textureCache else {
            return
        }

        // 资源监控：在内存紧张时丢帧以保护系统稳定性
        frameIndex += 1
        if ResourceMonitor.shared.shouldDropFrame(frameIndex: frameIndex) {
            resourceDroppedFrameCount += 1
            // 每 100 帧输出一次日志
            if resourceDroppedFrameCount % 100 == 1 {
                AppLogger.rendering.warning("[ResourceMonitor] 内存紧张，已丢弃 \(resourceDroppedFrameCount) 帧")
            }
            return
        }

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

        guard status == kCVReturnSuccess, let texture = cvTexture else { return }
        guard let mtlTexture = CVMetalTextureGetTexture(texture) else { return }

        textureLock.lock()
        // 保持对 CVMetalTexture 的强引用，确保 MTLTexture 不会失效
        currentCVTexture = texture
        currentTexture = mtlTexture
        textureLock.unlock()

        // 延迟刷新纹理缓存（每 N 帧刷新一次，降低 CPU 开销）
        textureFlushCounter += 1
        if textureFlushCounter >= textureFlushInterval {
            CVMetalTextureCacheFlush(cache, 0)
            textureFlushCounter = 0
        }

        // 更新 FPS 统计
        let now = CFAbsoluteTimeGetCurrent()
        frameTimestamps.append(now)
        frameTimestamps = frameTimestamps.filter { now - $0 < 1.0 }
        fps = Double(frameTimestamps.count)

        // 调试统计
        let updateTime = (now - updateStartTime) * 1000
        textureUpdateCountInPeriod += 1
        totalTextureUpdateTime += updateTime
        maxTextureUpdateTime = max(maxTextureUpdateTime, updateTime)

        // 计算更新间隔（保留用于内部统计）
        let updateInterval = (now - lastTextureUpdateTime) * 1000
        if textureUpdateCountInPeriod > 1 {
            maxTextureUpdateInterval = max(maxTextureUpdateInterval, updateInterval)
        }
        lastTextureUpdateTime = now

        // 每 5 秒重置统计（保留内部统计逻辑，移除日志输出）
        let elapsed = now - lastRenderStatsTime
        if elapsed >= 5.0 {
            // 重置统计
            lastRenderStatsTime = now
            textureUpdateCountInPeriod = 0
            renderCountInPeriod = 0
            totalTextureUpdateTime = 0
            maxTextureUpdateTime = 0
            totalRenderTime = 0
            maxRenderTime = 0
            maxTextureUpdateInterval = 0
        }

        // 触发渲染
        scheduleRender()
    }

    func clearTexture() {
        textureLock.lock()
        currentCVTexture = nil
        currentTexture = nil
        textureLock.unlock()

        fps = 0
        frameTimestamps.removeAll()

        // 清理时立即刷新纹理缓存
        if let cache = textureCache {
            CVMetalTextureCacheFlush(cache, 0)
        }
        textureFlushCounter = 0

        // 清除画面
        scheduleRender()
    }

    // MARK: - 渲染

    private func renderFrame() {
        let renderStartTime = CFAbsoluteTimeGetCurrent()

        guard let metalLayer, let commandQueue, let pipelineState, let samplerState else { return }

        let drawableSize = metalLayer.drawableSize
        guard drawableSize.width > 0, drawableSize.height > 0 else { return }

        guard let drawable = metalLayer.nextDrawable() else { return }
        guard let commandBuffer = commandQueue.makeCommandBuffer() else { return }

        let renderPassDescriptor = MTLRenderPassDescriptor()
        renderPassDescriptor.colorAttachments[0].texture = drawable.texture
        renderPassDescriptor.colorAttachments[0].loadAction = .clear
        renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 0.0)
        renderPassDescriptor.colorAttachments[0].storeAction = .store

        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else { return }

        textureLock.lock()
        let texture = currentTexture
        textureLock.unlock()

        if let texture {
            encoder.setRenderPipelineState(pipelineState)
            encoder.setFragmentSamplerState(samplerState, index: 0)

            // 计算保持纵横比的顶点
            let textureAspect = CGFloat(texture.width) / CGFloat(texture.height)
            let viewAspect = drawableSize.width / drawableSize.height

            var scaleX: Float = 1.0
            var scaleY: Float = 1.0

            if textureAspect > viewAspect {
                scaleY = Float(viewAspect / textureAspect)
            } else {
                scaleX = Float(textureAspect / viewAspect)
            }

            let vertices: [Float] = [
                -scaleX, -scaleY, 0.0, 1.0,
                scaleX, -scaleY, 1.0, 1.0,
                -scaleX, scaleY, 0.0, 0.0,
                scaleX, scaleY, 1.0, 0.0,
            ]

            encoder.setVertexBytes(vertices, length: vertices.count * MemoryLayout<Float>.size, index: 0)
            encoder.setFragmentTexture(texture, index: 0)

            // 设置颜色补偿资源（使用注入的滤镜实例）
            if let colorFilter {
                if let lutTexture = colorFilter.getLUTTexture() {
                    encoder.setFragmentTexture(lutTexture, index: 1)
                }
                if let lutSampler = lutSamplerState {
                    encoder.setFragmentSamplerState(lutSampler, index: 1)
                }
                if let uniformBuffer = colorFilter.getUniformBuffer() {
                    encoder.setFragmentBuffer(uniformBuffer, offset: 0, index: 0)
                }
            }

            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        }

        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()

        // 统计渲染耗时
        let renderTime = (CFAbsoluteTimeGetCurrent() - renderStartTime) * 1000
        renderCountInPeriod += 1
        totalRenderTime += renderTime
        maxRenderTime = max(maxRenderTime, renderTime)
    }

    // MARK: - 着色器

    private func createPipelineState(device: MTLDevice) -> MTLRenderPipelineState? {
        let shaderSource = """
        #include <metal_stdlib>
        using namespace metal;

        struct VertexOut {
            float4 position [[position]];
            float2 texCoord;
        };

        // 颜色补偿参数
        struct ColorCompensationParams {
            float temperature;
            float tint;
            float saturation;
            int enabled;
        };

        // sRGB -> Linear 转换
        float srgbToLinear(float c) {
            return (c <= 0.04045) ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4);
        }

        // Linear -> sRGB 转换
        float linearToSrgb(float c) {
            return (c <= 0.0031308) ? c * 12.92 : 1.055 * pow(c, 1.0/2.4) - 0.055;
        }

        float3 srgbToLinear3(float3 c) {
            return float3(srgbToLinear(c.r), srgbToLinear(c.g), srgbToLinear(c.b));
        }

        float3 linearToSrgb3(float3 c) {
            return float3(linearToSrgb(c.r), linearToSrgb(c.g), linearToSrgb(c.b));
        }

        // 应用 1D LUT（RGBA16Float 格式，R/G/B 通道分别存储三条曲线）
        float3 applyLUT(float3 color, texture1d<float> lut, sampler s) {
            // LUT 纹理中：R 通道存 R 曲线，G 通道存 G 曲线，B 通道存 B 曲线
            float4 lutSample = lut.sample(s, color.r);
            float r = lutSample.r;
            
            lutSample = lut.sample(s, color.g);
            float g = lutSample.g;
            
            lutSample = lut.sample(s, color.b);
            float b = lutSample.b;
            
            return float3(r, g, b);
        }

        // 应用色温
        float3 applyTemperature(float3 color, float temp, float tint) {
            // 色温：暖 = +R -B，冷 = -R +B
            color.r += temp * 0.1;
            color.b -= temp * 0.1;
            // 色调：绿 = +G，品红 = -G
            color.g += tint * 0.05;
            return clamp(color, 0.0, 1.0);
        }

        // 应用饱和度
        float3 applySaturation(float3 color, float sat) {
            float luma = dot(color, float3(0.2126, 0.7152, 0.0722));
            return mix(float3(luma), color, sat);
        }

        // 颜色补偿主函数
        float4 applyColorCompensation(float4 inputColor,
                                       constant ColorCompensationParams &params,
                                       texture1d<float> lut,
                                       sampler lutSampler) {
            if (params.enabled == 0) {
                return inputColor;
            }

            float3 color = inputColor.rgb;

            // 1. sRGB -> Linear
            color = srgbToLinear3(color);

            // 2. 应用 1D LUT
            color = applyLUT(color, lut, lutSampler);

            // 3. 应用色温/色调
            color = applyTemperature(color, params.temperature, params.tint);

            // 4. 应用饱和度
            color = applySaturation(color, params.saturation);

            // 5. Linear -> sRGB
            color = linearToSrgb3(color);

            return float4(color, inputColor.a);
        }

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
                                        texture1d<float> lut [[texture(1)]],
                                        sampler textureSampler [[sampler(0)]],
                                        sampler lutSampler [[sampler(1)]],
                                        constant ColorCompensationParams &colorParams [[buffer(0)]]) {
            float4 color = texture.sample(textureSampler, in.texCoord);
            color = applyColorCompensation(color, colorParams, lut, lutSampler);
            return color;
        }
        """

        do {
            let library = try device.makeLibrary(source: shaderSource, options: nil)
            let vertexFunction = library.makeFunction(name: "vertexShader")
            let fragmentFunction = library.makeFunction(name: "fragmentShader")

            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = vertexFunction
            descriptor.fragmentFunction = fragmentFunction
            descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
            descriptor.colorAttachments[0].isBlendingEnabled = true
            descriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
            descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
            descriptor.colorAttachments[0].sourceAlphaBlendFactor = .one
            descriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha

            return try device.makeRenderPipelineState(descriptor: descriptor)
        } catch {
            AppLogger.rendering.error("编译着色器失败: \(error.localizedDescription)")
            return nil
        }
    }
}
