//
//  ColorCompensationFilter.swift
//  ScreenPresenter
//
//  Created by Sun on 2026/1/4.
//
//  颜色补偿滤镜
//  管理 1D LUT 纹理和补偿参数，供渲染管线使用
//  支持多实例，每个设备面板可以使用独立的滤镜实例
//

import Foundation
import Metal
import simd

// MARK: - 颜色补偿参数结构（与 Shader 对应）

/// 颜色补偿 Shader 参数
/// 必须与 Metal Shader 中的结构体内存布局一致
struct ColorCompensationParams {
    var temperature: Float // 色温偏移
    var tint: Float // 色调偏移
    var saturation: Float // 饱和度
    var enabled: Int32 // 是否启用（使用 Int32 避免 bool 对齐问题）

    init(temperature: Float, tint: Float, saturation: Float, enabled: Bool) {
        self.temperature = temperature
        self.tint = tint
        self.saturation = saturation
        self.enabled = enabled ? 1 : 0
    }

    init(profile: ColorProfile, enabled: Bool) {
        self.temperature = profile.temperature
        self.tint = profile.tint
        self.saturation = profile.saturation
        self.enabled = enabled ? 1 : 0
    }

    /// 禁用状态的默认参数
    static let disabled = ColorCompensationParams(
        temperature: 0,
        tint: 0,
        saturation: 1,
        enabled: false
    )
}

// MARK: - 颜色补偿滤镜协议

/// 颜色补偿滤镜协议
/// 为未来扩展 3D LUT 等模式预留接口
protocol ColorCompensationFilterProtocol: AnyObject {
    /// 是否启用
    var isEnabled: Bool { get set }

    /// 当前配置
    var profile: ColorProfile { get set }

    /// 更新 LUT 纹理
    func updateLUT()

    /// 获取参数 Buffer
    func getUniformBuffer() -> MTLBuffer?

    /// 获取 LUT 纹理（RGBA16Float 格式，256x1）
    func getLUTTexture() -> MTLTexture?
}

// MARK: - 1D LUT 颜色补偿滤镜

/// 1D LUT 颜色补偿滤镜
/// 使用 256 级 1D LUT 进行颜色预补偿
/// 支持多实例，每个设备面板可以使用独立的滤镜
final class ColorCompensationFilter: ColorCompensationFilterProtocol {
    // MARK: - 共享 Metal 设备

    private static var sharedDevice: MTLDevice? = MTLCreateSystemDefaultDevice()

    // MARK: - 属性

    /// 是否启用
    var isEnabled: Bool = false {
        didSet {
            if oldValue != isEnabled {
                updateUniformBuffer()
            }
        }
    }

    /// 当前配置
    var profile: ColorProfile = .neutral {
        didSet {
            if oldValue != profile {
                updateLUT()
                updateUniformBuffer()
            }
        }
    }

    // MARK: - Metal 资源

    private var device: MTLDevice?
    private var lutTexture: MTLTexture?
    private var uniformBuffer: MTLBuffer?
    private let bufferLock = NSLock()

    // MARK: - Triple Buffering

    private var uniformBuffers: [MTLBuffer] = []
    private var currentBufferIndex = 0
    private let bufferCount = 3

    // MARK: - 初始化

    init() {
        setupMetal()
    }

    private func setupMetal() {
        guard let device = Self.sharedDevice else {
            AppLogger.rendering.error("ColorCompensationFilter: 无法获取 Metal 设备")
            return
        }
        self.device = device

        // 创建 Triple Buffering 的 Uniform Buffer
        let bufferSize = MemoryLayout<ColorCompensationParams>.stride
        for _ in 0 ..< bufferCount {
            if let buffer = device.makeBuffer(length: bufferSize, options: .storageModeShared) {
                uniformBuffers.append(buffer)
            }
        }

        // 创建初始 LUT 纹理
        updateLUT()
        updateUniformBuffer()

        AppLogger.rendering.debug("ColorCompensationFilter: 实例初始化成功")
    }

    // MARK: - LUT 管理

    /// 更新 LUT 纹理
    func updateLUT() {
        guard let device else { return }

        bufferLock.lock()
        defer { bufferLock.unlock() }

        // 生成 LUT 数据
        let luts = LUTGenerator.generateLUT(from: profile)

        // 创建纹理描述符（RGBA16Float 格式，256x1）
        let descriptor = MTLTextureDescriptor()
        descriptor.textureType = .type1D
        descriptor.pixelFormat = .rgba16Float
        descriptor.width = LUTGenerator.lutSize
        descriptor.height = 1
        descriptor.depth = 1
        descriptor.mipmapLevelCount = 1
        descriptor.usage = [.shaderRead]
        descriptor.storageMode = .shared

        // 创建纹理
        guard let texture = device.makeTexture(descriptor: descriptor) else {
            AppLogger.rendering.error("ColorCompensationFilter: 无法创建 LUT 纹理")
            return
        }

        // 转换数据并上传
        let rgbaData = LUTGenerator.convertToRGBA16FloatData(r: luts.r, g: luts.g, b: luts.b)
        rgbaData.withUnsafeBytes { rawBuffer in
            texture.replace(
                region: MTLRegion(origin: MTLOrigin(x: 0, y: 0, z: 0),
                                  size: MTLSize(width: LUTGenerator.lutSize, height: 1, depth: 1)),
                mipmapLevel: 0,
                withBytes: rawBuffer.baseAddress!,
                bytesPerRow: LUTGenerator.lutSize * 8 // 4 通道 * 2 字节
            )
        }

        lutTexture = texture
    }

    /// 更新 Uniform Buffer
    private func updateUniformBuffer() {
        bufferLock.lock()
        defer { bufferLock.unlock() }

        guard !uniformBuffers.isEmpty else { return }

        // 使用下一个 Buffer（Triple Buffering）
        currentBufferIndex = (currentBufferIndex + 1) % bufferCount
        let buffer = uniformBuffers[currentBufferIndex]

        // 写入参数
        let params = ColorCompensationParams(profile: profile, enabled: isEnabled)
        buffer.contents().storeBytes(of: params, as: ColorCompensationParams.self)

        uniformBuffer = buffer
    }

    // MARK: - 公开方法

    /// 获取当前 Uniform Buffer
    func getUniformBuffer() -> MTLBuffer? {
        bufferLock.lock()
        defer { bufferLock.unlock() }
        return uniformBuffer
    }

    /// 获取 LUT 纹理
    func getLUTTexture() -> MTLTexture? {
        bufferLock.lock()
        defer { bufferLock.unlock() }
        return lutTexture
    }

    /// 临时禁用（AB 对比）
    /// - Parameter disabled: 是否禁用
    func setTemporaryBypass(_ bypassed: Bool) {
        bufferLock.lock()
        defer { bufferLock.unlock() }

        guard !uniformBuffers.isEmpty else { return }

        // 更新当前 Buffer 的 enabled 状态
        let buffer = uniformBuffers[currentBufferIndex]
        let params = ColorCompensationParams(profile: profile, enabled: isEnabled && !bypassed)
        buffer.contents().storeBytes(of: params, as: ColorCompensationParams.self)
    }
}

// MARK: - 扩展：采样器配置

extension ColorCompensationFilter {
    /// 创建 LUT 采样器描述符
    /// 使用线性插值以获得平滑的颜色过渡
    static func createLUTSamplerDescriptor() -> MTLSamplerDescriptor {
        let descriptor = MTLSamplerDescriptor()
        descriptor.minFilter = .linear
        descriptor.magFilter = .linear
        descriptor.sAddressMode = .clampToEdge
        descriptor.tAddressMode = .clampToEdge
        descriptor.rAddressMode = .clampToEdge
        return descriptor
    }
}
