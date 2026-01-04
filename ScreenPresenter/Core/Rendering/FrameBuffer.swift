//
//  FrameBuffer.swift
//  ScreenPresenter
//
//  Created by Sun on 2026/1/4.
//
//  帧缓冲器
//  基于 scrcpy frame_buffer.c 的设计，实现线程安全的双帧缓冲
//  支持"最新帧优先"策略，适合实时投屏场景
//

import CoreVideo
import Foundation

// MARK: - 帧缓冲器

/// 线程安全的帧缓冲器
/// 实现双帧缓冲设计，支持生产者-消费者模式
///
/// 设计原理（与 scrcpy frame_buffer.c 一致）:
/// - pendingFrame: 最新的待显示帧
/// - pendingFrameConsumed: 标记帧是否已被消费
/// - 新帧到来时直接覆盖旧帧，跟踪跳过的帧数
///
/// 线程安全：
/// - push() 由解码线程调用
/// - consume() 由渲染线程调用
/// - 使用 NSLock 保护共享状态
final class FrameBuffer {
    // MARK: - 属性

    /// 待显示的帧
    private var pendingFrame: CVPixelBuffer?

    /// 帧是否已被消费
    private var pendingFrameConsumed = true

    /// 线程锁
    private let lock = NSLock()

    // MARK: - 统计

    /// 被跳过的帧数（新帧覆盖了未消费的旧帧）
    private(set) var skippedFrameCount = 0

    /// 推送的总帧数
    private(set) var pushedFrameCount = 0

    /// 消费的总帧数
    private(set) var consumedFrameCount = 0

    /// 上次统计重置时间
    private var lastStatsResetTime = CFAbsoluteTimeGetCurrent()

    // MARK: - 初始化

    init() {}

    // MARK: - 帧操作

    /// 推送新帧
    /// - Parameters:
    ///   - frame: 新的 CVPixelBuffer
    /// - Returns: 上一帧是否被跳过（未被消费就被覆盖）
    @discardableResult
    func push(_ frame: CVPixelBuffer) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        // 检查上一帧是否被跳过
        let previousSkipped = !pendingFrameConsumed

        if previousSkipped {
            skippedFrameCount += 1
        }

        // 用新帧替换旧帧
        pendingFrame = frame
        pendingFrameConsumed = false
        pushedFrameCount += 1

        return previousSkipped
    }

    /// 消费当前帧
    /// - Returns: 当前待显示的帧，如果没有新帧则返回 nil
    func consume() -> CVPixelBuffer? {
        lock.lock()
        defer { lock.unlock() }

        // 如果帧已经被消费过，返回 nil
        guard !pendingFrameConsumed else {
            return nil
        }

        pendingFrameConsumed = true
        consumedFrameCount += 1

        return pendingFrame
    }

    /// 获取当前帧（不改变消费状态）
    /// 用于需要重复访问同一帧的场景
    func peek() -> CVPixelBuffer? {
        lock.lock()
        defer { lock.unlock() }
        return pendingFrame
    }

    /// 检查是否有新帧待消费
    var hasNewFrame: Bool {
        lock.lock()
        defer { lock.unlock() }
        return !pendingFrameConsumed
    }

    /// 重置缓冲器
    func reset() {
        lock.lock()
        defer { lock.unlock() }

        pendingFrame = nil
        pendingFrameConsumed = true
    }

    // MARK: - 统计

    /// 获取并重置统计信息
    /// - Returns: (跳过帧数, 推送帧数, 消费帧数, 时间间隔)
    func getAndResetStats() -> (skipped: Int, pushed: Int, consumed: Int, interval: Double) {
        lock.lock()
        defer { lock.unlock() }

        let now = CFAbsoluteTimeGetCurrent()
        let interval = now - lastStatsResetTime

        let stats = (
            skipped: skippedFrameCount,
            pushed: pushedFrameCount,
            consumed: consumedFrameCount,
            interval: interval
        )

        // 重置统计
        skippedFrameCount = 0
        pushedFrameCount = 0
        consumedFrameCount = 0
        lastStatsResetTime = now

        return stats
    }

    /// 当前跳过率
    var skipRate: Double {
        lock.lock()
        defer { lock.unlock() }

        guard pushedFrameCount > 0 else { return 0 }
        return Double(skippedFrameCount) / Double(pushedFrameCount)
    }
}

// MARK: - 扩展：诊断日志

extension FrameBuffer {
    /// 输出诊断日志
    func logDiagnostics(prefix: String = "[FrameBuffer]") {
        let stats = getAndResetStats()

        guard stats.interval > 0 else { return }

        let pushFPS = Double(stats.pushed) / stats.interval
        let consumeFPS = Double(stats.consumed) / stats.interval
        let skipFPS = Double(stats.skipped) / stats.interval

        AppLogger.capture.info(
            "\(prefix) 推送: \(String(format: "%.1f", pushFPS)) fps, " +
                "消费: \(String(format: "%.1f", consumeFPS)) fps, " +
                "跳过: \(String(format: "%.1f", skipFPS)) fps"
        )
    }
}
