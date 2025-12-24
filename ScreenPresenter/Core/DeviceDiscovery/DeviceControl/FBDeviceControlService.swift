//
//  FBDeviceControlService.swift
//  ScreenPresenter
//
//  Created by Sun on 2025/12/24.
//
//  FBDeviceControl Swift 封装服务
//  提供类型安全的 Swift API，隔离 ObjC 桥接层
//
//  注意：此文件是主工程的本地封装，使用 AppLogger 记录日志
//  底层 FBDeviceControl 功能来自 FBDeviceControlKit 包
//

import FBDeviceControlKit
import Foundation

// MARK: - FBDeviceControl 服务

/// FBDeviceControl Swift 封装
/// 提供类型安全的设备信息获取 API
final class FBDeviceControlService {
    // MARK: - 单例

    static let shared = FBDeviceControlService()

    // MARK: - 状态

    /// FBDeviceControl 是否可用
    var isAvailable: Bool {
        FBDeviceControlBridge.shared.isAvailable
    }

    /// 初始化错误信息
    var initializationError: String? {
        FBDeviceControlBridge.shared.initializationError
    }

    // MARK: - 设备变化回调

    /// 设备变化回调
    var onDevicesChanged: (([FBDeviceInfoDTO]) -> Void)?

    // MARK: - 私有属性

    private var isObserving = false

    // MARK: - 初始化

    private init() {
        if isAvailable {
            AppLogger.device.info("FBDeviceControlService 已初始化，FBDeviceControl 可用")
        } else {
            AppLogger.device.warning("FBDeviceControlService: FBDeviceControl 不可用 - \(initializationError ?? "未知错误")")
        }
    }

    // MARK: - 公开方法

    /// 获取当前所有设备列表
    /// - Returns: 设备信息 DTO 数组
    func listDevices() -> [FBDeviceInfoDTO] {
        guard isAvailable else {
            return []
        }

        let dictionaries = FBDeviceControlBridge.shared.listDevices()
        return dictionaries.compactMap { parseDeviceInfo($0) }
    }

    /// 获取指定设备的详细信息
    /// - Parameter udid: 设备 UDID
    /// - Returns: 设备信息 DTO，如果设备不存在返回 nil
    func fetchDeviceInfo(udid: String) -> FBDeviceInfoDTO? {
        guard isAvailable else {
            return nil
        }

        guard let dictionary = FBDeviceControlBridge.shared.fetchDeviceInfo(udid) else {
            return nil
        }

        return parseDeviceInfo(dictionary)
    }

    /// 开始观察设备变化
    func startObserving() {
        guard isAvailable, !isObserving else {
            return
        }

        isObserving = true
        FBDeviceControlBridge.shared.startObserving { [weak self] dictionaries in
            guard let self else { return }
            let devices = dictionaries.compactMap { self.parseDeviceInfo($0) }

            AppLogger.device.debug("FBDeviceControl 设备变化: \(devices.count) 台设备")
            onDevicesChanged?(devices)
        }

        AppLogger.device.info("FBDeviceControlService: 开始观察设备变化")
    }

    /// 停止观察设备变化
    func stopObserving() {
        guard isObserving else {
            return
        }

        isObserving = false
        FBDeviceControlBridge.shared.stopObserving()
        AppLogger.device.info("FBDeviceControlService: 停止观察设备变化")
    }

    /// 手动刷新设备列表
    /// - Returns: 刷新后的设备信息 DTO 数组
    func refresh() -> [FBDeviceInfoDTO] {
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

        let deviceName = dictionary[kFBDeviceInfoDeviceName] as? String ?? "iOS 设备"
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
