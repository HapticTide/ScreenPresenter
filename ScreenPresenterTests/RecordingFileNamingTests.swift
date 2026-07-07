//
//  RecordingFileNamingTests.swift
//  ScreenPresenterTests
//
//  Created by Sun on 2026/06/30.
//
//  录制文件命名单元测试
//  验证截图目录和文件名稳定、可读且适合文件系统
//

import Foundation
import XCTest
@testable import ScreenPresenter

final class RecordingFileNamingTests: XCTestCase {
    func testDeviceDirectoryNameReplacesInvalidFileNameCharacters() {
        let result = RecordingFileNaming.deviceDirectoryName(
            platformName: "iOS",
            deviceName: #"Tank/iPhone:15*Pro?"#
        )

        XCTAssertEqual(result, "iOS-Tank-iPhone-15-Pro")
    }

    func testSnapshotFileNameIncludesElapsedSecondAndWallClockSecond() throws {
        var components = DateComponents()
        components.calendar = Calendar.current
        components.year = 2026
        components.month = 6
        components.day = 30
        components.hour = 10
        components.minute = 18
        components.second = 43

        let date = try XCTUnwrap(components.date)

        let result = RecordingFileNaming.snapshotFileName(elapsedSecond: 7, date: date)

        XCTAssertEqual(result, "000007_2026-06-30_10-18-43.jpg")
    }
}
