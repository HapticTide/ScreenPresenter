//
//  DeviceInsightService.swift
//  ScreenPresenter
//
//  Created by Sun on 2025/12/22.
//
//  设备感知服务
//  统一的设备信息查询入口
//
//  数据源优先级：
//  1. FBDeviceControl（详细设备信息：版本、build 等）
//  2. AVFoundation（基础信息 + 状态检测）
//
//  设计原则：
//  - FBDeviceControl 是增强层，不是核心依赖
//  - 不可用时自动 fallback 到 AVFoundation
//  - 提供设备型号映射、状态检测、缓存机制
//

import AppKit
import FBDeviceControlKit
import AVFoundation
import Foundation

// MARK: - 设备感知服务

/// 设备感知服务
/// 提供 iOS 设备的详细信息查询和缓存
final class DeviceInsightService {
    // MARK: - 单例

    static let shared = DeviceInsightService()

    // MARK: - 状态

    /// FBDeviceControl 是否可用
    var isFBDeviceControlAvailable: Bool {
        FBDeviceControlService.shared.isAvailable
    }

    // MARK: - 缓存

    /// 设备信息缓存 (udid -> DeviceInsight)
    private var insightCache: [String: DeviceInsight] = [:]

    /// 缓存过期时间（秒）
    private let cacheExpiration: TimeInterval = 5.0

    /// 缓存最后更新时间
    private var lastCacheUpdate: Date = .distantPast

    /// 缓存锁
    private let cacheLock = NSLock()

    /// 设备专用串行队列（用于防止同一设备的并发刷新）
    private var deviceQueues: [String: DispatchQueue] = [:]

    /// 设备队列锁
    private let queuesLock = NSLock()

    // MARK: - 初始化

    private init() {
        if isFBDeviceControlAvailable {
            AppLogger.device.info("DeviceInsightService 已初始化（FBDeviceControl 模式）")
        } else {
            AppLogger.device.info("DeviceInsightService 已初始化（AVFoundation fallback 模式）")
        }
    }

    // MARK: - 公开方法

    /// 获取设备详细信息
    /// - Parameter udid: 设备 UDID
    /// - Returns: 设备详细信息
    func getDeviceInsight(for udid: String) -> DeviceInsight {
        // 检查缓存
        cacheLock.lock()
        if
            let cached = insightCache[udid],
            Date().timeIntervalSince(lastCacheUpdate) < cacheExpiration {
            cacheLock.unlock()
            return cached
        }
        cacheLock.unlock()

        // 获取新的 insight
        let insight = fetchDeviceInsight(for: udid)

        // 更新缓存
        cacheLock.lock()
        insightCache[udid] = insight
        lastCacheUpdate = Date()
        cacheLock.unlock()

        return insight
    }

    /// 获取设备详细信息（通过 AVCaptureDevice）
    /// - Parameter captureDevice: AVCaptureDevice 实例
    /// - Returns: 设备详细信息
    func getDeviceInsight(for captureDevice: AVCaptureDevice) -> DeviceInsight {
        let udid = captureDevice.uniqueID

        // 检查缓存
        cacheLock.lock()
        if
            let cached = insightCache[udid],
            Date().timeIntervalSince(lastCacheUpdate) < cacheExpiration {
            cacheLock.unlock()
            return cached
        }
        cacheLock.unlock()

        // 获取新的 insight
        let insight = fetchDeviceInsight(for: captureDevice)

        // 更新缓存
        cacheLock.lock()
        insightCache[udid] = insight
        lastCacheUpdate = Date()
        cacheLock.unlock()

        return insight
    }

    /// 刷新指定设备的信息
    /// - Parameter udid: 设备 UDID
    /// - Returns: 刷新后的设备信息
    ///
    /// 注意：对同一 UDID 的刷新操作会串行化执行，避免并发访问 MobileDevice session
    @discardableResult
    func refresh(udid: String) -> DeviceInsight {
        // 使用设备专用队列串行化刷新操作
        serialQueue(for: udid).sync {
            // 清除缓存
            cacheLock.lock()
            insightCache.removeValue(forKey: udid)
            cacheLock.unlock()

            return fetchDeviceInsight(for: udid)
        }
    }

    /// 获取指定设备的串行队列
    /// - Parameter udid: 设备 UDID
    /// - Returns: 该设备专用的串行队列
    private func serialQueue(for udid: String) -> DispatchQueue {
        queuesLock.lock()
        defer { queuesLock.unlock() }

        if let queue = deviceQueues[udid] {
            return queue
        }

        let queue = DispatchQueue(label: "com.screenpresenter.DeviceInsight.\(udid)")
        deviceQueues[udid] = queue
        return queue
    }

    /// 刷新所有设备信息
    func refreshAll() {
        cacheLock.lock()
        insightCache.removeAll()
        lastCacheUpdate = .distantPast
        cacheLock.unlock()

        AppLogger.device.debug("设备信息缓存已清空")
    }

    /// 检查设备占用状态
    /// - Parameter captureDevice: AVCaptureDevice 实例
    /// - Returns: (是否被占用, 占用者描述)
    func checkDeviceOccupation(captureDevice: AVCaptureDevice) -> (isOccupied: Bool, occupiedBy: String?) {
        if captureDevice.isInUseByAnotherApplication {
            let occupier = detectOccupyingApp()
            return (true, occupier)
        }
        return (false, nil)
    }

    // MARK: - 私有方法

    /// 获取设备详细信息（内部实现）
    private func fetchDeviceInsight(for udid: String) -> DeviceInsight {
        // 优先尝试 FBDeviceControl
        if let dto = FBDeviceControlService.shared.fetchDeviceInfo(udid: udid) {
            return DeviceInsight.from(dto: dto)
        }

        // Fallback: 尝试通过 AVCaptureDevice 获取
        if let captureDevice = AVCaptureDevice(uniqueID: udid) {
            return fetchDeviceInsight(for: captureDevice)
        }

        // 返回降级结果
        return DeviceInsight.degraded(udid: udid, reason: "无法获取设备信息")
    }

    /// 获取设备详细信息（通过 AVCaptureDevice）
    private func fetchDeviceInsight(for captureDevice: AVCaptureDevice) -> DeviceInsight {
        let udid = captureDevice.uniqueID
        let deviceName = captureDevice.localizedName
        let modelID = captureDevice.modelID

        // 检测占用状态
        let isOccupied = captureDevice.isInUseByAnotherApplication
        let occupiedBy: String? = isOccupied ? detectOccupyingApp() : nil

        // 检测锁屏状态
        let isSuspended = captureDevice.isSuspended

        // 优先尝试 FBDeviceControl 补全信息
        if let dto = FBDeviceControlService.shared.fetchDeviceInfo(udid: udid) {
            var insight = DeviceInsight.from(dto: dto)
            // 用 AVFoundation 的实时状态覆盖
            insight.isOccupied = isOccupied
            insight.occupiedBy = occupiedBy
            if isSuspended {
                insight.state = .locked
            }
            return insight
        }

        // Fallback: 使用 AVFoundation 基础信息
        let modelName = Self.modelName(for: modelID)
        let state: IOSDevice.State = if isSuspended {
            .locked
        } else if isOccupied {
            .busy
        } else {
            .available
        }

        return DeviceInsight(
            udid: udid,
            deviceName: deviceName,
            modelIdentifier: modelID,
            modelName: modelName,
            systemVersion: nil, // AVFoundation 无法获取
            buildVersion: nil, // AVFoundation 无法获取
            state: state,
            isOccupied: isOccupied,
            occupiedBy: occupiedBy,
            connectionType: .usb
        )
    }

    /// 检测可能占用设备的应用
    private func detectOccupyingApp() -> String? {
        let occupyingProcesses = ["QuickTime Player", "Xcode", "Instruments"]
        let workspace = NSWorkspace.shared

        for processName in occupyingProcesses {
            if workspace.runningApplications.contains(where: { $0.localizedName == processName }) {
                AppLogger.device.info("检测到可能占用设备的应用: \(processName)")
                return processName
            }
        }

        return L10n.ios.hint.otherApp
    }
}

// MARK: - 设备型号映射

extension DeviceInsightService {
    /// 将型号标识符转换为用户友好的名称
    static func modelName(for identifier: String) -> String {
        let modelMap: [String: String] = [
            // iPhone 17 系列 (2025)
            "iPhone18,1": "iPhone 17",
            "iPhone18,2": "iPhone 17 Plus",
            "iPhone18,3": "iPhone 17 Pro",
            "iPhone18,4": "iPhone 17 Pro Max",

            // iPhone 16 系列 (2024)
            "iPhone17,1": "iPhone 16 Pro",
            "iPhone17,2": "iPhone 16 Pro Max",
            "iPhone17,3": "iPhone 16",
            "iPhone17,4": "iPhone 16 Plus",
            "iPhone17,5": "iPhone 16e",

            // iPhone 15 系列 (2023)
            "iPhone16,1": "iPhone 15 Pro",
            "iPhone16,2": "iPhone 15 Pro Max",
            "iPhone15,4": "iPhone 15",
            "iPhone15,5": "iPhone 15 Plus",

            // iPhone 14 系列 (2022)
            "iPhone15,2": "iPhone 14 Pro",
            "iPhone15,3": "iPhone 14 Pro Max",
            "iPhone14,7": "iPhone 14",
            "iPhone14,8": "iPhone 14 Plus",

            // iPhone 13 系列 (2021)
            "iPhone14,2": "iPhone 13 Pro",
            "iPhone14,3": "iPhone 13 Pro Max",
            "iPhone14,4": "iPhone 13 mini",
            "iPhone14,5": "iPhone 13",

            // iPhone 12 系列 (2020)
            "iPhone13,1": "iPhone 12 mini",
            "iPhone13,2": "iPhone 12",
            "iPhone13,3": "iPhone 12 Pro",
            "iPhone13,4": "iPhone 12 Pro Max",

            // iPhone 11 系列 (2019)
            "iPhone12,1": "iPhone 11",
            "iPhone12,3": "iPhone 11 Pro",
            "iPhone12,5": "iPhone 11 Pro Max",

            // iPhone XS/XR 系列 (2018)
            "iPhone11,2": "iPhone XS",
            "iPhone11,4": "iPhone XS Max",
            "iPhone11,6": "iPhone XS Max",
            "iPhone11,8": "iPhone XR",

            // iPhone X (2017)
            "iPhone10,3": "iPhone X",
            "iPhone10,6": "iPhone X",

            // iPhone 8 系列 (2017)
            "iPhone10,1": "iPhone 8",
            "iPhone10,4": "iPhone 8",
            "iPhone10,2": "iPhone 8 Plus",
            "iPhone10,5": "iPhone 8 Plus",

            // iPhone SE 系列
            "iPhone14,6": "iPhone SE (3rd gen)",
            "iPhone12,8": "iPhone SE (2nd gen)",
            "iPhone8,4": "iPhone SE (1st gen)",

            // iPad Pro 系列
            "iPad16,3": "iPad Pro 11-inch (M4)",
            "iPad16,4": "iPad Pro 11-inch (M4)",
            "iPad16,5": "iPad Pro 13-inch (M4)",
            "iPad16,6": "iPad Pro 13-inch (M4)",
            "iPad14,5": "iPad Pro 12.9-inch (6th gen)",
            "iPad14,6": "iPad Pro 12.9-inch (6th gen)",
            "iPad14,3": "iPad Pro 11-inch (4th gen)",
            "iPad14,4": "iPad Pro 11-inch (4th gen)",

            // iPad Air 系列
            "iPad14,8": "iPad Air 11-inch (M2)",
            "iPad14,9": "iPad Air 11-inch (M2)",
            "iPad14,10": "iPad Air 13-inch (M2)",
            "iPad14,11": "iPad Air 13-inch (M2)",
            "iPad13,16": "iPad Air (5th gen)",
            "iPad13,17": "iPad Air (5th gen)",

            // iPad 系列
            "iPad14,12": "iPad (A16)",
            "iPad13,18": "iPad (10th gen)",
            "iPad13,19": "iPad (10th gen)",
            "iPad12,1": "iPad (9th gen)",
            "iPad12,2": "iPad (9th gen)",

            // iPad mini 系列
            "iPad14,1": "iPad mini (6th gen)",
            "iPad14,2": "iPad mini (6th gen)",
        ]

        return modelMap[identifier] ?? identifier
    }
}

// MARK: - DeviceInsight 结构体

/// 设备详细信息
struct DeviceInsight {
    /// 设备 UDID
    let udid: String

    /// 用户设置的设备名称
    var deviceName: String

    /// 设备型号标识符（如 iPhone16,1）
    let modelIdentifier: String

    /// 设备型号名称（如 iPhone 15 Pro）
    let modelName: String

    /// iOS 版本（如 18.2）
    let systemVersion: String?

    /// 系统 build 版本
    let buildVersion: String?

    /// 设备状态
    var state: IOSDevice.State

    /// 是否被其他应用占用
    var isOccupied: Bool

    /// 占用的应用名称
    var occupiedBy: String?

    /// 连接类型
    let connectionType: ConnectionType

    enum ConnectionType: String {
        case usb = "USB"
        case wifi = "WiFi"
        case unknown
    }

    /// 从 FBDeviceInfoDTO 创建
    static func from(dto: FBDeviceInfoDTO) -> DeviceInsight {
        // 首先检查是否有错误信息，优先使用错误映射
        let state: IOSDevice.State = if let errorDomain = dto.rawErrorDomain, dto.rawErrorCode != nil {
            // 使用错误信息映射状态
            IOSDeviceStateMapper.mapFromError(
                domain: errorDomain,
                code: dto.rawErrorCode,
                description: dto.rawStatusHint
            )
        } else {
            // 使用 FBiOSTargetState 映射
            IOSDeviceStateMapper.mapFromFBDeviceState(dto.rawState)
        }

        let modelName = DeviceInsightService.modelName(for: dto.productType ?? "")

        return DeviceInsight(
            udid: dto.udid,
            deviceName: dto.deviceName,
            modelIdentifier: dto.productType ?? "",
            modelName: modelName,
            systemVersion: dto.productVersion,
            buildVersion: dto.buildVersion,
            state: state,
            isOccupied: false,
            occupiedBy: nil,
            connectionType: dto.connectionType == .wifi ? .wifi : .usb
        )
    }

    /// 降级结果（当无法获取详细信息时）
    static func degraded(udid: String, reason: String) -> DeviceInsight {
        AppLogger.device.warning("设备信息降级: \(reason)")
        return DeviceInsight(
            udid: udid,
            deviceName: "iOS 设备",
            modelIdentifier: "unknown",
            modelName: L10n.deviceInfo.unknownModel,
            systemVersion: nil,
            buildVersion: nil,
            state: .available, // 假设可用，让主流程继续
            isOccupied: false,
            occupiedBy: nil,
            connectionType: .usb
        )
    }

    /// 用户提示信息
    var userPrompt: String? {
        IOSDeviceStateMapper.userPrompt(for: state, occupiedBy: occupiedBy)
    }
}
