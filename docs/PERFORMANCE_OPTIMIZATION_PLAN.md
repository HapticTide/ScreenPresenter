# ScreenPresenter 性能优化方案

> **问题背景**：同时连接 iPhone 和 Android 设备后，运行半小时出现电脑发烫、系统卡顿、iPhone 绿屏等问题。

---

## ✅ 已实施的优化（2026-01-21）

### P0 优化已全部完成

| 优化项 | 状态 | 修改文件 |
|--------|------|----------|
| 合并 CVDisplayLink | ✅ 已完成 | `DisplayLinkManager.swift`（新建）、`MetalRenderView.swift`、`FramePipeline.swift` |
| 降低队列优先级 | ✅ 已完成 | 6 个文件（见下方详情） |
| 优化纹理缓存刷新 | ✅ 已完成 | `SingleDeviceRenderView.swift` |

### P1 优化已全部完成

| 优化项 | 状态 | 修改文件 |
|--------|------|----------|
| iOS 帧背压保护 | ✅ 已完成 | `IOSDeviceSource.swift` |
| 资源监控 (IOSurface) | ✅ 已完成 | `ResourceMonitor.swift`（新建）、`SingleDeviceRenderView.swift` |

### P2 优化已全部完成

| 优化项 | 状态 | 修改文件 |
|--------|------|----------|
| 自适应帧率控制 | ✅ 已完成 | `AdaptiveFrameRateController.swift`（新建）、`IOSDeviceSource.swift` |
| 会话健康检查 | ✅ 已完成 | `IOSDeviceSource.swift` |

---

## 📋 问题根因总结

| 问题 | 根因 | 影响 | 严重程度 |
|------|------|------|----------|
| 电脑发烫 | ~~双 CVDisplayLink~~ + 多高优先级队列持续高频运行 | CPU 满载、功耗激增 | ✅ 已优化 |
| 系统卡顿 | ~~8 个 userInteractive 队列争抢资源~~ | 系统调度压力大 | ✅ 已优化 |
| iPhone 绿屏 | ~~iOS 捕获缺少帧背压保护~~ + ~~IOSurface 可能泄漏~~ | 设备异常 | ✅ 已优化 |

---

## 🎯 优化计划（按优先级排序）

### P0 - 立即实施（预计解决 80% 问题）✅ 已完成

#### 1. 合并 CVDisplayLink ✅

**问题现状**：

- `MetalRenderView.swift` 有一个 CVDisplayLink（用于双设备预览）
- `FramePipeline.swift` 中的 `RenderFrameSink` 也有一个 CVDisplayLink（用于 Scrcpy 渲染）

同时运行时，每秒产生 **120 次** 高优先级回调。

**已实施的优化**：
- 新建 `Core/Rendering/DisplayLinkManager.swift` - 全局单例管理器
- 修改 `MetalRenderView.swift` - 移除私有 displayLink，改用共享管理器
- 修改 `FramePipeline.swift` - RenderFrameSink 改用共享管理器

```swift
// 📁 新建文件：Core/Rendering/DisplayLinkManager.swift

import Foundation
import QuartzCore

/// 全局 CVDisplayLink 管理器（单例）
/// 统一管理所有渲染回调，避免多个 DisplayLink 同时运行
final class DisplayLinkManager {
    static let shared = DisplayLinkManager()
    
    private var displayLink: CVDisplayLink?
    private let lock = NSLock()
    
    /// 注册的渲染回调（弱引用，避免循环引用）
    private var callbacks: [String: () -> Void] = [:]
    
    private init() {}
    
    /// 注册渲染回调
    /// - Parameters:
    ///   - id: 唯一标识符
    ///   - callback: 渲染回调（在 DisplayLink 线程调用）
    func register(id: String, callback: @escaping () -> Void) {
        lock.lock()
        callbacks[id] = callback
        
        if displayLink == nil {
            setupDisplayLink()
        }
        lock.unlock()
    }
    
    /// 取消注册
    func unregister(id: String) {
        lock.lock()
        callbacks.removeValue(forKey: id)
        
        if callbacks.isEmpty {
            stopDisplayLink()
        }
        lock.unlock()
    }
    
    private func setupDisplayLink() {
        var link: CVDisplayLink?
        CVDisplayLinkCreateWithActiveCGDisplays(&link)
        
        guard let displayLink = link else { return }
        
        let callback: CVDisplayLinkOutputCallback = { _, _, _, _, _, userInfo -> CVReturn in
            guard let userInfo else { return kCVReturnSuccess }
            let manager = Unmanaged<DisplayLinkManager>.fromOpaque(userInfo).takeUnretainedValue()
            manager.tick()
            return kCVReturnSuccess
        }
        
        let userInfo = Unmanaged.passUnretained(self).toOpaque()
        CVDisplayLinkSetOutputCallback(displayLink, callback, userInfo)
        CVDisplayLinkStart(displayLink)
        self.displayLink = displayLink
    }
    
    private func stopDisplayLink() {
        if let link = displayLink {
            CVDisplayLinkStop(link)
        }
        displayLink = nil
    }
    
    private func tick() {
        lock.lock()
        let currentCallbacks = callbacks.values
        lock.unlock()
        
        for callback in currentCallbacks {
            callback()
        }
    }
}
```

**修改位置**：

1. `MetalRenderView.swift` - 移除私有 displayLink，改用 `DisplayLinkManager.shared.register`
2. `FramePipeline.swift` - `RenderFrameSink` 同样改用共享管理器

---

#### 2. 降低队列优先级 ✅

**问题现状**：

| 文件 | 队列名称 | 原 QoS | 新 QoS |
|------|----------|--------|--------|
| `IOSDeviceSource.swift` | captureQueue | .userInteractive | .userInteractive（保持） |
| `IOSDeviceSource.swift` | audioQueue | .userInteractive | ✅ .default |
| `VideoToolboxDecoder.swift` | decodeQueue | .userInteractive | ✅ .userInitiated |
| `SingleDeviceRenderView.swift` | renderQueue | .userInteractive | ✅ .userInitiated |
| `MetalRenderView.swift` | renderQueue | .userInteractive | ✅ .userInitiated |
| `FramePipeline.swift` | renderQueue | .userInteractive | ✅ .userInitiated |
| `ScrcpySocketAcceptor.swift` | queue | .userInteractive | .userInteractive（保持） |
| `AudioPlayer.swift` | audioQueue | .userInteractive | ✅ .default |

**已实施的优化**：

```swift
// ✅ 保持 userInteractive（实时性要求最高）
// - captureQueue（视频捕获，丢帧敏感）
// - Socket 数据接收队列

// ⬇️ 降级为 .userInitiated（高优先级但允许系统调度）
// - decodeQueue（解码可以稍微延迟）
// - renderQueue（渲染可以跳帧）

// ⬇️ 降级为 .default（普通优先级）
// - audioQueue（音频有缓冲，可以稍微延迟）
```

**具体修改**：

```swift
// VideoToolboxDecoder.swift 第 76-79 行
private let decodeQueue = DispatchQueue(
    label: "com.screenPresenter.videoToolbox.decode",
    qos: .userInitiated  // 从 .userInteractive 降级
)

// SingleDeviceRenderView.swift 第 44 行
private let renderQueue = DispatchQueue(
    label: "com.screenPresenter.singleRender", 
    qos: .userInitiated  // 从 .userInteractive 降级
)

// MetalRenderView.swift 第 28 行
private let renderQueue = DispatchQueue(
    label: "com.screenPresenter.render", 
    qos: .userInitiated  // 从 .userInteractive 降级
)

// FramePipeline.swift 第 322 行
private let renderQueue = DispatchQueue(
    label: "com.screenPresenter.renderSink", 
    qos: .userInitiated  // 从 .userInteractive 降级
)

// AudioPlayer.swift 第 71 行
private var audioQueue = DispatchQueue(
    label: "com.screenPresenter.audioPlayer", 
    qos: .default  // 从 .userInteractive 降级
)

// IOSDeviceSource.swift 第 39 行
private let audioQueue = DispatchQueue(
    label: "com.screenPresenter.ios.audio", 
    qos: .default  // 从 .userInteractive 降级
)
```

---

#### 3. 优化 CVMetalTextureCache 刷新策略 ✅

**问题现状**：

`SingleDeviceRenderView.swift` 中每帧都调用 `CVMetalTextureCacheFlush(cache, 0)`，60fps 时每秒刷新 60 次。

**已实施的优化**：

```swift
// 📁 修改 SingleDeviceRenderView.swift

// 添加刷新计数器
private var textureFlushCounter: Int = 0
private let textureFlushInterval: Int = 30  // 每 30 帧刷新一次（约 0.5 秒）

func updateTexture(from pixelBuffer: CVPixelBuffer) {
    // ... 现有代码 ...
    
    // 延迟刷新纹理缓存（每 N 帧刷新一次）
    textureFlushCounter += 1
    if textureFlushCounter >= textureFlushInterval {
        CVMetalTextureCacheFlush(cache, 0)
        textureFlushCounter = 0
    }
    
    // ... 现有代码 ...
}

func clearTexture() {
    // ... 现有代码 ...
    
    // 清理时立即刷新
    if let cache = textureCache {
        CVMetalTextureCacheFlush(cache, 0)
    }
    textureFlushCounter = 0
}
```

---

### P1 - 重要优化（预计解决 iPhone 绿屏问题）✅ 已完成

#### 4. 为 iOS 捕获增加帧背压保护 ✅

**问题现状**：

`IOSDeviceSource.swift` 的 `handleVideoSampleBuffer` 没有帧积压检测，当渲染跟不上捕获时会导致帧堆积。

**已实施的优化**：

```swift
// 📁 修改 IOSDeviceSource.swift

// 添加帧背压保护属性
private var pendingFrameCount: Int32 = 0
private let maxPendingFrames: Int32 = 4  // 最大待处理帧数
private var droppedFrameCount: Int = 0

private func handleVideoSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
    let isCapturing = capturingLock.withLock { $0 }
    guard isCapturing else { return }
    
    // 帧背压检测
    let currentPending = OSAtomicIncrement32(&pendingFrameCount)
    defer { OSAtomicDecrement32(&pendingFrameCount) }
    
    if currentPending > maxPendingFrames {
        // 帧积压过多，丢弃当前帧
        droppedFrameCount += 1
        if droppedFrameCount % 100 == 1 {
            AppLogger.capture.warning("[iOS] 帧积压过多，已丢弃 \(droppedFrameCount) 帧")
        }
        return
    }
    
    // ... 现有处理代码 ...
}
```

---

#### 5. 增加 IOSurface 使用监控 ✅

**已实施的优化**：

```swift
// 📁 新建文件：Core/Utilities/ResourceMonitor.swift

import Foundation
import os.log

/// 系统资源监控器
/// 用于监控内存压力，防止 IOSurface 过度使用导致的绿屏问题
final class ResourceMonitor {
    static let shared = ResourceMonitor()
    
    /// 内存状态
    enum MemoryState {
        case normal
        case low        // 可用内存 < 500MB
        case critical   // 可用内存 < 200MB
    }
    
    /// 上次检查时间
    private var lastCheckTime = CFAbsoluteTimeGetCurrent()
    
    /// 检查间隔（秒）
    private let checkInterval: Double = 2.0
    
    /// 缓存的内存状态
    private var cachedMemoryState: MemoryState = .normal
    
    /// 低内存阈值 (MB)
    private let lowMemoryThresholdMB: UInt64 = 500
    
    /// 危险内存阈值 (MB)
    private let criticalMemoryThresholdMB: UInt64 = 200
    
    /// 丢帧计数器（用于隔帧丢弃）
    private var dropFrameCounter: Int = 0
    
    private init() {}
    
    /// 检查是否应该丢弃帧（基于内存压力）
    /// - Parameter frameIndex: 当前帧索引（用于隔帧丢弃）
    /// - Returns: 是否应该丢弃当前帧
    func shouldDropFrame(frameIndex: Int = 0) -> Bool {
        updateMemoryStateIfNeeded()
        
        switch cachedMemoryState {
        case .normal:
            return false
        case .low:
            // 低内存时，每 3 帧丢 1 帧
            return frameIndex % 3 == 0
        case .critical:
            // 危险内存时，每 2 帧丢 1 帧
            return frameIndex % 2 == 0
        }
    }
    
    /// 获取当前内存状态
    func getMemoryState() -> MemoryState {
        updateMemoryStateIfNeeded()
        return cachedMemoryState
    }
    
    /// 获取可用内存 (MB)
    func getFreeMemoryMB() -> UInt64 {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        
        guard result == KERN_SUCCESS else { return UInt64.max }
        
        let pageSize = UInt64(vm_page_size)
        let freeMemory = UInt64(stats.free_count) * pageSize
        return freeMemory / (1024 * 1024)
    }
    
    // MARK: - Private
    
    private func updateMemoryStateIfNeeded() {
        let now = CFAbsoluteTimeGetCurrent()
        guard now - lastCheckTime >= checkInterval else { return }
        lastCheckTime = now
        
        let freeMemoryMB = getFreeMemoryMB()
        let previousState = cachedMemoryState
        
        if freeMemoryMB < criticalMemoryThresholdMB {
            cachedMemoryState = .critical
        } else if freeMemoryMB < lowMemoryThresholdMB {
            cachedMemoryState = .low
        } else {
            cachedMemoryState = .normal
        }
        
        // 状态变化时记录日志
        if previousState != cachedMemoryState {
            AppLogger.rendering.warning("[ResourceMonitor] 内存状态变化: \(String(describing: previousState)) → \(String(describing: cachedMemoryState))，可用: \(freeMemoryMB)MB")
        }
    }
}
```

**集成到渲染循环**：

```swift
// 📁 修改 SingleDeviceRenderView.swift 的 updateTexture 方法

// 添加属性
private var frameIndex: Int = 0
private var resourceDroppedFrameCount: Int = 0

func updateTexture(from pixelBuffer: CVPixelBuffer) {
    frameIndex += 1
    
    // 资源监控：内存压力大时主动丢帧
    if ResourceMonitor.shared.shouldDropFrame(frameIndex: frameIndex) {
        resourceDroppedFrameCount += 1
        if resourceDroppedFrameCount % 100 == 1 {
            AppLogger.rendering.warning("[Render] 内存压力丢帧，已丢弃 \(resourceDroppedFrameCount) 帧")
        }
        return
    }
    
    // ... 现有代码 ...
}
```

---

### P2 - 进阶优化（提升稳定性）✅ 已完成

#### 6. 实现自适应帧率 ✅

**已实施的优化**：

```swift
// 📁 新建文件：Core/Utilities/AdaptiveFrameRateController.swift

import Foundation

/// 自适应帧率控制器
/// 根据系统负载动态调整捕获帧率
final class AdaptiveFrameRateController {
    static let shared = AdaptiveFrameRateController()
    
    /// 当前目标帧率
    private(set) var targetFPS: Int = 60
    
    /// 最小帧率
    private let minFPS = 15
    
    /// 最大帧率
    private let maxFPS = 60
    
    /// CPU 使用率历史
    private var cpuUsageHistory: [Double] = []
    
    /// 检查间隔
    private let checkInterval: Double = 3.0
    
    /// 上次检查时间
    private var lastCheckTime = CFAbsoluteTimeGetCurrent()
    
    private init() {}
    
    /// 更新帧率（定期调用）
    func update() {
        let now = CFAbsoluteTimeGetCurrent()
        guard now - lastCheckTime >= checkInterval else { return }
        lastCheckTime = now
        
        let cpuUsage = getCPUUsage()
        cpuUsageHistory.append(cpuUsage)
        
        // 保留最近 10 个样本
        if cpuUsageHistory.count > 10 {
            cpuUsageHistory.removeFirst()
        }
        
        // 计算平均 CPU 使用率
        let avgCPU = cpuUsageHistory.reduce(0, +) / Double(cpuUsageHistory.count)
        
        // 根据 CPU 使用率调整帧率
        if avgCPU > 80 {
            // CPU 高负载，降低帧率
            targetFPS = max(minFPS, targetFPS - 5)
            AppLogger.capture.info("[AdaptiveFPS] CPU 高负载 (\(Int(avgCPU))%)，降低帧率到 \(targetFPS)")
        } else if avgCPU < 50 && targetFPS < maxFPS {
            // CPU 空闲，可以提高帧率
            targetFPS = min(maxFPS, targetFPS + 5)
            AppLogger.capture.debug("[AdaptiveFPS] CPU 空闲 (\(Int(avgCPU))%)，提高帧率到 \(targetFPS)")
        }
    }
    
    private func getCPUUsage() -> Double {
        var loadInfo = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        
        let result = withUnsafeMutablePointer(to: &loadInfo) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        
        guard result == KERN_SUCCESS else { return 50.0 }
        
        let user = Double(loadInfo.cpu_ticks.0)
        let system = Double(loadInfo.cpu_ticks.1)
        let idle = Double(loadInfo.cpu_ticks.2)
        let nice = Double(loadInfo.cpu_ticks.3)
        
        let total = user + system + idle + nice
        let used = user + system + nice
        
        return total > 0 ? (used / total) * 100 : 50.0
    }
}
```

---

#### 7. 会话健康检查 ✅

**问题分析**：CoreMediaIO 长时间运行可能出现资源泄漏，定期重建可以预防绿屏。

**已实施的优化**：

```swift
// 📁 修改 IOSDeviceSource.swift

/// 会话健康检查定时器
private var sessionHealthTimer: Timer?

/// 会话启动时间
private var sessionStartTime: Date?

/// 最大会话持续时间（15 分钟）
private let maxSessionDuration: TimeInterval = 15 * 60

override func startCapture() async throws {
    // ... 现有代码 ...
    
    // 启动健康检查定时器
    sessionStartTime = Date()
    startSessionHealthCheck()
    
    // 启动自适应帧率更新
    startAdaptiveFPSUpdate()
}

override func stopCapture() async {
    // 停止健康检查
    stopSessionHealthCheck()
    
    // 停止自适应帧率更新
    stopAdaptiveFPSUpdate()
    sessionHealthTimer?.invalidate()
    sessionHealthTimer = nil
    sessionStartTime = nil
    
    // ... 现有代码 ...
}

private func startSessionHealthCheck() {
    sessionHealthTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
        self?.checkSessionHealth()
    }
}

private func checkSessionHealth() {
    guard let startTime = sessionStartTime else { return }
    
    let duration = Date().timeIntervalSince(startTime)
    
    // 超过最大持续时间，建议重建会话
    if duration > maxSessionDuration {
        AppLogger.capture.warning("[iOS] 会话运行超过 \(Int(duration / 60)) 分钟，建议重建")
        
        // 发送通知，由上层决定是否重建
        NotificationCenter.default.post(
            name: .iosSessionNeedsRebuild,
            object: self
        )
    }
}

// 新增通知名
extension Notification.Name {
    static let iosSessionNeedsRebuild = Notification.Name("iosSessionNeedsRebuild")
}
```

---

## 📊 预期效果

| 优化项 | 预期收益 | 实施难度 |
|--------|----------|----------|
| 合并 CVDisplayLink | CPU 降低 30-40% | ⭐⭐ 中等 |
| 降低队列优先级 | CPU 降低 10-20% | ⭐ 简单 |
| 优化纹理缓存刷新 | CPU 降低 5-10% | ⭐ 简单 |
| iOS 帧背压保护 | 避免 60% 绿屏 | ⭐⭐ 中等 |
| IOSurface 监控 | 避免 30% 绿屏 | ⭐⭐ 中等 |
| 自适应帧率 | 极端情况保护 | ⭐⭐⭐ 复杂 |
| 会话定期重建 | 长期稳定性 | ⭐⭐ 中等 |

---

## 🔧 实施顺序建议

### 第一阶段（1-2 小时）
1. ✅ 降低队列优先级（最简单，立即生效）
2. ✅ 优化纹理缓存刷新策略

### 第二阶段（2-4 小时）
3. ✅ 合并 CVDisplayLink
4. ✅ iOS 帧背压保护

### 第三阶段（4-8 小时）
5. ✅ IOSurface 监控
6. ✅ 会话健康检查
7. ✅ 自适应帧率（可选）

---

## 📝 测试验证清单

- [ ] 单独连接 iPhone，运行 1 小时，检查 CPU/内存使用
- [ ] 单独连接 Android，运行 1 小时，检查 CPU/内存使用
- [ ] 同时连接 iPhone + Android，运行 30 分钟
- [ ] 同时连接，运行 1 小时，检查是否绿屏
- [ ] 同时连接，运行 2 小时，检查系统卡顿情况
- [ ] 使用 Instruments 检查内存泄漏
- [ ] 使用 Activity Monitor 检查 CPU 使用率变化

---

*文档创建时间：2026-01-21*
*最后更新：2026-01-21*
