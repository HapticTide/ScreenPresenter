//
//  RecordingLibraryTests.swift
//  ScreenPresenterTests
//
//  Created by Sun on 2026/07/02.
//

import Foundation
import XCTest
@testable import ScreenPresenter

final class RecordingLibraryTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: temporaryDirectory)
        temporaryDirectory = nil
    }

    func testScanSortsSessionsAndParsesDurationPlatformDeviceNameAndSnapshotSeconds() throws {
        let olderSession = try makeSession(named: "2026-06-30 20-24-48", duration: 61)
        let newerSession = try makeSession(named: "2026-07-01 09-10-11", duration: 12)

        try makeDeviceDirectory(
            in: newerSession,
            named: "Android-Pixel 8",
            snapshotNames: ["000010_2026-07-01_09-10-21.jpg"]
        )
        try makeDeviceDirectory(
            in: newerSession,
            named: "iOS-iPhone 15 Pro",
            snapshotNames: [
                "000032_2026-07-01_09-10-43.jpg",
                "000002_2026-07-01_09-10-13.jpg"
            ]
        )
        try makeDeviceDirectory(
            in: olderSession,
            named: "iOS-iPad",
            snapshotNames: ["000001_2026-06-30_20-24-49.jpg"]
        )

        let library = RecordingLibrary(
            rootDirectory: temporaryDirectory,
            audioDurationProvider: { url in
                url.deletingLastPathComponent().lastPathComponent == "2026-07-01 09-10-11" ? 12 : 61
            }
        )

        let sessions = try library.scanSessions()

        XCTAssertEqual(sessions.map(\.directory.lastPathComponent), [
            "2026-07-01 09-10-11",
            "2026-06-30 20-24-48"
        ])
        XCTAssertEqual(sessions.map(\.duration), [12, 61])
        XCTAssertEqual(
            sessions[0].startedAt,
            sessionDate(fromDirectoryName: "2026-07-01 09-10-11")
        )
        XCTAssertEqual(sessions[0].deviceTracks.map(\.platform), [.ios, .android])
        XCTAssertEqual(sessions[0].deviceTracks.map(\.deviceName), ["iPhone 15 Pro", "Pixel 8"])
        XCTAssertEqual(sessions[0].deviceTracks[0].snapshots.map(\.elapsedSecond), [2, 32])
    }

    func testSnapshotAtReturnsNearestSnapshotAtOrBeforeTargetSecond() {
        let track = RecordingDeviceTrack(
            platform: .ios,
            deviceName: "iPhone",
            directory: temporaryDirectory.appendingPathComponent("iOS-iPhone", isDirectory: true),
            snapshots: [
                snapshot(elapsedSecond: 3),
                snapshot(elapsedSecond: 8),
                snapshot(elapsedSecond: 15)
            ]
        )

        XCTAssertEqual(track.snapshot(at: 2)?.elapsedSecond, 3)
        XCTAssertEqual(track.snapshot(at: 3)?.elapsedSecond, 3)
        XCTAssertEqual(track.snapshot(at: 10)?.elapsedSecond, 8)
        XCTAssertEqual(track.snapshot(at: 99)?.elapsedSecond, 15)
    }

    func testScanIgnoresInvalidSessionsDeviceDirectoriesAndSnapshots() throws {
        _ = try makeSession(named: "2026-07-01 09-10-11", duration: 30)
        let validSession = temporaryDirectory.appendingPathComponent("2026-07-01 09-10-11", isDirectory: true)
        try makeDeviceDirectory(
            in: validSession,
            named: "iOS-iPhone",
            snapshotNames: [
                "000001_2026-07-01_09-10-12.jpg",
                "000002_2026-07-01_09-10-13.png",
                "abc003_2026-07-01_09-10-14.jpg",
                "00004_2026-07-01_09-10-15.jpg",
                "000005.jpg"
            ]
        )
        try makeDeviceDirectory(
            in: validSession,
            named: "windows-Surface",
            snapshotNames: ["000003_2026-07-01_09-10-14.jpg"]
        )

        let invalidSession = temporaryDirectory.appendingPathComponent(
            "2026-07-02 09-10-11",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: invalidSession, withIntermediateDirectories: true)
        try makeDeviceDirectory(
            in: invalidSession,
            named: "Android-Pixel",
            snapshotNames: ["000001_2026-07-02_09-10-12.jpg"]
        )

        let library = RecordingLibrary(
            rootDirectory: temporaryDirectory,
            audioDurationProvider: { _ in 30 }
        )

        let sessions = try library.scanSessions()

        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions[0].deviceTracks.map(\.deviceName), ["iPhone"])
        XCTAssertEqual(sessions[0].deviceTracks[0].snapshots.map(\.elapsedSecond), [1])
    }

    private func makeSession(named name: String, duration: TimeInterval) throws -> URL {
        let directory = temporaryDirectory.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("audio-\(duration)".utf8).write(to: directory.appendingPathComponent("audio.m4a"))
        return directory
    }

    private func makeDeviceDirectory(
        in sessionDirectory: URL,
        named name: String,
        snapshotNames: [String]
    ) throws {
        let directory = sessionDirectory.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        for snapshotName in snapshotNames {
            try Data("snapshot".utf8).write(to: directory.appendingPathComponent(snapshotName))
        }
    }

    private func snapshot(elapsedSecond: Int) -> RecordingSnapshot {
        RecordingSnapshot(
            elapsedSecond: elapsedSecond,
            fileURL: temporaryDirectory.appendingPathComponent("\(elapsedSecond).jpg")
        )
    }

    private func sessionDate(fromDirectoryName directoryName: String) -> Date {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH-mm-ss"
        return formatter.date(from: directoryName)!
    }
}
