//
//  ResourceMonitor.swift
//  ScreenPresenter
//
//  Created by Sun on 2026/1/21.
//
//  资源监控工具
//  监控系统内存压力和资源使用情况
//  在资源紧张时触发丢帧以保护系统稳定性
//

import Foundation
import os.log

// MARK: - 资源监控器

/// 资源监控器
/// 监控系统内存压力，当资源紧张时建议丢帧
/// 主要用于防止 IOSurface 耗尽导致的绿屏问题
///
/// 注意：macOS 积极使用内存作为文件缓存，free_count 通常很低是正常的
/// 需要检测「可用内存」= free + inactive + purgeable，而非仅 free
final class ResourceMonitor {
    // MARK: - 单例

    static let shared = ResourceMonitor()

    // MARK: - 常量

    /// 检查间隔（秒）- 降低检查频率以减少开销
    private let checkInterval: Double = 5.0

    /// 低内存阈值（MB）- 可用内存低于此值时建议丢帧
    /// macOS 会积极缓存，所以阈值设得较低
    private let lowMemoryThresholdMB: UInt64 = 200

    /// 危险内存阈值（MB）- 低于此值强制丢帧
    private let criticalMemoryThresholdMB: UInt64 = 100

    /// 连续触发次数阈值 - 避免单次波动导致误判
    private let consecutiveThreshold: Int = 2

    // MARK: - 状态

    /// 上次检查时间
    private var lastCheckTime: CFAbsoluteTime = 0

    /// 当前内存状态
    private(set) var memoryState: MemoryState = .normal

    /// 连续低内存检测次数
    private var consecutiveLowCount: Int = 0

    /// 线程锁
    private let lock = NSLock()

    // MARK: - 内存状态

    enum MemoryState: CustomStringConvertible {
        case normal      // 正常 - 不丢帧
        case low         // 低内存 - 隔帧丢弃
        case critical    // 危险 - 强制丢帧

        var description: String {
            switch self {
            case .normal: return "正常"
            case .low: return "低内存"
            case .critical: return "危险"
            }
        }
    }

    // MARK: - 初始化

    private init() {
        AppLogger.rendering.info("[ResourceMonitor] 初始化，低内存阈值: \(lowMemoryThresholdMB)MB，危险阈值: \(criticalMemoryThresholdMB)MB")
    }

    // MARK: - 公开方法

    /// 检查是否应该丢帧
    /// 定期检查系统内存状态，在内存紧张时返回 true
    /// - Parameter frameIndex: 当前帧索引（用于按比例丢帧）
    /// - Returns: 是否应该丢弃当前帧
    func shouldDropFrame(frameIndex: Int = 0) -> Bool {
        // 限制检查频率
        let now = CFAbsoluteTimeGetCurrent()
        if now - lastCheckTime < checkInterval {
            // 使用缓存的状态
            return checkDropByState(frameIndex: frameIndex)
        }

        lock.lock()
        defer { lock.unlock() }

        lastCheckTime = now

        // 获取系统可用内存（包括可回收的缓存）
        let availableMemoryMB = getAvailableMemoryMB()

        // 更新内存状态（需要连续触发才生效，避免误判）
        let previousState = memoryState

        if availableMemoryMB < criticalMemoryThresholdMB {
            consecutiveLowCount += 1
            if consecutiveLowCount >= consecutiveThreshold {
                memoryState = .critical
            }
        } else if availableMemoryMB < lowMemoryThresholdMB {
            consecutiveLowCount += 1
            if consecutiveLowCount >= consecutiveThreshold {
                memoryState = .low
            }
        } else {
            // 内存正常，重置计数
            if consecutiveLowCount > 0 {
                consecutiveLowCount = 0
            }
            memoryState = .normal
        }

        // 状态变化时输出日志
        if previousState != memoryState {
            switch memoryState {
            case .critical:
                AppLogger.rendering.error("[ResourceMonitor] ⚠️ 内存危险！可用: \(availableMemoryMB)MB，强制丢帧")
            case .low:
                AppLogger.rendering.warning("[ResourceMonitor] 内存紧张，可用: \(availableMemoryMB)MB，建议降帧")
            case .normal:
                AppLogger.rendering.info("[ResourceMonitor] 内存恢复正常，可用: \(availableMemoryMB)MB")
            }
        }

        return checkDropByState(frameIndex: frameIndex)
    }

    /// 获取当前可用内存（MB）
    /// 包括 free + inactive + purgeable，更准确反映实际可用资源
    func getAvailableMemoryMB() -> UInt64 {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)

        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }

        guard result == KERN_SUCCESS else {
            return UInt64.max // 获取失败时返回最大值，不触发丢帧
        }

        let pageSize = UInt64(vm_page_size)

        // macOS 的「可用内存」应该包括：
        // - free_count: 真正空闲的页面
        // - inactive_count: 非活跃页面（可快速回收）
        // - purgeable_count: 可清除的页面（应用标记为可丢弃的缓存）
        // 不包括 speculative_count，因为它已包含在 free_count 中
        let freePages = UInt64(stats.free_count)
        let inactivePages = UInt64(stats.inactive_count)
        let purgeablePages = UInt64(stats.purgeable_count)

        let availablePages = freePages + inactivePages + purgeablePages
        let availableMemory = availablePages * pageSize
        return availableMemory / (1024 * 1024)
    }

    /// 获取传统 free 内存（仅用于诊断）
    func getFreeMemoryMB() -> UInt64 {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)

        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }

        guard result == KERN_SUCCESS else { return 0 }

        let pageSize = UInt64(vm_page_size)
        return UInt64(stats.free_count) * pageSize / (1024 * 1024)
    }

    /// 强制刷新状态
    func refresh() {
        lock.lock()
        lastCheckTime = 0
        lock.unlock()
        _ = shouldDropFrame()
    }

    /// 重置状态
    func reset() {
        lock.lock()
        memoryState = .normal
        consecutiveLowCount = 0
        lastCheckTime = 0
        lock.unlock()
    }

    // MARK: - 私有方法

    private func checkDropByState(frameIndex: Int) -> Bool {
        switch memoryState {
        case .normal:
            return false
        case .low:
            // 每 3 帧丢 1 帧（保留更多帧率）
            return frameIndex % 3 == 0
        case .critical:
            // 每 2 帧丢 1 帧
            return frameIndex % 2 == 0
        }
    }
}

// MARK: - 扩展：诊断信息

extension ResourceMonitor {
    /// 获取诊断信息
    var diagnosticInfo: String {
        let availableMemory = getAvailableMemoryMB()
        let freeMemory = getFreeMemoryMB()
        return """
        [ResourceMonitor 诊断]
        - 当前状态: \(memoryState)
        - 可用内存 (free+inactive+purgeable): \(availableMemory) MB
        - 纯 free 内存: \(freeMemory) MB
        - 低内存阈值: \(lowMemoryThresholdMB) MB
        - 危险阈值: \(criticalMemoryThresholdMB) MB
        - 连续低内存次数: \(consecutiveLowCount)
        """
    }
}
