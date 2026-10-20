//
//  AudioHelperController.swift
//  ScreenPresenterAudioHelper
//
//  Created by Tank on 2026/07/18.
//

@preconcurrency import AVFoundation
import CoreMedia
import Darwin
import Foundation
import os.lock

// MARK: - Helper 错误

private enum AudioHelperError: LocalizedError {
    case noDevice
    case permissionDenied
    case unavailable(String)

    var code: String {
        switch self {
        case .noDevice: "noDevice"
        case .permissionDenied: "permissionDenied"
        case .unavailable: "unavailable"
        }
    }

    var errorDescription: String? {
        switch self {
        case .noDevice:
            "未检测到麦克风设备"
        case .permissionDenied:
            "未获得麦克风权限"
        case let .unavailable(message):
            message
        }
    }
}

// MARK: - Helper 控制器

/// 独立 Helper 的完整生命周期：权限、采集、M4A 写入、收到 STOP 后收尾退出。
/// `@unchecked Sendable` 的安全约束：所有跨队列可变生命周期状态均只能通过 stateLock 访问。
final class AudioHelperController: @unchecked Sendable {
    private struct State {
        var audioCapture: AudioCapture?
        var stopMonitor: DispatchSourceTimer?
        var isFinishing = false
    }

    private let outputURL: URL
    private let controlDirectoryURL: URL
    private let ownerPID: Int32
    private let stateLock = OSAllocatedUnfairLock(initialState: State())

    init(outputURL: URL, controlDirectoryURL: URL, ownerPID: Int32) {
        self.outputURL = outputURL
        self.controlDirectoryURL = controlDirectoryURL
        self.ownerPID = ownerPID
    }

    func run() -> Never {
        // 在请求麦克风权限前就开始监听停止信号和宿主存活状态。
        // 用户停留在系统权限弹窗期间点击停止，或主 App 此时退出，Helper 也必须立即结束。
        installStopMonitor()
        Task { [self] in
            await startCapture()
        }
        dispatchMain()
    }

    private func startCapture() async {
        do {
            guard AVCaptureDevice.default(for: .audio) != nil else {
                throw AudioHelperError.noDevice
            }
            guard await ensureMicrophoneAccess() else {
                throw AudioHelperError.permissionDenied
            }

            let capture = AudioCapture(outputURL: outputURL) { [weak self] error in
                self?.writeErrorAndExit(.unavailable(error.localizedDescription))
            }
            try await capture.start()

            let shouldContinue = stateLock.withLock { state in
                guard !state.isFinishing else { return false }
                state.audioCapture = capture
                return true
            }
            guard shouldContinue else {
                await capture.stop()
                return
            }

            let startedAtMilliseconds = Int64((Date().timeIntervalSince1970 * 1_000).rounded())
            try writeControlFile(name: "ready", contents: "READY\t\(startedAtMilliseconds)\n")
        } catch let error as AudioHelperError {
            writeErrorAndExit(error)
        } catch {
            writeErrorAndExit(.unavailable(error.localizedDescription))
        }
    }

    private func ensureMicrophoneAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    continuation.resume(returning: granted)
                }
            }
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }

    private func installStopMonitor() {
        let stopURL = controlDirectoryURL.appendingPathComponent("stop")
        let monitor = DispatchSource.makeTimerSource(queue: .global(qos: .userInitiated))
        monitor.schedule(deadline: .now(), repeating: .milliseconds(100))
        monitor.setEventHandler { [weak self] in
            guard let self else { return }
            let stopRequested = FileManager.default.fileExists(atPath: stopURL.path)
            let ownerExited = kill(self.ownerPID, 0) != 0 && errno == ESRCH
            guard stopRequested || ownerExited else { return }
            self.finishAndExit()
        }
        stateLock.withLock { $0.stopMonitor = monitor }
        monitor.resume()
    }

    private func finishAndExit() {
        let resources = stateLock.withLock { state -> (AudioCapture?, DispatchSourceTimer?)? in
            guard !state.isFinishing else { return nil }
            state.isFinishing = true
            let capture = state.audioCapture
            let monitor = state.stopMonitor
            state.audioCapture = nil
            state.stopMonitor = nil
            return (capture, monitor)
        }
        guard let (capture, monitor) = resources else { return }
        monitor?.cancel()

        Task {
            await capture?.stop()
            exit(EXIT_SUCCESS)
        }
    }

    private func writeErrorAndExit(_ error: AudioHelperError) {
        let result = stateLock.withLock { state -> (shouldExit: Bool, monitor: DispatchSourceTimer?) in
            guard !state.isFinishing else { return (false, nil) }
            state.isFinishing = true
            state.audioCapture = nil
            let monitor = state.stopMonitor
            state.stopMonitor = nil
            return (true, monitor)
        }
        guard result.shouldExit else { return }
        result.monitor?.cancel()

        let message = (error.localizedDescription)
            .replacingOccurrences(of: "\t", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
        try? writeControlFile(
            name: "error",
            contents: "ERROR\t\(error.code)\t\(message)\n"
        )
        exit(EXIT_FAILURE)
    }

    private func writeControlFile(name: String, contents: String) throws {
        let url = controlDirectoryURL.appendingPathComponent(name)
        try Data(contents.utf8).write(to: url, options: .atomic)
    }
}

// MARK: - 音频采集

private final class AudioCapture: NSObject, @unchecked Sendable {
    private let outputURL: URL
    private let onFailure: @Sendable (Error) -> Void
    private let captureQueue = DispatchQueue(
        label: "com.screenPresenter.audioHelper.capture",
        qos: .userInitiated
    )

    private var isAcceptingSamples = false
    private var captureSession: AVCaptureSession?
    private var captureInput: AVCaptureDeviceInput?
    private var captureOutput: AVCaptureAudioDataOutput?
    private var assetWriter: AVAssetWriter?
    private var writerInput: AVAssetWriterInput?
    private var didReportFailure = false

    init(outputURL: URL, onFailure: @escaping @Sendable (Error) -> Void) {
        self.outputURL = outputURL
        self.onFailure = onFailure
        super.init()
    }

    func start() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            captureQueue.async { [weak self] in
                guard let self else {
                    continuation.resume(throwing: CocoaError(.coderInvalidValue))
                    return
                }

                do {
                    try self.configureCaptureAndWriter()
                    self.captureSession?.startRunning()
                    self.isAcceptingSamples = true
                    continuation.resume()
                } catch {
                    self.teardownCaptureSession()
                    self.cancelWriterAndRemoveEmptyFile()
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func stop() async {
        await withCheckedContinuation { continuation in
            captureQueue.async { [weak self] in
                guard let self else {
                    continuation.resume()
                    return
                }
                self.isAcceptingSamples = false
                self.teardownCaptureSession()
                self.finishWriter(continuation: continuation)
            }
        }
    }

    private func configureCaptureAndWriter() throws {
        try? FileManager.default.removeItem(at: outputURL)
        guard let microphone = AVCaptureDevice.default(for: .audio) else {
            throw AudioHelperError.noDevice
        }

        let captureInput = try AVCaptureDeviceInput(device: microphone)
        let captureOutput = AVCaptureAudioDataOutput()
        let captureSession = AVCaptureSession()
        captureSession.beginConfiguration()
        defer { captureSession.commitConfiguration() }

        guard captureSession.canAddInput(captureInput) else {
            throw AudioHelperError.unavailable("无法添加麦克风输入")
        }
        captureSession.addInput(captureInput)
        guard captureSession.canAddOutput(captureOutput) else {
            throw AudioHelperError.unavailable("无法添加麦克风输出")
        }
        captureSession.addOutput(captureOutput)
        captureOutput.setSampleBufferDelegate(self, queue: captureQueue)

        let assetWriter = try AVAssetWriter(outputURL: outputURL, fileType: .m4a)
        let outputSettings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 64_000
        ]
        let writerInput = AVAssetWriterInput(mediaType: .audio, outputSettings: outputSettings)
        writerInput.expectsMediaDataInRealTime = true
        guard assetWriter.canAdd(writerInput) else {
            throw assetWriter.error ?? AudioHelperError.unavailable("无法创建音频写入轨道")
        }
        assetWriter.add(writerInput)

        self.captureSession = captureSession
        self.captureInput = captureInput
        self.captureOutput = captureOutput
        self.assetWriter = assetWriter
        self.writerInput = writerInput
        didReportFailure = false
    }

    private func append(_ sampleBuffer: CMSampleBuffer) {
        guard isAcceptingSamples, CMSampleBufferDataIsReady(sampleBuffer) else { return }
        guard let assetWriter, let writerInput else { return }

        if assetWriter.status == .unknown {
            guard assetWriter.startWriting() else {
                reportFailure(assetWriter.error ?? CocoaError(.fileWriteUnknown))
                return
            }
            assetWriter.startSession(atSourceTime: CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
        }

        guard assetWriter.status == .writing else {
            if assetWriter.status == .failed {
                reportFailure(assetWriter.error ?? CocoaError(.fileWriteUnknown))
            }
            return
        }
        guard writerInput.isReadyForMoreMediaData else { return }
        if !writerInput.append(sampleBuffer) {
            reportFailure(assetWriter.error ?? CocoaError(.fileWriteUnknown))
        }
    }

    private func teardownCaptureSession() {
        captureOutput?.setSampleBufferDelegate(nil, queue: nil)
        if captureSession?.isRunning == true {
            captureSession?.stopRunning()
        }
        if let captureSession {
            captureSession.beginConfiguration()
            if let captureOutput { captureSession.removeOutput(captureOutput) }
            if let captureInput { captureSession.removeInput(captureInput) }
            captureSession.commitConfiguration()
        }
        captureOutput = nil
        captureInput = nil
        captureSession = nil
    }

    private func finishWriter(continuation: CheckedContinuation<Void, Never>) {
        guard let assetWriter, let writerInput else {
            continuation.resume()
            return
        }
        guard assetWriter.status == .writing else {
            cancelWriterAndRemoveEmptyFile()
            continuation.resume()
            return
        }

        writerInput.markAsFinished()
        assetWriter.finishWriting { [weak self] in
            self?.captureQueue.async {
                self?.assetWriter = nil
                self?.writerInput = nil
                continuation.resume()
            }
        }
    }

    private func cancelWriterAndRemoveEmptyFile() {
        assetWriter?.cancelWriting()
        assetWriter = nil
        writerInput = nil
        try? FileManager.default.removeItem(at: outputURL)
    }

    private func reportFailure(_ error: Error) {
        guard !didReportFailure else { return }
        didReportFailure = true
        isAcceptingSamples = false
        onFailure(error)
    }
}

extension AudioCapture: AVCaptureAudioDataOutputSampleBufferDelegate {
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        append(sampleBuffer)
    }
}
