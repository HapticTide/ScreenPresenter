//
//  IOSDeviceProvider.swift
//  ScreenPresenter
//
//  Created by Sun on 2025/12/24.
//
//  iOS 设备提供者
//  使用 AVFoundation 发现和管理 USB 连接的 iOS 设备
//
//  双层数据源策略：
//  1. 主层：AVFoundation（设备发现 + 捕获能力检测）— 稳定的公开 API
//  2. 增强层：FBDeviceControl（详细设备信息）— 可选，failover 到 AVFoundation
//
//  数据流：
//  AVFoundation 发现设备 → FBDeviceControl 补全信息 → IOSDevice 模型 → UI
//

import AVFoundation
import Combine
import FBDeviceControlKit
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

    /// FBDeviceControl 是否可用
    var isFBDeviceControlAvailable: Bool {
        FBDeviceControlService.shared.isAvailable
    }

    // MARK: - 配置

    /// 状态刷新间隔（秒）— 用于检测锁屏/占用状态变化
    private let stateRefreshInterval: TimeInterval = 2.0

    // MARK: - 私有属性

    private var discoverySession: AVCaptureDevice.DiscoverySession?
    private var deviceObservation: NSKeyValueObservation?
    private var stateRefreshTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    /// FBDeviceControl 设备信息缓存 (udid -> FBDeviceInfoDTO)
    private var fbDeviceInfoCache: [String: FBDeviceInfoDTO] = [:]

    // MARK: - 初始化

    override init() {
        super.init()
        setupNotifications()
        setupFBDeviceControl()
    }

    deinit {
        deviceObservation?.invalidate()
        stateRefreshTask?.cancel()
        FBDeviceControlService.shared.stopObserving()
    }

    // MARK: - 公开方法

    /// 开始监控设备
    func startMonitoring() {
        guard !isMonitoring else { return }

        isMonitoring = true
        lastError = nil
        setupDiscoverySession()
        startStateRefresh()
        startFBDeviceControlObserving()
    }

    // MARK: - FBDeviceControl 集成

    /// 设置 FBDeviceControl
    private func setupFBDeviceControl() {
        if FBDeviceControlService.shared.isAvailable {
            AppLogger.device.info("FBDeviceControl 可用，将用于增强设备信息")
        } else {
            let error = FBDeviceControlService.shared.initializationError ?? "未知错误"
            AppLogger.device.warning("FBDeviceControl 不可用: \(error)，使用 AVFoundation fallback")
        }
    }

    /// 开始 FBDeviceControl 观察
    private func startFBDeviceControlObserving() {
        guard FBDeviceControlService.shared.isAvailable else { return }

        FBDeviceControlService.shared.onDevicesChanged = { [weak self] fbDevices in
            Task { @MainActor in
                self?.handleFBDeviceControlUpdate(fbDevices)
            }
        }

        FBDeviceControlService.shared.startObserving()
    }

    /// 处理 FBDeviceControl 设备更新
    private func handleFBDeviceControlUpdate(_ fbDevices: [FBDeviceInfoDTO]) {
        // 更新缓存
        fbDeviceInfoCache.removeAll()
        for dto in fbDevices {
            fbDeviceInfoCache[dto.udid] = dto
        }

        AppLogger.device.debug("FBDeviceControl 更新: \(fbDevices.count) 台设备")

        // 触发设备列表刷新以应用新信息
        refreshDevices()
    }

    /// 使用 FBDeviceControl 信息增强设备
    private func enrichDevice(_ device: IOSDevice) -> IOSDevice {
        // 尝试从缓存获取 FBDeviceControl 信息
        guard let dto = fbDeviceInfoCache[device.id] else {
            // 尝试实时获取
            if let dto = FBDeviceControlService.shared.fetchDeviceInfo(udid: device.id) {
                fbDeviceInfoCache[device.id] = dto
                return device.enriched(with: dto)
            }
            return device
        }

        return device.enriched(with: dto)
    }

    /// 设置设备发现会话
    private func setupDiscoverySession() {
        // 检查相机权限
        let authStatus = AVCaptureDevice.authorizationStatus(for: .video)
        AppLogger.device.info("相机权限状态: \(authStatus.rawValue) (0=未确定, 1=受限, 2=拒绝, 3=已授权)")

        if authStatus == .notDetermined {
            // 请求权限
            AppLogger.device.info("请求相机权限...")
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                AppLogger.device.info("相机权限请求结果: \(granted ? "已授权" : "已拒绝")")
                if granted {
                    Task { @MainActor in
                        self?.refreshDevices()
                    }
                }
            }
        } else if authStatus == .denied || authStatus == .restricted {
            AppLogger.device.error("相机权限被拒绝，无法发现 iOS 设备。请在系统偏好设置中授权。")
            lastError = "相机权限被拒绝"
        }

        // 创建发现会话，监听外部 muxed 设备（USB 屏幕镜像）
        // 注意：USB 屏幕镜像设备使用 .muxed 媒体类型，而不是 .video
        discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.external],
            mediaType: .muxed,
            position: .unspecified
        )

        AppLogger.device.info("已创建 DiscoverySession，当前设备数: \(discoverySession?.devices.count ?? 0)")

        // 监听设备列表变化
        deviceObservation = discoverySession?.observe(\.devices, options: [.new, .initial]) { [weak self] session, _ in
            AppLogger.device.debug("KVO: 设备列表变化，当前设备数: \(session.devices.count)")
            Task { @MainActor in
                self?.refreshDevices()
            }
        }

        // 诊断：列出所有视频捕获设备
        logAllCaptureDevices()

        // 立即刷新一次
        refreshDevices()

        AppLogger.device.info("iOS 设备监控已启动")
    }

    /// 诊断：列出所有视频捕获设备（用于调试）
    private func logAllCaptureDevices() {
        AppLogger.device.info("=== 诊断：捕获设备检测 ===")

        // 1. 检查 video 媒体类型的外部设备
        let videoExternalDevices = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.external],
            mediaType: .video,
            position: .unspecified
        ).devices
        AppLogger.device.info("外部视频设备数: \(videoExternalDevices.count)")

        // 2. 检查 muxed 媒体类型的外部设备（USB 屏幕镜像特征）
        let muxedExternalDevices = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.external],
            mediaType: .muxed,
            position: .unspecified
        ).devices
        AppLogger.device.info("外部 muxed 设备数: \(muxedExternalDevices.count)")

        // 3. 列出所有视频设备（不限类型）
        let allVideoDevices = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .external, .continuityCamera, .deskViewCamera],
            mediaType: .video,
            position: .unspecified
        ).devices

        if allVideoDevices.isEmpty {
            AppLogger.device.info("未发现任何视频捕获设备")
        } else {
            AppLogger.device.info("所有视频设备列表:")
            for device in allVideoDevices {
                let suspended = device.isSuspended ? " [SUSPENDED]" : ""
                let muxed = device.hasMediaType(.muxed) ? " [MUXED]" : ""
                AppLogger.device.info("""
                    - \(device.localizedName)\(suspended)\(muxed)
                      类型: \(device.deviceType.rawValue)
                      型号: \(device.modelID)
                """)
            }
        }

        // 4. 检查 muxed 外部设备中的 iOS 设备
        let iosDevices = muxedExternalDevices.filter {
            $0.modelID.hasPrefix("iPhone") ||
                $0.modelID.hasPrefix("iPad") ||
                $0.modelID == "iOS Device"
        }
        if !iosDevices.isEmpty {
            AppLogger.device.info("发现的 iOS muxed 设备:")
            for device in iosDevices {
                let suspended = device.isSuspended ? " [SUSPENDED]" : ""
                AppLogger.device.info("""
                    - \(device.localizedName)\(suspended) [MUXED]
                      类型: \(device.deviceType.rawValue)
                      型号: \(device.modelID)
                """)
            }
        }

        AppLogger.device.info("=== 诊断结束 ===")
    }

    /// 停止监控
    func stopMonitoring() {
        isMonitoring = false
        deviceObservation?.invalidate()
        deviceObservation = nil
        discoverySession = nil
        stateRefreshTask?.cancel()
        stateRefreshTask = nil

        AppLogger.device.info("iOS 设备监控已停止")
    }

    /// 手动刷新设备列表
    func refreshDevices() {
        guard let session = discoverySession else {
            // 如果没有会话，创建临时查询（使用 muxed 媒体类型）
            let tempSession = AVCaptureDevice.DiscoverySession(
                deviceTypes: [.external],
                mediaType: .muxed,
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
        // 记录原始捕获设备数量（用于调试）
        AppLogger.device.debug("发现 \(captureDevices.count) 个外部视频捕获设备")

        // 步骤 1：从 AVFoundation 创建基础设备列表
        var iosDevices = captureDevices.compactMap { device -> IOSDevice? in
            IOSDevice.from(captureDevice: device)
        }

        // 步骤 2：使用 FBDeviceControl 增强设备信息（如果可用）
        if FBDeviceControlService.shared.isAvailable {
            iosDevices = iosDevices.map { enrichDevice($0) }
        }

        // 检查设备列表或状态是否变化
        let hasDeviceChanges = iosDevices.map(\.id) != devices.map(\.id)
        let hasStateChanges = !hasDeviceChanges && hasDeviceStateChanges(iosDevices)

        if hasDeviceChanges || hasStateChanges {
            devices = iosDevices

            if iosDevices.isEmpty {
                if captureDevices.isEmpty {
                    AppLogger.device.info("未发现任何外部视频设备")
                } else {
                    AppLogger.device.info("发现 \(captureDevices.count) 个外部设备，但没有可用的 iOS 屏幕镜像设备")
                }
            } else {
                for device in iosDevices {
                    // 使用增强的设备信息显示
                    let displayInfo = buildDeviceDisplayInfo(device)
                    if hasDeviceChanges {
                        AppLogger.device.info("iOS 设备已更新: \(displayInfo)")
                    }
                }
            }
        }
    }

    /// 检查设备状态（锁屏、占用等）是否发生变化
    private func hasDeviceStateChanges(_ newDevices: [IOSDevice]) -> Bool {
        for newDevice in newDevices {
            guard let oldDevice = devices.first(where: { $0.id == newDevice.id }) else {
                continue
            }

            // 比较关键状态
            if
                newDevice.isLocked != oldDevice.isLocked ||
                newDevice.isOccupied != oldDevice.isOccupied ||
                newDevice.userPrompt != oldDevice.userPrompt {
                return true
            }
        }
        return false
    }

    /// 构建设备显示信息（用于日志和诊断）
    private func buildDeviceDisplayInfo(_ device: IOSDevice) -> String {
        var info = device.displayName

        if let modelName = device.displayModelName {
            info += " (\(modelName))"
        }

        if let version = device.systemVersion, version != L10n.deviceInfo.unknown {
            info += " iOS \(version)"
        }

        if let prompt = device.userPrompt {
            info += " ⚠️ \(prompt)"
        }

        return info
    }

    /// 获取设备的用户提示信息（用于 UI 显示）
    func getUserPrompt(for deviceID: String) -> String? {
        devices.first { $0.id == deviceID }?.userPrompt
    }

    // MARK: - 状态刷新（轻量级增强）

    /// 启动定期状态刷新
    /// 用于检测设备状态变化（锁屏、占用等），补充 AVFoundation 的连接/断开事件
    private func startStateRefresh() {
        stateRefreshTask?.cancel()
        stateRefreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(self?.stateRefreshInterval ?? 5.0) * 1_000_000_000)

                guard !Task.isCancelled, let self else { break }

                // 只在有设备时刷新状态
                if !devices.isEmpty {
                    await refreshDeviceStates()
                }
            }
        }

        AppLogger.device.debug("设备状态刷新已启动，间隔: \(stateRefreshInterval)s")
    }

    /// 刷新所有设备的状态信息
    /// 检测状态变化（锁屏、占用等）并更新 UI
    private func refreshDeviceStates() async {
        guard let session = discoverySession else { return }

        AppLogger.device.debug("开始刷新设备状态，当前设备数: \(devices.count)")

        var hasChanges = false

        for captureDevice in session.devices {
            guard let existingDevice = devices.first(where: { $0.id == captureDevice.uniqueID }) else {
                continue
            }

            // 使用 IOSDeviceStateMapper 重新检测状态
            let (newState, newIsOccupied, newOccupiedBy) = IOSDeviceStateMapper.detectState(from: captureDevice)
            let newPrompt = IOSDeviceStateMapper.userPrompt(for: newState, occupiedBy: newOccupiedBy)

            // 检测状态变化
            let oldPrompt = existingDevice.userPrompt
            let oldState = existingDevice.state
            let oldIsOccupied = existingDevice.isOccupied

            if newState != oldState || newIsOccupied != oldIsOccupied || newPrompt != oldPrompt {
                hasChanges = true

                // 记录状态变化
                switch (oldState, newState) {
                case (_, .locked) where oldState != .locked:
                    AppLogger.device.warning("🔒 设备已锁屏/息屏: \(existingDevice.displayName)")
                case (.locked, _) where newState != .locked:
                    AppLogger.device.info("🔓 设备已解锁: \(existingDevice.displayName)")
                case (_, .busy) where !oldIsOccupied && newIsOccupied:
                    AppLogger.device.warning("⚠️ 设备被占用: \(existingDevice.displayName)")
                case (.busy, _) where oldIsOccupied && !newIsOccupied:
                    AppLogger.device.info("✅ 设备占用已释放: \(existingDevice.displayName)")
                default:
                    if let prompt = newPrompt, prompt != oldPrompt {
                        AppLogger.device.warning("设备状态变化: \(existingDevice.displayName) - \(prompt)")
                    } else if oldPrompt != nil, newPrompt == nil {
                        AppLogger.device.info("设备状态恢复正常: \(existingDevice.displayName)")
                    }
                }
            }
        }

        // 如果有变化，完整刷新设备列表（会触发 UI 更新）
        if hasChanges {
            AppLogger.device.info("检测到设备状态变化，刷新设备列表")
            refreshDevices()
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
