//
//  IOSDevice.swift
//  ScreenPresenter
//
//  Created by Sun on 2025/12/24.
//
//  iOS 设备模型
//  表示通过 USB 连接的 iPhone/iPad 设备
//
//  ID 设计：
//  - id: 设备真实 UDID（40位十六进制），用于唯一标识设备
//  - avUniqueID: AVFoundation uniqueID（UUID 格式），用于 AVCaptureDevice 操作
//  - 当 FBDeviceControl 不可用时，id 会 fallback 到 avUniqueID
//

import AVFoundation
import FBDeviceControlKit
import Foundation

// MARK: - iOS 设备

/// iOS 设备信息
struct IOSDevice: Identifiable, Hashable {
    /// 设备唯一 ID
    /// 优先使用 iOS 设备的真实 UDID（40位十六进制，如 "00008020-001234567890002E"）
    /// 当 FBDeviceControl 不可用时，fallback 到 AVFoundation uniqueID
    let id: String

    /// AVFoundation uniqueID（UUID 格式，用于 AVCaptureDevice 操作）
    /// 这是 AVFoundation 系统生成的 ID，与设备真实 UDID 不同
    let avUniqueID: String

    /// 设备名称（如 "iPhone 15 Pro"）
    let name: String

    /// 设备型号标识（如 "iPhone16,1"）
    let modelID: String?

    /// 连接类型
    let connectionType: ConnectionType

    /// 设备位置 ID（用于 USB 识别）
    let locationID: UInt32?

    /// 关联的 AVCaptureDevice
    weak var captureDevice: AVCaptureDevice?

    // MARK: - 设备状态

    /// 设备状态（状态机）
    var state: State = .available

    /// 最后检测时间
    var lastSeenAt: Date = .init()

    // MARK: - 设备信息（从 AVFoundation 获取）

    /// 用户设置的设备名称（来自 AVCaptureDevice.localizedName）
    var deviceName: String?

    /// iOS 版本（如 "18.2"）—— AVFoundation 无法获取，始终为 nil
    var productVersion: String?

    /// 设备型号标识符（如 "iPhone16,1"）
    var productType: String?

    /// 用户友好的型号名称（如 "iPhone 17 Pro"）—— 来自 FBDeviceControl
    var modelName: String?

    /// 系统 build 版本（如 "22C5125e"）—— AVFoundation 无法获取，始终为 nil
    var buildVersion: String?

    /// 是否被其他应用占用
    var isOccupied: Bool = false

    /// 占用的应用名称
    var occupiedBy: String?

    // MARK: - 计算属性

    /// 是否有真实 UDID（id 不等于 avUniqueID 时表示有真实 UDID）
    var hasRealUDID: Bool {
        id != avUniqueID
    }

    /// 显示名称（优先使用设备名，fallback 到 name）
    var displayName: String {
        if let deviceName, !deviceName.isEmpty, deviceName != "iOS 设备" {
            return deviceName
        }
        return name
    }

    /// 详细型号名称（优先使用 FBDeviceControl 提供的 modelName）
    var displayModelName: String? {
        // 优先使用 FBDeviceControl 提供的用户友好名称
        if let modelName, !modelName.isEmpty {
            return modelName
        }
        // Fallback: 返回型号标识符
        return modelID
    }

    /// iOS 版本（AVFoundation 无法获取，返回 nil）
    var systemVersion: String? {
        productVersion
    }

    /// 是否处于锁屏/息屏状态
    var isLocked: Bool {
        state == .locked
    }

    /// 是否可以立即开始捕获
    var isReadyForCapture: Bool {
        state == .available && !isOccupied
    }

    /// 用户提示信息（根据状态自动生成）
    var userPrompt: String? {
        IOSDeviceStateMapper.userPrompt(for: state, occupiedBy: occupiedBy)
    }

    /// 设备外观配置（用于 bezel 绘制）
    /// 基于 productType 精确识别设备型号
    var deviceModel: DeviceModel {
        DeviceModel.from(productType: productType)
    }

    // MARK: - 连接类型枚举

    enum ConnectionType: String {
        case usb = "USB"
        case unknown = "Unknown"

        var icon: String {
            switch self {
            case .usb: "cable.connector"
            case .unknown: "questionmark.circle"
            }
        }
    }

    // MARK: - 设备状态枚举

    /// iOS 设备状态
    enum State: Equatable, CustomStringConvertible {
        /// 可用状态
        case available
        /// 未信任此电脑
        case notTrusted
        /// 未配对
        case notPaired
        /// 设备锁屏/未解锁
        case locked
        /// iOS 16+ Developer Mode 关闭
        case developerModeOff
        /// 会话繁忙/恢复中
        case busy
        /// 不可用（带原因和底层错误）
        case unavailable(reason: String, underlying: String?)

        var description: String {
            switch self {
            case .available: "available"
            case .notTrusted: "notTrusted"
            case .notPaired: "notPaired"
            case .locked: "locked"
            case .developerModeOff: "developerModeOff"
            case .busy: "busy"
            case let .unavailable(reason, _): "unavailable(\(reason))"
            }
        }

        /// 是否为问题状态（需要用户干预）
        var isProblem: Bool {
            switch self {
            case .available: false
            default: true
            }
        }

        /// 状态颜色指示
        var statusColor: String {
            switch self {
            case .available: "systemGreen"
            case .locked, .busy: "systemOrange"
            case .notTrusted, .notPaired, .developerModeOff: "systemRed"
            case .unavailable: "systemGray"
            }
        }

        static func == (lhs: State, rhs: State) -> Bool {
            switch (lhs, rhs) {
            case (.available, .available),
                 (.notTrusted, .notTrusted),
                 (.notPaired, .notPaired),
                 (.locked, .locked),
                 (.developerModeOff, .developerModeOff),
                 (.busy, .busy):
                true
            case let (.unavailable(r1, u1), .unavailable(r2, u2)):
                r1 == r2 && u1 == u2
            default:
                false
            }
        }
    }

    // MARK: - 初始化

    init(
        id: String,
        avUniqueID: String,
        name: String,
        modelID: String? = nil,
        connectionType: ConnectionType = .usb,
        locationID: UInt32? = nil,
        captureDevice: AVCaptureDevice? = nil,
        state: State = .available,
        deviceName: String? = nil,
        productVersion: String? = nil,
        productType: String? = nil,
        modelName: String? = nil,
        buildVersion: String? = nil,
        isOccupied: Bool = false,
        occupiedBy: String? = nil
    ) {
        self.id = id
        self.avUniqueID = avUniqueID
        self.name = name
        self.modelID = modelID
        self.connectionType = connectionType
        self.locationID = locationID
        self.captureDevice = captureDevice
        self.state = state
        self.deviceName = deviceName
        self.productVersion = productVersion
        self.productType = productType ?? modelID
        self.modelName = modelName
        self.buildVersion = buildVersion
        self.isOccupied = isOccupied
        self.occupiedBy = occupiedBy
        lastSeenAt = Date()
    }

    // MARK: - 从 AVCaptureDevice 创建

    /// 从 AVCaptureDevice 创建 IOSDevice
    /// 注意：此时 id 使用 AVFoundation uniqueID，需要后续通过 enriched() 更新为真实 UDID
    static func from(captureDevice: AVCaptureDevice) -> IOSDevice? {
        let deviceType = captureDevice.deviceType
        let externalDeviceType: AVCaptureDevice.DeviceType = if #available(macOS 14.0, *) {
            .external
        } else {
            .externalUnknown
        }
        let rawName = captureDevice.localizedName
        let modelID = captureDevice.modelID

        // 记录发现的设备（用于调试）
        AppLogger.device.debug("检测到捕获设备: \(rawName), 类型: \(deviceType.rawValue), 型号: \(modelID)")

        // 必须是外部设备类型
        guard deviceType == externalDeviceType else {
            AppLogger.device.debug("跳过非外部设备: \(rawName), 类型: \(deviceType.rawValue)")
            return nil
        }

        // 检查是否是 iOS 设备（通过模型ID判断）
        // 注意：muxed 设备的 modelID 可能是 "iOS Device" 而不是具体型号
        let isIOSDevice = modelID.hasPrefix("iPhone") ||
            modelID.hasPrefix("iPad") ||
            modelID.hasPrefix("iPod") ||
            modelID == "iOS Device"

        guard isIOSDevice else {
            AppLogger.device.debug("跳过非 iOS 设备: \(rawName), 型号: \(modelID)")
            return nil
        }

        // 检查是否是 USB 连接的屏幕镜像设备（排除 WiFi 连接的 Continuity Camera）
        // USB 屏幕镜像支持 muxed 媒体类型（音视频复用），WiFi Continuity Camera 只支持纯视频
        guard isScreenMirrorDevice(captureDevice, rawName: rawName) else {
            AppLogger.device.info("跳过 WiFi 连接的设备（Continuity Camera）: \(rawName)")
            return nil
        }

        // 额外验证：尝试获取设备确保它真正可用
        guard AVCaptureDevice(uniqueID: captureDevice.uniqueID) != nil else {
            AppLogger.device.warning("设备验证失败（无法通过 uniqueID 获取设备）: \(rawName)")
            return nil
        }

        // 清理设备名称，去掉系统添加的后缀
        let displayName = cleanDeviceName(rawName)

        // 使用 AVFoundation 检测设备状态
        let (state, isOccupied, occupiedBy) = IOSDeviceStateMapper.detectState(from: captureDevice)

        // 记录设备信息和状态（此时只有 AVFoundation 基础信息，后续 enriched() 会补充 FBDeviceControl 详情）
        var logMessage = "发现 iOS 设备: \(displayName), 型号标识: \(modelID)"
        if state == .locked {
            logMessage += " [锁屏/息屏]"
        }
        if isOccupied {
            logMessage += " [被占用]"
        }
        if state.isProblem {
            logMessage += " [状态: \(state)]"
        }
        AppLogger.device.info("\(logMessage)")

        // 记录用户提示
        if let prompt = IOSDeviceStateMapper.userPrompt(for: state, occupiedBy: occupiedBy) {
            AppLogger.device.warning("设备状态提示: \(prompt)")
        }

        // 创建设备：此时 id 暂时使用 avUniqueID，后续 enriched() 会更新为真实 UDID
        let avUniqueID = captureDevice.uniqueID
        return IOSDevice(
            id: avUniqueID, // 暂时使用 avUniqueID，enriched() 后会更新
            avUniqueID: avUniqueID,
            name: displayName,
            modelID: modelID,
            connectionType: .usb,
            locationID: nil,
            captureDevice: captureDevice,
            state: state,
            deviceName: displayName,
            productVersion: nil, // AVFoundation 无法获取
            productType: modelID,
            buildVersion: nil, // AVFoundation 无法获取
            isOccupied: isOccupied,
            occupiedBy: occupiedBy
        )
    }

    /// 判断是否是 USB 连接的屏幕镜像设备
    /// 用于区分 USB 屏幕镜像和 WiFi Continuity Camera
    ///
    /// 区分方法：
    /// 1. USB 屏幕镜像支持 .muxed 媒体类型（音视频复用）
    /// 2. WiFi Continuity Camera 只支持 .video，且设备名称包含 "相机"/"Camera" 等后缀
    private static func isScreenMirrorDevice(_ device: AVCaptureDevice, rawName: String) -> Bool {
        let hasMuxed = device.hasMediaType(.muxed)

        // 方法 1：检查是否支持 muxed 媒体类型
        // USB 连接的屏幕镜像设备支持 muxed（音视频复用）
        if hasMuxed {
            AppLogger.device.debug("设备支持 muxed 媒体类型，识别为屏幕镜像: \(rawName)")
            return true
        }

        // 方法 2：检查设备名称是否是 Continuity Camera 特征
        // Continuity Camera 的设备名称通常包含 "相机"、"Camera" 等后缀
        let continuityNamePatterns = [
            "的相机",
            "的桌上视角相机",
            "的摄像头",
            "'s Camera",
            "'s Desk View Camera",
            " Camera",
        ]

        for pattern in continuityNamePatterns {
            if rawName.contains(pattern) {
                // 名称包含 Camera 相关后缀，是 Continuity Camera
                AppLogger.device.info("""
                    设备被识别为 Continuity Camera（WiFi 连接）: \(rawName)
                    - 不支持 muxed 媒体类型
                    - 名称包含 '\(pattern)'
                    提示：如需使用 USB 屏幕镜像，请确保：
                    1. 使用 USB 线缆连接 iPhone
                    2. iPhone 已解锁并信任此 Mac
                    3. 关闭 iPhone 的连续互通相机功能（设置 > 通用 > 隔空播放与接力）
                """)
                return false
            }
        }

        // 没有 muxed 支持，但名称也不像 Continuity Camera
        // 保守起见，认为是屏幕镜像设备
        AppLogger.device.debug("设备不支持 muxed，但名称不像 Continuity Camera，尝试作为屏幕镜像: \(rawName)")
        return true
    }

    /// 清理设备名称，去掉系统添加的后缀
    /// 例如: "Nokia"的相机 → Nokia
    ///       "iPhone"的桌上视角相机 → iPhone
    private static func cleanDeviceName(_ name: String) -> String {
        var cleanName = name

        // 去掉常见后缀
        let suffixes = [
            "的相机",
            "的桌上视角相机",
            "的摄像头",
            "'s Camera",
            "'s Desk View Camera",
            " Camera",
        ]

        for suffix in suffixes {
            if cleanName.hasSuffix(suffix) {
                cleanName = String(cleanName.dropLast(suffix.count))
                break
            }
        }

        // 去掉首尾引号（英文和中文引号）
        let quotePatterns: [(String, String)] = [
            ("\"", "\""),
            ("\u{201C}", "\u{201D}"), // 中文引号 " "
        ]

        for (openQuote, closeQuote) in quotePatterns {
            if cleanName.hasPrefix(openQuote), cleanName.hasSuffix(closeQuote) {
                cleanName = String(cleanName.dropFirst().dropLast())
                break
            }
        }

        return cleanName.trimmingCharacters(in: .whitespaces)
    }

    // MARK: - 从 DeviceInsight 增强信息

    /// 使用 DeviceInsight 信息增强设备
    /// - Parameter insight: DeviceInsight 数据（来自 DeviceInsightService）
    /// - Returns: 增强后的 IOSDevice（包含真实 UDID）
    func enriched(with insight: DeviceInsight) -> IOSDevice {
        // 确定设备 ID：优先使用真实 UDID
        let deviceID: String
        if let realUDID = insight.realUDID, !realUDID.isEmpty {
            deviceID = realUDID
            AppLogger.device.debug("设备 ID 已更新为真实 UDID: \(realUDID)")
        } else {
            deviceID = id // 保持原 ID（可能是 avUniqueID）
        }

        // 更新设备名称
        var newDeviceName = deviceName
        if !insight.deviceName.isEmpty, insight.deviceName != "iOS 设备" {
            newDeviceName = insight.deviceName
        }

        // 更新版本信息
        var newProductVersion = productVersion
        if let version = insight.systemVersion {
            newProductVersion = version
        }

        // 更新型号信息（modelID、productType、modelName）
        var newModelID = modelID
        var newProductType = productType
        var newModelName = modelName
        if !insight.modelIdentifier.isEmpty, insight.modelIdentifier != "unknown" {
            newModelID = insight.modelIdentifier
            newProductType = insight.modelIdentifier
        }
        if !insight.modelName.isEmpty {
            newModelName = insight.modelName
        }

        // 更新 build 版本
        var newBuildVersion = buildVersion
        if let build = insight.buildVersion {
            newBuildVersion = build
        }

        return IOSDevice(
            id: deviceID,
            avUniqueID: avUniqueID, // 保持 AVFoundation uniqueID 不变
            name: name,
            modelID: newModelID,
            connectionType: connectionType,
            locationID: locationID,
            captureDevice: captureDevice,
            state: insight.state,
            deviceName: newDeviceName,
            productVersion: newProductVersion,
            productType: newProductType,
            modelName: newModelName,
            buildVersion: newBuildVersion,
            isOccupied: insight.isOccupied,
            occupiedBy: insight.occupiedBy
        )
    }

    /// 使用 FBDeviceControl 信息增强设备
    /// - Parameter dto: FBDeviceInfoDTO 数据
    /// - Returns: 增强后的 IOSDevice（包含真实 UDID）
    func enriched(with dto: FBDeviceInfoDTO) -> IOSDevice {
        // 确定设备 ID：使用 FBDeviceControl 提供的真实 UDID
        let deviceID = dto.udid.isEmpty ? id : dto.udid

        // 更新设备名称
        var newDeviceName = deviceName
        if !dto.deviceName.isEmpty, dto.deviceName != "iOS 设备" {
            newDeviceName = dto.deviceName
        }

        // 更新版本信息
        var newProductVersion = productVersion
        if let version = dto.productVersion {
            newProductVersion = version
        }

        // 更新型号信息（modelID、productType、modelName）
        var newModelID = modelID
        var newProductType = productType
        var newModelName = modelName
        if let type = dto.productType {
            newModelID = type
            newProductType = type
        }
        if let name = dto.modelName {
            newModelName = name
        }

        // 更新 build 版本
        var newBuildVersion = buildVersion
        if let build = dto.buildVersion {
            newBuildVersion = build
        }

        // 状态映射：首先检查是否有错误信息，优先使用错误映射
        let newState: State = if let errorDomain = dto.rawErrorDomain, dto.rawErrorCode != nil {
            IOSDeviceStateMapper.mapFromError(
                domain: errorDomain,
                code: dto.rawErrorCode,
                description: dto.rawStatusHint
            )
        } else {
            IOSDeviceStateMapper.mapFromFBDeviceState(dto.rawState)
        }

        return IOSDevice(
            id: deviceID,
            avUniqueID: avUniqueID, // 保持 AVFoundation uniqueID 不变
            name: name,
            modelID: newModelID,
            connectionType: connectionType,
            locationID: locationID,
            captureDevice: captureDevice,
            state: newState,
            deviceName: newDeviceName,
            productVersion: newProductVersion,
            productType: newProductType,
            modelName: newModelName,
            buildVersion: newBuildVersion,
            isOccupied: isOccupied,
            occupiedBy: occupiedBy
        )
    }

    /// 从 FBDeviceInfoDTO 创建 IOSDevice（当 AVFoundation 不可用时的 fallback）
    /// - Parameter dto: FBDeviceInfoDTO 数据
    /// - Returns: IOSDevice 实例
    static func from(dto: FBDeviceInfoDTO) -> IOSDevice {
        // 状态映射：首先检查是否有错误信息，优先使用错误映射
        let state: IOSDevice.State = if let errorDomain = dto.rawErrorDomain, dto.rawErrorCode != nil {
            IOSDeviceStateMapper.mapFromError(
                domain: errorDomain,
                code: dto.rawErrorCode,
                description: dto.rawStatusHint
            )
        } else {
            IOSDeviceStateMapper.mapFromFBDeviceState(dto.rawState)
        }

        // 注意：从 FBDeviceControl 创建时，没有 AVFoundation uniqueID
        // 使用真实 UDID 作为 avUniqueID 的 fallback
        return IOSDevice(
            id: dto.udid,
            avUniqueID: dto.udid, // 无 AVFoundation，使用真实 UDID
            name: dto.deviceName,
            modelID: dto.productType,
            connectionType: dto.connectionType == .wifi ? .unknown : .usb,
            locationID: nil,
            captureDevice: nil,
            state: state,
            deviceName: dto.deviceName,
            productVersion: dto.productVersion,
            productType: dto.productType,
            modelName: dto.modelName,
            buildVersion: dto.buildVersion,
            isOccupied: false,
            occupiedBy: nil
        )
    }

    /// 关联 AVCaptureDevice（用于 FBDeviceControl 优先模式）
    /// - Parameter captureDevice: AVCaptureDevice 实例
    /// - Returns: 更新了 avUniqueID 和 captureDevice 的新 IOSDevice
    func withAVCaptureDevice(_ captureDevice: AVCaptureDevice) -> IOSDevice {
        IOSDevice(
            id: id, // 保持 FBDeviceControl 的真实 UDID
            avUniqueID: captureDevice.uniqueID, // 使用 AVFoundation uniqueID
            name: name,
            modelID: modelID,
            connectionType: connectionType,
            locationID: locationID,
            captureDevice: captureDevice,
            state: state,
            deviceName: deviceName,
            productVersion: productVersion,
            productType: productType,
            modelName: modelName,
            buildVersion: buildVersion,
            isOccupied: isOccupied,
            occupiedBy: occupiedBy
        )
    }

    // MARK: - AVCaptureDevice 操作

    /// 获取关联的 AVCaptureDevice
    /// 优先使用缓存的 captureDevice，如果不可用则通过 avUniqueID 查找
    func getAVCaptureDevice() -> AVCaptureDevice? {
        if let device = captureDevice {
            return device
        }
        return AVCaptureDevice(uniqueID: avUniqueID)
    }

    // MARK: - Hashable

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: IOSDevice, rhs: IOSDevice) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - DeviceInfo 协议扩展

extension IOSDevice: DeviceInfo {
    var model: String? {
        modelID
    }

    var platform: DevicePlatform {
        .ios
    }
}
