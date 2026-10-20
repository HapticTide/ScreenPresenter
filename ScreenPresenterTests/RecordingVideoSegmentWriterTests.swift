//
//  RecordingVideoSegmentWriterTests.swift
//  ScreenPresenterTests
//
//  Created by Tank on 2026/07/17.
//

import AVFoundation
import CoreVideo
import XCTest
@testable import ScreenPresenter

final class RecordingVideoSegmentWriterTests: XCTestCase {
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

    func testOutputSizeLimitsLongSideAndKeepsEvenDimensions() {
        XCTAssertEqual(
            RecordingVideoSegmentWriter.outputSize(
                width: 1_290,
                height: 2_796,
                maxLongSide: 1_280
            ),
            CGSize(width: 590, height: 1_280)
        )
        XCTAssertEqual(
            RecordingVideoSegmentWriter.outputSize(width: 592, height: 1_280, maxLongSide: 1_280),
            CGSize(width: 592, height: 1_280)
        )
    }

    func testWritesTwoSecondHEVCVideoWithoutAudioTrack() async throws {
        let outputURL = temporaryDirectory.appendingPathComponent("000000000_0001.mp4")
        let writer = RecordingVideoSegmentWriter(
            outputURL: outputURL,
            configuration: .screenRecording
        )
        let pixelBuffer = try makePixelBuffer(width: 592, height: 1_280)

        for frameIndex in 0..<60 {
            try await writer.append(
                pixelBuffer: pixelBuffer,
                sessionTime: Double(frameIndex) / 30
            )
        }
        try await writer.finish()

        let asset = AVURLAsset(url: outputURL)
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        let duration = try await asset.load(.duration).seconds

        XCTAssertEqual(videoTracks.count, 1)
        XCTAssertEqual(audioTracks.count, 0)
        XCTAssertEqual(duration, 2, accuracy: 0.15)
    }

    private func makePixelBuffer(width: Int, height: Int) throws -> CVPixelBuffer {
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32BGRA,
            [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary,
            &pixelBuffer
        )
        XCTAssertEqual(status, kCVReturnSuccess)
        return try XCTUnwrap(pixelBuffer)
    }
}
