# ScreenPresenter 工程审计报告

> **审计日期**: 2025-12-23  
> **审计版本**: v1.2 (重新审计)  
> **项目状态**: ✅ **合格，可作为演示台交付**  
> **审计标准**: 工程级真实性 / 稳定性 / 合规性

---

## 目录

1. [审计概述](#1-审计概述)
2. [总体架构审计](#2-总体架构审计)
3. [iOS 路线审计](#3-ios-路线审计)
4. [Android 路线审计](#4-android-路线审计)
5. [Metal 渲染审计](#5-metal-渲染审计)
6. [稳定性与长稳审计](#6-稳定性与长稳审计)
7. [日志与可诊断性审计](#7-日志与可诊断性审计)
8. [最终审计结论](#8-最终审计结论)
9. [风险清单与改进计划](#9-风险清单与改进计划)
10. [版本迭代记录](#10-版本迭代记录)

---

## 1. 审计概述

### 1.1 产品定位

**演示台 (ScreenPresenter)** - 用于同时展示 iOS 和 Android 设备屏幕的专业演示工具。

### 1.2 技术架构要求

| 要求 | 目标 | 实现状态 |
|------|------|----------|
| UI 框架 | 纯 AppKit（非 SwiftUI） | ✅ 完全符合 |
| 渲染引擎 | Metal 核心渲染 | ✅ 完全符合 |
| iOS 采集 | CoreMediaIO + AVFoundation | ✅ 完全符合 |
| Android 采集 | scrcpy + VideoToolbox | ✅ 完全符合 |

### 1.3 审计结论速览

```
┌─────────────────────────────────────────────────────────────┐
│  ✅ 合格，可作为演示台交付                                    │
│                                                             │
│  ✅ 核心技术路径正确且完整                                    │
│  ✅ 架构设计合理，无 Demo 级 shortcut                        │
│  ✅ scrcpy/adb 已内置到 App Bundle                          │
│  ✅ 渲染已隔离到专用队列                                      │
│  ✅ iOS 设备占用检测已实现                                    │
│  ⚠️ 缺少长时间稳定性测试数据                                  │
└─────────────────────────────────────────────────────────────┘
```

---

## 2. 总体架构审计

### 2.1 UI 框架一致性

> **是否完整遵循 AppKit 实现 UI？**

| 检查项 | 状态 | 代码位置 | 说明 |
|--------|------|----------|------|
| 使用 AppKit | ✅ **Yes** | `AppDelegate.swift:16` | `@main final class AppDelegate: NSObject, NSApplicationDelegate` |
| 主视图控制器 | ✅ **Yes** | `MainViewController.swift:16` | `final class MainViewController: NSViewController` |
| 渲染视图 | ✅ **Yes** | `MetalRenderView.swift:18` | `final class MetalRenderView: NSView` |
| 无 SwiftUI | ✅ **Yes** | 全项目搜索 | 未发现 SwiftUI / NSHostingView |
| 无 SwiftUI lifecycle | ✅ **Yes** | 全项目搜索 | 使用 AppKit 生命周期 |

**结论**: ✅ **架构一致**

### 2.2 渲染架构

> **渲染主路径是否以 Metal 为核心？**

| 检查项 | 状态 | 代码位置 | 说明 |
|--------|------|----------|------|
| Metal 核心渲染 | ✅ **Yes** | `MetalRenderer.swift:20-26` | MTLDevice, MTLCommandQueue, MTLRenderPipelineState |
| 使用 CAMetalLayer | ✅ **Yes** | `MetalRenderView.swift:57-64` | `makeBackingLayer()` 返回 CAMetalLayer |
| 自定义着色器 | ✅ **Yes** | `MetalRenderer.swift:362-394` | 实现 vertexShader 和 fragmentShader |
| 纹理合成职责 | ✅ **Yes** | `MetalRenderer.swift:193-318` | 多路画面合成、缩放、纵横比保持 |
| 非套壳实现 | ✅ **Yes** | 全文 | 非 AVSampleBufferDisplayLayer 套壳 |

**结论**: ✅ **Metal 是真正的渲染核心**

### 2.3 Demo 级 Shortcut 检查

> **是否存在 Demo 级的偷懒实现？**

| 检查项 | 状态 | 说明 |
|--------|------|------|
| 外部窗口拉起 | ✅ **无** | scrcpy 使用 `--no-display --no-audio --no-control` |
| 临时 sleep/retry loop | ✅ **无** | 仅有合理的设备枚举等待 (500ms) |
| print 代替日志 | ✅ **无** | 使用 AppLogger 基于 os.log |
| 硬编码路径 | ✅ **无** | 工具链路径动态获取 |

**结论**: ✅ **无 Demo 级 shortcut**

---

## 3. iOS 路线审计

### 3.1 技术路径真实性

> **是否使用 QuickTime 同款路径？**

| 检查项 | 状态 | 代码位置 |
|--------|------|----------|
| CoreMediaIO 启用 | ✅ **Yes** | `IOSScreenMirrorActivator.swift:44-70` |
| kCMIOHardwarePropertyAllowScreenCaptureDevices | ✅ **Yes** | `IOSDeviceSource.swift:176-178` |
| AVCaptureDevice.DiscoverySession | ✅ **Yes** | `IOSDeviceProvider.swift:61-65` |
| AVCaptureSession 捕获 | ✅ **Yes** | `IOSDeviceSource.swift:217-261` |
| 实时 CMSampleBuffer | ✅ **Yes** | `IOSDeviceSource.swift:266-281` |
| CVPixelBuffer 提取 | ✅ **Yes** | `IOSDeviceSource.swift:270` |

**技术路径验证**:

```
CoreMediaIO (kCMIOHardwarePropertyAllowScreenCaptureDevices)
    ↓
AVCaptureDevice.DiscoverySession (deviceTypes: [.external])
    ↓
AVCaptureSession + AVCaptureVideoDataOutput
    ↓
CMSampleBuffer → CVPixelBuffer → MTLTexture → Metal 渲染
```

**代码证据**:

```swift
// IOSScreenMirrorActivator.swift:44-70
var prop = CMIOObjectPropertyAddress(
    mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyAllowScreenCaptureDevices),
    mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
    mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
)
var allow: UInt32 = 1
CMIOObjectSetPropertyData(CMIOObjectID(kCMIOObjectSystemObject), &prop, ...)
```

```swift
// IOSDeviceSource.swift:266-281
private func handleVideoSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
    guard isCapturingFlag else { return }
    guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
    _latestPixelBuffer = pixelBuffer
    // ...
}
```

**结论**: ✅ **技术路径正确，是 QuickTime 同款路径**

### 3.2 稳定性与恢复能力

| 场景 | 状态 | 代码位置 | 说明 |
|------|------|----------|------|
| QuickTime 占用检测 | ✅ **已实现** | `IOSDeviceSource.swift:211-215` | `isInUseByAnotherApplication` |
| 设备连接通知 | ✅ **已实现** | `IOSDeviceProvider.swift:139-148` | `.AVCaptureDeviceWasConnected` |
| 设备断开通知 | ✅ **已实现** | `IOSDeviceProvider.swift:150-159` | `.AVCaptureDeviceWasDisconnected` |
| 锁屏→解锁恢复 | ⚠️ **待验证** | - | 有轮询检测，无专门处理 |
| 资源泄漏 | ⚠️ **待验证** | - | 需要长时间测试 |

**设备占用检测代码证据**:

```swift
// IOSDeviceSource.swift:211-215
if captureDevice.isInUseByAnotherApplication {
    AppLogger.capture.warning("设备被其他应用占用: \(captureDevice.localizedName)")
    throw DeviceSourceError.deviceInUse("QuickTime")
}
```

**结论**: ✅ **基本合格，核心功能已实现**

---

## 4. Android 路线审计

### 4.1 scrcpy 集成真实性

> **scrcpy 是否内置在 App Bundle 内？**

| 检查项 | 状态 | 路径 |
|--------|------|------|
| scrcpy 内置 | ✅ **Yes** | `Resources/Tools/scrcpy` |
| scrcpy-server 内置 | ✅ **Yes** | `Resources/Tools/scrcpy-server` |
| adb 内置 | ✅ **Yes** | `Resources/Tools/platform-tools/adb` |
| 原始流模式 | ✅ **Yes** | `--no-display --no-audio --no-control` |
| 路径/版本日志 | ✅ **Yes** | `ToolchainManager.swift` |

**内置工具结构验证**:

```
Resources/Tools/
├── scrcpy              # 内置可执行文件
├── scrcpy-server       # 推送到 Android 设备的服务端
└── platform-tools/
    └── adb             # Android Debug Bridge
```

**工具链优先级代码证据**:

```swift
// ToolchainManager.swift:114-127
var adbPath: String {
    if let bundled = bundledAdbPath, FileManager.default.fileExists(atPath: bundled) {
        return bundled  // 优先使用内嵌版本
    }
    return systemAdbPath ?? "/usr/local/bin/adb"
}

var scrcpyPath: String {
    if let bundled = bundledScrcpyPath, FileManager.default.fileExists(atPath: bundled) {
        return bundled  // 优先使用内嵌版本
    }
    return systemScrcpyPath ?? "/opt/homebrew/bin/scrcpy"
}
```

**结论**: ✅ **scrcpy 已真正内置，非外部工具拉起**

### 4.2 adb 与授权处理

| 检查项 | 状态 | 代码位置 |
|--------|------|----------|
| adb start-server | ✅ **Yes** | `AndroidDeviceProvider.swift:105-116` |
| adb devices -l | ✅ **Yes** | `AndroidDeviceProvider.swift:79-101` |
| unauthorized 提示 | ✅ **Yes** | `AndroidDevice.swift:51-64` |
| offline 提示 | ✅ **Yes** | `AndroidDevice.swift:57` |
| noPermissions 提示 | ✅ **Yes** | `AndroidDevice.swift:59` |

**设备状态处理代码证据**:

```swift
// AndroidDevice.swift:51-64
var actionHint: String? {
    switch self {
    case .device: nil
    case .unauthorized: L10n.android.hint.unauthorized  // "请在手机上点击「允许 USB 调试」"
    case .offline: L10n.android.hint.offline            // "请重新插拔数据线"
    case .noPermissions: L10n.android.hint.noPermissions
    case .unknown: L10n.android.hint.unknown
    }
}
```

**结论**: ✅ **授权状态处理完善**

### 4.3 VideoToolbox 解码路径

> **是否使用 VideoToolbox 硬解？**

| 检查项 | 状态 | 代码位置 |
|--------|------|----------|
| VideoToolbox 硬解 | ✅ **Yes** | `ScrcpyDeviceSource.swift:437-648` |
| VTDecompressionSession | ✅ **Yes** | `ScrcpyDeviceSource.swift:548-584` |
| H.264 支持 | ✅ **Yes** | `ScrcpyDeviceSource.swift:506-513` |
| H.265 支持 | ✅ **Yes** | `ScrcpyDeviceSource.swift:525-534` |
| NAL 单元解析 | ✅ **Yes** | `ScrcpyDeviceSource.swift:650-784` |

**完整解码链路验证**:

```
scrcpy stdout (H.264/H.265 raw stream)
    ↓
NALUnitParser.parse(data:) → [NALUnit]
    ↓
SPS/PPS/VPS 提取 → CMVideoFormatDescriptionCreateFromH264/HEVCParameterSets
    ↓
NAL Units → CMBlockBuffer → CMSampleBuffer
    ↓
VTDecompressionSessionDecodeFrame
    ↓
CVPixelBuffer (kCVPixelFormatType_32BGRA, Metal 兼容)
    ↓
MTLTexture → Metal 渲染
```

**代码证据**:

```swift
// ScrcpyDeviceSource.swift:548-584
private func createDecompressionSession(formatDescription: CMFormatDescription) -> Bool {
    let outputPixelBufferAttributes: [String: Any] = [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        kCVPixelBufferMetalCompatibilityKey as String: true,
    ]
    
    var session: VTDecompressionSession?
    let status = VTDecompressionSessionCreate(
        allocator: kCFAllocatorDefault,
        formatDescription: formatDescription,
        decoderSpecification: nil,
        imageBufferAttributes: outputPixelBufferAttributes as CFDictionary,
        outputCallback: &outputCallback,
        decompressionSessionOut: &session
    )
    // ...
}
```

**结论**: ✅ **VideoToolbox 硬解链路完整，非 "scrcpy 窗口显示正常" 的伪实现**

---

## 5. Metal 渲染审计

### 5.1 渲染职责

| 职责 | 状态 | 代码位置 |
|------|------|----------|
| 多路画面合成 | ✅ **Yes** | `MetalRenderer.swift:176-188` |
| 左右并排渲染 | ✅ **Yes** | `MetalRenderer.swift:193-228` |
| 上下布局渲染 | ✅ **Yes** | `MetalRenderer.swift:231-266` |
| 单视图渲染 | ✅ **Yes** | `MetalRenderer.swift:269-280` |
| 缩放处理 | ✅ **Yes** | `MetalRenderer.swift:283-318` |
| 纵横比保持 | ✅ **Yes** | `MetalRenderer.swift:291-304` |
| CAMetalLayer | ✅ **Yes** | `MetalRenderView.swift:57-64` |
| 无 CPU 图像合成 | ✅ **Yes** | 全文 |

**纵横比保持代码证据**:

```swift
// MetalRenderer.swift:291-304
let textureAspect = CGFloat(texture.width) / CGFloat(texture.height)
let containerAspect = containerSize.width / containerSize.height

var scaleX: Float = 1.0
var scaleY: Float = 1.0

if textureAspect > containerAspect {
    scaleY = Float(containerAspect / textureAspect)
} else {
    scaleX = Float(textureAspect / containerAspect)
}
```

**结论**: ✅ **Metal 是真正的渲染核心，非装饰品**

### 5.2 并发与性能

| 检查项 | 状态 | 代码位置 | 说明 |
|--------|------|----------|------|
| iOS 采集独立队列 | ✅ **Yes** | `IOSDeviceSource.swift:41-42` | `captureQueue`, `audioQueue` |
| 渲染队列隔离 | ✅ **Yes** | `MetalRenderView.swift:28` | 专用 `renderQueue` |
| displayLink 回调隔离 | ✅ **Yes** | `MetalRenderView.swift:201-205` | 在 renderQueue 执行 |
| UI 主线程不参与解码 | ✅ **Yes** | 全文 | 解码在后台任务中 |
| 无锁 UI 等待 | ✅ **Yes** | 全文 | 无同步等待 |
| Android 解码队列 | ✅ **Yes** | `ScrcpyDeviceSource.swift:451-458` | 专用 `decodeQueue` + `decoderLock` |

**渲染队列隔离代码证据**:

```swift
// MetalRenderView.swift:28
private let renderQueue = DispatchQueue(label: "com.screenPresenter.render", qos: .userInteractive)

// MetalRenderView.swift:195-205
private func displayLinkCallback() {
    renderLock.lock()
    defer { renderLock.unlock() }
    guard isRendering else { return }
    
    // 在专用渲染队列执行渲染，避免阻塞主线程
    renderQueue.async { [weak self] in
        self?.renderFrame()
    }
}
```

**结论**: ✅ **并发设计合理，无高风险阻塞点**

---

## 6. 稳定性与长稳审计

### 6.1 测试数据

| 测试项 | 状态 | 说明 |
|--------|------|------|
| iOS + Android 同时运行 ≥30min | ❌ **无数据** | 需要执行 |
| fps 均值/波动 | ❌ **无数据** | 需要监控 |
| 丢帧统计 | ❌ **无数据** | 需要监控 |
| 内存泄漏检测 | ❌ **无数据** | 需要 Instruments |

### 6.2 代码中的稳定性保障

| 保障措施 | 状态 | 代码位置 |
|----------|------|----------|
| 帧率统计 | ✅ **已实现** | `MetalRenderer.swift:396-401` |
| 进程监控 | ✅ **已实现** | `ScrcpyDeviceSource.swift:404-431` |
| 错误状态处理 | ✅ **已实现** | `DeviceSource.swift:56-86` |
| 资源清理 | ✅ **已实现** | 各类 `deinit` 和 `disconnect()` |

**结论**: ⚠️ **代码有保障措施，但缺少实测数据**

---

## 7. 日志与可诊断性审计

### 7.1 日志系统

| 检查项 | 状态 | 代码位置 |
|--------|------|----------|
| 统一日志模块 | ✅ **Yes** | `Logger.swift:33-140` |
| 基于 os.log | ✅ **Yes** | `Logger.swift:61` |
| 10 个分类 | ✅ **Yes** | `Logger.swift:17-28` |
| 日志级别控制 | ✅ **Yes** | `Logger.swift:49` |
| 性能测量工具 | ✅ **Yes** | `Logger.swift:242-258` |

**日志分类**:

```swift
enum LogCategory: String {
    case app = "App"
    case device = "Device"
    case capture = "Capture"
    case rendering = "Rendering"
    case connection = "Connection"
    case recording = "Recording"
    case annotation = "Annotation"
    case performance = "Performance"
    case process = "Process"
    case permission = "Permission"
}
```

### 7.2 错误分类

| 错误类型 | 用户提示 |
|----------|----------|
| connectionFailed | "连接失败: {reason}" |
| permissionDenied | "权限被拒绝" |
| windowNotFound | "未找到投屏窗口" |
| captureStartFailed | "捕获启动失败: {reason}" |
| processTerminated | "进程已终止 (退出码: {code})" |
| timeout | "连接超时" |
| deviceInUse | "设备被其他应用占用: {app}" |

### 7.3 待改进项

| 功能 | 状态 | 优先级 |
|------|------|--------|
| 应用内日志导出 | ❌ **未实现** | P3 |
| 日志级别动态调整 UI | ❌ **未实现** | P3 |
| 崩溃日志收集 | ❌ **未实现** | P3 |

**结论**: ✅ **日志系统完善，符合产品工具标准**

---

## 8. 最终审计结论

### ✅ **合格，可作为演示台交付**

### 8.1 审计通过项

| # | 审计项 | 状态 |
|---|--------|------|
| 1 | 纯 AppKit UI 实现 | ✅ 通过 |
| 2 | Metal 核心渲染 | ✅ 通过 |
| 3 | 无 Demo 级 shortcut | ✅ 通过 |
| 4 | CoreMediaIO + AVFoundation iOS 采集 | ✅ 通过 |
| 5 | QuickTime 同款技术路径 | ✅ 通过 |
| 6 | iOS 设备占用检测 | ✅ 通过 |
| 7 | scrcpy 内置到 App Bundle | ✅ 通过 |
| 8 | adb 内置到 App Bundle | ✅ 通过 |
| 9 | VideoToolbox 硬解码 | ✅ 通过 |
| 10 | H.264/H.265 NAL 解析 | ✅ 通过 |
| 11 | 渲染队列隔离 | ✅ 通过 |
| 12 | Android 解码专用队列 | ✅ 通过 |
| 13 | 结构化日志系统 | ✅ 通过 |
| 14 | 设备状态处理完善 | ✅ 通过 |

### 8.2 待验证/待改进项

| # | 待改进项 | 优先级 | 影响 |
|---|----------|--------|------|
| 1 | 30 分钟稳定性测试 | P2 | 中 |
| 2 | 锁屏/解锁专门处理 | P2 | 低 |
| ~~3~~ | ~~Android 解码专用队列~~ | ~~P2~~ | ✅ 已完成 |
| 4 | 应用内日志导出 | P3 | 低 |

---

## 9. 风险清单与改进计划

### 9.1 风险矩阵

```
影响
 ↑
高 │                               
   │                               
   │                               
   │                               
中 │              ┌─────────┐      
   │              │ P2      │      
   │              │ 稳定性  │      
   │              │ 测试    │      
   │              └─────────┘      
低 │  ┌─────────┐          ┌─────────┐
   │  │ P2      │          │ P3      │
   │  │ 锁屏    │          │ 日志    │
   │  │ 处理    │          │ 导出    │
   │  └─────────┘          └─────────┘
   └─────────────────────────────────→ 概率
         低          中          高
```

### 9.2 已完成的关键修复

| ID | 风险 | 状态 | 实现方式 |
|----|------|------|----------|
| R1 | scrcpy/adb 未内置 | ✅ **已修复** | 内置到 `Resources/Tools/` |
| R2 | 主线程渲染 | ✅ **已修复** | 使用专用 `renderQueue` |
| R3 | 设备占用检测缺失 | ✅ **已修复** | `isInUseByAnotherApplication` |
| R4 | 外部窗口拉起 | ✅ **已修复** | `--no-display` 模式 |

### 9.3 改进计划

#### Phase 2: 稳定性增强 (P2)

| 任务 | 状态 | 预计工时 |
|------|------|----------|
| 执行 30min 稳定性测试 | ⬜ 待执行 | 2h |
| 添加内存监控 | ⬜ 待实现 | 4h |
| 添加帧率统计面板 | ⬜ 待实现 | 2h |
| 优化锁屏/解锁处理 | ⬜ 待实现 | 2h |

#### Phase 3: 体验优化 (P3)

| 任务 | 状态 | 预计工时 |
|------|------|----------|
| 添加日志导出功能 | ⬜ 待实现 | 2h |
| 添加性能监控面板 | ⬜ 待实现 | 4h |
| 支持无线 ADB | ⬜ 待实现 | 4h |

---

## 10. 版本迭代记录

### v1.2.0 (当前) - 重新审计

**审计结论**: ✅ **合格，可作为演示台交付**

**核心技术验证通过**:
- ✅ 纯 AppKit UI（无 SwiftUI）
- ✅ Metal 核心渲染（非套壳）
- ✅ CoreMediaIO + AVFoundation iOS 采集（QuickTime 同款路径）
- ✅ scrcpy + VideoToolbox Android 采集（完整硬解链路）
- ✅ scrcpy/adb 内置到 App Bundle
- ✅ 渲染队列隔离
- ✅ Android 解码专用队列（`decodeQueue` + `decoderLock`）
- ✅ iOS 设备占用检测
- ✅ 结构化日志系统（10 分类）

**待改进**:
- ⬜ 稳定性测试数据
- ⬜ 锁屏/解锁处理
- ⬜ 日志导出功能

---

### v1.1.0 - Phase 1 完成

**审计结论**: ✅ 基本合格

**已实现**:
- ✅ Phase 1 关键缺陷修复
- ✅ scrcpy v3.3.4 内置 (静态链接)
- ✅ adb v36.0.0 内置
- ✅ 渲染队列隔离
- ✅ iOS 设备占用检测

---

### v1.0.0 - 初始版本

**审计结论**: ⚠️ 部分合格

**待改进**:
- ❌ scrcpy 未内置
- ❌ 主线程渲染风险
- ❌ 设备占用检测缺失

---

## 附录

### A. 审计检查清单

<details>
<summary>点击展开完整检查清单</summary>

#### 总体架构
- [x] 使用 AppKit 实现 UI
- [x] 无 SwiftUI / NSHostingView
- [x] Metal 作为渲染核心
- [x] 无 Demo 级 shortcut

#### iOS 路线
- [x] CoreMediaIO 启用 (kCMIOHardwarePropertyAllowScreenCaptureDevices)
- [x] AVCaptureSession 捕获
- [x] 实时 CMSampleBuffer
- [x] 设备占用检测 (isInUseByAnotherApplication)
- [x] 设备连接/断开通知
- [ ] 锁屏/解锁专门处理

#### Android 路线
- [x] scrcpy 内置 Bundle
- [x] scrcpy-server 内置
- [x] adb 内置 Bundle
- [x] --no-display 模式
- [x] VideoToolbox 硬解
- [x] H.264 支持
- [x] H.265 支持
- [x] NAL 单元解析
- [x] 授权状态处理
- [x] 解码专用队列 (decodeQueue)

#### Metal 渲染
- [x] 多路合成
- [x] 纵横比保持
- [x] CAMetalLayer
- [x] 渲染队列隔离
- [x] 无 CPU 图像合成

#### 稳定性
- [ ] 长时间测试数据
- [ ] 内存监控
- [x] 帧率统计

#### 日志诊断
- [x] 统一日志模块 (os.log)
- [x] 分类日志 (10 类)
- [x] 错误分类 (7 种)
- [ ] 日志导出

</details>

### B. 代码位置索引

| 模块 | 文件 | 关键功能 |
|------|------|----------|
| 应用入口 | `AppDelegate.swift` | AppKit 生命周期 |
| 主视图 | `MainViewController.swift` | NSViewController |
| Metal 渲染器 | `MetalRenderer.swift` | 纹理合成、布局渲染 |
| Metal 视图 | `MetalRenderView.swift` | CAMetalLayer、渲染队列 |
| iOS 采集 | `IOSDeviceSource.swift` | AVCaptureSession |
| iOS 激活器 | `IOSScreenMirrorActivator.swift` | CoreMediaIO |
| iOS 设备发现 | `IOSDeviceProvider.swift` | DiscoverySession |
| Android 采集 | `ScrcpyDeviceSource.swift` | VideoToolbox 解码 |
| Android 设备 | `AndroidDevice.swift` | 状态处理 |
| Android 发现 | `AndroidDeviceProvider.swift` | adb 轮询 |
| 工具链管理 | `ToolchainManager.swift` | scrcpy/adb 路径 |
| 日志系统 | `Logger.swift` | os.log 封装 |

### C. 参考文档

- [CoreMediaIO Programming Guide](https://developer.apple.com/documentation/coremediaio)
- [AVFoundation Programming Guide](https://developer.apple.com/documentation/avfoundation)
- [Metal Programming Guide](https://developer.apple.com/documentation/metal)
- [VideoToolbox Programming Guide](https://developer.apple.com/documentation/videotoolbox)
- [scrcpy Documentation](https://github.com/Genymobile/scrcpy)

---

> **文档维护**: 本文档应随项目迭代持续更新  
> **最后更新**: 2025-12-23 (重新审计)
