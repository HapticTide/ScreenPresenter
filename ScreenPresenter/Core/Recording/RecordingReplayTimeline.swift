//
//  RecordingReplayTimeline.swift
//  ScreenPresenter
//
//  Created by Tank on 2026/07/17.
//

import Foundation

// MARK: - 回放内容状态

enum RecordingReplayContentState: Equatable {
    case snapshot(fileURL: URL)
    case video(fileURL: URL, localTime: TimeInterval)
    case interrupted
    case empty
}

enum RecordingReplayTimeline {
    static func state(for track: RecordingDeviceTrack, at time: TimeInterval) -> RecordingReplayContentState {
        if !track.videoSegments.isEmpty {
            guard let match = track.videoSegment(at: time) else { return .interrupted }
            return .video(fileURL: match.segment.fileURL, localTime: match.localTime)
        }

        guard let snapshot = track.snapshot(at: Int(floor(time))) else { return .empty }
        return .snapshot(fileURL: snapshot.fileURL)
    }
}
