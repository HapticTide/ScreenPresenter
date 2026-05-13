//
//  IOSDeviceProvider.swift
//  ScreenPresenter
//
//  Created by Sun on 2025/12/24.
//
//  iOS 设备提供者
//  管理 USB 连接的 iOS 设备发现和状态监控
//
//  架构设计（FBDeviceControl 优先模式）：
//  - 当 FBDeviceControl 可用时：
//    FBDeviceControl 提供设备列表和完整信息（名称、UDID、型号、版本）
//    → 为每个设备查找对应的 AVCaptureDevice（用于视频捕获）
//    → AVFoundation 补充实时状态（锁屏、占用）
//
//  - 当 FBDeviceControl 不可用时（fallback）：
//    AVFoundation 发现设备 → 使用有限的设备信息
//
//  优势：
//  - 设备名称直接来自 FBDeviceControl，准确且无需清理后缀
//  - 型号、版本等信息完整可靠
//  - 匹配逻辑更简单：用准确名称匹配带后缀的 AVFoundation 名称
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

    /// FBDeviceControl 是否可用（委托给 DeviceInsightService）
    var isFBDeviceControlAvailable: Bool {
        DeviceInsightService.shared.isFBDeviceControlAvailable
    }

    // MARK: - 配置

    /// 状态刷新间隔（秒）— 用于检测锁屏/占用状态变化
    private let stateRefreshInterval: TimeInterval = 2.0

    // MARK: - 私有属性

    private var discoverySession: AVCaptureDevice.DiscoverySession?
    private var deviceObservation: NSKeyValueObservation?
    private var stateRefreshTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    private var externalDeviceType: AVCaptureDevice.DeviceType {
        if #available(macOS 14.0, *) {
            return .external
        }
        return .externalUnknown
    }

    private var diagnosticVideoDeviceTypes: [AVCaptureDevice.DeviceType] {
        var deviceTypes: [AVCaptureDevice.DeviceType] = [
            .builtInWideAngleCamera,
            .deskViewCamera,
            externalDeviceType,
        ]

        if #available(macOS 14.0, *) {
            deviceTypes.append(.continuityCamera)
        }

        return deviceTypes
    }

    // MARK: - 初始化

    override init() {
        super.init()
        setupNotifications()

        // 记录 FBDeviceControl 状态（由 DeviceInsightService 管理）
        if isFBDeviceControlAvailable {
            AppLogger.device.info("IOSDeviceProvider 已初始化，FBDeviceControl 增强可用")
        } else {
            AppLogger.device.info("IOSDeviceProvider 已初始化，使用 AVFoundation fallback 模式")
        }
    }

    deinit {
        deviceObservation?.invalidate()
        stateRefreshTask?.cancel()
    }

    // MARK: - 公开方法

    /// 开始监控设备
    func startMonitoring() {
        guard !isMonitoring else { return }

        isMonitoring = true
        lastError = nil
        setupDiscoverySession()
        startStateRefresh()
        setupFBDeviceControlObserver()
    }

    /// 设置 FBDeviceControl 设备变化观察
    /// 当 FBDeviceControl 检测到设备变化时，触发设备列表刷新
    private func setupFBDeviceControlObserver() {
        guard isFBDeviceControlAvailable else { return }

        FBDeviceControlService.shared.onDevicesChanged = { [weak self] _ in
            Task { @MainActor in
                AppLogger.device.info("FBDeviceControl 检测到设备变化，刷新设备列表")
                self?.refreshDevices()
            }
        }
        FBDeviceControlService.shared.startObserving()
        AppLogger.device.info("已启动 FBDeviceControl 设备变化观察")
    }

    /// 设置设备发现会话
    private func setupDiscoverySession() {
        // 检查相机权限
        let authStatus = AVCaptureDevice.authorizationStatus(for: .video)

        if authStatus == .notDetermined {
            // 请求权限
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                if granted {
                    Task { @MainActor in
                        self?.refreshDevices()
                    }
                }
            }
        } else if authStatus == .denied || authStatus == .restricted {
            AppLogger.device.warning("相机权限被拒绝，无法发现 iOS 设备。请在系统偏好设置中授权。")
            lastError = "相机权限被拒绝"
        }

        // 创建发现会话，监听外部 muxed 设备（USB 屏幕镜像）
        // 注意：USB 屏幕镜像设备使用 .muxed 媒体类型，而不是 .video
        discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [externalDeviceType],
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
            deviceTypes: [externalDeviceType],
            mediaType: .video,
            position: .unspecified
        ).devices
        AppLogger.device.info("外部视频设备数: \(videoExternalDevices.count)")

        // 2. 检查 muxed 媒体类型的外部设备（USB 屏幕镜像特征）
        let muxedExternalDevices = AVCaptureDevice.DiscoverySession(
            deviceTypes: [externalDeviceType],
            mediaType: .muxed,
            position: .unspecified
        ).devices
        AppLogger.device.info("外部 muxed 设备数: \(muxedExternalDevices.count)")

        // 3. 列出所有视频设备（不限类型）
        let allVideoDevices = AVCaptureDevice.DiscoverySession(
            deviceTypes: diagnosticVideoDeviceTypes,
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

        // 停止 FBDeviceControl 观察
        if isFBDeviceControlAvailable {
            FBDeviceControlService.shared.stopObserving()
            FBDeviceControlService.shared.onDevicesChanged = nil
        }

        AppLogger.device.info("iOS 设备监控已停止")
    }

    /// 手动刷新设备列表
    func refreshDevices() {
        guard let session = discoverySession else {
            // 如果没有会话，创建临时查询（使用 muxed 媒体类型）
            let tempSession = AVCaptureDevice.DiscoverySession(
                deviceTypes: [externalDeviceType],
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

    /// 更新单个设备的信息（不刷新设备列表）
    /// - Parameter device: 更新后的设备信息
    func updateDevice(_ device: IOSDevice) {
        // 使用 avUniqueID 匹配设备，保持一致性
        guard let index = devices.firstIndex(where: { $0.avUniqueID == device.avUniqueID }) else {
            AppLogger.device.warning("更新设备失败：未找到设备 \(device.displayName) (avUniqueID: \(device.avUniqueID))")
            return
        }
        devices[index] = device
        AppLogger.device.info("设备信息已更新: \(device.displayName)")
    }

    /// 获取 AVCaptureDevice
    /// - Parameter deviceID: 设备 ID（可以是真实 UDID 或 avUniqueID）
    func captureDevice(for deviceID: String) -> AVCaptureDevice? {
        // 先查找设备，获取 avUniqueID
        if let device = devices.first(where: { $0.id == deviceID }) {
            return AVCaptureDevice(uniqueID: device.avUniqueID)
        }
        // fallback: 直接尝试用 deviceID
        return AVCaptureDevice(uniqueID: deviceID)
    }

    // MARK: - 私有方法

    private func updateDeviceList(from captureDevices: [AVCaptureDevice]) {
        // 筛选出 iOS 屏幕镜像设备
        let iosCaptureDevices = captureDevices.filter { device in
            guard device.deviceType == externalDeviceType else { return false }
            let modelID = device.modelID
            let isIOSDevice = modelID.hasPrefix("iPhone") ||
                modelID.hasPrefix("iPad") ||
                modelID.hasPrefix("iPod") ||
                modelID == "iOS Device"
            guard isIOSDevice else { return false }
            // 必须支持 muxed 媒体类型（USB 屏幕镜像特征）
            return device.hasMediaType(.muxed)
        }

        // 根据 FBDeviceControl 是否可用选择不同的发现策略
        let iosDevices: [IOSDevice] = if isFBDeviceControlAvailable {
            // FBDeviceControl 优先模式：以 FBDeviceControl 设备列表为主数据源
            buildDeviceListFromFBDeviceControl(captureDevices: iosCaptureDevices)
        } else {
            // Fallback 模式：使用 AVFoundation 发现
            buildDeviceListFromAVFoundation(captureDevices: iosCaptureDevices)
        }

        // 检查设备列表或状态是否变化
        let hasDeviceChanges = iosDevices.map(\.id) != devices.map(\.id)
        let hasStateChanges = hasDeviceStateChanges(iosDevices)

        if hasDeviceChanges || hasStateChanges {
            // 记录变化详情
            if hasDeviceChanges {
                let oldIds = devices.map(\.id)
                let newIds = iosDevices.map(\.id)
                AppLogger.device.info("设备列表变化: \(oldIds) -> \(newIds)")
            }
            if hasStateChanges {
                for newDevice in iosDevices {
                    if let oldDevice = devices.first(where: { $0.id == newDevice.id }) {
                        if newDevice.state != oldDevice.state {
                            AppLogger.device
                                .info("设备状态变化: \(newDevice.displayName) \(oldDevice.state) -> \(newDevice.state)")
                        }
                        if newDevice.isOccupied != oldDevice.isOccupied {
                            AppLogger.device
                                .info(
                                    "设备占用变化: \(newDevice.displayName) \(oldDevice.isOccupied) -> \(newDevice.isOccupied)"
                                )
                        }
                    }
                }
            }

            // 更新设备列表（触发 @Published）
            devices = iosDevices

            if iosDevices.isEmpty {
                AppLogger.device.info("当前无 iOS 设备连接")
            } else {
                for device in iosDevices {
                    let displayInfo = buildDeviceDisplayInfo(device)
                    AppLogger.device.debug("当前设备: \(displayInfo)")
                }
            }
        }
        // 无变化时不输出日志，减少控制台噪音
    }

    // MARK: - FBDeviceControl 优先模式

    /// 以 FBDeviceControl 设备列表为主数据源构建设备列表
    /// - Parameter captureDevices: AVFoundation 发现的可捕获设备
    /// - Returns: iOS 设备列表
    ///
    /// 优势：
    /// - 设备信息直接来自 FBDeviceControl（准确、完整、无需清理名称后缀）
    /// - 匹配逻辑更可靠（用准确的名称去匹配带后缀的名称）
    private func buildDeviceListFromFBDeviceControl(captureDevices: [AVCaptureDevice]) -> [IOSDevice] {
        let fbDevices = FBDeviceControlService.shared.listDevices()

        guard !fbDevices.isEmpty else {
            return buildDeviceListFromAVFoundation(captureDevices: captureDevices)
        }

        var iosDevices: [IOSDevice] = []

        for dto in fbDevices {
            // 为每个 FBDeviceControl 设备查找对应的 AVCaptureDevice
            let matchedCaptureDevice = findAVCaptureDevice(for: dto, in: captureDevices)

            // 从 FBDeviceControl DTO 创建 IOSDevice
            var device = IOSDevice.from(dto: dto)

            if let captureDevice = matchedCaptureDevice {
                // 关联 AVCaptureDevice，更新 avUniqueID
                device = device.withAVCaptureDevice(captureDevice)

                // 用 AVFoundation 的实时状态更新（锁屏、占用）
                let (avState, isOccupied, occupiedBy) = IOSDeviceStateMapper.detectState(from: captureDevice)
                if captureDevice.isSuspended {
                    device.state = .locked
                } else if isOccupied {
                    device.state = .busy
                } else if device.state == .available, avState != IOSDevice.State.available {
                    // 只有当 FBDeviceControl 认为设备可用时，才用 AVFoundation 状态覆盖
                    device.state = avState
                }
                device.isOccupied = isOccupied
                device.occupiedBy = occupiedBy
            } else {
                // 没有对应的 AVCaptureDevice
                // 这通常意味着设备需要信任或解锁才能被 AVFoundation 发现
                if device.state == .available {
                    // FBDeviceControl 认为设备可用，但 AVFoundation 找不到
                    // 最可能的原因是设备锁屏或未信任
                    device.state = .notTrusted
                }
            }

            iosDevices.append(device)
        }

        return iosDevices
    }

    /// 为 FBDeviceControl 设备查找对应的 AVCaptureDevice
    /// - Parameters:
    ///   - dto: FBDeviceControl 设备信息
    ///   - captureDevices: 可用的 AVCaptureDevice 列表
    /// - Returns: 匹配的 AVCaptureDevice，如果找不到返回 nil
    private func findAVCaptureDevice(
        for dto: FBDeviceInfoDTO,
        in captureDevices: [AVCaptureDevice]
    ) -> AVCaptureDevice? {
        guard !captureDevices.isEmpty else { return nil }

        // 策略 1：单设备自动匹配（最常见场景）
        if captureDevices.count == 1 {
            return captureDevices[0]
        }

        // 策略 2：通过设备名称匹配
        // FBDeviceControl 的 deviceName 是准确的，AVFoundation 的 localizedName 可能带后缀
        let fbDeviceName = dto.deviceName

        // 精确匹配
        if let exactMatch = captureDevices.first(where: { $0.localizedName == fbDeviceName }) {
            return exactMatch
        }

        // 模糊匹配：AVFoundation 名称包含 FBDeviceControl 名称
        // 例如："Sun的相机" 包含 "Sun"
        if let fuzzyMatch = captureDevices.first(where: { $0.localizedName.contains(fbDeviceName) }) {
            return fuzzyMatch
        }

        // 反向模糊匹配：FBDeviceControl 名称包含 AVFoundation 名称的清理版本
        for captureDevice in captureDevices {
            let cleanedAVName = cleanAVFoundationDeviceName(captureDevice.localizedName)
            if fbDeviceName.contains(cleanedAVName) || cleanedAVName.contains(fbDeviceName) {
                return captureDevice
            }
        }
        return nil
    }

    /// 清理 AVFoundation 设备名称（去掉系统添加的后缀）
    private func cleanAVFoundationDeviceName(_ name: String) -> String {
        var cleanName = name

        // 去掉常见后缀
        let suffixes = [
            "的相机", "的桌上视角相机", "的摄像头",
            "'s Camera", "'s Desk View Camera", " Camera",
        ]

        for suffix in suffixes {
            if cleanName.hasSuffix(suffix) {
                cleanName = String(cleanName.dropLast(suffix.count))
                break
            }
        }

        // 去掉首尾引号
        let quotePatterns: [(String, String)] = [
            ("\"", "\""),
            ("\u{201C}", "\u{201D}"),
        ]

        for (openQuote, closeQuote) in quotePatterns {
            if cleanName.hasPrefix(openQuote), cleanName.hasSuffix(closeQuote) {
                cleanName = String(cleanName.dropFirst().dropLast())
                break
            }
        }

        return cleanName.trimmingCharacters(in: .whitespaces)
    }

    // MARK: - AVFoundation Fallback 模式

    /// 使用 AVFoundation 发现设备（FBDeviceControl 不可用时的 fallback）
    private func buildDeviceListFromAVFoundation(captureDevices: [AVCaptureDevice]) -> [IOSDevice] {
        AppLogger.device.debug("AVFoundation fallback 模式")

        return captureDevices.compactMap { captureDevice -> IOSDevice? in
            IOSDevice.from(captureDevice: captureDevice)
        }
    }

    /// 检查设备状态（锁屏、占用、型号等）是否发生变化
    private func hasDeviceStateChanges(_ newDevices: [IOSDevice]) -> Bool {
        for newDevice in newDevices {
            // 使用 id 匹配设备（FBDeviceControl 模式下是真实 UDID，fallback 模式下是 avUniqueID）
            guard let oldDevice = devices.first(where: { $0.id == newDevice.id }) else {
                continue
            }

            // 比较关键状态和型号信息
            // productType 变化会影响 bezel 样式，需要触发 UI 更新
            if
                newDevice.state != oldDevice.state ||
                newDevice.isOccupied != oldDevice.isOccupied ||
                newDevice.userPrompt != oldDevice.userPrompt ||
                newDevice.productType != oldDevice.productType {
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
    /// 在新架构下，直接重新运行设备发现流程
    private func refreshDeviceStates() async {
        // 静默刷新，只在有变化时输出日志
        refreshDevices()
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
                        // 清除断开设备的缓存
                        DeviceInsightService.shared.refresh(udid: device.uniqueID)
                    }
                    self?.refreshDevices()
                }
            }
            .store(in: &cancellables)
    }
}
