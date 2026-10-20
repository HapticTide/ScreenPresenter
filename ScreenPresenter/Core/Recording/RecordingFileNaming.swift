//
//  RecordingFileNaming.swift
//  ScreenPresenter
//
//  Created by Sun on 2026/06/30.
//
//  录制文件命名工具
//  统一生成会话目录、设备目录和截图文件名
//

import Foundation

// MARK: - 录制文件命名

enum RecordingFileNaming {
    private static let invalidFileNameCharacters = CharacterSet(charactersIn: "/\\?%*|\"<>:")

    private static let sessionFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH-mm-ss"
        return formatter
    }()

    private static let snapshotFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return formatter
    }()

    static func sessionDirectoryName(date: Date) -> String {
        sessionFormatter.string(from: date)
    }

    static func deviceDirectoryName(platformName: String, deviceName: String) -> String {
        let sanitizedName = sanitizeFileNameComponent(deviceName)
        return "\(platformName)-\(sanitizedName)"
    }

    static func snapshotFileName(elapsedSecond: Int, date: Date) -> String {
        let clampedSecond = max(0, elapsedSecond)
        let elapsed = String(format: "%06d", clampedSecond)
        return "\(elapsed)_\(snapshotFormatter.string(from: date)).jpg"
    }

    /// 视频分段文件名包含会话内起始毫秒和设备轨道内递增序号。
    static func videoSegmentFileName(startMilliseconds: Int64, sequence: Int) -> String {
        let clampedMilliseconds = max(0, startMilliseconds)
        let clampedSequence = max(1, sequence)
        return String(format: "%09lld_%04d.mp4", clampedMilliseconds, clampedSequence)
    }

    static func parseVideoSegmentFileName(_ fileName: String) -> RecordingVideoSegmentFileComponents? {
        let url = URL(fileURLWithPath: fileName)
        guard url.pathExtension.lowercased() == "mp4" else { return nil }

        let components = url.deletingPathExtension().lastPathComponent.split(
            separator: "_",
            omittingEmptySubsequences: false
        )
        guard components.count == 2,
              components[0].count == 9,
              components[1].count == 4,
              components[0].allSatisfy(\.isNumber),
              components[1].allSatisfy(\.isNumber),
              let startMilliseconds = Int64(components[0]),
              let sequence = Int(components[1]),
              sequence > 0 else {
            return nil
        }

        return RecordingVideoSegmentFileComponents(
            startMilliseconds: startMilliseconds,
            sequence: sequence
        )
    }

    static func sanitizeFileNameComponent(_ value: String) -> String {
        let scalars = value.unicodeScalars.map { scalar -> String in
            invalidFileNameCharacters.contains(scalar) || CharacterSet.newlines.contains(scalar)
                ? "-"
                : String(scalar)
        }

        let collapsed = scalars.joined()
            .replacingOccurrences(of: #"-+"#, with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-. "))

        return collapsed.isEmpty ? "Unknown" : collapsed
    }
}
