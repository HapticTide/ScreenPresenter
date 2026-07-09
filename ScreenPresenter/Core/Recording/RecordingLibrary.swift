//
//  RecordingLibrary.swift
//  ScreenPresenter
//
//  Created by Sun on 2026/07/02.
//
//  录制历史扫描模型
//  从录制根目录解析会话、设备轨道和截图索引
//

import AVFoundation
import Foundation

// MARK: - 录制平台

enum RecordingPlatform: String, Hashable {
    case ios = "iOS"
    case android = "Android"

    var sortPriority: Int {
        switch self {
        case .ios:
            0
        case .android:
            1
        }
    }

    var displayName: String {
        switch self {
        case .ios:
            "iOS"
        case .android:
            "Android"
        }
    }
}

// MARK: - 录制截图

struct RecordingSnapshot: Hashable {
    let elapsedSecond: Int
    let fileURL: URL
}

// MARK: - 设备轨道

struct RecordingDeviceTrack: Hashable {
    let platform: RecordingPlatform
    let deviceName: String
    let directory: URL
    let snapshots: [RecordingSnapshot]

    func snapshot(at elapsedSecond: Int) -> RecordingSnapshot? {
        if let snapshot = snapshots.last(where: { $0.elapsedSecond <= elapsedSecond }) {
            return snapshot
        }

        // 设备可能在录制开始后才接入投屏。回放时间早于第一张截图时，
        // 仍显示该设备第一张可用截图，避免回放页出现整块空白。
        return snapshots.first
    }
}

// MARK: - 录制会话

struct RecordingSession: Hashable {
    let directory: URL
    /// 音频文件地址。纯截图录制（无麦克风/拒权限）时为 nil。
    let audioURL: URL?
    let startedAt: Date
    let duration: TimeInterval
    let deviceTracks: [RecordingDeviceTrack]
}

// MARK: - 录制历史扫描

struct RecordingLibrary {
    typealias AudioDurationProvider = (URL) throws -> TimeInterval

    private let rootDirectory: URL
    private let fileManager: FileManager
    private let audioDurationProvider: AudioDurationProvider

    private static let sessionDirectoryFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH-mm-ss"
        return formatter
    }()

    init(
        rootDirectory: URL? = nil,
        fileManager: FileManager = .default,
        audioDurationProvider: @escaping AudioDurationProvider = RecordingLibrary.defaultAudioDuration
    ) {
        self.fileManager = fileManager
        self.rootDirectory = rootDirectory ?? RecordingLibrary.defaultRootDirectory(fileManager: fileManager)
        self.audioDurationProvider = audioDurationProvider
    }

    func scanSessions() throws -> [RecordingSession] {
        guard fileManager.directoryExists(at: rootDirectory) else {
            return []
        }

        let sessionDirectories = try fileManager.contentsOfDirectory(
            at: rootDirectory,
            includingPropertiesForKeys: [.creationDateKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )

        let sessions = sessionDirectories.compactMap { directory -> RecordingSession? in
            guard fileManager.directoryExists(at: directory) else {
                return nil
            }

            let audioFileURL = directory.appendingPathComponent("audio.m4a", isDirectory: false)
            let hasAudio = fileManager.fileExists(atPath: audioFileURL.path)
            let deviceTracks = scanDeviceTracks(in: directory)
            let hasSnapshots = deviceTracks.contains { !$0.snapshots.isEmpty }

            // 无音频且无任何截图才视为无效目录。纯截图录制仍应出现在历史中。
            guard hasAudio || hasSnapshots else {
                return nil
            }

            let audioDuration = hasAudio ? (try? audioDurationProvider(audioFileURL)) ?? 0 : 0
            let duration = audioDuration > 0 ? audioDuration : snapshotDuration(of: deviceTracks)

            return RecordingSession(
                directory: directory,
                audioURL: hasAudio ? audioFileURL : nil,
                startedAt: startedAt(for: directory),
                duration: duration,
                deviceTracks: deviceTracks
            )
        }

        return sessions.sorted { lhs, rhs in
            lhs.startedAt > rhs.startedAt
        }
    }

    /// 无音频时根据截图的最大相对秒估算录制时长。
    private func snapshotDuration(of tracks: [RecordingDeviceTrack]) -> TimeInterval {
        let maxSecond = tracks.compactMap { $0.snapshots.last?.elapsedSecond }.max() ?? 0
        return TimeInterval(maxSecond + 1)
    }

    private func scanDeviceTracks(in sessionDirectory: URL) -> [RecordingDeviceTrack] {
        guard let deviceDirectories = try? fileManager.contentsOfDirectory(
            at: sessionDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            AppLogger.capture.warning("读取录制设备截图目录失败: \(sessionDirectory.path)")
            return []
        }

        let tracks = deviceDirectories.compactMap { directory -> RecordingDeviceTrack? in
            guard fileManager.directoryExists(at: directory),
                  let device = parseDeviceDirectoryName(directory.lastPathComponent) else {
                return nil
            }

            return RecordingDeviceTrack(
                platform: device.platform,
                deviceName: device.deviceName,
                directory: directory,
                snapshots: scanSnapshots(in: directory)
            )
        }

        return tracks.sorted { lhs, rhs in
            if lhs.platform.sortPriority != rhs.platform.sortPriority {
                return lhs.platform.sortPriority < rhs.platform.sortPriority
            }

            let order = lhs.directory.lastPathComponent
                .localizedStandardCompare(rhs.directory.lastPathComponent)
            return order == .orderedAscending
        }
    }

    private func scanSnapshots(in deviceDirectory: URL) -> [RecordingSnapshot] {
        guard let files = try? fileManager.contentsOfDirectory(
            at: deviceDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            AppLogger.capture.warning("读取录制截图文件失败: \(deviceDirectory.path)")
            return []
        }

        let snapshots = files.compactMap { fileURL -> RecordingSnapshot? in
            guard fileURL.pathExtension.lowercased() == "jpg",
                  let elapsedSecond = parseSnapshotElapsedSecond(
                    fileURL.deletingPathExtension().lastPathComponent
                  ) else {
                return nil
            }

            return RecordingSnapshot(elapsedSecond: elapsedSecond, fileURL: fileURL)
        }

        return snapshots.sorted { lhs, rhs in
            lhs.elapsedSecond < rhs.elapsedSecond
        }
    }

    private func parseDeviceDirectoryName(_ name: String) -> (platform: RecordingPlatform, deviceName: String)? {
        for platform in [RecordingPlatform.ios, .android] {
            for prefix in ["\(platform.rawValue)-", "\(platform.rawValue.lowercased())-"] where name.hasPrefix(prefix) {
                return (platform, String(name.dropFirst(prefix.count)))
            }
        }
        return nil
    }

    private func parseSnapshotElapsedSecond(_ baseName: String) -> Int? {
        guard let separatorIndex = baseName.firstIndex(of: "_") else {
            return nil
        }

        let firstComponent = baseName[..<separatorIndex]
        guard firstComponent.count == 6,
              firstComponent.allSatisfy(\.isNumber) else {
            return nil
        }
        return Int(firstComponent)
    }

    private func startedAt(for directory: URL) -> Date {
        if let date = RecordingLibrary.sessionDirectoryFormatter.date(from: directory.lastPathComponent) {
            return date
        }

        let values = try? directory.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
        return values?.creationDate ?? values?.contentModificationDate ?? .distantPast
    }

    private static func defaultRootDirectory(fileManager: FileManager) -> URL {
        let moviesDirectory = fileManager.urls(for: .moviesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Movies", isDirectory: true)

        return moviesDirectory.appendingPathComponent("ScreenPresenter Recordings", isDirectory: true)
    }

    private static func defaultAudioDuration(audioURL: URL) throws -> TimeInterval {
        let audioFile = try AVAudioFile(forReading: audioURL)
        let sampleRate = audioFile.fileFormat.sampleRate
        guard sampleRate > 0 else {
            return 0
        }

        return Double(audioFile.length) / sampleRate
    }
}

private extension FileManager {
    func directoryExists(at url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }
}
