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

    /// 注入的根目录（测试用）；为 nil 时动态读取用户偏好，使保存位置改动即时生效。
    private let injectedRootDirectory: URL?
    private let fileManager: FileManager
    private let audioDurationProvider: AudioDurationProvider

    /// 生效的录制根目录：优先注入值，否则取偏好中的保存位置。
    private var rootDirectory: URL {
        injectedRootDirectory ?? UserPreferences.shared.recordingsRootDirectory(fileManager: fileManager)
    }

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
        self.injectedRootDirectory = rootDirectory
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

        let sessions = sessionDirectories.compactMap(makeSession(from:))

        return sessions.sorted { lhs, rhs in
            lhs.startedAt > rhs.startedAt
        }
    }

    /// 从单个会话目录构建 `RecordingSession`。无音频且无任何截图则视为无效目录返回 nil。
    /// 供历史扫描与停录后即时构建会话共用。
    func makeSession(from directory: URL) -> RecordingSession? {
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

    /// 将指定会话移入废纸篓（可恢复，比直接删除更安全）。仅允许删除录制根目录下的会话。
    func deleteSession(_ session: RecordingSession) throws {
        let directory = session.directory.standardizedFileURL
        let root = rootDirectory.standardizedFileURL
        guard directory.deletingLastPathComponent().path == root.path else {
            AppLogger.capture.warning("拒绝删除非录制根目录下的目录: \(directory.path)")
            throw CocoaError(.fileWriteNoPermission)
        }
        try fileManager.trashItem(at: directory, resultingItemURL: nil)
        AppLogger.capture.info("已将录制会话移入废纸篓: \(directory.path)")
    }

    /// 统计给定会话占用的磁盘字节总数（用于历史窗口展示总占用）。
    func totalSize(of sessions: [RecordingSession]) -> Int64 {
        sessions.reduce(0) { $0 + directorySize(at: $1.directory) }
    }

    private func directorySize(at directory: URL) -> Int64 {
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey]
        ) else {
            return 0
        }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            let values = try? fileURL.resourceValues(
                forKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey]
            )
            total += Int64(values?.totalFileAllocatedSize ?? values?.fileAllocatedSize ?? 0)
        }
        return total
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
