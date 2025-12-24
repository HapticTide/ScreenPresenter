//
//  AndroidDevice.swift
//  ScreenPresenter
//
//  Created by Sun on 2025/12/22.
//
//  Android 设备模型
//  定义 Android 设备的数据结构和状态
//

import Foundation

// MARK: - Android 设备状态

enum AndroidDeviceState: String, Equatable {
    case device // 已授权，可用
    case unauthorized // 未授权（需要在手机上点击允许）
    case offline // 离线
    case noPermissions = "no permissions" // 无权限
    case unknown // 未知状态

    /// 用户友好的状态描述
    var displayName: String {
        switch self {
        case .device:
            L10n.android.state.device
        case .unauthorized:
            L10n.android.state.unauthorized
        case .offline:
            L10n.android.state.offline
        case .noPermissions:
            L10n.android.state.noPermissions
        case .unknown:
            L10n.android.state.unknown
        }
    }

    /// 状态颜色
    var statusColor: String {
        switch self {
        case .device:
            "green"
        case .unauthorized:
            "orange"
        case .offline, .noPermissions, .unknown:
            "red"
        }
    }

    /// 下一步操作提示
    var actionHint: String? {
        switch self {
        case .device:
            nil
        case .unauthorized:
            L10n.android.hint.unauthorized
        case .offline:
            L10n.android.hint.offline
        case .noPermissions:
            L10n.android.hint.noPermissions
        case .unknown:
            L10n.android.hint.unknown
        }
    }
}

// MARK: - Android 设备

struct AndroidDevice: Identifiable, Equatable, Hashable {
    /// 设备序列号（唯一标识）
    let serial: String

    /// 设备状态
    var state: AndroidDeviceState

    /// 设备型号（ro.product.model，如 M2007J17C）
    var model: String?

    /// 设备名称（device 字段）
    var device: String?

    /// 产品名称
    var product: String?

    /// 传输 ID
    var transportId: String?

    /// 连接类型
    var connectionType: ConnectionType = .usb

    // MARK: - 详细信息（通过 getprop 获取）

    /// 品牌（ro.product.brand，如 Xiaomi）
    var brand: String?

    /// 市场名称（ro.product.marketname，如 Redmi Note 9 Pro）
    var marketName: String?

    /// Android 版本（ro.build.version.release，如 12）
    var androidVersion: String?

    /// SDK 版本（ro.build.version.sdk，如 31）
    var sdkVersion: String?

    var id: String { serial }

    /// 显示名称（优先使用市场名称）
    var displayName: String {
        // 优先使用市场名称
        if let marketName, !marketName.isEmpty {
            return marketName
        }
        // 其次使用品牌+型号组合
        if let brand, let model {
            let formattedModel = model.replacingOccurrences(of: "_", with: " ")
            return "\(brand) \(formattedModel)"
        }
        // 最后使用型号
        if let model {
            return model.replacingOccurrences(of: "_", with: " ")
        }
        return serial
    }

    /// 型号显示名称（用于副标题）
    var displayModelName: String? {
        model?.replacingOccurrences(of: "_", with: " ")
    }

    /// 系统版本显示（如 Android 12）
    var displaySystemVersion: String? {
        guard let androidVersion else { return nil }
        return "Android \(androidVersion)"
    }

    /// 连接类型
    enum ConnectionType: String {
        case usb = "USB"
        case wifi = "Wi-Fi"
    }
}

// MARK: - 解析扩展

extension AndroidDevice {
    /// 从 adb devices -l 输出解析设备
    /// 示例输出: "R5CT419NJXY device usb:1-1 product:p3s model:SM_G998B device:p3s transport_id:1"
    static func parse(from line: String) -> AndroidDevice? {
        let line = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty, !line.hasPrefix("List of devices") else { return nil }

        let components = line.split(separator: " ", omittingEmptySubsequences: true)
        guard components.count >= 2 else { return nil }

        let serial = String(components[0])
        let stateString = String(components[1])
        let state = AndroidDeviceState(rawValue: stateString) ?? .unknown

        var device = AndroidDevice(serial: serial, state: state)

        // 解析额外属性
        for component in components.dropFirst(2) {
            let keyValue = component.split(separator: ":", maxSplits: 1)
            guard keyValue.count == 2 else { continue }

            let key = String(keyValue[0])
            let value = String(keyValue[1])

            switch key {
            case "model":
                device.model = value
            case "device":
                device.device = value
            case "product":
                device.product = value
            case "transport_id":
                device.transportId = value
            case "usb":
                device.connectionType = .usb
            default:
                break
            }
        }

        // 如果 serial 包含 : 通常是 Wi-Fi 连接
        if serial.contains(":") {
            device.connectionType = .wifi
        }

        return device
    }
}
