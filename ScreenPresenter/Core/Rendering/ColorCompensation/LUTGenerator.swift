//
//  LUTGenerator.swift
//  ScreenPresenter
//
//  Created by Sun on 2026/1/4.
//
//  1D LUT 生成器
//  根据 ColorProfile 参数生成 256 级查找表
//

import Foundation

// MARK: - LUT 生成器

/// 1D LUT 生成器
/// 根据 ColorProfile 的亮度曲线参数生成 R/G/B 三通道的 256 级查找表
enum LUTGenerator {
    /// LUT 长度（256 级，对应 8-bit 输入）
    static let lutSize = 256

    // MARK: - 生成方法

    /// 根据 ColorProfile 生成三通道 LUT
    /// - Parameter profile: 颜色补偿配置
    /// - Returns: (R, G, B) 三个通道的 LUT 数组，每个包含 256 个 Float 值 (0.0~1.0)
    static func generateLUT(from profile: ColorProfile) -> (r: [Float], g: [Float], b: [Float]) {
        // 当前实现：三通道使用相同的曲线（未来可扩展为独立通道调整）
        let lut = generateChannelLUT(
            gamma: profile.gamma,
            blackLift: profile.blackLift,
            whiteClip: profile.whiteClip,
            rollOff: profile.highlightRollOff
        )
        return (r: lut, g: lut, b: lut)
    }

    /// 生成单通道 LUT 曲线
    /// - Parameters:
    ///   - gamma: 伽马值 (1.0 = 线性)
    ///   - blackLift: 黑位提升 (正值提升暗部)
    ///   - whiteClip: 白点裁切 (限制最大亮度)
    ///   - rollOff: 高光滚降系数 (柔化高光过渡)
    /// - Returns: 256 个 Float 值的数组
    static func generateChannelLUT(
        gamma: Float,
        blackLift: Float,
        whiteClip: Float,
        rollOff: Float
    ) -> [Float] {
        var lut = [Float](repeating: 0, count: lutSize)

        for i in 0 ..< lutSize {
            var x = Float(i) / Float(lutSize - 1)

            // 1. 应用 Gamma
            // gamma < 1.0: 提亮中间调（曲线上凸）
            // gamma > 1.0: 压暗中间调（曲线下凹）
            if gamma != 1.0, x > 0 {
                x = pow(x, gamma)
            }

            // 2. 应用 Black Lift（提升/压低暗部）
            // 线性映射：output = input * (1 - blackLift) + blackLift
            // blackLift > 0: 提升暗部（黑色变灰）
            // blackLift < 0: 压低暗部（增加对比度）
            if blackLift != 0 {
                x = x * (1.0 - blackLift) + blackLift
            }

            // 3. 应用 Highlight Roll-off（高光柔化）
            // 使用指数衰减平滑高光过渡，防止高光过曝
            if rollOff > 0, x > (1.0 - rollOff) {
                let threshold = 1.0 - rollOff
                let t = (x - threshold) / rollOff
                // 指数衰减曲线：1 - e^(-2t) / (1 - e^(-2))
                let expFactor: Float = 1.0 - exp(-2.0)
                x = threshold + rollOff * (1.0 - exp(-t * 2.0)) / expFactor
            }

            // 4. 应用 White Clip（白点裁切）
            x = min(x, whiteClip)

            // 5. 钳位到有效范围 [0, 1]
            lut[i] = max(0.0, min(1.0, x))
        }

        return lut
    }

    // MARK: - 验证方法

    /// 验证 LUT 是否单调递增（非严格）
    /// - Parameter lut: LUT 数组
    /// - Returns: 是否单调递增
    static func isMonotonic(_ lut: [Float]) -> Bool {
        for i in 1 ..< lut.count {
            if lut[i] < lut[i - 1] {
                return false
            }
        }
        return true
    }

    /// 生成恒等 LUT（无变换）
    /// - Returns: 256 个线性映射值
    static func generateIdentityLUT() -> [Float] {
        (0 ..< lutSize).map { Float($0) / Float(lutSize - 1) }
    }

    // MARK: - 调试方法

    /// 打印 LUT 曲线（用于调试）
    /// - Parameters:
    ///   - lut: LUT 数组
    ///   - samplePoints: 采样点数（默认 16）
    static func debugPrintLUT(_ lut: [Float], samplePoints: Int = 16) {
        let step = max(1, (lutSize - 1) / (samplePoints - 1))
        var output = "LUT Curve:\n"
        for i in stride(from: 0, to: lutSize, by: step) {
            let input = Float(i) / Float(lutSize - 1)
            let inputPercent = Int(input * 100)
            let outputPercent = Int(lut[i] * 100)
            output += String(format: "  %3d%% → %3d%%\n", inputPercent, outputPercent)
        }
        print(output)
    }
}

// MARK: - 扩展：转换为 Metal 纹理数据

extension LUTGenerator {
    /// 将 LUT 转换为 16-bit Float 数据（用于 MTLTexture）
    /// - Parameter lut: LUT 数组
    /// - Returns: 16-bit Float 数据
    static func convertToFloat16Data(_ lut: [Float]) -> Data {
        var data = Data(capacity: lut.count * 2)
        for value in lut {
            var float16 = float16FromFloat32(value)
            data.append(Data(bytes: &float16, count: 2))
        }
        return data
    }

    /// Float32 转 Float16
    /// - Parameter value: 32-bit 浮点数
    /// - Returns: 16-bit 浮点数
    private static func float16FromFloat32(_ value: Float) -> UInt16 {
        let bits = value.bitPattern

        let sign = (bits >> 31) & 0x1
        let exponent = Int((bits >> 23) & 0xFF) - 127
        let mantissa = bits & 0x7F_FFFF

        // 处理特殊情况
        if exponent > 15 {
            // 溢出，返回最大值
            return UInt16(sign << 15) | 0x7C00
        } else if exponent < -14 {
            // 下溢，返回 0
            return UInt16(sign << 15)
        }

        let f16Exponent = UInt16(exponent + 15)
        let f16Mantissa = UInt16(mantissa >> 13)

        return UInt16(sign << 15) | (f16Exponent << 10) | f16Mantissa
    }

    /// 将 RGB 三通道 LUT 合并为 RGBA 格式数据
    /// - Parameters:
    ///   - r: R 通道 LUT
    ///   - g: G 通道 LUT
    ///   - b: B 通道 LUT
    /// - Returns: RGBA16Float 格式数据
    static func convertToRGBA16FloatData(r: [Float], g: [Float], b: [Float]) -> Data {
        precondition(r.count == lutSize && g.count == lutSize && b.count == lutSize)

        var data = Data(capacity: lutSize * 8) // 4 通道 * 2 字节
        for i in 0 ..< lutSize {
            var rVal = float16FromFloat32(r[i])
            var gVal = float16FromFloat32(g[i])
            var bVal = float16FromFloat32(b[i])
            var aVal = float16FromFloat32(1.0) // Alpha 固定为 1

            data.append(Data(bytes: &rVal, count: 2))
            data.append(Data(bytes: &gVal, count: 2))
            data.append(Data(bytes: &bVal, count: 2))
            data.append(Data(bytes: &aVal, count: 2))
        }
        return data
    }
}
