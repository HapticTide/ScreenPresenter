# ScreenPresenter

macOS 设备投屏工具，支持同时展示 iOS 和 Android 设备屏幕。

## 特性

- 📱 **iOS 投屏**: 使用 QuickTime 同款路径 (CoreMediaIO + AVFoundation)
- 🤖 **Android 投屏**: 通过 scrcpy 码流 + VideoToolbox 硬解
- 🖥️ **Metal 渲染**: 使用 CAMetalLayer 实现高性能 60fps 渲染
- 🔄 **多设备**: 支持同时展示两台设备（iOS + Android）
- 🎛️ **纯 AppKit**: 无 SwiftUI 依赖，系统兼容性更好

## 系统要求

- macOS 14.0+
- Apple Silicon 或 Intel Mac

## 架构说明

### 技术栈

| 层级 | 技术 |
|------|------|
| UI 框架 | AppKit (NSApplication/NSWindow/NSView) |
| 渲染 | Metal (CAMetalLayer + CVMetalTextureCache) |
| iOS 捕获 | CoreMediaIO + AVFoundation |
| Android 捕获 | scrcpy 码流 + VideoToolbox |
| 设备感知 | MobileDevice.framework (可选增强) |

### 模块结构

```
ScreenPresenter/
├── Core/
│   ├── AppState.swift              # 全局应用状态管理
│   ├── Rendering/
│   │   ├── MetalRenderer.swift     # Metal 渲染器核心
│   │   ├── MetalRenderView.swift   # CAMetalLayer 渲染视图
│   │   └── FramePipeline.swift     # 帧数据结构
│   ├── DeviceSource/
│   │   ├── DeviceSource.swift      # 设备源协议
│   │   ├── IOSDeviceSource.swift   # iOS 设备源 (AVFoundation)
│   │   ├── ScrcpyDeviceSource.swift # Android 设备源 (scrcpy)
│   │   └── IOSScreenMirrorActivator.swift # CoreMediaIO 激活器
│   ├── DeviceDiscovery/
│   │   ├── IOSDeviceProvider.swift # iOS 设备发现
│   │   └── AndroidDeviceProvider.swift # Android 设备发现
│   ├── DeviceInsight/
│   │   └── DeviceInsightService.swift # MobileDevice 增强层
│   ├── Process/
│   │   ├── ProcessRunner.swift     # 进程管理
│   │   └── ToolchainManager.swift  # 工具链管理
│   └── ...
├── Views/
│   ├── MainViewController.swift    # 主视图控制器
│   └── Components/                 # UI 组件
└── Resources/
    └── Tools/                      # 内置工具 (scrcpy, adb)
```

### 数据流

```
┌──────────────────────────────────────────────────────────┐
│                     iOS 设备                              │
│  USB → CoreMediaIO → AVFoundation → CMSampleBuffer       │
│                           ↓                               │
│                    CVPixelBuffer                          │
└────────────────────────┬─────────────────────────────────┘
                         │
                         ▼
              ┌─────────────────────┐
              │  CVMetalTextureCache │
              │     ↓        ↓       │
              │  MTLTexture  MTLTexture
              │     (left)   (right) │
              └─────────┬───────────┘
                        │
                        ▼
              ┌─────────────────────┐
              │   Metal Renderer    │
              │    (CAMetalLayer)   │
              │  Aspect-fit + 合成   │
              └─────────────────────┘
                         │
                         ▼
              ┌─────────────────────┐
              │    MetalRenderView  │
              │   (CVDisplayLink)   │
              └─────────────────────┘
                         ↑
                         │
              ┌─────────────────────┐
              │      Android 设备    │
              │ scrcpy → H.264/H.265 │
              │        ↓             │
              │   VideoToolbox 硬解  │
              │        ↓             │
              │    CVPixelBuffer     │
              └─────────────────────┘
```

## iOS 投屏说明

### 主线路径 (CMIO + AVFoundation)

这是 QuickTime Player 使用的同款路径，稳定可靠：

1. **CoreMediaIO**: 设置 `kCMIOHardwarePropertyAllowScreenCaptureDevices = true`
2. **AVFoundation**: 使用 `AVCaptureSession` 捕获 iOS 屏幕设备
3. **帧输出**: `CMSampleBuffer → CVPixelBuffer → MTLTexture`

### MobileDevice 增强层

MobileDevice.framework 作为**可选增强层**：
- 提供：设备名称、型号、系统版本、信任状态
- **不影响主捕获流程**：MobileDevice 失败时，投屏功能仍可用

## Android 投屏说明

### 内置工具

应用内置 scrcpy 和 adb，支持零配置使用：

```
Resources/Tools/
├── scrcpy           # Android 投屏工具
└── platform-tools/
    └── adb          # Android 调试工具
```

### 启动前自检

1. `adb version` - 检查 adb 可用性
2. `adb start-server` - 启动 adb 服务
3. `adb devices` - 检查设备授权状态

### 码流解码

```
scrcpy --no-display → H.264/H.265 码流
        ↓
   VideoToolbox 硬解
        ↓
    CVPixelBuffer
        ↓
     MTLTexture
```

## 稳定性机制

- **插拔恢复**: 自动检测设备插拔，支持重连
- **错误诊断**: 结构化日志记录（设备信息、fps、错误分类）
- **降级策略**: MobileDevice 失效不影响主功能

## 构建运行

1. 使用 Xcode 15+ 打开 `ScreenPresenter.xcodeproj`
2. 选择 `My Mac` 作为目标设备
3. 点击运行

### 首次使用

1. 授予摄像头权限（用于捕获 iOS 设备）
2. 连接 iOS 设备，在设备上点击"信任此电脑"
3. Android 设备需开启"USB 调试"，连接后在设备上点击"允许"

## 许可证

内部工具，仅供内部使用。
