//
//  RecordingSessionMetadataTests.swift
//  ScreenPresenterTests
//
//  Created by Tank on 2026/07/17.
//

import Foundation
import XCTest
@testable import ScreenPresenter

final class RecordingSessionMetadataTests: XCTestCase {
    func testSessionMetadataRoundTripsFixedVideoConfiguration() throws {
        let metadata = RecordingSessionMetadata(
            version: 2,
            startedAt: Date(timeIntervalSince1970: 1_700_000_000.125),
            durationMilliseconds: 3_600_000,
            video: .screenRecording
        )

        let data = try RecordingSessionMetadata.encode(metadata)
        let decoded = try RecordingSessionMetadata.decode(from: data)

        XCTAssertEqual(decoded, metadata)
        XCTAssertEqual(decoded.video.framesPerSecond, 30)
        XCTAssertEqual(decoded.video.averageBitRate, 600_000)
        XCTAssertEqual(decoded.video.maxLongSide, 1_280)
    }

    func testDecodeRejectsUnsupportedMetadataVersion() throws {
        let json = """
        {
          "version": 1,
          "startedAt": "2026-07-17T07:30:00.000Z",
          "durationMilliseconds": 1000,
          "video": {
            "codec": "hevc",
            "framesPerSecond": 30,
            "averageBitRate": 600000,
            "maxLongSide": 1280
          }
        }
        """
        let data = Data(json.utf8)

        XCTAssertThrowsError(try RecordingSessionMetadata.decode(from: data))
    }
}
