//
//  RecordingService.swift
//  ScreenPresenter
//
//  Created by Sun on 2026/06/30.
//
//  录制服务
//  负责独立录制 Mac 麦克风，并按设备保存 HEVC 视频分段
//

import AVFoundation
import Combine
import CoreVideo
import Foundation

// MARK: - 录制状态

enum RecordingState: Equatable {
    case idle
    case starting(outputDirectory: URL)
    case recording(startedAt: Date, outputDirectory: URL)
    case stopping(outputDirectory: URL)
    case failed(String)

    var isRecording: Bool {
        switch self {
        case .starting, .recording, .stopping:
            true
        case .idle, .failed:
            false
        }
    }

    var isCapturingFrames: Bool {
        if case .recording = self { return true }
        return false
    }

    var isStopping: Bool {
        if case .stopping = self { return true }
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

// MARK: - 音频轨道状态

/// 录制时音频轨道的最终状态。用于向用户准确说明"为什么没有声音"。
enum RecordingAudioStatus: Equatable {
    /// 音频正常录制中。
    case enabled
    /// 用户在偏好设置中主动关闭了麦克风录制。
    case disabled
    /// 设备没有麦克风硬件。
    case noDevice
    /// 存在麦克风，但未授予权限（被拒绝 / 受限 / 用户拒绝）。
    case permissionDenied
    /// 存在麦克风且有权限，但录音器启动失败（被占用、硬件异常等）。
    case unavailable
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

    /// 本次录制音频轨道的最终状态。默认无音频；startRecording 时按实际情况判定。
    private(set) var audioStatus: RecordingAudioStatus = .noDevice

    /// 本次录制是否启用了会议音频。麦克风不可用或权限被拒时为 false，视频仍继续录制。
    var isAudioEnabled: Bool { audioStatus == .enabled }

    // MARK: - 私有属性

    private let frameProvider: FrameProvider
    private let fileManager: FileManager

    private var audioProcess: RecordingAudioProcess?
    private var videoTask: Task<Void, Never>?
    private var elapsedTask: Task<Void, Never>?
    private var startedAt: Date?
    private var outputDirectory: URL?
    private var deviceDirectories: [String: URL] = [:]
    private var videoTracks: [String: DeviceVideoTrack] = [:]
    private var pendingFinishTasks: [Task<Void, Never>] = []
    private var isStopping = false
    private var activeOperationID: UUID?

    /// 录制启动前要求的最小可用磁盘空间。
    private let minFreeBytesToStart: Int64 = 1_024 * 1_024 * 1_024
    /// 录制过程中的安全下限，低于此值主动停录。
    private let minFreeBytesDuringRecording: Int64 = 200 * 1_024 * 1_024
    /// 连续写入失败达到此阈值即主动停录。
    private let maxConsecutiveWriteFailures = 3

    private var videoTickCount = 0

    private final class DeviceVideoTrack {
        let directory: URL
        var sequence = 0
        var currentWriter: RecordingVideoSegmentWriter?
        var currentSize: CGSize?
        var lastFrameTime: TimeInterval?
        var isAppendPending = false
        var appendTask: Task<Void, Never>?
        var consecutiveWriteFailures = 0

        init(directory: URL) {
            self.directory = directory
        }
    }

    // MARK: - 初始化

    init(fileManager: FileManager = .default, frameProvider: @escaping FrameProvider) {
        self.fileManager = fileManager
        self.frameProvider = frameProvider
        super.init()
    }

    deinit {
        videoTask?.cancel()
        elapsedTask?.cancel()
        audioProcess?.cancel()
    }

    // MARK: - 公开方法

    func startRecording() async throws {
        guard !state.isRecording else { return }

        let operationID = UUID()
        activeOperationID = operationID

        lastOutputDirectory = nil
        elapsedSeconds = 0
        audioStatus = .noDevice
        videoTickCount = 0
        isStopping = false
        deviceDirectories.removeAll()
        videoTracks.removeAll()
        pendingFinishTasks.removeAll()

        do {
            let directory = try createSessionDirectory(startedAt: Date())
            outputDirectory = directory
            state = .starting(outputDirectory: directory)

            // 录制前预检磁盘空间，避免录到一半写满。
            if availableCapacity(at: directory) < minFreeBytesToStart {
                throw RecordingServiceError.insufficientDiskSpace
            }

            // 音频降级为可选轨道：无麦克风 / 权限被拒 / 麦克风不可用都不中断录制，仅记录画面，
            // 并把具体成因记入 audioStatus 供 UI 准确提示。
            guard let audioTrack = await configureAudioTrack(
                in: directory,
                operationID: operationID
            ) else {
                throw CancellationError()
            }
            guard activeOperationID == operationID, case .starting = state else {
                throw CancellationError()
            }
            audioStatus = audioTrack.status

            // 统一以音频 Helper 实际启动时间作为会话 epoch；无音频时使用当前时间。
            // 这样首次权限弹窗停留时间不会被错误计入视频全局时间轴。
            let startedAt = audioTrack.startedAt ?? Date()
            self.startedAt = startedAt
            state = .recording(startedAt: startedAt, outputDirectory: directory)

            startSchedulingTasks()
            AppLogger.capture.info("录制已开始: \(directory.path)，音频状态: \(String(describing: audioStatus))")
        } catch is CancellationError {
            if activeOperationID == operationID {
                await cleanupAfterFailedStart()
                activeOperationID = nil
                state = .idle
            }
            throw CancellationError()
        } catch {
            if activeOperationID == operationID {
                await cleanupAfterFailedStart()
                activeOperationID = nil
                state = .failed(error.localizedDescription)
            }
            throw error
        }
    }

    @discardableResult
    func stopRecording() async -> URL? {
        let wasRecording = state.isRecording
        let wasCapturingFrames = state.isCapturingFrames
        guard wasRecording, !isStopping else { return lastOutputDirectory }
        isStopping = true
        activeOperationID = nil

        if let outputDirectory {
            state = .stopping(outputDirectory: outputDirectory)
        }

        stopSchedulingTasks()
        await stopAudioCapture()

        let directory = outputDirectory
        let sessionStartedAt = startedAt

        for track in videoTracks.values {
            finishCurrentSegment(for: track)
        }
        let finishTasks = pendingFinishTasks
        for task in finishTasks {
            await task.value
        }

        let audioDuration = await recordedAudioDuration(in: directory)
        let shouldPreserveSession = wasCapturingFrames || audioDuration != nil

        if shouldPreserveSession, let directory {
            writeSessionMetadata(
                in: directory,
                sessionStartedAt: sessionStartedAt,
                audioDuration: audioDuration
            )
        }

        outputDirectory = nil
        startedAt = nil
        deviceDirectories.removeAll()
        videoTracks.removeAll()
        pendingFinishTasks.removeAll()
        isStopping = false
        activeOperationID = nil

        state = .idle
        if shouldPreserveSession, let directory {
            lastOutputDirectory = directory
        } else if let directory {
            removeDirectoryIfEmptyOrResidual(directory)
        }

        if shouldPreserveSession, let directory {
            AppLogger.capture.info("录制已停止: \(directory.path)")
        }

        return shouldPreserveSession ? (directory ?? lastOutputDirectory) : nil
    }
}

// MARK: - 录制内部实现

private extension RecordingService {

    // MARK: - 权限和录音

    /// 判定音频轨道状态并在可用时启动录音器。区分三种"没有音频"的成因:
    /// 无麦克风硬件 / 权限被拒 / 麦克风存在但不可用。
    private struct AudioTrackStart {
        let status: RecordingAudioStatus
        let startedAt: Date?
    }

    private func configureAudioTrack(
        in directory: URL,
        operationID: UUID
    ) async -> AudioTrackStart? {
        // 0. 用户主动关闭麦克风录制时，直接纯画面录制，不查硬件/权限。
        guard UserPreferences.shared.recordingMicrophoneEnabled else {
            AppLogger.capture.info("用户已关闭麦克风录制，仅录制设备视频")
            return AudioTrackStart(status: .disabled, startedAt: nil)
        }

        // 麦克风设备检查、权限申请和采集全部放在独立 Helper 中。
        // 主 App 内仍有 iPhone 投屏 AVCaptureSession，
        // 若两者处于同一进程，macOS 会聚合 AVFoundation 隐私状态，导致停录后橙色状态残留。
        let audioURL = directory.appendingPathComponent("audio.m4a")
        do {
            let result = try await RecordingAudioProcess.start(
                outputURL: audioURL,
                onLaunched: { [weak self] process in
                    guard let self, self.activeOperationID == operationID else {
                        process.cancel()
                        return
                    }
                    self.audioProcess = process
                },
                onUnexpectedTermination: { [weak self] error in
                    Task { @MainActor in
                        guard let self, self.state.isCapturingFrames else { return }
                        _ = await self.stopRecording()
                        self.state = .failed(error.localizedDescription)
                    }
                }
            )
            guard activeOperationID == operationID else {
                result.process.cancel()
                return nil
            }
            audioProcess = result.process
            return AudioTrackStart(status: .enabled, startedAt: result.startedAt)
        } catch let error as RecordingAudioProcessError {
            guard activeOperationID == operationID else { return nil }
            return audioTrackStart(for: error)
        } catch {
            guard activeOperationID == operationID else { return nil }
            AppLogger.capture.warning("启动录音 Helper 失败，仅录制设备视频: \(error.localizedDescription)")
            return AudioTrackStart(status: .unavailable, startedAt: nil)
        }
    }

    private func audioTrackStart(for error: RecordingAudioProcessError) -> AudioTrackStart {
        if case let .helperFailed(code, _) = error {
            switch code {
            case .noDevice:
                return AudioTrackStart(status: .noDevice, startedAt: nil)
            case .permissionDenied:
                return AudioTrackStart(status: .permissionDenied, startedAt: nil)
            case .unavailable:
                break
            }
        }
        AppLogger.capture.warning("麦克风可用但录音 Helper 启动失败，仅录制设备视频: \(error.localizedDescription)")
        return AudioTrackStart(status: .unavailable, startedAt: nil)
    }

    // MARK: - 目录

    private func createSessionDirectory(startedAt: Date) throws -> URL {
        // 根目录取自偏好（保存位置），录制写入与历史扫描保持一致。
        let rootDirectory = UserPreferences.shared.recordingsRootDirectory(fileManager: fileManager)
        try fileManager.createDirectory(at: rootDirectory, withIntermediateDirectories: true)

        let baseName = RecordingFileNaming.sessionDirectoryName(date: startedAt)
        for sequence in 0..<10_000 {
            let directoryName = sequence == 0
                ? baseName
                : "\(baseName)-\(String(format: "%03d", sequence))"
            let candidate = rootDirectory.appendingPathComponent(directoryName, isDirectory: true)
            guard !fileManager.fileExists(atPath: candidate.path) else { continue }

            // 不使用 withIntermediateDirectories，确保同名目录在竞争条件下不会被复用。
            try fileManager.createDirectory(at: candidate, withIntermediateDirectories: false)
            return candidate
        }

        throw RecordingServiceError.outputDirectoryUnavailable
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

    // MARK: - 录制定时任务

    private func startSchedulingTasks() {
        stopSchedulingTasks()

        // RecordingService 整体由 MainActor 隔离，计时任务直接继承该隔离域。
        // 不再依赖窗口 RunLoop；此前 RunLoop Timer 在部分启动路径中不会触发，
        // 导致界面一直显示 00:00，且共用同一调度方式的视频取帧也完全不执行。
        elapsedTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: 500_000_000)
                } catch {
                    return
                }
                guard !Task.isCancelled, let self else { return }
                self.updateElapsedSeconds()
            }
        }

        let framesPerSecond = RecordingVideoConfiguration.screenRecording.framesPerSecond
        let videoIntervalNanoseconds = UInt64(1_000_000_000 / framesPerSecond)
        videoTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: videoIntervalNanoseconds)
                } catch {
                    return
                }
                guard !Task.isCancelled, let self else { return }
                self.captureCurrentDeviceFrames()
            }
        }
    }

    private func updateElapsedSeconds() {
        guard let startedAt else {
            elapsedSeconds = 0
            return
        }
        elapsedSeconds = max(0, Int(Date().timeIntervalSince(startedAt)))
    }

    // MARK: - 视频帧

    private func captureCurrentDeviceFrames() {
        guard state.isCapturingFrames, let startedAt else { return }

        // 周期性空间检查（约每 10 秒一次），低于安全线主动停录。
        videoTickCount += 1
        if videoTickCount % (RecordingVideoConfiguration.screenRecording.framesPerSecond * 10) == 0,
           let outputDirectory,
           availableCapacity(at: outputDirectory) < minFreeBytesDuringRecording {
            abortRecording(with: .insufficientDiskSpace)
            return
        }

        let sessionTime = max(0, Date().timeIntervalSince(startedAt))
        let snapshots = frameProvider()
        let activeKeys = Set(snapshots.map { trackKey(for: $0) })
        finishInactiveTracks(activeKeys: activeKeys, sessionTime: sessionTime)

        for snapshot in snapshots {
            append(snapshot: snapshot, sessionTime: sessionTime)
        }
    }

    private func finishInactiveTracks(activeKeys: Set<String>, sessionTime: TimeInterval) {
        for (key, track) in videoTracks where !activeKeys.contains(key) {
            guard let lastFrameTime = track.lastFrameTime,
                  sessionTime - lastFrameTime >= 0.5 else {
                continue
            }
            finishCurrentSegment(for: track)
            track.lastFrameTime = nil
        }
    }

    private func append(snapshot: RecordingFrameSnapshot, sessionTime: TimeInterval) {
        do {
            let track = try videoTrack(for: snapshot)
            let sourceSize = CGSize(
                width: CVPixelBufferGetWidth(snapshot.pixelBuffer),
                height: CVPixelBufferGetHeight(snapshot.pixelBuffer)
            )
            if track.currentWriter == nil || track.currentSize != sourceSize {
                finishCurrentSegment(for: track)
                track.sequence += 1
                let startMilliseconds = Int64((sessionTime * 1_000).rounded())
                let fileName = RecordingFileNaming.videoSegmentFileName(
                    startMilliseconds: startMilliseconds,
                    sequence: track.sequence
                )
                track.currentWriter = RecordingVideoSegmentWriter(
                    outputURL: track.directory.appendingPathComponent(fileName),
                    configuration: .screenRecording
                )
                track.currentSize = sourceSize
            }
            track.lastFrameTime = sessionTime

            guard let writer = track.currentWriter, !track.isAppendPending else { return }
            // 每个设备轨道最多保留一个待编码帧。编码跟不上 30fps 时直接丢弃新帧，
            // 避免一小时录制期间无界积压 Task 和 CVPixelBuffer。
            track.isAppendPending = true
            let appendTask = Task { [weak self, weak track] in
                do {
                    try await writer.append(pixelBuffer: snapshot.pixelBuffer, sessionTime: sessionTime)
                    await MainActor.run {
                        guard let track else { return }
                        self?.completeVideoAppend(for: track, success: true)
                    }
                } catch {
                    AppLogger.capture.warning("写入录制视频帧失败: \(error.localizedDescription)")
                    await MainActor.run {
                        guard let track else { return }
                        self?.completeVideoAppend(for: track, success: false)
                    }
                }
            }
            track.appendTask = appendTask
        } catch {
            AppLogger.capture.warning("创建录制视频分段失败: \(error.localizedDescription)")
            abortRecording(with: .outputDirectoryUnavailable)
        }
    }

    private func trackKey(for snapshot: RecordingFrameSnapshot) -> String {
        "\(snapshot.platform.rawValue)-\(snapshot.deviceName)"
    }

    private func videoTrack(for snapshot: RecordingFrameSnapshot) throws -> DeviceVideoTrack {
        let key = trackKey(for: snapshot)
        if let track = videoTracks[key] { return track }

        let track = DeviceVideoTrack(directory: try directory(for: snapshot))
        videoTracks[key] = track
        return track
    }

    private func finishCurrentSegment(for track: DeviceVideoTrack) {
        guard let writer = track.currentWriter else { return }
        track.currentWriter = nil
        track.currentSize = nil
        let appendTask = track.appendTask

        let task = Task {
            await appendTask?.value
            do {
                try await writer.finish()
            } catch {
                AppLogger.capture.warning("完成录制视频分段失败: \(error.localizedDescription)")
            }
        }
        pendingFinishTasks.append(task)
    }

    private func completeVideoAppend(for track: DeviceVideoTrack, success: Bool) {
        track.isAppendPending = false
        track.appendTask = nil
        handleVideoWriteResult(for: track, success: success)
    }

    /// 按设备轨道汇总视频帧写入结果，避免一个设备的成功掩盖另一个设备的持续失败。
    private func handleVideoWriteResult(for track: DeviceVideoTrack, success: Bool) {
        guard state.isCapturingFrames else { return }
        if success {
            track.consecutiveWriteFailures = 0
        } else {
            track.consecutiveWriteFailures += 1
            if track.consecutiveWriteFailures >= maxConsecutiveWriteFailures {
                abortRecording(with: .insufficientDiskSpace)
            }
        }
    }

    /// 因异常（磁盘不足/写失败）被动停录：收尾资源并置为 failed，供 UI 感知。
    private func abortRecording(with error: RecordingServiceError) {
        AppLogger.capture.error("录制被动停止: \(error.localizedDescription)")
        Task { @MainActor in
            _ = await stopRecording()
            state = .failed(error.localizedDescription)
        }
    }

    /// 返回目录所在卷的可用空间（重要用途口径），失败时返回 Int64.max 不误停。
    private func availableCapacity(at url: URL) -> Int64 {
        let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage ?? .max
    }

    private func cleanupAfterFailedStart() async {
        stopSchedulingTasks()
        await stopAudioCapture()

        // 删除本次启动已创建、但未产出有效内容的会话目录，避免残留空壳。
        if let directory = outputDirectory {
            removeDirectoryIfEmptyOrResidual(directory)
        }

        startedAt = nil
        outputDirectory = nil
        deviceDirectories.removeAll()
        videoTracks.removeAll()
        pendingFinishTasks.removeAll()
        isStopping = false
        elapsedSeconds = 0
    }

    /// 调用前已经验证目录中不存在有效音频或视频；这里只负责删除空目录及无效残片。
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

    /// 返回已完成音频文件的有效时长。只有能够被 AVFoundation 正常解析且时长大于零，
    /// 才将其视作需要保留的用户录制内容。
    private func recordedAudioDuration(in directory: URL?) async -> TimeInterval? {
        guard let directory else { return nil }
        let audioURL = directory.appendingPathComponent("audio.m4a")
        guard fileManager.fileExists(atPath: audioURL.path) else { return nil }

        let asset = AVURLAsset(url: audioURL)
        guard let duration = try? await asset.load(.duration) else { return nil }
        let seconds = duration.seconds
        guard seconds.isFinite, seconds > 0 else { return nil }
        return seconds
    }

    private func writeSessionMetadata(
        in directory: URL,
        sessionStartedAt: Date?,
        audioDuration: TimeInterval?
    ) {
        // 正常启动后使用 Helper 上报的准确 epoch；如果用户在 starting 阶段停止，
        // 则用已完成音频的实际时长反推开始时间，避免删除已经录到的有效内容。
        let metadataStartedAt = sessionStartedAt
            ?? Date().addingTimeInterval(-(audioDuration ?? 0))
        let elapsedDuration = max(0, Date().timeIntervalSince(metadataStartedAt))
        let finalDuration = max(elapsedDuration, audioDuration ?? 0)
        let durationMilliseconds = Int64((finalDuration * 1_000).rounded())

        do {
            let metadata = RecordingSessionMetadata(
                version: RecordingSessionMetadata.currentVersion,
                startedAt: metadataStartedAt,
                durationMilliseconds: durationMilliseconds,
                video: .screenRecording
            )
            try RecordingSessionMetadata.encode(metadata).write(
                to: directory.appendingPathComponent("session.json"),
                options: .atomic
            )
        } catch {
            AppLogger.capture.error("写入录制会话元数据失败: \(error.localizedDescription)")
        }
    }

    private func stopSchedulingTasks() {
        videoTask?.cancel()
        elapsedTask?.cancel()
        videoTask = nil
        elapsedTask = nil
    }

    private func stopAudioCapture() async {
        guard let audioProcess else { return }
        self.audioProcess = nil
        await audioProcess.stop()
    }
}
