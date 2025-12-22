//
//  IOSDeviceProvider.swift
//  DemoConsole
//
//  Created by Sun on 2025/12/24.
//
//  iOS 设备提供者
//  使用 AVFoundation 发现和管理 USB 连接的 iOS 设备
//

import AVFoundation
import Combine
import Foundation

// MARK: - iOS 设备提供者

@MainActor
final class IOSDeviceProvider: NSObject, ObservableObject {
    // MARK: - 状态

    /// 已发现的 iOS 设备列表
    @Published private(set) var devices: [IOSDevice] = []

    /// 是否正在监控
    @Published private(set) var isMonitoring = false

    /// 最后一次错误
    @Published private(set) var lastError: String?

    /// 服务状态
    @Published private(set) var serviceStatus: ServiceStatus = .idle

    // MARK: - 服务状态枚举

    enum ServiceStatus: Equatable {
        case idle
        case monitoring
        case error(String)

        var displayName: String {
            switch self {
            case .idle: "未启动"
            case .monitoring: "监控中"
            case let .error(msg): "错误: \(msg)"
            }
        }

        var isReady: Bool {
            if case .monitoring = self { return true }
            return false
        }
    }

    // MARK: - 私有属性

    private var discoverySession: AVCaptureDevice.DiscoverySession?
    private var deviceObservation: NSKeyValueObservation?
    private var cancellables = Set<AnyCancellable>()

    // MARK: - 初始化

    override init() {
        super.init()
        setupNotifications()
    }

    deinit {
        deviceObservation?.invalidate()
    }

    // MARK: - 公开方法

    /// 开始监控设备
    func startMonitoring() {
        guard !isMonitoring else { return }

        isMonitoring = true
        lastError = nil
        serviceStatus = .monitoring

        // 直接设置设备发现会话
        // 注意：AVCaptureDevice.DiscoverySession 发现外部设备不需要摄像头权限
        // 权限会在实际创建 AVCaptureSession 并添加输入时由系统自动请求
        setupDiscoverySession()
    }

    /// 设置设备发现会话
    private func setupDiscoverySession() {
        // 创建发现会话，监听外部视频设备
        // 使用更广泛的设备类型以确保能检测到 iOS 设备
        discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.external, .builtInWideAngleCamera],
            mediaType: .video,
            position: .unspecified
        )

        // 打印所有发现的设备用于调试
        if let devices = discoverySession?.devices {
            AppLogger.device.info("AVCaptureDevice 发现 \(devices.count) 个设备:")
            for device in devices {
                AppLogger.device
                    .info("  - \(device.localizedName) (类型: \(device.deviceType.rawValue), ID: \(device.uniqueID))")
            }
        }

        // 监听设备列表变化
        deviceObservation = discoverySession?.observe(\.devices, options: [.new, .initial]) { [weak self] _, _ in
            Task { @MainActor in
                self?.refreshDevices()
            }
        }

        // 立即刷新一次
        refreshDevices()

        AppLogger.device.info("iOS 设备监控已启动")
    }

    /// 停止监控
    func stopMonitoring() {
        isMonitoring = false
        deviceObservation?.invalidate()
        deviceObservation = nil
        discoverySession = nil
        serviceStatus = .idle

        AppLogger.device.info("iOS 设备监控已停止")
    }

    /// 手动刷新设备列表
    func refreshDevices() {
        guard let session = discoverySession else {
            // 如果没有会话，创建临时查询
            let tempSession = AVCaptureDevice.DiscoverySession(
                deviceTypes: [.external],
                mediaType: .video,
                position: .unspecified
            )
            updateDeviceList(from: tempSession.devices)
            return
        }

        updateDeviceList(from: session.devices)
    }

    /// 获取特定设备
    func device(for id: String) -> IOSDevice? {
        devices.first { $0.id == id }
    }

    /// 获取 AVCaptureDevice
    func captureDevice(for deviceID: String) -> AVCaptureDevice? {
        AVCaptureDevice(uniqueID: deviceID)
    }

    // MARK: - 私有方法

    private func updateDeviceList(from captureDevices: [AVCaptureDevice]) {
        AppLogger.device.debug("正在更新设备列表，共 \(captureDevices.count) 个 AVCaptureDevice")

        let iosDevices = captureDevices.compactMap { device -> IOSDevice? in
            IOSDevice.from(captureDevice: device)
        }

        AppLogger.device.debug("过滤后 iOS 设备数量: \(iosDevices.count)")

        // 只在设备列表真正变化时更新
        if iosDevices.map(\.id) != devices.map(\.id) {
            devices = iosDevices

            if iosDevices.isEmpty {
                AppLogger.device.info("未发现 iOS 设备")
            } else {
                AppLogger.device
                    .info("发现 \(iosDevices.count) 个 iOS 设备: \(iosDevices.map(\.name).joined(separator: ", "))")
            }
        }
    }

    private func setupNotifications() {
        // 监听设备连接/断开通知
        NotificationCenter.default.publisher(for: .AVCaptureDeviceWasConnected)
            .sink { [weak self] notification in
                Task { @MainActor in
                    if let device = notification.object as? AVCaptureDevice {
                        AppLogger.device.info("设备已连接: \(device.localizedName)")
                    }
                    self?.refreshDevices()
                }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .AVCaptureDeviceWasDisconnected)
            .sink { [weak self] notification in
                Task { @MainActor in
                    if let device = notification.object as? AVCaptureDevice {
                        AppLogger.device.info("设备已断开: \(device.localizedName)")
                    }
                    self?.refreshDevices()
                }
            }
            .store(in: &cancellables)
    }
}
