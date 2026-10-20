//
//  RecordingSessionMetadata.swift
//  ScreenPresenter
//
//  Created by Tank on 2026/07/17.
//

import Foundation

// MARK: - 视频配置

struct RecordingVideoConfiguration: Codable, Equatable {
    let codec: String
    let framesPerSecond: Int
    let averageBitRate: Int
    let maxLongSide: Int

    /// 当前视频录制使用固定参数，避免偏好设置与历史文件产生组合兼容问题。
    static let screenRecording = RecordingVideoConfiguration(
        codec: "hevc",
        framesPerSecond: 30,
        averageBitRate: 600_000,
        maxLongSide: 1_280
    )
}

// MARK: - 会话元数据

struct RecordingSessionMetadata: Codable, Equatable {
    static let currentVersion = 2

    let version: Int
    let startedAt: Date
    let durationMilliseconds: Int64
    let video: RecordingVideoConfiguration

    static func encode(_ metadata: RecordingSessionMetadata) throws -> Data {
        try metadataEncoder.encode(metadata)
    }

    static func decode(from data: Data) throws -> RecordingSessionMetadata {
        let metadata = try metadataDecoder.decode(RecordingSessionMetadata.self, from: data)
        guard metadata.version == currentVersion else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return metadata
    }

    private static let metadataEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, valueEncoder in
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            var container = valueEncoder.singleValueContainer()
            try container.encode(formatter.string(from: date))
        }
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    private static let metadataDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { valueDecoder in
            let container = try valueDecoder.singleValueContainer()
            let value = try container.decode(String.self)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            guard let date = formatter.date(from: value) else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "录制会话开始时间不是有效的 ISO-8601 毫秒时间"
                )
            }
            return date
        }
        return decoder
    }()
}

// MARK: - 视频分段文件名

struct RecordingVideoSegmentFileComponents: Equatable {
    let startMilliseconds: Int64
    let sequence: Int
}
