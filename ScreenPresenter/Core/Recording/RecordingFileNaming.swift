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
