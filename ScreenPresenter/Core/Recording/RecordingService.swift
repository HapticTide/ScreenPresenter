//
//  RecordingService.swift
//  ScreenPresenter
//
//  Created by Sun on 2026/06/30.
//
//  录制服务
//  负责录制 Mac 麦克风并按秒保存投屏设备截图
//

import AVFoundation
import Combine
import CoreImage
import Foundation
import ImageIO
import UniformTypeIdentifiers

// MARK: - 录制状态

enum RecordingState: Equatable {
    case idle
    case recording(startedAt: Date, outputDirectory: URL)
    case failed(String)

    var isRecording: Bool {
        if case .recording = self {
            return true
        }
        return false
    }
}

enum RecordingServiceError: LocalizedError {
    case microphonePermissionDenied
    case recorderStartFailed
    case outputDirectoryUnavailable

    var errorDescription: String? {
        switch self {
        case .microphonePermissionDenied:
            L10n.recording.microphonePermissionDenied
        case .recorderStartFailed:
            L10n.recording.startFailed
        case .outputDirectoryUnavailable:
            L10n.recording.outputDirectoryUnavailable
        }
    }
}

// MARK: - 录制服务

@MainActor
final class RecordingService: NSObject {
    typealias FrameProvider = () -> [RecordingFrameSnapshot]

    // MARK: - 发布者

    let stateChangedPublisher = PassthroughSubject<Void, Never>()

    // MARK: - 状态

    private(set) var state: RecordingState = .idle {
        didSet { stateChangedPublisher.send() }
    }

    private(set) var elapsedSeconds: Int = 0 {
        didSet { stateChangedPublisher.send() }
    }

    private(set) var lastOutputDirectory: URL? {
        didSet { stateChangedPublisher.send() }
    }

    // MARK: - 私有属性

    private let frameProvider: FrameProvider
    private let fileManager: FileManager
    private let imageContext = CIContext(options: [.useSoftwareRenderer: false])

    private var audioRecorder: AVAudioRecorder?
    private var snapshotTimer: Timer?
    private var elapsedTimer: Timer?
    private var startedAt: Date?
    private var outputDirectory: URL?
    private var deviceDirectories: [String: URL] = [:]

    private let maxSnapshotLongSide: CGFloat = 1280
    private let jpegQuality: CGFloat = 0.65

    // MARK: - 初始化

    init(fileManager: FileManager = .default, frameProvider: @escaping FrameProvider) {
        self.fileManager = fileManager
        self.frameProvider = frameProvider
        super.init()
    }

    deinit {
        snapshotTimer?.invalidate()
        elapsedTimer?.invalidate()
        audioRecorder?.stop()
    }

    // MARK: - 公开方法

    func startRecording() async throws {
        guard !state.isRecording else { return }

        lastOutputDirectory = nil
        elapsedSeconds = 0
        deviceDirectories.removeAll()

        do {
            try await ensureMicrophoneAccess()

            let now = Date()
            let directory = try createSessionDirectory(startedAt: now)
            let audioURL = directory.appendingPathComponent("audio.m4a")
            let recorder = try makeAudioRecorder(outputURL: audioURL)

            guard recorder.record() else {
                throw RecordingServiceError.recorderStartFailed
            }

            startedAt = now
            outputDirectory = directory
            audioRecorder = recorder
            state = .recording(startedAt: now, outputDirectory: directory)

            startTimers()
            AppLogger.capture.info("录制已开始: \(directory.path)")
        } catch {
            cleanupAfterFailedStart()
            state = .failed(error.localizedDescription)
            throw error
        }
    }

    @discardableResult
    func stopRecording() -> URL? {
        let wasRecording = state.isRecording

        stopTimers()
        stopAudioRecorder()

        let directory = outputDirectory
        outputDirectory = nil
        startedAt = nil
        deviceDirectories.removeAll()

        state = .idle
        if let directory {
            lastOutputDirectory = directory
        }

        if wasRecording, let directory {
            AppLogger.capture.info("录制已停止: \(directory.path)")
        }

        return directory ?? lastOutputDirectory
    }

    // MARK: - 权限和录音

    private func ensureMicrophoneAccess() async throws {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return
        case .notDetermined:
            let granted = await requestMicrophoneAccess()
            guard granted else {
                throw RecordingServiceError.microphonePermissionDenied
            }
        case .denied, .restricted:
            throw RecordingServiceError.microphonePermissionDenied
        @unknown default:
            throw RecordingServiceError.microphonePermissionDenied
        }
    }

    private func requestMicrophoneAccess() async -> Bool {
        await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    private func makeAudioRecorder(outputURL: URL) throws -> AVAudioRecorder {
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 64_000,
        ]

        let recorder = try AVAudioRecorder(url: outputURL, settings: settings)
        recorder.delegate = self
        recorder.isMeteringEnabled = false
        recorder.prepareToRecord()
        return recorder
    }

    // MARK: - 目录

    private func createSessionDirectory(startedAt: Date) throws -> URL {
        guard let moviesDirectory = fileManager.urls(for: .moviesDirectory, in: .userDomainMask).first else {
            throw RecordingServiceError.outputDirectoryUnavailable
        }

        let rootDirectory = moviesDirectory.appendingPathComponent("ScreenPresenter Recordings", isDirectory: true)
        let sessionDirectory = rootDirectory.appendingPathComponent(
            RecordingFileNaming.sessionDirectoryName(date: startedAt),
            isDirectory: true
        )

        try fileManager.createDirectory(at: sessionDirectory, withIntermediateDirectories: true)
        return sessionDirectory
    }

    private func directory(for snapshot: RecordingFrameSnapshot) throws -> URL {
        let key = "\(snapshot.platform.rawValue)-\(snapshot.deviceName)"
        if let directory = deviceDirectories[key] {
            return directory
        }

        guard let outputDirectory else {
            throw RecordingServiceError.outputDirectoryUnavailable
        }

        let directoryName = RecordingFileNaming.deviceDirectoryName(
            platformName: snapshot.platform.rawValue,
            deviceName: snapshot.deviceName
        )
        let directory = outputDirectory.appendingPathComponent(directoryName, isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        deviceDirectories[key] = directory
        return directory
    }

    // MARK: - 定时器

    private func startTimers() {
        stopTimers()

        let elapsedTimer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.updateElapsedSeconds()
            }
        }
        RunLoop.main.add(elapsedTimer, forMode: .common)
        self.elapsedTimer = elapsedTimer

        let snapshotTimer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.captureCurrentDeviceSnapshots()
            }
        }
        RunLoop.main.add(snapshotTimer, forMode: .common)
        self.snapshotTimer = snapshotTimer
    }

    private func updateElapsedSeconds() {
        guard let startedAt else {
            elapsedSeconds = 0
            return
        }
        elapsedSeconds = max(0, Int(Date().timeIntervalSince(startedAt)))
    }

    // MARK: - 截图

    private func captureCurrentDeviceSnapshots() {
        guard state.isRecording, let startedAt else { return }

        let now = Date()
        let elapsedSecond = max(1, Int(now.timeIntervalSince(startedAt)))
        elapsedSeconds = elapsedSecond

        for snapshot in frameProvider() {
            do {
                let deviceDirectory = try directory(for: snapshot)
                let fileName = RecordingFileNaming.snapshotFileName(elapsedSecond: elapsedSecond, date: now)
                let outputURL = deviceDirectory.appendingPathComponent(fileName)
                try writeJPEG(pixelBuffer: snapshot.pixelBuffer, to: outputURL)
            } catch {
                AppLogger.capture.warning("保存录制截图失败: \(error.localizedDescription)")
            }
        }
    }

    private func writeJPEG(pixelBuffer: CVPixelBuffer, to outputURL: URL) throws {
        let image = CIImage(cvImageBuffer: pixelBuffer)
        let scale = snapshotScale(for: image.extent.size)
        let outputImage = scale < 1
            ? image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            : image

        guard let cgImage = imageContext.createCGImage(outputImage, from: outputImage.extent) else {
            throw RecordingServiceError.outputDirectoryUnavailable
        }

        guard let destination = CGImageDestinationCreateWithURL(
            outputURL as CFURL,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            throw RecordingServiceError.outputDirectoryUnavailable
        }

        let options: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: jpegQuality,
        ]
        CGImageDestinationAddImage(destination, cgImage, options as CFDictionary)

        if !CGImageDestinationFinalize(destination) {
            throw RecordingServiceError.outputDirectoryUnavailable
        }
    }

    private func snapshotScale(for size: CGSize) -> CGFloat {
        let longSide = max(size.width, size.height)
        guard longSide > maxSnapshotLongSide else { return 1 }
        return maxSnapshotLongSide / longSide
    }

    private func cleanupAfterFailedStart() {
        stopTimers()
        stopAudioRecorder()

        startedAt = nil
        outputDirectory = nil
        deviceDirectories.removeAll()
        elapsedSeconds = 0
    }

    private func stopTimers() {
        snapshotTimer?.invalidate()
        elapsedTimer?.invalidate()
        snapshotTimer = nil
        elapsedTimer = nil
    }

    private func stopAudioRecorder() {
        guard let recorder = audioRecorder else { return }
        recorder.stop()
        recorder.delegate = nil
        audioRecorder = nil
    }
}

// MARK: - AVAudioRecorderDelegate

extension RecordingService: AVAudioRecorderDelegate {
    nonisolated func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        Task { @MainActor in
            let message = error?.localizedDescription ?? L10n.recording.startFailed
            AppLogger.capture.error("录制音频编码失败: \(message)")
            _ = stopRecording()
            state = .failed(message)
        }
    }
}
