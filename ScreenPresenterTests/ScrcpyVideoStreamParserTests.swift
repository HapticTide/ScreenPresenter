//
//  ScrcpyVideoStreamParserTests.swift
//  ScreenPresenterTests
//
//  Created by Sun on 2025/12/24.
//
//  Scrcpy 视频流解析器单元测试
//  测试 AnnexB 分割、AVCC 转换、协议解析等核心功能
//

import CoreMedia
import VideoToolbox
import XCTest
@testable import ScreenPresenter

// MARK: - AnnexB 分割测试

final class AnnexBSplitTests: XCTestCase {
    // MARK: - 4 字节起始码测试

    func testAnnexBSplitWithFourByteStartCode() {
        // 构造测试数据：4字节起始码 + H.264 SPS
        // SPS NAL type = 7, 第一个字节 = 0x67 (forbidden_zero_bit=0, nal_ref_idc=3, nal_unit_type=7)
        let testData = Data([
            0x00, 0x00, 0x00, 0x01, // 4字节起始码
            0x67, 0x42, 0x00, 0x1e, // SPS 数据
            0x00, 0x00, 0x00, 0x01, // 下一个起始码
            0x68, 0xce, 0x3c, 0x80, // PPS 数据
        ])

        let parser = ScrcpyVideoStreamParser(codecType: kCMVideoCodecType_H264, useRawStream: true)
        let nalUnits = parser.append(testData)

        XCTAssertEqual(nalUnits.count, 1, "应该解析出 1 个 NAL 单元（最后一个等待更多数据）")
        XCTAssertEqual(nalUnits[0].type, 7, "第一个 NAL 应该是 SPS (type=7)")
        XCTAssertTrue(nalUnits[0].isParameterSet, "SPS 应该标记为参数集")
    }

    func testAnnexBSplitWithThreeByteStartCode() {
        // 构造测试数据：3字节起始码 + H.264 IDR
        let testData = Data([
            0x00, 0x00, 0x01, // 3字节起始码
            0x65, 0x88, 0x84, // IDR slice 数据
            0x00, 0x00, 0x01, // 下一个起始码
            0x01, 0x00, 0x00, // Non-IDR slice
        ])

        let parser = ScrcpyVideoStreamParser(codecType: kCMVideoCodecType_H264, useRawStream: true)
        let nalUnits = parser.append(testData)

        XCTAssertEqual(nalUnits.count, 1, "应该解析出 1 个 NAL 单元")
        XCTAssertEqual(nalUnits[0].type, 5, "第一个 NAL 应该是 IDR (type=5)")
        XCTAssertTrue(nalUnits[0].isKeyFrame, "IDR 应该标记为关键帧")
    }

    func testAnnexBSplitMixedStartCodes() {
        // 混合 3 字节和 4 字节起始码
        let testData = Data([
            0x00, 0x00, 0x00, 0x01, // 4字节起始码
            0x67, 0x42, 0x00, 0x1e, // SPS
            0x00, 0x00, 0x01, // 3字节起始码
            0x68, 0xce, 0x3c, 0x80, // PPS
            0x00, 0x00, 0x00, 0x01, // 4字节起始码
            0x65, 0x88, // IDR (部分)
        ])

        let parser = ScrcpyVideoStreamParser(codecType: kCMVideoCodecType_H264, useRawStream: true)
        let nalUnits = parser.append(testData)

        XCTAssertEqual(nalUnits.count, 2, "应该解析出 2 个 NAL 单元")
        XCTAssertEqual(nalUnits[0].type, 7, "第一个应该是 SPS")
        XCTAssertEqual(nalUnits[1].type, 8, "第二个应该是 PPS")
    }

    // MARK: - 流式解析测试

    func testStreamingParse() {
        let parser = ScrcpyVideoStreamParser(codecType: kCMVideoCodecType_H264, useRawStream: true)

        // 分多次追加数据
        let part1 = Data([0x00, 0x00, 0x00, 0x01, 0x67]) // 起始码 + SPS 开始
        let part2 = Data([0x42, 0x00, 0x1e]) // SPS 剩余
        let part3 = Data([0x00, 0x00, 0x00, 0x01, 0x68, 0xce]) // PPS 开始
        let part4 = Data([0x3c, 0x80, 0x00, 0x00, 0x00, 0x01]) // PPS 剩余 + 下一个起始码

        var totalNALs: [ParsedNALUnit] = []

        totalNALs.append(contentsOf: parser.append(part1))
        XCTAssertEqual(totalNALs.count, 0, "第一部分不应该产生完整 NAL")

        totalNALs.append(contentsOf: parser.append(part2))
        XCTAssertEqual(totalNALs.count, 0, "第二部分不应该产生完整 NAL")

        totalNALs.append(contentsOf: parser.append(part3))
        XCTAssertEqual(totalNALs.count, 1, "第三部分应该产生 1 个 NAL (SPS)")

        totalNALs.append(contentsOf: parser.append(part4))
        XCTAssertEqual(totalNALs.count, 2, "第四部分应该累计产生 2 个 NAL")
    }

    // MARK: - H.265 测试

    func testH265NALTypeParsing() {
        // H.265 VPS: NAL type = 32, 第一个字节 = 0x40 (type=32 << 1 | 0 = 0x40)
        let testData = Data([
            0x00, 0x00, 0x00, 0x01, // 起始码
            0x40, 0x01, 0x0c, 0x01, // VPS
            0x00, 0x00, 0x00, 0x01, // 起始码
            0x42, 0x01, 0x01, 0x01, // SPS (type=33)
        ])

        let parser = ScrcpyVideoStreamParser(codecType: kCMVideoCodecType_HEVC, useRawStream: true)
        let nalUnits = parser.append(testData)

        XCTAssertEqual(nalUnits.count, 1, "应该解析出 1 个 NAL 单元")
        XCTAssertEqual(nalUnits[0].type, 32, "第一个 NAL 应该是 VPS (type=32)")
        XCTAssertTrue(nalUnits[0].isParameterSet, "VPS 应该标记为参数集")
    }
}

// MARK: - AVCC 转换测试

final class AnnexBToAVCCConverterTests: XCTestCase {
    func testSingleNALConversion() {
        let nalData = Data([0x67, 0x42, 0x00, 0x1e, 0x95, 0x4c])

        let avccData = AnnexBToAVCCConverter.convert(nalData)

        // 验证长度前缀（大端序）
        XCTAssertEqual(avccData.count, nalData.count + 4, "AVCC 数据应该是 NAL 数据 + 4 字节长度")

        let length = avccData.withUnsafeBytes { buffer -> UInt32 in
            buffer.load(as: UInt32.self).bigEndian
        }
        XCTAssertEqual(Int(length), nalData.count, "长度前缀应该等于 NAL 数据长度")

        // 验证数据内容
        let payload = avccData.suffix(from: 4)
        XCTAssertEqual(payload, nalData, "AVCC payload 应该等于原始 NAL 数据")
    }

    func testEmptyDataConversion() {
        let nalData = Data()
        let avccData = AnnexBToAVCCConverter.convert(nalData)

        XCTAssertEqual(avccData.count, 4, "空数据转换应该只有 4 字节长度前缀")

        let length = avccData.withUnsafeBytes { buffer -> UInt32 in
            buffer.load(as: UInt32.self).bigEndian
        }
        XCTAssertEqual(length, 0, "空数据的长度应该是 0")
    }

    func testLargeDataConversion() {
        // 测试较大的数据
        let nalData = Data(repeating: 0xab, count: 65535)
        let avccData = AnnexBToAVCCConverter.convert(nalData)

        XCTAssertEqual(avccData.count, 65535 + 4)

        let length = avccData.withUnsafeBytes { buffer -> UInt32 in
            buffer.load(as: UInt32.self).bigEndian
        }
        XCTAssertEqual(Int(length), 65535)
    }

    func testBatchConversion() {
        let nalUnit1 = ParsedNALUnit(
            type: 7,
            data: Data([0x67, 0x42, 0x00]),
            isParameterSet: true,
            isKeyFrame: false,
            codecType: kCMVideoCodecType_H264
        )
        let nalUnit2 = ParsedNALUnit(
            type: 8,
            data: Data([0x68, 0xce]),
            isParameterSet: true,
            isKeyFrame: false,
            codecType: kCMVideoCodecType_H264
        )

        let avccData = AnnexBToAVCCConverter.convert([nalUnit1, nalUnit2])

        // 总长度 = 4 + 3 + 4 + 2 = 13
        XCTAssertEqual(avccData.count, 13, "批量转换结果长度应该正确")
    }
}

// MARK: - 协议元数据解析测试

final class ScrcpyProtocolParsingTests: XCTestCase {
    func testDeviceMetaParsing() {
        // 构造 64 字节的设备名称
        var deviceNameBytes = "Pixel 6 Pro".utf8.map(\.self)
        deviceNameBytes.append(contentsOf: [UInt8](repeating: 0, count: 64 - deviceNameBytes.count))
        let data = Data(deviceNameBytes)

        let meta = ScrcpyDeviceMeta.parse(from: data)

        XCTAssertNotNil(meta, "设备元数据应该解析成功")
        XCTAssertEqual(meta?.deviceName, "Pixel 6 Pro", "设备名称应该正确")
    }

    func testDeviceMetaParsingWithNullTerminator() {
        // 设备名称中间有 null 终止符
        var data = Data(repeating: 0, count: 64)
        let name = "Test\0Device"
        data.replaceSubrange(0..<name.utf8.count, with: name.utf8)

        let meta = ScrcpyDeviceMeta.parse(from: data)

        XCTAssertNotNil(meta)
        XCTAssertEqual(meta?.deviceName, "Test", "应该在 null 终止符处截断")
    }

    func testDeviceMetaParsingInsufficientData() {
        let data = Data(repeating: 0x41, count: 32) // 只有 32 字节

        let meta = ScrcpyDeviceMeta.parse(from: data)

        XCTAssertNil(meta, "数据不足时应该返回 nil")
    }

    func testCodecMetaParsing() {
        // H.264 codec ID: "h264" = 0x68323634
        let data = Data([0x68, 0x32, 0x36, 0x34])

        let meta = ScrcpyCodecMeta.parse(from: data)

        XCTAssertNotNil(meta)
        XCTAssertEqual(meta?.codecId, 0x6832_3634)
        XCTAssertEqual(meta?.codecName, "h264")
        XCTAssertEqual(meta?.cmCodecType, kCMVideoCodecType_H264)
    }

    func testCodecMetaParsingHEVC() {
        // H.265 codec ID: "h265" = 0x68323635
        let data = Data([0x68, 0x32, 0x36, 0x35])

        let meta = ScrcpyCodecMeta.parse(from: data)

        XCTAssertNotNil(meta)
        XCTAssertEqual(meta?.cmCodecType, kCMVideoCodecType_HEVC)
    }

    func testFrameHeaderParsing() {
        // PTS = 1000000 (1秒), packetSize = 4096
        var data = Data()
        var pts: UInt64 = 1_000_000
        var size: UInt32 = 4096
        data.append(contentsOf: withUnsafeBytes(of: pts.bigEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: size.bigEndian) { Array($0) })

        let header = ScrcpyFrameHeader.parse(from: data)

        XCTAssertNotNil(header)
        XCTAssertEqual(header?.pts, 1_000_000)
        XCTAssertEqual(header?.packetSize, 4096)
        XCTAssertFalse(header?.isConfigPacket ?? true, "普通帧不应该是配置包")
        XCTAssertEqual(header?.cmTime.seconds, 1.0, accuracy: 0.001)
    }

    func testFrameHeaderParsingConfigPacket() {
        // 配置包：PTS bit62 为 1
        var data = Data()
        var pts: UInt64 = (1 << 62) | 0
        var size: UInt32 = 128
        data.append(contentsOf: withUnsafeBytes(of: pts.bigEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: size.bigEndian) { Array($0) })

        let header = ScrcpyFrameHeader.parse(from: data)

        XCTAssertNotNil(header)
        XCTAssertTrue(header?.isConfigPacket ?? false, "应该识别为配置包")
        XCTAssertEqual(header?.actualPTS, 0, "实际 PTS 应该是 0")
    }

    func testVideoSessionMetaParsing() {
        var data = Data()
        var flags: UInt32 = 0x8000_0000
        var width: UInt32 = 1080
        var height: UInt32 = 1920
        data.append(contentsOf: withUnsafeBytes(of: flags.bigEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: width.bigEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: height.bigEndian) { Array($0) })

        let meta = ScrcpyVideoSessionMeta.parse(from: data)
        let header = ScrcpyFrameHeader.parse(from: data)

        XCTAssertNotNil(meta)
        XCTAssertEqual(meta?.width, 1080)
        XCTAssertEqual(meta?.height, 1920)
        XCTAssertTrue(header?.isSessionMeta ?? false, "应该识别为 session meta")
    }

    func testScrcpy4ProtocolParsingWithSessionMeta() {
        let parser = ScrcpyVideoStreamParser(codecType: kCMVideoCodecType_H264, useRawStream: false)

        var data = Data([0x00])

        var deviceNameBytes = "Pixel 8".utf8.map(\.self)
        deviceNameBytes.append(contentsOf: [UInt8](repeating: 0, count: 64 - deviceNameBytes.count))
        data.append(contentsOf: deviceNameBytes)

        var codecId: UInt32 = 0x6832_3634
        data.append(contentsOf: withUnsafeBytes(of: codecId.bigEndian) { Array($0) })

        var sessionFlags: UInt32 = 0x8000_0000
        var sessionWidth: UInt32 = 1080
        var sessionHeight: UInt32 = 1920
        data.append(contentsOf: withUnsafeBytes(of: sessionFlags.bigEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: sessionWidth.bigEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: sessionHeight.bigEndian) { Array($0) })

        let frameData = Data([
            0x00, 0x00, 0x00, 0x01,
            0x65, 0x88, 0x84, 0x00,
        ])
        var pts: UInt64 = (1 << 61) | 1000
        var packetSize = UInt32(frameData.count)
        data.append(contentsOf: withUnsafeBytes(of: pts.bigEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: packetSize.bigEndian) { Array($0) })
        data.append(frameData)

        let nalUnits = parser.append(data)

        XCTAssertEqual(parser.codecMeta?.codecName, "h264")
        XCTAssertEqual(parser.sessionMeta?.width, 1080)
        XCTAssertEqual(parser.sessionMeta?.height, 1920)
        XCTAssertEqual(nalUnits.count, 1)
        XCTAssertTrue(nalUnits[0].isEffectiveKeyFrame)
    }
}

// MARK: - 参数集提取测试

final class ParameterSetExtractionTests: XCTestCase {
    func testH264ParameterSetExtraction() {
        let parser = ScrcpyVideoStreamParser(codecType: kCMVideoCodecType_H264, useRawStream: true)

        // 发送 SPS + PPS + IDR
        let testData = Data([
            0x00, 0x00, 0x00, 0x01, 0x67, 0x42, 0x00, 0x1e, // SPS
            0x00, 0x00, 0x00, 0x01, 0x68, 0xce, 0x3c, 0x80, // PPS
            0x00, 0x00, 0x00, 0x01, 0x65, 0x88, 0x84, 0x00, // IDR
            0x00, 0x00, 0x00, 0x01, // 终止用起始码
        ])

        _ = parser.append(testData)

        XCTAssertNotNil(parser.sps, "SPS 应该被提取")
        XCTAssertNotNil(parser.pps, "PPS 应该被提取")
        XCTAssertTrue(parser.hasCompleteParameterSets, "应该有完整参数集")
        XCTAssertEqual(parser.sps?.count, 4, "SPS 长度应该正确")
        XCTAssertEqual(parser.pps?.count, 4, "PPS 长度应该正确")
    }

    func testH265ParameterSetExtraction() {
        let parser = ScrcpyVideoStreamParser(codecType: kCMVideoCodecType_HEVC, useRawStream: true)

        // H.265: VPS(32) + SPS(33) + PPS(34)
        let testData = Data([
            0x00, 0x00, 0x00, 0x01, 0x40, 0x01, 0x0c, 0x01, // VPS (type=32)
            0x00, 0x00, 0x00, 0x01, 0x42, 0x01, 0x01, 0x01, // SPS (type=33)
            0x00, 0x00, 0x00, 0x01, 0x44, 0x01, 0xc0, 0x73, // PPS (type=34)
            0x00, 0x00, 0x00, 0x01, // 终止用起始码
        ])

        _ = parser.append(testData)

        XCTAssertNotNil(parser.vps, "VPS 应该被提取")
        XCTAssertNotNil(parser.sps, "SPS 应该被提取")
        XCTAssertNotNil(parser.pps, "PPS 应该被提取")
        XCTAssertTrue(parser.hasCompleteParameterSets, "应该有完整参数集")
    }

    func testResetClearsParameterSets() {
        let parser = ScrcpyVideoStreamParser(codecType: kCMVideoCodecType_H264, useRawStream: true)

        let testData = Data([
            0x00, 0x00, 0x00, 0x01, 0x67, 0x42, 0x00, 0x1e, // SPS
            0x00, 0x00, 0x00, 0x01, 0x68, 0xce, 0x3c, 0x80, // PPS
            0x00, 0x00, 0x00, 0x01, // 终止
        ])

        _ = parser.append(testData)
        XCTAssertTrue(parser.hasCompleteParameterSets)

        parser.reset()

        XCTAssertNil(parser.sps, "重置后 SPS 应该为 nil")
        XCTAssertNil(parser.pps, "重置后 PPS 应该为 nil")
        XCTAssertFalse(parser.hasCompleteParameterSets, "重置后不应该有完整参数集")
    }
}

// MARK: - 边界条件测试

final class EdgeCaseTests: XCTestCase {
    func testEmptyData() {
        let parser = ScrcpyVideoStreamParser(codecType: kCMVideoCodecType_H264, useRawStream: true)
        let nalUnits = parser.append(Data())

        XCTAssertTrue(nalUnits.isEmpty, "空数据不应该产生 NAL 单元")
    }

    func testIncompleteStartCode() {
        let parser = ScrcpyVideoStreamParser(codecType: kCMVideoCodecType_H264, useRawStream: true)

        // 只有部分起始码
        let nalUnits = parser.append(Data([0x00, 0x00]))

        XCTAssertTrue(nalUnits.isEmpty, "不完整起始码不应该产生 NAL 单元")
    }

    func testMultipleResets() {
        let parser = ScrcpyVideoStreamParser(codecType: kCMVideoCodecType_H264, useRawStream: true)

        for _ in 0..<100 {
            _ = parser.append(Data([0x00, 0x00, 0x00, 0x01, 0x67]))
            parser.reset()
        }

        XCTAssertEqual(parser.totalBytesReceived, 0, "重置后统计应该清零")
    }
}
