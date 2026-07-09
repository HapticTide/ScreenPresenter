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
    case insufficientDiskSpace

    var errorDescription: String? {
        switch self {
        case .microphonePermissionDenied:
            L10n.recording.microphonePermissionDenied
        case .recorderStartFailed:
            L10n.recording.startFailed
        case .outputDirectoryUnavailable:
            L10n.recording.outputDirectoryUnavailable
        case .insufficientDiskSpace:
            L10n.recording.insufficientDiskSpace
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

    /// 本次录制是否启用了音频轨道。麦克风不可用或权限被拒时为 false，仍进行纯截图录制。
    private(set) var isAudioEnabled = false

    // MARK: - 私有属性

    private let frameProvider: FrameProvider
    private let fileManager: FileManager

    private var audioRecorder: AVAudioRecorder?
    private var snapshotTimer: Timer?
    private var elapsedTimer: Timer?
    private var startedAt: Date?
    private var outputDirectory: URL?
    private var deviceDirectories: [String: URL] = [:]

    private let maxSnapshotLongSide: CGFloat = 1280
    private let jpegQuality: CGFloat = 0.65

    /// 录制启动前要求的最小可用磁盘空间。
    private let minFreeBytesToStart: Int64 = 1_024 * 1_024 * 1_024
    /// 录制过程中的安全下限，低于此值主动停录。
    private let minFreeBytesDuringRecording: Int64 = 200 * 1_024 * 1_024
    /// 连续写入失败达到此阈值即主动停录。
    private let maxConsecutiveWriteFailures = 3

    private var consecutiveWriteFailures = 0
    private var snapshotTickCount = 0

    private lazy var snapshotEncoder = SnapshotEncoder(
        maxLongSide: maxSnapshotLongSide,
        quality: jpegQuality,
        maxPendingFrames: 12
    )

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
        isAudioEnabled = false
        consecutiveWriteFailures = 0
        snapshotTickCount = 0
        deviceDirectories.removeAll()

        do {
            let now = Date()
            let directory = try createSessionDirectory(startedAt: now)

            // 录制前预检磁盘空间，避免录到一半写满。
            if availableCapacity(at: directory) < minFreeBytesToStart {
                throw RecordingServiceError.insufficientDiskSpace
            }

            // 音频降级为可选轨道：麦克风不可用或权限被拒时不再中断录制，仅记录画面截图。
            if await ensureMicrophoneAccess() {
                let audioURL = directory.appendingPathComponent("audio.m4a")
                if let recorder = try? makeAudioRecorder(outputURL: audioURL), recorder.record() {
                    audioRecorder = recorder
                    isAudioEnabled = true
                } else {
                    AppLogger.capture.warning("音频录制启动失败，仅录制画面截图")
                }
            } else {
                AppLogger.capture.info("未获得麦克风权限，仅录制画面截图")
            }

            startedAt = now
            outputDirectory = directory
            state = .recording(startedAt: now, outputDirectory: directory)

            startTimers()
            AppLogger.capture.info("录制已开始: \(directory.path)，音频: \(isAudioEnabled)")
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

    /// 检查麦克风访问权限。返回是否可用于录音，不再以抛错方式阻断整场录制。
    private func ensureMicrophoneAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .notDetermined:
            return await requestMicrophoneAccess()
        case .denied, .restricted:
            return false
        @unknown default:
            return false
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

        // 周期性空间检查（约每 10 秒一次），低于安全线主动停录。
        snapshotTickCount += 1
        if snapshotTickCount % 10 == 0, let outputDirectory,
           availableCapacity(at: outputDirectory) < minFreeBytesDuringRecording {
            abortRecording(with: .insufficientDiskSpace)
            return
        }

        let now = Date()
        let elapsedSecond = max(1, Int(now.timeIntervalSince(startedAt)))
        elapsedSeconds = elapsedSecond

        for snapshot in frameProvider() {
            do {
                let deviceDirectory = try directory(for: snapshot)
                let fileName = RecordingFileNaming.snapshotFileName(elapsedSecond: elapsedSecond, date: now)
                let outputURL = deviceDirectory.appendingPathComponent(fileName)
                // 深拷贝在主线程完成，编码/写盘在后台执行，结果回主线程记账。
                snapshotEncoder.submit(pixelBuffer: snapshot.pixelBuffer, to: outputURL) { [weak self] ok in
                    self?.handleSnapshotWriteResult(success: ok)
                }
            } catch {
                AppLogger.capture.warning("保存录制截图失败: \(error.localizedDescription)")
                handleSnapshotWriteResult(success: false)
            }
        }
    }

    /// 汇总一帧写盘结果：连续失败达阈值则主动停录。仅在录制中生效。
    private func handleSnapshotWriteResult(success: Bool) {
        guard state.isRecording else { return }
        if success {
            consecutiveWriteFailures = 0
        } else {
            consecutiveWriteFailures += 1
            if consecutiveWriteFailures >= maxConsecutiveWriteFailures {
                abortRecording(with: .insufficientDiskSpace)
            }
        }
    }

    /// 因异常（磁盘不足/写失败）被动停录：收尾资源并置为 failed，供 UI 感知。
    private func abortRecording(with error: RecordingServiceError) {
        AppLogger.capture.error("录制被动停止: \(error.localizedDescription)")
        _ = stopRecording()
        state = .failed(error.localizedDescription)
    }

    /// 返回目录所在卷的可用空间（重要用途口径），失败时返回 Int64.max 不误停。
    private func availableCapacity(at url: URL) -> Int64 {
        let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage ?? .max
    }

    private func cleanupAfterFailedStart() {
        stopTimers()
        stopAudioRecorder()

        // 删除本次启动已创建、但未产出有效内容的会话目录，避免残留空壳。
        if let directory = outputDirectory {
            removeDirectoryIfEmptyOrResidual(directory)
        }

        startedAt = nil
        outputDirectory = nil
        deviceDirectories.removeAll()
        elapsedSeconds = 0
    }

    /// 仅当目录为空、或只含启动失败残片(如未写入内容的 audio.m4a)时删除，避免误删有效数据。
    private func removeDirectoryIfEmptyOrResidual(_ directory: URL) {
        guard fileManager.fileExists(atPath: directory.path) else { return }

        let contents = (try? fileManager.contentsOfDirectory(atPath: directory.path)) ?? []
        let residualOnly = contents.allSatisfy { $0 == "audio.m4a" || $0 == ".DS_Store" }
        guard residualOnly else {
            AppLogger.capture.warning("启动失败目录含额外内容，保留不删除: \(directory.path)")
            return
        }

        do {
            try fileManager.removeItem(at: directory)
            AppLogger.capture.info("已清理启动失败的空录制目录: \(directory.path)")
        } catch {
            AppLogger.capture.warning("清理启动失败目录失败: \(error.localizedDescription)")
        }
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

// MARK: - 截图编码器

/// 将截图的缩放、JPEG 编码与写盘放到后台串行队列执行，避免阻塞主线程。
/// 提交前在调用线程完成 pixelBuffer 深拷贝，规避上游复用缓冲导致的读到错帧/崩溃。
final class SnapshotEncoder {
    private let context = CIContext(options: [.useSoftwareRenderer: false])
    private let queue = DispatchQueue(label: "com.screenPresenter.recording.encode", qos: .utility)
    private let maxLongSide: CGFloat
    private let quality: CGFloat
    private let maxPendingFrames: Int

    private let lock = NSLock()
    private var pendingCount = 0

    init(maxLongSide: CGFloat, quality: CGFloat, maxPendingFrames: Int) {
        self.maxLongSide = maxLongSide
        self.quality = quality
        self.maxPendingFrames = maxPendingFrames
    }

    /// 提交一帧编码。深拷贝在调用线程同步完成；编码与写盘在后台执行。
    /// completion 在主线程回调，参数为是否成功写盘。
    func submit(pixelBuffer: CVPixelBuffer, to outputURL: URL, completion: @escaping (Bool) -> Void) {
        // 背压：积压过多时丢最新帧，避免内存无限增长。
        lock.lock()
        if pendingCount >= maxPendingFrames {
            lock.unlock()
            AppLogger.capture.warning("截图编码积压，丢弃当前帧")
            return
        }
        pendingCount += 1
        lock.unlock()

        guard let copy = Self.deepCopy(pixelBuffer) else {
            lock.lock(); pendingCount -= 1; lock.unlock()
            AppLogger.capture.warning("截图缓冲拷贝失败，跳过当前帧")
            DispatchQueue.main.async { completion(false) }
            return
        }

        queue.async { [weak self] in
            guard let self else { return }
            let ok = self.encodeAndWrite(pixelBuffer: copy, to: outputURL)
            self.lock.lock(); self.pendingCount -= 1; self.lock.unlock()
            DispatchQueue.main.async { completion(ok) }
        }
    }

    private func encodeAndWrite(pixelBuffer: CVPixelBuffer, to outputURL: URL) -> Bool {
        let image = CIImage(cvImageBuffer: pixelBuffer)
        let longSide = max(image.extent.width, image.extent.height)
        let scale = longSide > maxLongSide ? maxLongSide / longSide : 1
        let outputImage = scale < 1
            ? image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            : image

        guard let cgImage = context.createCGImage(outputImage, from: outputImage.extent) else {
            return false
        }
        guard let destination = CGImageDestinationCreateWithURL(
            outputURL as CFURL,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            return false
        }
        CGImageDestinationAddImage(
            destination,
            cgImage,
            [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary
        )
        return CGImageDestinationFinalize(destination)
    }

    /// 深拷贝 CVPixelBuffer（逐平面 memcpy），使后台编码不受上游缓冲复用影响。
    private static func deepCopy(_ source: CVPixelBuffer) -> CVPixelBuffer? {
        let width = CVPixelBufferGetWidth(source)
        let height = CVPixelBufferGetHeight(source)
        let format = CVPixelBufferGetPixelFormatType(source)
        let attrs: [CFString: Any] = [
            kCVPixelBufferIOSurfacePropertiesKey: [:],
            kCVPixelBufferMetalCompatibilityKey: true,
        ]

        var destination: CVPixelBuffer?
        guard CVPixelBufferCreate(
            kCFAllocatorDefault, width, height, format, attrs as CFDictionary, &destination
        ) == kCVReturnSuccess, let destination else {
            return nil
        }

        CVPixelBufferLockBaseAddress(source, .readOnly)
        CVPixelBufferLockBaseAddress(destination, [])
        defer {
            CVPixelBufferUnlockBaseAddress(destination, [])
            CVPixelBufferUnlockBaseAddress(source, .readOnly)
        }

        let planeCount = max(1, CVPixelBufferGetPlaneCount(source))
        if CVPixelBufferGetPlaneCount(source) == 0 {
            guard let src = CVPixelBufferGetBaseAddress(source),
                  let dst = CVPixelBufferGetBaseAddress(destination) else { return nil }
            let bytes = CVPixelBufferGetBytesPerRow(source) * height
            memcpy(dst, src, min(bytes, CVPixelBufferGetBytesPerRow(destination) * height))
            return destination
        }

        for plane in 0..<planeCount {
            guard let src = CVPixelBufferGetBaseAddressOfPlane(source, plane),
                  let dst = CVPixelBufferGetBaseAddressOfPlane(destination, plane) else { return nil }
            let srcBytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(source, plane)
            let dstBytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(destination, plane)
            let planeHeight = CVPixelBufferGetHeightOfPlane(source, plane)
            let copyBytesPerRow = min(srcBytesPerRow, dstBytesPerRow)
            for row in 0..<planeHeight {
                memcpy(dst + row * dstBytesPerRow, src + row * srcBytesPerRow, copyBytesPerRow)
            }
        }
        return destination
    }
}
