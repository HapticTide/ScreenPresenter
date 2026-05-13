//
//  ScrcpyAudioStreamParser.swift
//  ScreenPresenter
//
//  Created by Sun on 2026/1/6.
//
//  Scrcpy 音频流解析器
//  解析 scrcpy-server 发送的音频数据包
//

import Foundation

// MARK: - Scrcpy 音频流解析器

/// Scrcpy 音频流解析器
/// 解析 scrcpy-server 发送的音频数据包格式：
/// - 首先接收 4 字节的 codec_id
/// - 然后是连续的数据包，每个包包含：
///   - 8 字节 PTS（前 2 位是标志位）
///   - 4 字节 packet_size
///   - packet_size 字节的音频数据
final class ScrcpyAudioStreamParser {
    // MARK: - 常量

    /// 数据包头大小
    private static let packetHeaderSize = 12

    /// 配置包标志位
    private static let packetFlagConfig: UInt64 = 1 << 62

    /// 关键帧标志位
    private static let packetFlagKeyFrame: UInt64 = 1 << 61

    /// PTS 掩码（去掉标志位）
    private static let ptsMask: UInt64 = (1 << 61) - 1

    // MARK: - Codec ID 定义

    /// Opus 编解码器 ID
    static let codecIdOpus: UInt32 = 0x6f70_7573 // "opus" in ASCII

    /// AAC 编解码器 ID
    static let codecIdAAC: UInt32 = 0x0061_6163 // "aac" in ASCII

    /// FLAC 编解码器 ID
    static let codecIdFLAC: UInt32 = 0x666c_6163 // "flac" in ASCII

    /// RAW PCM 编解码器 ID
    static let codecIdRAW: UInt32 = 0x0072_6177 // "raw" in ASCII

    // MARK: - 属性

    /// 已接收的 codec_id
    private(set) var codecId: UInt32?

    /// 是否已解析 codec_id
    private var codecIdParsed = false

    /// 数据缓冲区
    private var buffer = Data()

    /// 解析到的音频数据包回调 (data, pts, isConfig, isKeyFrame)
    var onAudioPacket: ((Data, UInt64, Bool, Bool) -> Void)?

    /// Config Packet 回调 (data, codecId)
    var onConfigPacket: ((Data, UInt32) -> Void)?

    /// Codec ID 解析完成回调
    var onCodecIdParsed: ((UInt32) -> Void)?

    // MARK: - 初始化

    init() {}

    // MARK: - 公开方法

    /// 处理接收到的数据
    /// - Parameter data: 原始网络数据
    func processData(_ data: Data) {
        buffer.append(data)

        // 首先解析 codec_id
        if !codecIdParsed {
            parseCodecId()
        }

        // 解析数据包
        while codecIdParsed {
            if !parseNextPacket() {
                break
            }
        }
    }

    /// 重置解析器状态
    func reset() {
        codecId = nil
        codecIdParsed = false
        buffer.removeAll()
    }

    // MARK: - 私有方法

    /// 安全地从 Data 读取 UInt32（大端）
    private func readUInt32BigEndian(from data: Data, at offset: Int) -> UInt32? {
        guard offset + 4 <= data.count else {
            AppLogger.capture.error("[AudioStreamParser] 读取 UInt32 越界: offset=\(offset), dataCount=\(data.count)")
            return nil
        }
        let startIndex = data.startIndex
        let byte0 = UInt32(data[startIndex + offset])
        let byte1 = UInt32(data[startIndex + offset + 1])
        let byte2 = UInt32(data[startIndex + offset + 2])
        let byte3 = UInt32(data[startIndex + offset + 3])
        return (byte0 << 24) | (byte1 << 16) | (byte2 << 8) | byte3
    }

    /// 安全地从 Data 读取 UInt64（大端）
    private func readUInt64BigEndian(from data: Data, at offset: Int) -> UInt64? {
        guard offset + 8 <= data.count else {
            AppLogger.capture.error("[AudioStreamParser] 读取 UInt64 越界: offset=\(offset), dataCount=\(data.count)")
            return nil
        }
        let startIndex = data.startIndex
        let byte0 = UInt64(data[startIndex + offset])
        let byte1 = UInt64(data[startIndex + offset + 1])
        let byte2 = UInt64(data[startIndex + offset + 2])
        let byte3 = UInt64(data[startIndex + offset + 3])
        let byte4 = UInt64(data[startIndex + offset + 4])
        let byte5 = UInt64(data[startIndex + offset + 5])
        let byte6 = UInt64(data[startIndex + offset + 6])
        let byte7 = UInt64(data[startIndex + offset + 7])
        return (byte0 << 56) | (byte1 << 48) | (byte2 << 40) | (byte3 << 32)
            | (byte4 << 24) | (byte5 << 16) | (byte6 << 8) | byte7
    }

    /// 解析 codec_id
    private func parseCodecId() {
        guard buffer.count >= 4 else { return }

        // 使用安全的字节读取方式
        guard let id = readUInt32BigEndian(from: buffer, at: 0) else { return }
        codecId = id
        buffer.removeFirst(4)
        codecIdParsed = true

        let codecName = switch id {
        case Self.codecIdOpus:
            "opus"
        case Self.codecIdAAC:
            "aac"
        case Self.codecIdFLAC:
            "flac"
        case Self.codecIdRAW:
            "raw"
        default:
            String(format: "0x%08x", id)
        }
        AppLogger.capture.info("[AudioStreamParser] 音频编解码器: \(codecName)")
        onCodecIdParsed?(id)
    }

    /// 解析下一个数据包
    /// - Returns: 是否成功解析了一个完整的数据包
    private func parseNextPacket() -> Bool {
        // 检查是否有足够的头数据
        guard buffer.count >= Self.packetHeaderSize else { return false }

        // 使用安全的字节读取方式读取 PTS 和 packet_size
        guard
            let ptsAndFlags = readUInt64BigEndian(from: buffer, at: 0),
            let packetSize = readUInt32BigEndian(from: buffer, at: 8) else {
            return false
        }

        // 检查是否有完整的数据包
        let totalSize = Self.packetHeaderSize + Int(packetSize)
        guard buffer.count >= totalSize else { return false }

        // 安全地提取数据（考虑 Data 的 startIndex）
        let startIndex = buffer.startIndex
        let dataStart = startIndex + Self.packetHeaderSize
        let dataEnd = startIndex + totalSize

        guard
            dataStart >= buffer.startIndex,
            dataEnd <= buffer.endIndex else {
            AppLogger.capture
                .error(
                    "[AudioStreamParser] 提取数据越界: startIndex=\(startIndex), dataStart=\(dataStart), dataEnd=\(dataEnd), bufferEnd=\(buffer.endIndex)"
                )
            return false
        }

        let packetData = buffer.subdata(in: dataStart..<dataEnd)
        buffer.removeFirst(totalSize)

        // 解析标志位
        let isConfig = (ptsAndFlags & Self.packetFlagConfig) != 0
        let isKeyFrame = (ptsAndFlags & Self.packetFlagKeyFrame) != 0
        let pts = ptsAndFlags & Self.ptsMask

        // 如果是 Config Packet，调用专门的回调
        if isConfig, let codecId {
            onConfigPacket?(packetData, codecId)
        }

        // 总是回调，让解码器决定如何处理
        onAudioPacket?(packetData, pts, isConfig, isKeyFrame)

        return true
    }
}
