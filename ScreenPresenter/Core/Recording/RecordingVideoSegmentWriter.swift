//
//  RecordingVideoSegmentWriter.swift
//  ScreenPresenter
//
//  Created by Tank on 2026/07/17.
//

import AVFoundation
import CoreImage
import CoreVideo
import Foundation

// MARK: - HEVC 视频分段写入器

/// 一个实例只负责一个连续投屏区间。所有 AVAssetWriter 操作都由 actor 串行保护。
actor RecordingVideoSegmentWriter {
    let outputURL: URL

    private let configuration: RecordingVideoConfiguration
    private let context = CIContext(options: [.useSoftwareRenderer: false])

    private var assetWriter: AVAssetWriter?
    private var writerInput: AVAssetWriterInput?
    private var adaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var firstSessionTime: TimeInterval?
    private var lastPresentationTime = CMTime.invalid
    private var isFinished = false

    init(outputURL: URL, configuration: RecordingVideoConfiguration) {
        self.outputURL = outputURL
        self.configuration = configuration
    }

    /// 保持宽高比，将长边限制到指定值，并向下取偶数以满足硬件编码器要求。
    nonisolated static func outputSize(width: Int, height: Int, maxLongSide: Int) -> CGSize {
        guard width > 0, height > 0, maxLongSide > 0 else { return .zero }

        let longSide = max(width, height)
        let scale = min(1, Double(maxLongSide) / Double(longSide))
        let scaledWidth = max(2, Int(Double(width) * scale) / 2 * 2)
        let scaledHeight = max(2, Int(Double(height) * scale) / 2 * 2)
        return CGSize(width: scaledWidth, height: scaledHeight)
    }

    func append(pixelBuffer: CVPixelBuffer, sessionTime: TimeInterval) async throws {
        guard !isFinished else { return }

        if assetWriter == nil {
            try configureWriter(for: pixelBuffer)
            firstSessionTime = sessionTime
        }

        guard let writerInput, let adaptor, let firstSessionTime else {
            throw CocoaError(.fileWriteUnknown)
        }

        // 编码器短时背压时小幅等待；超过约 50ms 后丢弃当前帧，避免任务无限堆积。
        for _ in 0..<50 where !writerInput.isReadyForMoreMediaData {
            try await Task.sleep(for: .milliseconds(1))
        }
        guard writerInput.isReadyForMoreMediaData else { return }

        guard let outputBuffer = makeOutputBuffer(using: adaptor) else {
            throw CocoaError(.fileWriteOutOfSpace)
        }
        render(pixelBuffer, into: outputBuffer)

        let localSeconds = max(0, sessionTime - firstSessionTime)
        var presentationTime = CMTime(
            seconds: localSeconds,
            preferredTimescale: CMTimeScale(configuration.framesPerSecond * 1_000)
        )
        if lastPresentationTime.isValid, presentationTime <= lastPresentationTime {
            presentationTime = lastPresentationTime + CMTime(
                value: 1,
                timescale: CMTimeScale(configuration.framesPerSecond)
            )
        }

        guard adaptor.append(outputBuffer, withPresentationTime: presentationTime) else {
            throw assetWriter?.error ?? CocoaError(.fileWriteUnknown)
        }
        lastPresentationTime = presentationTime
    }

    func finish() async throws {
        guard !isFinished else { return }
        isFinished = true

        guard let assetWriter, let writerInput else { return }
        writerInput.markAsFinished()

        await withCheckedContinuation { continuation in
            assetWriter.finishWriting {
                continuation.resume()
            }
        }

        guard assetWriter.status == .completed else {
            throw assetWriter.error ?? CocoaError(.fileWriteUnknown)
        }
    }

    private func configureWriter(for pixelBuffer: CVPixelBuffer) throws {
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let size = Self.outputSize(width: width, height: height, maxLongSide: configuration.maxLongSide)
        guard size.width > 0, size.height > 0 else {
            throw CocoaError(.fileWriteInvalidFileName)
        }

        try? FileManager.default.removeItem(at: outputURL)
        let assetWriter = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
        let outputSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.hevc,
            AVVideoWidthKey: Int(size.width),
            AVVideoHeightKey: Int(size.height),
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: configuration.averageBitRate,
                AVVideoExpectedSourceFrameRateKey: configuration.framesPerSecond,
                AVVideoMaxKeyFrameIntervalKey: configuration.framesPerSecond * 5,
                AVVideoAllowFrameReorderingKey: true
            ]
        ]
        let writerInput = AVAssetWriterInput(mediaType: .video, outputSettings: outputSettings)
        writerInput.expectsMediaDataInRealTime = true
        guard assetWriter.canAdd(writerInput) else {
            throw assetWriter.error ?? CocoaError(.fileWriteUnknown)
        }
        assetWriter.add(writerInput)

        let attributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: Int(size.width),
            kCVPixelBufferHeightKey as String: Int(size.height),
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ]
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: writerInput,
            sourcePixelBufferAttributes: attributes
        )

        guard assetWriter.startWriting() else {
            throw assetWriter.error ?? CocoaError(.fileWriteUnknown)
        }
        assetWriter.startSession(atSourceTime: .zero)

        self.assetWriter = assetWriter
        self.writerInput = writerInput
        self.adaptor = adaptor
    }

    private func makeOutputBuffer(using adaptor: AVAssetWriterInputPixelBufferAdaptor) -> CVPixelBuffer? {
        guard let pool = adaptor.pixelBufferPool else { return nil }
        var pixelBuffer: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pixelBuffer) == kCVReturnSuccess else {
            return nil
        }
        return pixelBuffer
    }

    private func render(_ source: CVPixelBuffer, into destination: CVPixelBuffer) {
        let image = CIImage(cvPixelBuffer: source)
        let destinationWidth = CGFloat(CVPixelBufferGetWidth(destination))
        let destinationHeight = CGFloat(CVPixelBufferGetHeight(destination))
        let scaleX = destinationWidth / image.extent.width
        let scaleY = destinationHeight / image.extent.height
        let scaledImage = image.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
        context.render(
            scaledImage,
            to: destination,
            bounds: CGRect(x: 0, y: 0, width: destinationWidth, height: destinationHeight),
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )
    }
}
