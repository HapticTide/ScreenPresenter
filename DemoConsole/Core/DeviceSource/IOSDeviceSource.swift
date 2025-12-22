//
//  IOSDeviceSource.swift
//  DemoConsole
//
//  Created by Sun on 2025/12/24.
//
//  iOS 设备源
//  使用 AVFoundation 直接捕获 USB 连接的 iPhone/iPad 视频流
//

import AVFoundation
import Combine
import CoreMedia
import Foundation

// MARK: - iOS 设备源

@MainActor
final class IOSDeviceSource: BaseDeviceSource {
    // MARK: - 属性

    /// 关联的 iOS 设备
    let iosDevice: IOSDevice

    /// 是否支持音频
    override var supportsAudio: Bool { true }

    // MARK: - 私有属性

    private var captureSession: AVCaptureSession?
    private var videoOutput: AVCaptureVideoDataOutput?
    private var audioOutput: AVCaptureAudioDataOutput?
    private let captureQueue = DispatchQueue(label: "com.democonsole.ios.capture", qos: .userInteractive)
    private let audioQueue = DispatchQueue(label: "com.democonsole.ios.audio", qos: .userInteractive)

    /// 视频输出代理
    private var videoDelegate: VideoCaptureDelegate?

    /// 是否正在捕获（线程安全标志）
    private var isCapturingFlag: Bool = false

    // MARK: - 初始化

    init(device: IOSDevice) {
        iosDevice = device

        let deviceInfo = GenericDeviceInfo(
            id: device.id,
            name: device.name,
            model: device.modelID,
            platform: .ios
        )

        super.init(
            displayName: device.name,
            sourceType: .quicktime // 复用 quicktime 类型
        )

        self.deviceInfo = deviceInfo
    }

    // MARK: - DeviceSource 实现

    override func connect() async throws {
        updateState(.connecting)

        AppLogger.device.info("正在查找设备: \(iosDevice.id)")

        // 获取 AVCaptureDevice
        guard let captureDevice = AVCaptureDevice(uniqueID: iosDevice.id) else {
            let error = DeviceSourceError.connectionFailed("无法找到设备")
            AppLogger.device.error("设备查找失败: \(iosDevice.id)")
            updateState(.error(error))
            throw error
        }

        AppLogger.device.info("找到设备: \(captureDevice.localizedName), 类型: \(captureDevice.deviceType.rawValue)")

        // 检查是否可用
        guard !captureDevice.isSuspended else {
            let error = DeviceSourceError.connectionFailed("设备已暂停")
            AppLogger.device.error("设备已暂停: \(iosDevice.name)")
            updateState(.error(error))
            throw error
        }

        // 创建捕获会话
        let session = AVCaptureSession()
        session.sessionPreset = .high

        // 添加视频输入
        do {
            AppLogger.device.info("正在创建视频输入...")
            let videoInput = try AVCaptureDeviceInput(device: captureDevice)
            if session.canAddInput(videoInput) {
                session.addInput(videoInput)
                AppLogger.device.info("视频输入已添加")
            } else {
                throw DeviceSourceError.connectionFailed("无法添加视频输入到会话")
            }
        } catch let error as DeviceSourceError {
            updateState(.error(error))
            throw error
        } catch let error as NSError {
            AppLogger.device.error("创建视频输入失败: \(error.localizedDescription), 错误码: \(error.code), 域: \(error.domain)")

            // 检查是否是权限错误
            // AVFoundation 权限错误通常是 AVError.applicationIsNotAuthorizedToUseDevice
            if error.domain == AVFoundationErrorDomain, error.code == -11852 {
                AppLogger.device.error("需要摄像头权限才能访问 iOS 设备视频流")
                let deviceError = DeviceSourceError.permissionDenied
                updateState(.error(deviceError))
                throw deviceError
            }

            let deviceError = DeviceSourceError.connectionFailed(error.localizedDescription)
            updateState(.error(deviceError))
            throw deviceError
        }

        // 尝试添加音频输入（可选）
        if let audioDevice = findAudioDevice(for: iosDevice.id) {
            do {
                let audioInput = try AVCaptureDeviceInput(device: audioDevice)
                if session.canAddInput(audioInput) {
                    session.addInput(audioInput)
                    AppLogger.device.info("已添加音频输入")
                }
            } catch {
                AppLogger.device.warning("无法添加音频输入: \(error.localizedDescription)")
            }
        }

        // 配置视频输出
        let videoOutput = AVCaptureVideoDataOutput()
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        ]
        videoOutput.alwaysDiscardsLateVideoFrames = true

        // 创建代理
        let delegate = VideoCaptureDelegate { [weak self] sampleBuffer in
            self?.handleVideoSampleBuffer(sampleBuffer)
        }
        videoOutput.setSampleBufferDelegate(delegate, queue: captureQueue)
        videoDelegate = delegate

        if session.canAddOutput(videoOutput) {
            session.addOutput(videoOutput)
            self.videoOutput = videoOutput
        } else {
            throw DeviceSourceError.connectionFailed("无法添加视频输出")
        }

        // 配置音频输出
        let audioOutput = AVCaptureAudioDataOutput()
        if session.canAddOutput(audioOutput) {
            session.addOutput(audioOutput)
            self.audioOutput = audioOutput
        }

        captureSession = session
        updateState(.connected)

        // 获取视频尺寸
        let formatDescription = captureDevice.activeFormat.formatDescription
        let dimensions = CMVideoFormatDescriptionGetDimensions(formatDescription)
        updateCaptureSize(CGSize(width: CGFloat(dimensions.width), height: CGFloat(dimensions.height)))

        AppLogger.device.info("iOS 设备已连接: \(iosDevice.name)")
    }

    override func disconnect() async {
        await stopCapture()

        captureSession?.stopRunning()
        captureSession = nil
        videoOutput = nil
        audioOutput = nil
        videoDelegate = nil

        updateState(.disconnected)
        AppLogger.device.info("iOS 设备已断开: \(iosDevice.name)")
    }

    override func reconnect() async throws {
        await disconnect()
        try await connect()
    }

    override func startCapture() async throws {
        guard let session = captureSession else {
            throw DeviceSourceError.captureStartFailed("未连接到设备")
        }

        guard state == .connected || state == .paused else {
            throw DeviceSourceError.captureStartFailed("设备状态不正确: \(state.displayText)")
        }

        // 设置捕获标志（在启动会话前设置）
        isCapturingFlag = true
        updateState(.capturing)

        AppLogger.device.info("正在启动捕获会话...")

        // 在后台线程启动会话
        await Task.detached { [session] in
            session.startRunning()
        }.value

        AppLogger.device.info("iOS 设备捕获已开始: \(iosDevice.name), 会话运行中: \(session.isRunning)")
    }

    override func stopCapture() async {
        isCapturingFlag = false

        guard let session = captureSession, session.isRunning else { return }

        // 在后台线程停止会话
        await Task.detached { [session] in
            session.stopRunning()
        }.value

        updateState(.connected)
        AppLogger.device.info("iOS 设备捕获已停止: \(iosDevice.name)")
    }

    override func pauseCapture() {
        guard state == .capturing else { return }
        updateState(.paused)
    }

    override func resumeCapture() {
        guard state == .paused else { return }
        updateState(.capturing)
    }

    // MARK: - 私有方法

    private func findAudioDevice(for deviceID: String) -> AVCaptureDevice? {
        // 查找与视频设备关联的音频设备
        let audioSession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.external, .externalUnknown],
            mediaType: .audio,
            position: .unspecified
        )

        // 尝试通过设备名称匹配
        let videoDeviceName = iosDevice.name
        return audioSession.devices.first { audioDevice in
            audioDevice.localizedName.contains(videoDeviceName) ||
                videoDeviceName.contains(audioDevice.localizedName)
        }
    }

    private func handleVideoSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        // 使用线程安全的标志检查
        guard isCapturingFlag else { return }

        // 获取图像缓冲区
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        // 获取时间戳
        let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)

        // 获取尺寸
        let width = CVPixelBufferGetWidth(imageBuffer)
        let height = CVPixelBufferGetHeight(imageBuffer)
        let size = CGSize(width: width, height: height)

        // 创建 CapturedFrame
        let frame = CapturedFrame(
            pixelBuffer: imageBuffer,
            presentationTime: presentationTime,
            size: size
        )

        // 在主线程更新 UI 相关状态
        Task { @MainActor [weak self] in
            guard let self else { return }

            // 更新捕获尺寸（如果变化）
            if captureSize != size {
                updateCaptureSize(size)
            }

            // 发送帧
            emitFrame(frame)
        }
    }
}

// MARK: - 视频捕获代理

private final class VideoCaptureDelegate: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    private let handler: (CMSampleBuffer) -> Void

    init(handler: @escaping (CMSampleBuffer) -> Void) {
        self.handler = handler
        super.init()
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        handler(sampleBuffer)
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didDrop sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        // 帧被丢弃，可以记录日志
    }
}
