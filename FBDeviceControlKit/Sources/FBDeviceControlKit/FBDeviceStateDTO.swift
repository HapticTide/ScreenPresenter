//
//  FBDeviceStateDTO.swift
//  FBDeviceControlKit
//
//  Created by Sun on 2025/12/24.
//
//  FBDeviceControl 设备状态 DTO
//  用于表示设备连接/状态变化事件
//

import Foundation

// MARK: - 设备状态 DTO

/// FBDeviceControl 设备状态传输对象
public struct FBDeviceStateDTO: Sendable {
    /// 设备 UDID
    public let udid: String

    /// 事件类型
    public let eventType: EventType

    /// 时间戳
    public let timestamp: Date

    /// 附加信息
    public let info: FBDeviceInfoDTO?

    // MARK: - 事件类型

    public enum EventType: String, Sendable {
        /// 设备已连接
        case connected
        /// 设备已断开
        case disconnected
        /// 设备状态变化
        case stateChanged
        /// 未知事件
        case unknown
    }

    // MARK: - 初始化

    public init(
        udid: String,
        eventType: EventType,
        timestamp: Date,
        info: FBDeviceInfoDTO?
    ) {
        self.udid = udid
        self.eventType = eventType
        self.timestamp = timestamp
        self.info = info
    }
}

// MARK: - FBiOSTargetState 映射

public extension FBDeviceStateDTO {
    /// FBiOSTargetState 枚举值映射
    /// 对应 FBControlCore/Management/FBiOSTargetConstants.h
    enum FBTargetState: Int, Sendable {
        case creating = 0
        case shutdown = 1
        case booting = 2
        case booted = 3
        case shuttingDown = 4
        case dfu = 5
        case recovery = 6
        case restoreOS = 7
        case unknown = 99

        /// 状态描述
        public var description: String {
            switch self {
            case .creating: "Creating"
            case .shutdown: "Shutdown"
            case .booting: "Booting"
            case .booted: "Booted"
            case .shuttingDown: "ShuttingDown"
            case .dfu: "DFU"
            case .recovery: "Recovery"
            case .restoreOS: "RestoreOS"
            case .unknown: "Unknown"
            }
        }

        /// 是否可用（可以进行操作）
        public var isAvailable: Bool {
            self == .booted
        }

        /// 是否处于恢复/特殊模式
        public var isRecoveryMode: Bool {
            switch self {
            case .dfu, .recovery, .restoreOS:
                true
            default:
                false
            }
        }
    }

    /// 从原始状态值创建 FBTargetState
    static func targetState(from rawValue: Int) -> FBTargetState {
        FBTargetState(rawValue: rawValue) ?? .unknown
    }
}
