//
//  AdaptiveFrameRateController.swift
//  ScreenPresenter
//
//  Created by Sun on 2026/1/21.
//
//  自适应帧率控制器
//  仅在极端高负载时自动降低帧率，保护系统稳定性
//
//  设计原则：
//  1. 正常情况下不介入，保持稳定的 60fps
//  2. 仅当 CPU 持续超过 95% 约 20 秒时才降低帧率
//  3. CPU 低于 60% 时快速恢复
//  4. 最低只降到 30fps，保证基本体验
//

import Foundation
import os.log

// MARK: - 自适应帧率控制器

/// 自适应帧率控制器
/// 仅在极端高负载时自动降低帧率，保护系统稳定性
///
/// - 默认启用，但仅在 CPU 持续超过 95% 约 20 秒时才降帧
/// - 最低降到 30fps，保证基本使用体验
/// - CPU 低于 60% 时快速恢复到 60fps
final class AdaptiveFrameRateController {
    // MARK: - 单例

    static let shared = AdaptiveFrameRateController()

    // MARK: - 常量

    /// 最小帧率（极端情况下的保底值）
    private let minFPS: Int = 30

    /// 最大帧率（正常运行的目标值）
    private let maxFPS: Int = 60

    /// 检查间隔（秒）
    private let checkInterval: Double = 5.0

    /// CPU 极端高负载阈值（仅超过此值才考虑降帧）
    private let extremeHighLoadThreshold: Double = 95.0

    /// CPU 恢复阈值（低于此值恢复帧率）
    private let recoveryThreshold: Double = 60.0

    /// 连续高负载触发次数（5秒 × 4次 = 20秒）
    private let highLoadTriggerCount: Int = 4

    /// 连续恢复触发次数（5秒 × 2次 = 10秒）
    private let recoveryTriggerCount: Int = 2

    // MARK: - 状态

    /// 是否启用自适应帧率（默认启用）
    private(set) var isEnabled: Bool = true

    /// 当前目标帧率
    private(set) var targetFPS: Int = 60

    /// 是否处于降帧模式
    private(set) var isInLowFPSMode: Bool = false

    /// 上次检查时间
    private var lastCheckTime: CFAbsoluteTime = 0

    /// 上次 CPU 统计数据（用于计算增量）
    private var lastCPUTicks: (user: UInt64, system: UInt64, idle: UInt64, nice: UInt64)?

    /// 连续高负载检测次数
    private var consecutiveHighLoadCount: Int = 0

    /// 连续恢复检测次数
    private var consecutiveRecoveryCount: Int = 0

    /// 线程锁
    private let lock = NSLock()

    /// 帧率变化回调
    var onFPSChanged: ((Int) -> Void)?

    // MARK: - 初始化

    private init() {
        targetFPS = maxFPS
    }

    // MARK: - 禁用（一般不需要调用）

    /// 禁用自适应帧率
    func disable() {
        lock.lock()
        isEnabled = false
        targetFPS = maxFPS
        isInLowFPSMode = false
        consecutiveHighLoadCount = 0
        consecutiveRecoveryCount = 0
        lock.unlock()
    }

    // MARK: - 公开方法

    /// 更新帧率（定期调用）
    /// 仅在极端高负载时降低帧率
    func update() {
        guard isEnabled else { return }

        let now = CFAbsoluteTimeGetCurrent()
        guard now - lastCheckTime >= checkInterval else { return }

        lock.lock()
        defer { lock.unlock() }

        lastCheckTime = now

        // 获取 CPU 使用率
        let cpuUsage = getCPUUsage()
        let previousFPS = targetFPS

        if isInLowFPSMode {
            // 当前处于降帧模式，检查是否可以恢复
            if cpuUsage < recoveryThreshold {
                consecutiveRecoveryCount += 1
                consecutiveHighLoadCount = 0

                if consecutiveRecoveryCount >= recoveryTriggerCount {
                    // 恢复正常帧率
                    targetFPS = maxFPS
                    isInLowFPSMode = false
                    consecutiveRecoveryCount = 0
                    AppLogger.capture.info("[AdaptiveFPS] CPU 恢复正常 (\(Int(cpuUsage))%)，恢复帧率到 \(targetFPS)fps")
                }
            } else {
                // 仍然高负载，重置恢复计数
                consecutiveRecoveryCount = 0
            }
        } else {
            // 当前处于正常模式，检查是否需要降帧
            if cpuUsage > extremeHighLoadThreshold {
                consecutiveHighLoadCount += 1
                consecutiveRecoveryCount = 0

                if consecutiveHighLoadCount >= highLoadTriggerCount {
                    // 极端高负载，降低帧率
                    targetFPS = minFPS
                    isInLowFPSMode = true
                    consecutiveHighLoadCount = 0
                    AppLogger.capture.warning("[AdaptiveFPS] ⚠️ CPU 极端高负载 (\(Int(cpuUsage))%)，降低帧率到 \(targetFPS)fps")
                }
            } else {
                // CPU 正常，重置计数
                consecutiveHighLoadCount = 0
            }
        }

        // 帧率变化时触发回调
        if previousFPS != targetFPS {
            onFPSChanged?(targetFPS)
        }
    }

    /// 重置为默认帧率
    func reset() {
        lock.lock()
        targetFPS = maxFPS
        isInLowFPSMode = false
        consecutiveHighLoadCount = 0
        consecutiveRecoveryCount = 0
        lastCPUTicks = nil
        lock.unlock()
    }

    /// 获取当前状态描述
    var statusDescription: String {
        if isInLowFPSMode {
            return "降帧保护模式: \(targetFPS)fps"
        } else {
            return "正常: \(targetFPS)fps"
        }
    }

    // MARK: - 私有方法

    /// 获取 CPU 使用率（0-100）
    /// 使用增量计算，更准确反映当前负载
    private func getCPUUsage() -> Double {
        var loadInfo = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)

        let result = withUnsafeMutablePointer(to: &loadInfo) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }

        guard result == KERN_SUCCESS else {
            return 50.0 // 获取失败时返回中间值
        }

        let currentUser = UInt64(loadInfo.cpu_ticks.0)
        let currentSystem = UInt64(loadInfo.cpu_ticks.1)
        let currentIdle = UInt64(loadInfo.cpu_ticks.2)
        let currentNice = UInt64(loadInfo.cpu_ticks.3)

        // 首次调用，记录基准值并返回中间值
        guard let last = lastCPUTicks else {
            lastCPUTicks = (currentUser, currentSystem, currentIdle, currentNice)
            return 50.0
        }

        // 计算增量
        let deltaUser = currentUser - last.user
        let deltaSystem = currentSystem - last.system
        let deltaIdle = currentIdle - last.idle
        let deltaNice = currentNice - last.nice

        let deltaTotal = deltaUser + deltaSystem + deltaIdle + deltaNice
        let deltaUsed = deltaUser + deltaSystem + deltaNice

        // 更新基准值
        lastCPUTicks = (currentUser, currentSystem, currentIdle, currentNice)

        guard deltaTotal > 0 else { return 50.0 }

        return (Double(deltaUsed) / Double(deltaTotal)) * 100.0
    }
}

// MARK: - 扩展：诊断信息

extension AdaptiveFrameRateController {
    /// 获取诊断信息
    var diagnosticInfo: String {
        return """
        [AdaptiveFrameRateController 诊断]
        - 启用状态: \(isEnabled ? "是" : "否")
        - 当前模式: \(isInLowFPSMode ? "降帧保护" : "正常")
        - 当前目标帧率: \(targetFPS) fps
        - 帧率范围: \(minFPS) - \(maxFPS) fps
        - 极端高负载阈值: \(extremeHighLoadThreshold)%
        - 恢复阈值: \(recoveryThreshold)%
        - 连续高负载次数: \(consecutiveHighLoadCount)/\(highLoadTriggerCount)
        - 连续恢复次数: \(consecutiveRecoveryCount)/\(recoveryTriggerCount)
        """
    }
}
