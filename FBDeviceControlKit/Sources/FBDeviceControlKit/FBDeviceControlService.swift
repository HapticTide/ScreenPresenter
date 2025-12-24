//
//  FBDeviceControlService.swift
//  FBDeviceControlKit
//
//  Created by Sun on 2025/12/24.
//
//  FBDeviceControl Swift 封装服务
//  提供类型安全的 Swift API，隔离 ObjC 桥接层
//

import CFBDeviceControl
import Foundation
import os.log

// MARK: - FBDeviceControl 服务

/// FBDeviceControl Swift 封装
/// 提供类型安全的设备信息获取 API
public final class FBDeviceControlService: @unchecked Sendable {
    // MARK: - 单例

    public static let shared = FBDeviceControlService()

    // MARK: - 日志

    private let logger = Logger(
        subsystem: "com.fbdevicecontrolkit",
        category: "FBDeviceControlService"
    )

    // MARK: - 状态

    /// FBDeviceControl 是否可用
    public var isAvailable: Bool {
        FBDeviceControlBridge.shared.isAvailable
    }

    /// 初始化错误信息
    public var initializationError: String? {
        FBDeviceControlBridge.shared.initializationError
    }

    // MARK: - 设备变化回调

    /// 设备变化回调
    public var onDevicesChanged: (([FBDeviceInfoDTO]) -> Void)?

    // MARK: - 私有属性

    private var isObserving = false

    // MARK: - 初始化

    private init() {
        if isAvailable {
            logger.info("FBDeviceControlService initialized, FBDeviceControl is available")
        } else {
            logger.warning("FBDeviceControlService: FBDeviceControl not available - \(self.initializationError ?? "Unknown error")")
        }
    }

    // MARK: - 公开方法

    /// 获取当前所有设备列表
    /// - Returns: 设备信息 DTO 数组
    public func listDevices() -> [FBDeviceInfoDTO] {
        guard isAvailable else {
            return []
        }

        let dictionaries = FBDeviceControlBridge.shared.listDevices()
        return dictionaries.compactMap { parseDeviceInfo($0) }
    }

    /// 获取指定设备的详细信息
    /// - Parameter udid: 设备 UDID
    /// - Returns: 设备信息 DTO，如果设备不存在返回 nil
    public func fetchDeviceInfo(udid: String) -> FBDeviceInfoDTO? {
        guard isAvailable else {
            return nil
        }

        guard let dictionary = FBDeviceControlBridge.shared.fetchDeviceInfo(udid) else {
            return nil
        }

        return parseDeviceInfo(dictionary)
    }

    /// 开始观察设备变化
    public func startObserving() {
        guard isAvailable, !isObserving else {
            return
        }

        isObserving = true
        FBDeviceControlBridge.shared.startObserving { [weak self] dictionaries in
            guard let self else { return }
            let devices = dictionaries.compactMap { self.parseDeviceInfo($0) }

            logger.debug("FBDeviceControl device change: \(devices.count) device(s)")
            onDevicesChanged?(devices)
        }

        logger.info("FBDeviceControlService: Started observing device changes")
    }

    /// 停止观察设备变化
    public func stopObserving() {
        guard isObserving else {
            return
        }

        isObserving = false
        FBDeviceControlBridge.shared.stopObserving()
        logger.info("FBDeviceControlService: Stopped observing device changes")
    }

    /// 手动刷新设备列表
    /// - Returns: 刷新后的设备信息 DTO 数组
    public func refresh() -> [FBDeviceInfoDTO] {
        guard isAvailable else {
            return []
        }

        let dictionaries = FBDeviceControlBridge.shared.refresh()
        return dictionaries.compactMap { parseDeviceInfo($0) }
    }

    // MARK: - 私有方法

    /// 解析设备信息字典为 DTO
    private func parseDeviceInfo(_ dictionary: [AnyHashable: Any]) -> FBDeviceInfoDTO? {
        guard let udid = dictionary[kFBDeviceInfoUDID] as? String, !udid.isEmpty else {
            return nil
        }

        let deviceName = dictionary[kFBDeviceInfoDeviceName] as? String ?? "iOS Device"
        let productVersion = dictionary[kFBDeviceInfoProductVersion] as? String
        let productType = dictionary[kFBDeviceInfoProductType] as? String
        let buildVersion = dictionary[kFBDeviceInfoBuildVersion] as? String
        let serialNumber = dictionary[kFBDeviceInfoSerialNumber] as? String
        let modelNumber = dictionary[kFBDeviceInfoModelNumber] as? String
        let hardwareModel = dictionary[kFBDeviceInfoHardwareModel] as? String
        let architecture = dictionary[kFBDeviceInfoArchitecture] as? String
        let rawState = dictionary[kFBDeviceInfoRawState] as? Int ?? -1
        let rawErrorDomain = dictionary[kFBDeviceInfoRawErrorDomain] as? String
        let rawErrorCode = dictionary[kFBDeviceInfoRawErrorCode] as? Int
        let rawStatusHint = dictionary[kFBDeviceInfoRawStatusHint] as? String

        let connectionTypeString = dictionary[kFBDeviceInfoConnectionType] as? String ?? "USB"
        let connectionType: FBDeviceInfoDTO.ConnectionType = switch connectionTypeString.uppercased() {
        case "USB":
            .usb
        case "WIFI":
            .wifi
        default:
            .unknown
        }

        return FBDeviceInfoDTO(
            udid: udid,
            deviceName: deviceName,
            productVersion: productVersion,
            productType: productType,
            buildVersion: buildVersion,
            serialNumber: serialNumber,
            modelNumber: modelNumber,
            hardwareModel: hardwareModel,
            connectionType: connectionType,
            architecture: architecture,
            rawState: rawState,
            rawErrorDomain: rawErrorDomain,
            rawErrorCode: rawErrorCode,
            rawStatusHint: rawStatusHint
        )
    }
}

