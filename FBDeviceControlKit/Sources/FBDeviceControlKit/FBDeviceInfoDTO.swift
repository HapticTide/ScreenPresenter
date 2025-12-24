//
//  FBDeviceInfoDTO.swift
//  FBDeviceControlKit
//
//  Created by Sun on 2025/12/24.
//
//  FBDeviceControl 设备信息 DTO
//  纯 Swift 结构体，用于隔离 ObjC 类型
//

import Foundation

// MARK: - 设备信息 DTO

/// FBDeviceControl 设备信息传输对象
/// 从 ObjC 桥接层获取，纯 Swift 类型
public struct FBDeviceInfoDTO: Sendable {
    /// 设备 UDID（稳定主键）
    public let udid: String

    /// 用户设置的设备名称（如 "Ada's iPhone"）
    public let deviceName: String

    /// iOS 版本（如 "18.2"）
    public let productVersion: String?

    /// 机型标识（如 "iPhone17,1"）
    public let productType: String?

    /// 系统 build 版本（如 "22C5125e"）
    public let buildVersion: String?

    /// 序列号
    public let serialNumber: String?

    /// 型号编号
    public let modelNumber: String?

    /// 硬件型号
    public let hardwareModel: String?

    /// 连接类型（USB/WiFi）
    public let connectionType: ConnectionType

    /// 设备架构（如 "arm64"）
    public let architecture: String?

    /// 原始状态（来自 FBiOSTargetState）
    public let rawState: Int

    /// 原始错误域（如果有错误）
    public let rawErrorDomain: String?

    /// 原始错误码（如果有错误）
    public let rawErrorCode: Int?

    /// 状态提示（用于调试）
    public let rawStatusHint: String?

    // MARK: - 连接类型

    public enum ConnectionType: String, Sendable {
        case usb = "USB"
        case wifi = "WiFi"
        case unknown = "Unknown"
    }

    // MARK: - 初始化

    public init(
        udid: String,
        deviceName: String,
        productVersion: String?,
        productType: String?,
        buildVersion: String?,
        serialNumber: String?,
        modelNumber: String?,
        hardwareModel: String?,
        connectionType: ConnectionType,
        architecture: String?,
        rawState: Int,
        rawErrorDomain: String?,
        rawErrorCode: Int?,
        rawStatusHint: String?
    ) {
        self.udid = udid
        self.deviceName = deviceName
        self.productVersion = productVersion
        self.productType = productType
        self.buildVersion = buildVersion
        self.serialNumber = serialNumber
        self.modelNumber = modelNumber
        self.hardwareModel = hardwareModel
        self.connectionType = connectionType
        self.architecture = architecture
        self.rawState = rawState
        self.rawErrorDomain = rawErrorDomain
        self.rawErrorCode = rawErrorCode
        self.rawStatusHint = rawStatusHint
    }

    // MARK: - 便捷初始化

    /// 创建降级版本（当 FBDeviceControl 不可用时）
    public static func degraded(
        udid: String,
        deviceName: String = "iOS Device",
        productType: String? = nil,
        reason: String
    ) -> FBDeviceInfoDTO {
        FBDeviceInfoDTO(
            udid: udid,
            deviceName: deviceName,
            productVersion: nil,
            productType: productType,
            buildVersion: nil,
            serialNumber: nil,
            modelNumber: nil,
            hardwareModel: nil,
            connectionType: .usb,
            architecture: nil,
            rawState: -1,
            rawErrorDomain: nil,
            rawErrorCode: nil,
            rawStatusHint: reason
        )
    }
}

// MARK: - 扩展信息键

public extension FBDeviceInfoDTO {
    /// FBDeviceControl extendedInformation 中的常用键
    enum ExtendedInfoKey {
        public static let activationState = "activationState"
        public static let batteryLevel = "batteryLevel"
        public static let buildVersion = "buildVersion"
        public static let cpuArchitecture = "cpuArchitecture"
        public static let deviceClass = "deviceClass"
        public static let deviceColor = "deviceColor"
        public static let deviceEnclosureColor = "deviceEnclosureColor"
        public static let deviceName = "deviceName"
        public static let firmwareVersion = "firmwareVersion"
        public static let hardwareModel = "hardwareModel"
        public static let internationalMobileEquipmentIdentity = "internationalMobileEquipmentIdentity"
        public static let modelNumber = "modelNumber"
        public static let phoneNumber = "phoneNumber"
        public static let productName = "productName"
        public static let productType = "productType"
        public static let productVersion = "productVersion"
        public static let serialNumber = "serialNumber"
        public static let timeZone = "timeZone"
        public static let uniqueChipID = "uniqueChipID"
        public static let wiFiAddress = "wiFiAddress"
    }
}
