//
//  ScrcpyVideoStreamParser.swift
//  ScreenPresenter
//
//  Created by Sun on 2025/12/24.
//
//  Scrcpy 视频流解析器
//  解析 scrcpy 标准协议：meta + frame header + AnnexB 格式的 H.264/H.265 码流
//

import CoreMedia
import Foundation
import VideoToolbox

// MARK: - Scrcpy 协议元数据

/// Scrcpy 设备元数据（64 字节）
struct ScrcpyDeviceMeta {
    /// 设备名称
    let deviceName: String

    /// 从数据解析
    static func parse(from data: Data) -> ScrcpyDeviceMeta? {
        guard data.count >= 64 else {
            AppLogger.capture.warning("[ScrcpyMeta] 设备元数据长度不足 - 期望: 64, 实际: \(data.count)")
            return nil
        }

        // 设备名称是 64 字节的 UTF-8 字符串，以 null 结尾
        let nameData = data.prefix(64)
        let name = nameData.withUnsafeBytes { buffer -> String in
            let bytes = buffer.bindMemory(to: UInt8.self)
            // 找到 null 终止符
            var length = 64
            for i in 0..<64 {
                if bytes[i] == 0 {
                    length = i
                    break
                }
            }
            return String(decoding: bytes.prefix(length), as: UTF8.self)
        }

        return ScrcpyDeviceMeta(deviceName: name)
    }
}

/// Scrcpy 视频编解码器元数据（12 字节）
/// 根据 scrcpy 文档：codec id (u32) + width (u32) + height (u32)
struct ScrcpyCodecMeta {
    /// 编解码器 ID（大端序 32 位整数）
    let codecId: UInt32

    /// 初始视频宽度
    let width: UInt32

    /// 初始视频高度
    let height: UInt32

    /// 字节大小
    static let size = 12

    /// 编解码器名称
    var codecName: String {
        // scrcpy 使用 FourCC 编码
        let bytes = withUnsafeBytes(of: codecId.bigEndian) { Array($0) }
        return String(bytes: bytes, encoding: .ascii) ?? "Unknown"
    }

    /// 对应的 CMVideoCodecType
    var cmCodecType: CMVideoCodecType {
        switch codecId {
        case 0x6832_3634: // "h264"
            kCMVideoCodecType_H264
        case 0x6832_3635: // "h265" 或 "hevc"
            kCMVideoCodecType_HEVC
        default:
            kCMVideoCodecType_H264
        }
    }

    /// 从数据解析（12 字节）
    static func parse(from data: Data) -> ScrcpyCodecMeta? {
        guard data.count >= 12 else {
            AppLogger.capture.warning("[ScrcpyMeta] 编解码器元数据长度不足 - 期望: 12, 实际: \(data.count)")
            return nil
        }

        // scrcpy 协议使用大端序
        var codecId: UInt32 = 0
        var width: UInt32 = 0
        var height: UInt32 = 0

        data.withUnsafeBytes { buffer in
            let bytes = buffer.bindMemory(to: UInt8.self)

            // codec id (bytes 0-3)
            codecId = UInt32(bytes[0]) << 24
            codecId |= UInt32(bytes[1]) << 16
            codecId |= UInt32(bytes[2]) << 8
            codecId |= UInt32(bytes[3])

            // width (bytes 4-7)
            width = UInt32(bytes[4]) << 24
            width |= UInt32(bytes[5]) << 16
            width |= UInt32(bytes[6]) << 8
            width |= UInt32(bytes[7])

            // height (bytes 8-11)
            height = UInt32(bytes[8]) << 24
            height |= UInt32(bytes[9]) << 16
            height |= UInt32(bytes[10]) << 8
            height |= UInt32(bytes[11])
        }

        return ScrcpyCodecMeta(codecId: codecId, width: width, height: height)
    }
}

/// Scrcpy 帧头（12 字节）
struct ScrcpyFrameHeader: Equatable {
    /// 显示时间戳（微秒，大端序 64 位整数）
    let pts: UInt64

    /// 数据包大小（大端序 32 位整数）
    let packetSize: UInt32

    /// 是否为配置包（PTS 的最高位为 1 表示配置包）
    var isConfigPacket: Bool {
        pts & (1 << 63) != 0
    }

    /// 实际 PTS（去掉配置位）
    var actualPTS: UInt64 {
        pts & ~(1 << 63)
    }

    /// CMTime 表示的 PTS
    var cmTime: CMTime {
        CMTime(value: Int64(actualPTS), timescale: 1_000_000)
    }

    /// 从数据解析
    static func parse(from data: Data) -> ScrcpyFrameHeader? {
        guard data.count >= 12 else {
            AppLogger.capture.warning("[ScrcpyMeta] 帧头长度不足 - 期望: 12, 实际: \(data.count)")
            return nil
        }

        // scrcpy 协议使用大端序
        // 需要手动从大端序字节构建数值
        var pts: UInt64 = 0
        var packetSize: UInt32 = 0

        data.withUnsafeBytes { buffer in
            let bytes = buffer.bindMemory(to: UInt8.self)

            // 解析 PTS (8 字节大端序)
            pts = UInt64(bytes[0]) << 56
            pts |= UInt64(bytes[1]) << 48
            pts |= UInt64(bytes[2]) << 40
            pts |= UInt64(bytes[3]) << 32
            pts |= UInt64(bytes[4]) << 24
            pts |= UInt64(bytes[5]) << 16
            pts |= UInt64(bytes[6]) << 8
            pts |= UInt64(bytes[7])

            // 解析 packetSize (4 字节大端序)
            packetSize = UInt32(bytes[8]) << 24
            packetSize |= UInt32(bytes[9]) << 16
            packetSize |= UInt32(bytes[10]) << 8
            packetSize |= UInt32(bytes[11])
        }

        return ScrcpyFrameHeader(pts: pts, packetSize: packetSize)
    }

    /// 字节大小
    static let size = 12
}

// MARK: - NAL 单元类型

/// H.264 NAL 单元类型
enum H264NALUnitType: UInt8 {
    case unspecified = 0
    case sliceNonIDR = 1
    case slicePartitionA = 2
    case slicePartitionB = 3
    case slicePartitionC = 4
    case sliceIDR = 5
    case sei = 6
    case sps = 7
    case pps = 8
    case accessUnitDelimiter = 9
    case endOfSequence = 10
    case endOfStream = 11
    case fillerData = 12

    var isParameterSet: Bool {
        self == .sps || self == .pps
    }

    var isKeyFrame: Bool {
        self == .sliceIDR
    }
}

/// H.265 NAL 单元类型
enum H265NALUnitType: UInt8 {
    case trailN = 0
    case trailR = 1
    case blaWLP = 16
    case blaWRADL = 17
    case blaNLP = 18
    case idrWRADL = 19
    case idrNLP = 20
    case craNUT = 21
    case vps = 32
    case sps = 33
    case pps = 34
    case accessUnitDelimiter = 35
    case eosNUT = 36
    case eobNUT = 37
    case prefixSeiNUT = 39
    case suffixSeiNUT = 40

    var isParameterSet: Bool {
        self == .vps || self == .sps || self == .pps
    }

    var isKeyFrame: Bool {
        (19...21).contains(rawValue) || (16...18).contains(rawValue)
    }
}

// MARK: - 解析后的 NAL 单元

/// 解析后的 NAL 单元
struct ParsedNALUnit {
    /// NAL 类型（原始值）
    let type: UInt8

    /// NAL 数据（不含起始码）
    let data: Data

    /// 是否为参数集（SPS/PPS/VPS）
    let isParameterSet: Bool

    /// 是否为关键帧
    let isKeyFrame: Bool

    /// 编解码类型
    let codecType: CMVideoCodecType
}

// MARK: - 解析器状态

/// 解析器状态
enum ScrcpyParserState: Equatable {
    /// 等待 dummy byte
    case waitingDummyByte
    /// 等待设备元数据
    case waitingDeviceMeta
    /// 等待编解码器元数据
    case waitingCodecMeta
    /// 等待帧头
    case waitingFrameHeader
    /// 等待帧数据
    case waitingFrameData(header: ScrcpyFrameHeader)
    /// 解析帧数据（raw stream 模式）
    case parsingRawStream
}

// MARK: - Scrcpy 视频流解析器

/// Scrcpy 视频流解析器
/// 解析 scrcpy 标准协议的 NAL 单元，提取 SPS/PPS/VPS 参数集
final class ScrcpyVideoStreamParser {
    // MARK: - 属性

    /// 编解码类型（初始值，可能被协议更新）
    private var codecType: CMVideoCodecType

    /// 数据缓冲区
    private var buffer = Data()

    /// 缓冲区锁
    private let bufferLock = NSLock()

    /// VPS 参数集（仅 H.265）
    private(set) var vps: Data?

    /// SPS 参数集
    private(set) var sps: Data?

    /// PPS 参数集
    private(set) var pps: Data?

    /// 上一个 SPS（用于检测分辨率变化）
    private var lastSPS: Data?

    /// 解析统计
    private(set) var parsedNALCount = 0
    private(set) var totalBytesReceived = 0

    // MARK: - 协议元数据

    /// 解析器状态
    private var parserState: ScrcpyParserState = .waitingDummyByte

    /// 设备元数据
    private(set) var deviceMeta: ScrcpyDeviceMeta?

    /// 编解码器元数据
    private(set) var codecMeta: ScrcpyCodecMeta?

    /// 是否使用 raw stream 模式（跳过协议头）
    var useRawStream: Bool = false

    /// 当前帧的 PTS
    private(set) var currentFramePTS: CMTime = .invalid

    // MARK: - 码率统计

    /// 上一秒接收的字节数
    private var bytesReceivedInLastSecond = 0

    /// 上次码率更新时间
    private var lastBitrateUpdateTime = CFAbsoluteTimeGetCurrent()

    /// 当前码率（bps）
    private(set) var currentBitrate: Double = 0

    // MARK: - 回调

    /// SPS 变化回调（分辨率变化）
    var onSPSChanged: ((Data) -> Void)?

    /// 是否已有完整参数集
    var hasCompleteParameterSets: Bool {
        if codecType == kCMVideoCodecType_H264 {
            sps != nil && pps != nil
        } else {
            vps != nil && sps != nil && pps != nil
        }
    }

    /// 当前使用的编解码类型
    var currentCodecType: CMVideoCodecType {
        codecMeta?.cmCodecType ?? codecType
    }

    // MARK: - 初始化

    /// 初始化解析器
    /// - Parameters:
    ///   - codecType: 编解码类型
    ///   - useRawStream: 是否使用 raw stream 模式
    init(codecType: CMVideoCodecType, useRawStream: Bool = false) {
        self.codecType = codecType
        self.useRawStream = useRawStream
        parserState = useRawStream ? .parsingRawStream : .waitingDummyByte
        AppLogger.capture
            .info(
                "[StreamParser] 初始化，编解码器: \(codecType == kCMVideoCodecType_H264 ? "H.264" : "H.265"), rawStream: \(useRawStream)"
            )
    }

    // MARK: - 公开方法

    /// 追加数据并解析
    /// - Parameter data: 接收到的数据
    /// - Returns: 解析出的 NAL 单元列表
    func append(_ data: Data) -> [ParsedNALUnit] {
        bufferLock.lock()
        defer { bufferLock.unlock() }

        buffer.append(data)
        totalBytesReceived += data.count

        // 更新码率统计
        updateBitrateStatistics(bytesReceived: data.count)

        // 根据模式选择解析方式
        if useRawStream || parserState == .parsingRawStream {
            return parseNALUnits()
        } else {
            return parseProtocol()
        }
    }

    /// 重置解析器状态
    func reset() {
        bufferLock.lock()
        defer { bufferLock.unlock() }

        buffer.removeAll()
        vps = nil
        sps = nil
        pps = nil
        lastSPS = nil
        parsedNALCount = 0
        totalBytesReceived = 0
        deviceMeta = nil
        codecMeta = nil
        parserState = useRawStream ? .parsingRawStream : .waitingDummyByte
        currentFramePTS = .invalid
        bytesReceivedInLastSecond = 0
        currentBitrate = 0

        AppLogger.capture.info("[StreamParser] 已重置")
    }

    /// 获取参数集信息字符串（用于日志）
    var parameterSetsDescription: String {
        var parts: [String] = []
        if let vps { parts.append("VPS: \(vps.count)B") }
        if let sps { parts.append("SPS: \(sps.count)B") }
        if let pps { parts.append("PPS: \(pps.count)B") }
        return parts.isEmpty ? "无参数集" : parts.joined(separator: ", ")
    }

    /// 获取协议元数据描述
    var protocolDescription: String {
        var parts: [String] = []
        if let deviceMeta {
            parts.append("设备: \(deviceMeta.deviceName)")
        }
        if let codecMeta {
            parts.append("编解码器: \(codecMeta.codecName)")
        }
        return parts.isEmpty ? "未解析" : parts.joined(separator: ", ")
    }

    // MARK: - 码率统计

    /// 更新码率统计
    private func updateBitrateStatistics(bytesReceived: Int) {
        bytesReceivedInLastSecond += bytesReceived

        let now = CFAbsoluteTimeGetCurrent()
        let elapsed = now - lastBitrateUpdateTime

        if elapsed >= 1.0 {
            currentBitrate = Double(bytesReceivedInLastSecond * 8) / elapsed
            bytesReceivedInLastSecond = 0
            lastBitrateUpdateTime = now
        }
    }

    // MARK: - 协议解析

    /// 协议解析帧计数（用于调试）
    private var frameCount = 0

    /// 解析 scrcpy 协议
    private func parseProtocol() -> [ParsedNALUnit] {
        var nalUnits: [ParsedNALUnit] = []

        while true {
            switch parserState {
            case .waitingDummyByte:
                // 等待 1 字节的 dummy byte
                // scrcpy 的 dummy byte 应该是 0x00
                guard buffer.count >= 1 else {
                    print("⏳ [StreamParser] 等待 dummy byte，缓冲区: \(buffer.count) 字节")
                    return nalUnits
                }

                // 打印前几个字节用于诊断
                let previewCount = min(10, buffer.count)
                let preview = buffer.prefix(previewCount).map { String(format: "%02X", $0) }.joined(separator: " ")
                print("🔍 [StreamParser] 缓冲区前\(previewCount)字节: \(preview)")

                let firstByte = buffer[0]
                // 检查是否是真正的 dummy byte (0x00)
                // 如果不是 0x00，可能服务端没有发送 dummy byte
                if firstByte == 0x00 {
                    buffer.removeFirst(1)
                    print("✅ [StreamParser] 收到 dummy byte: 0x00")
                    AppLogger.capture.info("[StreamParser] 收到 dummy byte: 0x00")
                } else {
                    // 不是 0x00，假设没有 dummy byte，直接进入设备元数据阶段
                    print("⚠️ [StreamParser] 首字节不是 0x00 (是 0x\(String(format: "%02X", firstByte)))，跳过 dummy byte 阶段")
                }
                parserState = .waitingDeviceMeta

            case .waitingDeviceMeta:
                // 等待 64 字节的设备元数据
                guard buffer.count >= 64 else {
                    print("⏳ [StreamParser] 等待设备元数据，缓冲区: \(buffer.count)/64 字节")
                    return nalUnits
                }
                let metaData = buffer.prefix(64)
                buffer.removeFirst(64)

                if let meta = ScrcpyDeviceMeta.parse(from: Data(metaData)) {
                    deviceMeta = meta
                    print("✅ [StreamParser] 设备元数据: \(meta.deviceName)")
                    AppLogger.capture.info("[StreamParser] ✅ 设备元数据: \(meta.deviceName)")
                } else {
                    print("❌ [StreamParser] 设备元数据解析失败")
                    AppLogger.capture.warning("[StreamParser] ⚠️ 设备元数据解析失败")
                }
                parserState = .waitingCodecMeta

            case .waitingCodecMeta:
                // 等待 12 字节的编解码器元数据 (codec id + width + height)
                guard buffer.count >= ScrcpyCodecMeta.size else {
                    print("⏳ [StreamParser] 等待编解码器元数据，缓冲区: \(buffer.count)/\(ScrcpyCodecMeta.size) 字节")
                    return nalUnits
                }

                let codecData = Data(buffer.prefix(ScrcpyCodecMeta.size))

                // 打印原始字节用于诊断
                let hexStr = codecData.map { String(format: "%02X", $0) }.joined(separator: " ")
                print("🔍 [StreamParser] 编解码器元数据原始字节: \(hexStr)")

                buffer.removeFirst(ScrcpyCodecMeta.size)

                if let meta = ScrcpyCodecMeta.parse(from: codecData) {
                    codecMeta = meta
                    codecType = meta.cmCodecType
                    print("✅ [StreamParser] 编解码器: \(meta.codecName), 分辨率: \(meta.width)x\(meta.height)")
                    AppLogger.capture
                        .info(
                            "[StreamParser] ✅ 编解码器元数据: \(meta.codecName), 分辨率: \(meta.width)x\(meta.height)"
                        )
                } else {
                    print("❌ [StreamParser] 编解码器元数据解析失败")
                    AppLogger.capture.warning("[StreamParser] ⚠️ 编解码器元数据解析失败")
                }
                parserState = .waitingFrameHeader

            case .waitingFrameHeader:
                // 等待 12 字节的帧头
                guard buffer.count >= ScrcpyFrameHeader.size else {
                    if frameCount == 0 {
                        print("⏳ [StreamParser] 等待首个帧头，缓冲区: \(buffer.count)/12 字节")
                    }
                    return nalUnits
                }
                let headerData = Data(buffer.prefix(ScrcpyFrameHeader.size))

                // 打印帧头原始字节用于诊断
                if frameCount < 3 {
                    let hexStr = headerData.map { String(format: "%02X", $0) }.joined(separator: " ")
                    print("🔍 [StreamParser] 帧头#\(frameCount + 1)原始字节: \(hexStr)")
                }

                buffer.removeFirst(ScrcpyFrameHeader.size)

                guard let header = ScrcpyFrameHeader.parse(from: headerData) else {
                    print("❌ [StreamParser] 帧头解析失败")
                    AppLogger.capture.warning("[StreamParser] ⚠️ 帧头解析失败")
                    continue
                }

                frameCount += 1
                if frameCount <= 3 {
                    print(
                        "📦 [StreamParser] 帧头#\(frameCount): PTS=\(header.pts), 大小=\(header.packetSize), 配置包=\(header.isConfigPacket)"
                    )
                }

                currentFramePTS = header.cmTime
                parserState = .waitingFrameData(header: header)

            case let .waitingFrameData(header):
                // 等待帧数据
                guard buffer.count >= Int(header.packetSize) else {
                    if frameCount <= 3 {
                        print("⏳ [StreamParser] 等待帧#\(frameCount)数据，缓冲区: \(buffer.count)/\(header.packetSize) 字节")
                    }
                    return nalUnits
                }
                let frameData = buffer.prefix(Int(header.packetSize))
                buffer.removeFirst(Int(header.packetSize))

                // 解析帧数据中的 NAL 单元
                let parsedUnits = parseNALUnitsFromData(Data(frameData), pts: header.cmTime)
                nalUnits.append(contentsOf: parsedUnits)

                if frameCount <= 5 {
                    print("📦 [StreamParser] 帧#\(frameCount): \(header.packetSize)字节 -> \(parsedUnits.count)个NAL")
                }

                parserState = .waitingFrameHeader

            case .parsingRawStream:
                // Raw stream 模式，直接解析 NAL 单元
                let parsedUnits = parseNALUnits()
                nalUnits.append(contentsOf: parsedUnits)
                return nalUnits
            }
        }
    }

    /// 从帧数据中解析 NAL 单元
    private func parseNALUnitsFromData(_ data: Data, pts: CMTime) -> [ParsedNALUnit] {
        var nalUnits: [ParsedNALUnit] = []
        let tempBuffer = data
        var searchStart = 0

        while searchStart < tempBuffer.count - 4 {
            // 查找当前起始码
            guard let startCodeInfo = findStartCodeInData(tempBuffer, from: searchStart) else {
                searchStart += 1
                continue
            }

            let (startCodeOffset, startCodeLength) = startCodeInfo
            let nalStart = startCodeOffset + startCodeLength

            // 查找下一个起始码
            var nalEnd = tempBuffer.count
            if let nextStartCode = findStartCodeInData(tempBuffer, from: nalStart) {
                nalEnd = nextStartCode.0
            }

            // 提取 NAL 单元数据
            let nalData = tempBuffer.subdata(in: nalStart..<nalEnd)
            if let nalUnit = parseNALUnit(data: nalData, pts: pts) {
                nalUnits.append(nalUnit)
                parsedNALCount += 1
            }

            searchStart = nalEnd
        }

        return nalUnits
    }

    /// 在数据中查找起始码
    private func findStartCodeInData(_ data: Data, from: Int) -> (Int, Int)? {
        var i = from
        while i < data.count - 3 {
            if data[i] == 0x00, data[i + 1] == 0x00, data[i + 2] == 0x00, data[i + 3] == 0x01 {
                return (i, 4)
            }
            if data[i] == 0x00, data[i + 1] == 0x00, data[i + 2] == 0x01 {
                return (i, 3)
            }
            i += 1
        }
        return nil
    }

    // MARK: - 私有方法

    /// 解析缓冲区中的 NAL 单元
    private func parseNALUnits() -> [ParsedNALUnit] {
        var nalUnits: [ParsedNALUnit] = []
        var searchStart = 0

        // 查找起始码 (0x00 0x00 0x00 0x01 或 0x00 0x00 0x01)
        while searchStart < buffer.count - 4 {
            // 查找当前起始码
            guard let startCodeInfo = findStartCode(from: searchStart) else {
                searchStart += 1
                continue
            }

            let (startCodeOffset, startCodeLength) = startCodeInfo
            let nalStart = startCodeOffset + startCodeLength

            // 查找下一个起始码
            var nalEnd = buffer.count
            if let nextStartCode = findStartCode(from: nalStart) {
                nalEnd = nextStartCode.0
            } else {
                // 没有找到下一个起始码，保留当前数据等待更多数据
                break
            }

            // 提取 NAL 单元数据
            let nalData = buffer.subdata(in: nalStart..<nalEnd)
            if let nalUnit = parseNALUnit(data: nalData) {
                nalUnits.append(nalUnit)
                parsedNALCount += 1
            }

            searchStart = nalEnd
        }

        // 移除已处理的数据
        if searchStart > 0 {
            buffer.removeSubrange(0..<searchStart)
        }

        return nalUnits
    }

    /// 查找起始码
    /// - Parameter from: 搜索起始位置
    /// - Returns: (起始码位置, 起始码长度) 或 nil
    private func findStartCode(from: Int) -> (Int, Int)? {
        var i = from
        while i < buffer.count - 3 {
            // 检查 4 字节起始码: 0x00 0x00 0x00 0x01
            if
                buffer[i] == 0x00,
                buffer[i + 1] == 0x00,
                buffer[i + 2] == 0x00,
                buffer[i + 3] == 0x01 {
                return (i, 4)
            }

            // 检查 3 字节起始码: 0x00 0x00 0x01
            if
                buffer[i] == 0x00,
                buffer[i + 1] == 0x00,
                buffer[i + 2] == 0x01 {
                return (i, 3)
            }

            i += 1
        }
        return nil
    }

    /// 解析单个 NAL 单元
    private func parseNALUnit(data: Data, pts: CMTime = .invalid) -> ParsedNALUnit? {
        guard !data.isEmpty else {
            AppLogger.capture.warning("[StreamParser] 解析失败: NAL 数据为空")
            return nil
        }

        let nalType: UInt8
        let isParameterSet: Bool
        let isKeyFrame: Bool

        if codecType == kCMVideoCodecType_H264 {
            // H.264: NAL type 在第一个字节的低 5 位
            nalType = data[0] & 0x1f
            let type = H264NALUnitType(rawValue: nalType)
            isParameterSet = type?.isParameterSet ?? false
            isKeyFrame = type?.isKeyFrame ?? false

            // 诊断日志：检查 NAL 类型有效性
            if nalType == 0 || nalType > 31 {
                AppLogger.capture
                    .warning(
                        "[StreamParser] H.264 NAL 类型异常 - 期望: 1-31, 实际: \(nalType), 首字节: 0x\(String(format: "%02X", data[0]))"
                    )
            }

            // 存储参数集并检测变化
            if nalType == H264NALUnitType.sps.rawValue {
                if let lastSPS, lastSPS != data {
                    AppLogger.capture.info("[StreamParser] ⚠️ H.264 SPS 变化，可能分辨率改变")
                    onSPSChanged?(data)
                }
                lastSPS = data
                sps = data
                AppLogger.capture.info("[StreamParser] 收到 H.264 SPS: \(data.count) 字节")
            } else if nalType == H264NALUnitType.pps.rawValue {
                pps = data
                AppLogger.capture.info("[StreamParser] 收到 H.264 PPS: \(data.count) 字节")
            }
        } else {
            // H.265: NAL type 在第一个字节的位 6-1
            nalType = (data[0] >> 1) & 0x3f
            let type = H265NALUnitType(rawValue: nalType)
            isParameterSet = type?.isParameterSet ?? false
            isKeyFrame = type?.isKeyFrame ?? false

            // 诊断日志：检查 NAL 类型有效性
            if nalType > 63 {
                AppLogger.capture
                    .warning(
                        "[StreamParser] H.265 NAL 类型异常 - 期望: 0-63, 实际: \(nalType), 首字节: 0x\(String(format: "%02X", data[0]))"
                    )
            }

            // 存储参数集并检测变化
            if nalType == H265NALUnitType.vps.rawValue {
                vps = data
                AppLogger.capture.info("[StreamParser] 收到 H.265 VPS: \(data.count) 字节")
            } else if nalType == H265NALUnitType.sps.rawValue {
                if let lastSPS, lastSPS != data {
                    AppLogger.capture.info("[StreamParser] ⚠️ H.265 SPS 变化，可能分辨率改变")
                    onSPSChanged?(data)
                }
                lastSPS = data
                sps = data
                AppLogger.capture.info("[StreamParser] 收到 H.265 SPS: \(data.count) 字节")
            } else if nalType == H265NALUnitType.pps.rawValue {
                pps = data
                AppLogger.capture.info("[StreamParser] 收到 H.265 PPS: \(data.count) 字节")
            }
        }

        return ParsedNALUnit(
            type: nalType,
            data: data,
            isParameterSet: isParameterSet,
            isKeyFrame: isKeyFrame,
            codecType: codecType
        )
    }
}

// MARK: - AnnexB to AVCC 转换器

/// AnnexB to AVCC 转换器
/// 将 AnnexB 格式（起始码分隔）转换为 AVCC 格式（长度前缀）
enum AnnexBToAVCCConverter {
    /// 将 NAL 单元数据转换为 AVCC 格式
    /// - Parameter nalData: AnnexB 格式的 NAL 数据（不含起始码）
    /// - Returns: AVCC 格式的数据（4字节长度前缀 + NAL 数据）
    static func convert(_ nalData: Data) -> Data {
        // AVCC 格式使用 4 字节大端序长度前缀
        var length = UInt32(nalData.count).bigEndian
        var avccData = Data(bytes: &length, count: 4)
        avccData.append(nalData)
        return avccData
    }

    /// 批量转换多个 NAL 单元
    /// - Parameter nalUnits: NAL 单元列表
    /// - Returns: 合并后的 AVCC 格式数据
    static func convert(_ nalUnits: [ParsedNALUnit]) -> Data {
        var result = Data()
        for nalUnit in nalUnits {
            result.append(convert(nalUnit.data))
        }
        return result
    }
}

// MARK: - 格式描述创建器

/// 视频格式描述创建器
enum VideoFormatDescriptionFactory {
    /// 从 H.264 参数集创建格式描述
    /// - Parameters:
    ///   - sps: SPS 数据
    ///   - pps: PPS 数据
    /// - Returns: 格式描述
    static func createH264FormatDescription(sps: Data, pps: Data) -> CMFormatDescription? {
        var formatDescription: CMFormatDescription?

        let status = sps.withUnsafeBytes { spsBuffer in
            pps.withUnsafeBytes { ppsBuffer in
                let parameterSetPointers: [UnsafePointer<UInt8>] = [
                    spsBuffer.baseAddress!.assumingMemoryBound(to: UInt8.self),
                    ppsBuffer.baseAddress!.assumingMemoryBound(to: UInt8.self),
                ]
                let parameterSetSizes: [Int] = [sps.count, pps.count]

                return CMVideoFormatDescriptionCreateFromH264ParameterSets(
                    allocator: kCFAllocatorDefault,
                    parameterSetCount: 2,
                    parameterSetPointers: parameterSetPointers,
                    parameterSetSizes: parameterSetSizes,
                    nalUnitHeaderLength: 4,
                    formatDescriptionOut: &formatDescription
                )
            }
        }

        if status == noErr {
            AppLogger.capture.info("[FormatFactory] ✅ H.264 格式描述创建成功")
            return formatDescription
        } else {
            AppLogger.capture.error("[FormatFactory] ❌ H.264 格式描述创建失败，错误码: \(status)")
            return nil
        }
    }

    /// 从 H.265 参数集创建格式描述
    /// - Parameters:
    ///   - vps: VPS 数据
    ///   - sps: SPS 数据
    ///   - pps: PPS 数据
    /// - Returns: 格式描述
    static func createH265FormatDescription(vps: Data, sps: Data, pps: Data) -> CMFormatDescription? {
        var formatDescription: CMFormatDescription?

        let status = vps.withUnsafeBytes { vpsBuffer in
            sps.withUnsafeBytes { spsBuffer in
                pps.withUnsafeBytes { ppsBuffer in
                    let parameterSetPointers: [UnsafePointer<UInt8>] = [
                        vpsBuffer.baseAddress!.assumingMemoryBound(to: UInt8.self),
                        spsBuffer.baseAddress!.assumingMemoryBound(to: UInt8.self),
                        ppsBuffer.baseAddress!.assumingMemoryBound(to: UInt8.self),
                    ]
                    let parameterSetSizes: [Int] = [vps.count, sps.count, pps.count]

                    return CMVideoFormatDescriptionCreateFromHEVCParameterSets(
                        allocator: kCFAllocatorDefault,
                        parameterSetCount: 3,
                        parameterSetPointers: parameterSetPointers,
                        parameterSetSizes: parameterSetSizes,
                        nalUnitHeaderLength: 4,
                        extensions: nil,
                        formatDescriptionOut: &formatDescription
                    )
                }
            }
        }

        if status == noErr {
            AppLogger.capture.info("[FormatFactory] ✅ H.265 格式描述创建成功")
            return formatDescription
        } else {
            AppLogger.capture.error("[FormatFactory] ❌ H.265 格式描述创建失败，错误码: \(status)")
            return nil
        }
    }
}
