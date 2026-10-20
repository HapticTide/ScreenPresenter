//
//  RecordingAudioProcessTests.swift
//  ScreenPresenterTests
//
//  Created by Tank on 2026/07/18.
//

import XCTest
@testable import ScreenPresenter

final class RecordingAudioProcessTests: XCTestCase {
    func testHelperArgumentsContainModeAndOutputPath() {
        let outputURL = URL(fileURLWithPath: "/tmp/session/audio.m4a")
        let controlDirectoryURL = URL(fileURLWithPath: "/tmp/control", isDirectory: true)

        XCTAssertEqual(
            RecordingAudioProcessProtocol.helperArguments(
                outputURL: outputURL,
                controlDirectoryURL: controlDirectoryURL,
                ownerPID: 123
            ),
            [
                "--output",
                outputURL.path,
                "--control-directory",
                controlDirectoryURL.path,
                "--owner-pid",
                "123"
            ]
        )
    }

    func testParsesReadyAndErrorHandshake() {
        let startedAt = Date(timeIntervalSince1970: 1_725_000_000.123)
        XCTAssertEqual(
            RecordingAudioProcessProtocol.parseHandshake("READY\t1725000000123\n"),
            .ready(startedAt: startedAt)
        )
        XCTAssertEqual(
            RecordingAudioProcessProtocol.parseHandshake("ERROR\tpermissionDenied\t麦克风不可用\n"),
            .error(code: .permissionDenied, message: "麦克风不可用")
        )
        XCTAssertNil(RecordingAudioProcessProtocol.parseHandshake("UNKNOWN\n"))
    }

    func testParsesLegacyReadyHandshakeWithoutBlockingRecordingStart() {
        let fallbackStartedAt = Date(timeIntervalSince1970: 1_725_000_100)

        XCTAssertEqual(
            RecordingAudioProcessProtocol.parseHandshake(
                "READY\n",
                legacyStartedAt: fallbackStartedAt
            ),
            .ready(startedAt: fallbackStartedAt)
        )
    }

    func testRecordingLifecycleBusyStatesAreMutuallyExclusiveWithFrameCapture() {
        let directory = URL(fileURLWithPath: "/tmp/session", isDirectory: true)
        let startedAt = Date(timeIntervalSince1970: 1_725_000_000)

        XCTAssertTrue(RecordingState.starting(outputDirectory: directory).isRecording)
        XCTAssertFalse(RecordingState.starting(outputDirectory: directory).isCapturingFrames)
        XCTAssertTrue(
            RecordingState.recording(startedAt: startedAt, outputDirectory: directory).isCapturingFrames
        )
        XCTAssertTrue(RecordingState.stopping(outputDirectory: directory).isRecording)
        XCTAssertTrue(RecordingState.stopping(outputDirectory: directory).isStopping)
        XCTAssertFalse(RecordingState.idle.isRecording)
    }
}
