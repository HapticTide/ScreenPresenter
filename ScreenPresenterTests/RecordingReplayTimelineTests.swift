//
//  RecordingReplayTimelineTests.swift
//  ScreenPresenterTests
//
//  Created by Tank on 2026/07/17.
//

import Foundation
import XCTest
@testable import ScreenPresenter

final class RecordingReplayTimelineTests: XCTestCase {
    private let directory = FileManager.default.temporaryDirectory

    func testReturnsInterruptedBetweenVideoSegments() {
        let track = makeVideoTrack()

        XCTAssertEqual(RecordingReplayTimeline.state(for: track, at: 7), .interrupted)
    }

    func testReturnsVideoAndLocalTimeInsideSegment() {
        let track = makeVideoTrack()
        let secondURL = directory.appendingPathComponent("second.mp4")

        XCTAssertEqual(
            RecordingReplayTimeline.state(for: track, at: 11),
            .video(fileURL: secondURL, localTime: 1)
        )
    }

    func testLegacySnapshotTrackStillReturnsSnapshot() {
        let snapshotURL = directory.appendingPathComponent("3.jpg")
        let track = RecordingDeviceTrack(
            platform: .ios,
            deviceName: "iPhone",
            directory: directory,
            snapshots: [RecordingSnapshot(elapsedSecond: 3, fileURL: snapshotURL)]
        )

        XCTAssertEqual(
            RecordingReplayTimeline.state(for: track, at: 4),
            .snapshot(fileURL: snapshotURL)
        )
    }

    private func makeVideoTrack() -> RecordingDeviceTrack {
        RecordingDeviceTrack(
            platform: .ios,
            deviceName: "iPhone",
            directory: directory,
            snapshots: [],
            videoSegments: [
                RecordingVideoSegment(
                    startTime: 2,
                    duration: 4,
                    fileURL: directory.appendingPathComponent("first.mp4")
                ),
                RecordingVideoSegment(
                    startTime: 10,
                    duration: 3,
                    fileURL: directory.appendingPathComponent("second.mp4")
                )
            ]
        )
    }
}
