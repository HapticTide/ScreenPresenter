//
//  IOSDeviceStateMapper.swift
//  ScreenPresenter
//
//  Created by Sun on 2025/12/24.
//
//  iOS 设备状态映射器
//  将 AVFoundation 检测结果映射为 IOSDevice.State
//  并提供用户友好的提示文案
//

import AppKit
import AVFoundation
import FBDeviceControlKit
import Foundation

// MARK: - iOS 设备状态映射器

/// iOS 设备状态映射器
/// 负责将底层状态信息映射为统一的 IOSDevice.State
enum IOSDeviceStateMapper {
    // MARK: - 状态检测

    /// 从 AVCaptureDevice 检测设备状态
    /// - Parameter captureDevice: AVCaptureDevice 实例
    /// - Returns: (状态, 是否被占用, 占用者)
    static func detectState(from captureDevice: AVCaptureDevice) -> (
        state: IOSDevice.State,
        isOccupied: Bool,
        occupiedBy: String?
    ) {
        // 检测占用状态
        let isOccupied = captureDevice.isInUseByAnotherApplication
        let occupiedBy: String? = isOccupied ? detectOccupyingApp() : nil

        // 检测设备是否被暂停（可能表示锁屏）
        // 注意：isSuspended 在捕获前通常为 false，锁屏检测需要 AVCaptureSession 中断通知
        let isSuspended = captureDevice.isSuspended

        // 根据检测结果映射状态
        if isSuspended {
            return (.locked, isOccupied, occupiedBy)
        }

        if isOccupied {
            return (.busy, true, occupiedBy)
        }

        // 默认为可用状态
        return (.available, false, nil)
    }

    /// 从错误信息映射状态
    /// - Parameters:
    ///   - errorDomain: 错误域
    ///   - errorCode: 错误码
    ///   - errorDescription: 错误描述
    /// - Returns: 映射后的状态
    static func mapFromError(
        domain: String?,
        code: Int?,
        description: String?
    ) -> IOSDevice.State {
        // FBDeviceControl 自定义错误码映射
        if domain == "FBDeviceControl" {
            switch code {
            case -1001: // 设备未激活
                return .notTrusted
            case -1002: // 设备未配对/未信任
                return .notPaired
            case -1003: // 开发者模式未开启
                return .developerModeOff
            default:
                break
            }
        }

        // AVFoundation 错误映射
        if domain == AVFoundationErrorDomain {
            switch code {
            case AVError.applicationIsNotAuthorized.rawValue:
                return .notTrusted
            case -11818: // AVErrorSessionWasInterrupted (iOS only, use raw value)
                return .busy
            case -11800: // AVErrorUnknown - 可能表示设备不可用
                return .unavailable(reason: "设备不可用", underlying: nil)
            default:
                break
            }
        }

        // CoreMediaIO 错误映射
        if domain == "com.apple.CoreMediaIO" {
            switch code {
            case -67818: // kCMIODevicePermissionsError
                return .notTrusted
            case -67819: // kCMIODeviceNotReadyError
                return .locked
            case -67820: // kCMIODeviceInUseError
                return .busy
            default:
                break
            }
        }

        // 字符串匹配映射
        if let desc = description?.lowercased() {
            if desc.contains("not paired") || desc.contains("not trusted") {
                return .notPaired
            }
            if desc.contains("trust") || desc.contains("pair") {
                return .notTrusted
            }
            if desc.contains("lock") || desc.contains("suspend") || desc.contains("screen off") {
                return .locked
            }
            if desc.contains("developer") || desc.contains("devmode") {
                return .developerModeOff
            }
            if desc.contains("busy") || desc.contains("in use") || desc.contains("occupied") {
                return .busy
            }
            if desc.contains("activationstate") {
                return .notTrusted
            }
        }

        // 无法识别的错误
        return .unavailable(
            reason: description ?? L10n.common.unknown,
            underlying: domain.map { "[\($0):\(code ?? 0)]" }
        )
    }

    /// 从 FBDeviceControl 的 FBiOSTargetState 映射状态
    /// - Parameter rawState: FBiOSTargetState 的原始值
    /// - Returns: 映射后的 IOSDevice.State
    ///
    /// FBiOSTargetState 枚举值（来自 FBControlCore/Management/FBiOSTargetConstants.h）:
    /// - 0: Creating
    /// - 1: Shutdown
    /// - 2: Booting
    /// - 3: Booted (可用)
    /// - 4: ShuttingDown
    /// - 5: DFU
    /// - 6: Recovery
    /// - 7: RestoreOS
    /// - 99: Unknown
    static func mapFromFBDeviceState(_ rawState: Int) -> IOSDevice.State {
        let fbState = FBDeviceStateDTO.targetState(from: rawState)

        switch fbState {
        case .booted:
            // 设备已启动，可用
            return .available
        case .booting:
            // 设备正在启动，繁忙状态
            return .busy
        case .shutdown, .shuttingDown:
            // 设备关机/正在关机
            return .unavailable(reason: "设备已关机", underlying: nil)
        case .dfu:
            // DFU 模式
            return .unavailable(reason: "设备处于 DFU 模式", underlying: nil)
        case .recovery:
            // 恢复模式
            return .unavailable(reason: "设备处于恢复模式", underlying: nil)
        case .restoreOS:
            // 正在恢复系统
            return .busy
        case .creating:
            // 正在创建（主要用于模拟器）
            return .busy
        case .unknown:
            // 未知状态
            return .unavailable(reason: "未知设备状态", underlying: "rawState=\(rawState)")
        }
    }

    // MARK: - 用户提示

    /// 获取状态对应的用户提示文案
    /// - Parameters:
    ///   - state: 设备状态
    ///   - occupiedBy: 占用的应用名称（可选）
    /// - Returns: 用户提示文案（如果需要提示）
    static func userPrompt(for state: IOSDevice.State, occupiedBy: String? = nil) -> String? {
        switch state {
        case .available:
            nil
        case .notTrusted:
            L10n.ios.hint.trust
        case .notPaired:
            L10n.ios.hint.trust // 未配对使用相同提示
        case .locked:
            L10n.ios.hint.locked
        case .developerModeOff:
            "请在 iPhone 设置中开启开发者模式（Developer Mode）"
        case .busy:
            if let app = occupiedBy {
                L10n.ios.hint.occupied(app)
            } else {
                L10n.ios.hint.occupiedUnknown
            }
        case let .unavailable(reason, _):
            reason
        }
    }

    /// 获取状态图标名称
    /// - Parameter state: 设备状态
    /// - Returns: SF Symbol 名称
    static func statusIcon(for state: IOSDevice.State) -> String {
        switch state {
        case .available:
            "checkmark.circle.fill"
        case .notTrusted, .notPaired:
            "exclamationmark.shield.fill"
        case .locked:
            "lock.fill"
        case .developerModeOff:
            "wrench.and.screwdriver.fill"
        case .busy:
            "hourglass"
        case .unavailable:
            "xmark.circle.fill"
        }
    }

    /// 获取状态颜色
    /// - Parameter state: 设备状态
    /// - Returns: NSColor
    static func statusColor(for state: IOSDevice.State) -> NSColor {
        switch state {
        case .available:
            .systemGreen
        case .locked, .busy:
            .systemOrange
        case .notTrusted, .notPaired, .developerModeOff:
            .systemRed
        case .unavailable:
            .systemGray
        }
    }

    // MARK: - 私有方法

    /// 检测可能占用设备的应用
    private static func detectOccupyingApp() -> String? {
        // 常见占用者：QuickTime Player、Xcode、Instruments
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
