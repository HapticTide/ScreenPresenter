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
    case device = "device"           // 已授权，可用
    case unauthorized = "unauthorized" // 未授权（需要在手机上点击允许）
    case offline = "offline"          // 离线
    case noPermissions = "no permissions" // 无权限
    case unknown = "unknown"          // 未知状态
    
    /// 用户友好的状态描述
    var displayName: String {
        switch self {
        case .device:
            return "已连接"
        case .unauthorized:
            return "等待授权"
        case .offline:
            return "离线"
        case .noPermissions:
            return "权限不足"
        case .unknown:
            return "未知状态"
        }
    }
    
    /// 状态颜色
    var statusColor: String {
        switch self {
        case .device:
            return "green"
        case .unauthorized:
            return "orange"
        case .offline, .noPermissions, .unknown:
            return "red"
        }
    }
    
    /// 下一步操作提示
    var actionHint: String? {
        switch self {
        case .device:
            return nil
        case .unauthorized:
            return "请在手机上点击「允许 USB 调试」"
        case .offline:
            return "请重新插拔数据线"
        case .noPermissions:
            return "请检查 adb 权限设置"
        case .unknown:
            return "请重新连接设备"
        }
    }
}

// MARK: - Android 设备

struct AndroidDevice: Identifiable, Equatable, Hashable {
    /// 设备序列号（唯一标识）
    let serial: String
    
    /// 设备状态
    var state: AndroidDeviceState
    
    /// 设备型号
    var model: String?
    
    /// 设备名称
    var device: String?
    
    /// 产品名称
    var product: String?
    
    /// 传输 ID
    var transportId: String?
    
    /// 连接类型
    var connectionType: ConnectionType = .usb
    
    var id: String { serial }
    
    /// 显示名称
    var displayName: String {
        if let model = model {
            return model.replacingOccurrences(of: "_", with: " ")
        }
        return serial
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
