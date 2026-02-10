# ScreenPresenter

macOS 设备投屏工具，支持同时展示 iOS 和 Android 设备屏幕，具备仿真设备边框渲染效果。
 
## ✨ 特性 

- 📱 **iOS 投屏**: QuickTime 同款路径 (CoreMediaIO + AVFoundation)
- 🤖 **Android 投屏**: scrcpy 码流 + VideoToolbox 硬件解码
- 🖥️ **Metal 渲染**: CVDisplayLink 驱动的 60fps 高性能渲染
- 🔄 **双设备展示**: 支持同时展示两台设备（iOS + Android）
- 📐 **仿真边框**: 根据真实设备型号绘制设备外观（动态岛/刘海/打孔屏/侧边按键）
- 📝 **Markdown 编辑器**: 内嵌多标签页编辑器，支持语法高亮、10+ 主题、查找替换
- 🎛️ **纯 AppKit**: 零 SwiftUI 依赖，最大化系统兼容性
- 🌐 **多语言**: 中英文双语支持

## 📋 系统要求

- macOS 14.0+
- Apple Silicon 或 Intel Mac
- Xcode 15+

## 🏗️ 架构说明

### 技术栈

| 层级 | 技术 |
|------|------|
| UI 框架 | AppKit (NSWindow / NSView) |
| 渲染引擎 | Metal (CAMetalLayer + CVMetalTextureCache) |
| 帧同步 | CVDisplayLink |
| iOS 捕获 | CoreMediaIO + AVFoundation |
| Android 捕获 | scrcpy-server + Socket + VideoToolbox |
| 设备识别 | FBDeviceControl (可选增强) |
| Markdown 编辑 | WKWebView + CodeMirror |

### 模块结构

```
ScreenPresenter/
├── Core/
│   ├── AppState.swift                    # 全局应用状态 (Combine)
│   ├── Rendering/
│   │   ├── MetalRenderer.swift           # Metal 渲染器核心
│   │   ├── MetalRenderView.swift         # CAMetalLayer + CVDisplayLink
│   │   ├── SingleDeviceRenderView.swift  # 单设备渲染封装
│   │   ├── VideoToolboxDecoder.swift     # H.264/H.265 硬件解码器
│   │   └── CapturedFrame.swift           # 帧数据结构
│   ├── DeviceSource/
│   │   ├── DeviceSource.swift            # 设备源协议
│   │   ├── IOSDeviceSource.swift         # iOS 设备源 (AVFoundation)
│   │   ├── IOSScreenMirrorActivator.swift # CoreMediaIO DAL 激活
│   │   ├── ScrcpyDeviceSource.swift      # Android 设备源
│   │   └── Scrcpy/
│   │       ├── ScrcpyServerLauncher.swift    # scrcpy-server 启动器
│   │       ├── ScrcpySocketAcceptor.swift    # Socket 连接管理
│   │       └── ScrcpyVideoStreamParser.swift # 码流解析器
│   ├── DeviceDiscovery/
│   │   ├── IOSDevice.swift               # iOS 设备模型
│   │   ├── IOSDeviceProvider.swift       # iOS 设备发现
│   │   ├── IOSDeviceStateMapper.swift    # 设备状态映射
│   │   ├── AndroidDevice.swift           # Android 设备模型
│   │   ├── AndroidDeviceProvider.swift   # Android 设备发现
│   │   └── DeviceControl/
│   │       ├── FBDeviceControlService.swift  # FBDeviceControl 封装
│   │       └── AndroidADBService.swift       # ADB 服务封装
│   ├── Preferences/
│   │   └── UserPreferences.swift         # 用户偏好设置
│   ├── Process/
│   │   ├── ProcessRunner.swift           # 进程管理
│   │   └── ToolchainManager.swift        # 工具链管理
│   └── Utilities/                        # 工具类
├── Views/
│   ├── MainViewController.swift          # 主视图控制器
│   ├── PreferencesWindowController.swift # 偏好设置窗口
│   ├── Components/
│   │   ├── PreviewContainerView.swift    # 预览容器（布局动画）
│   │   ├── DevicePanelView.swift         # 设备面板（边框+渲染+状态）
│   │   ├── DeviceBezelView.swift         # 设备边框绘制
│   │   ├── DeviceModel.swift             # 设备型号定义 (50+ 型号)
│   │   └── ToastView.swift               # Toast 通知
│   └── Showcase/                         # 设备展示模式
├── MarkdownEditor/                       # Markdown 编辑器 Swift Package
│   └── Sources/MarkdownEditor/
│       ├── Editor/                       # 编辑器核心（WKWebView + CodeMirror）
│       ├── Integration/                  # 宿主应用集成接口
│       ├── Panels/                       # 查找 / 替换面板
│       └── Main/                         # 主题、配置、热键
├── MarkdownKit/                          # 编辑器桥接层
├── MarkdownCore/                         # 编辑器核心类型
├── MarkdownPreview/                      # Markdown 预览
├── FBDeviceControlKit/                   # 设备信息增强层
└── Resources/
    ├── Tools/
    │   ├── scrcpy                        # Android 投屏客户端
    │   ├── scrcpy-server                 # Android 投屏服务端
    │   └── platform-tools/
    │       └── adb                       # Android 调试工具
    ├── en.lproj/                         # 英文本地化
    └── zh-Hans.lproj/                    # 简体中文本地化
```

### 数据流

```
┌──────────────────────────────────────────────────────────────┐
│                         iOS 设备                              │
│  USB → CoreMediaIO DAL → AVCaptureSession → CMSampleBuffer   │
│                              ↓                                │
│                       CVPixelBuffer (BGRA)                    │
└─────────────────────────────┬────────────────────────────────┘
                              │
                              ▼
                  ┌─────────────────────┐
                  │  CVMetalTextureCache │
                  │         ↓            │
                  │     MTLTexture       │
                  └──────────┬──────────┘
                             │
                             ▼
┌────────────────────────────────────────────────────────────────┐
│                      Metal Renderer                            │
│  CAMetalLayer + CVDisplayLink (60fps) + Aspect-fit + 圆角遮罩  │
└────────────────────────────────────────────────────────────────┘
                             ↑
                             │
                  ┌──────────┴──────────┐
                  │  CVMetalTextureCache │
                  │         ↑            │
                  │   CVPixelBuffer      │
                  └──────────┬──────────┘
                             │
┌────────────────────────────┴─────────────────────────────────┐
│                       Android 设备                            │
│  scrcpy-server (设备端) → H.264/H.265 码流                    │
│         ↓                                                     │
│  Socket (ADB 端口转发) → ScrcpyVideoStreamParser             │
│         ↓                                                     │
│  VideoToolbox 硬件解码 → CVPixelBuffer                        │
└──────────────────────────────────────────────────────────────┘
```

## 📱 iOS 投屏

### QuickTime 同款路径

这是与 QuickTime Player 完全相同的捕获路径，稳定可靠：

1. **CoreMediaIO DAL 激活**: 设置 `kCMIOHardwarePropertyAllowScreenCaptureDevices = true`
2. **AVCaptureSession**: 捕获 iOS 设备的屏幕输出
3. **直接像素传输**: `CMSampleBuffer → CVPixelBuffer → MTLTexture`

### FBDeviceControl 增强层

`FBDeviceControl.framework` 作为**可选增强层**：

| 功能 | 来源 |
|------|------|
| 设备 UDID | FBDeviceControl |
| 设备名称 | FBDeviceControl |
| 产品型号 (iPhone16,1) | FBDeviceControl |
| 系统版本 | FBDeviceControl |
| 信任状态 | FBDeviceControl |

> ⚠️ **重要**: FBDeviceControl 失败不影响主捕获流程，仅降级为 AVFoundation 模式。

## 🤖 Android 投屏

### 内置工具

应用内置完整工具链，支持零配置使用：

```
Resources/Tools/
├── scrcpy                    # 投屏客户端（仅解析用）
├── scrcpy-server             # 投屏服务端（推送到设备运行）
└── platform-tools/
    └── adb                   # Android 调试桥
```

### 连接流程

```
ScreenPresenter                    adb                     Android Device
     │                              │                            │
     │──── adb devices ────────────>│                            │
     │<─── 设备列表 ────────────────│                            │
     │                              │                            │
     │──── adb push scrcpy-server ─>│────── 传输服务端 ─────────>│
     │                              │                            │
     │──── adb forward tcp:27183 ──>│────── 端口转发 ───────────>│
     │                              │                            │
     │──── adb shell app_process ──>│────── 启动服务端 ─────────>│
     │                              │                            │
     │<═══════════════ Socket 连接 ═════════════════════════════>│
     │<═══════════════ H.264/H.265 码流 ════════════════════════>│
     │                              │                            │
     │──── VideoToolbox 硬解 ───────│                            │
```

### 可配置参数

| 参数 | 默认值 | 说明 |
|------|--------|------|
| 码率 | 8 Mbps | 4 / 8 / 16 / 32 Mbps |
| 最大分辨率 | 原始 | 720 / 1080 / 1440 / 2160 |
| 编解码器 | H.264 | H.264 / H.265 |

### 丢帧策略

VideoToolbox 解码器内置智能丢帧策略：

```swift
// 待解码帧超过阈值时，丢弃非关键帧
private let maxPendingFrames = 3

if currentPending > maxPendingFrames, !nalUnit.isKeyFrame {
    droppedFrameCount += 1
    return  // 丢弃非关键帧
}
```

## 📐 设备边框渲染

### 支持的设备型号

应用根据真实设备规格绘制精确的设备边框：

**iOS 设备 (16 种)**
- iPhone 17 Pro / 17 / 16 Pro / 16 / 15 Pro / 15 / 14 Pro / 14
- iPhone 13 / 13 Pro / 12 / 11 / X 系列
- iPhone SE / Legacy
- 通用 iPhone

**Android 设备 (40+ 种)**
- Samsung Galaxy S / S Ultra / A / Note / Fold / Flip
- Google Pixel / Pixel Pro / Pixel Fold / Pixel A
- 小米 Mi / Ultra / MIX / Redmi / Redmi Note / Redmi K / POCO
- 一加 OnePlus / Ace / Nord
- OPPO Find / Find X / Reno / A
- Vivo X / X Fold / S / Y / iQOO / iQOO Neo
- 华为 P / Mate / Mate X / Nova
- 荣耀 Honor / Magic / X
- Realme GT / Realme
- Sony Xperia 1 / 5 / 10
- Motorola Edge / Razr / Moto G
- ASUS ROG / Zenfone
- 游戏手机: Red Magic / Black Shark / Legion
- 其他: Meizu / Nothing Phone / TCL / ZTE
- 通用 Android

### 边框特性

| 特性 | 说明 |
|------|------|
| 动态岛 | iPhone 14 Pro 及之后（15/16/17 全系、Air） |
| 刘海 | iPhone X ~ 14/14 Plus、16e |
| 打孔屏 | 大多数 Android |
| Home 按钮 | iPhone SE / Legacy |
| 侧边按键 | 静音开关 / 音量键 / 电源键 |
| 连续曲率圆角 | `.continuous` 圆角风格 |

## � Markdown 编辑器

内嵌的 Markdown 编辑器，用于在投屏演示过程中随时记录笔记。

### 主要功能

- **多标签页**: 同时编辑多个文档，标签栏支持拖拽排序和右键菜单
- **语法高亮**: 基于 CodeMirror 6，支持 Markdown 及 30+ 编程语言
- **丰富主题**: GitHub Light/Dark、Xcode Light/Dark、Dracula、Cobalt 等 10+ 主题
- **查找替换**: ⌘F 查找 / ⌘⇧F 替换，支持正则表达式
- **格式工具栏**: 标题、粗体、斜体、链接、代码块等快捷操作
- **文件操作**: 新建、打开、保存、另存为，支持 .md / .markdown / .txt
- **灵活布局**: 编辑器位置可配置为左侧、右侧或居中
- **主题独立**: 编辑器主题不影响主窗口外观

## �🔧 用户设置

### 通用设置
- 布局模式（双设备 / 单设备）
- iOS 设备位置（左侧 / 右侧）
- 自动重连开关
- 背景透明度
- 显示设备边框

### Markdown 编辑器设置
- 编辑器主题（GitHub Light/Dark、Xcode、Dracula、Cobalt 等）
- 编辑器位置（左侧 / 右侧 / 居中）
- 显示/隐藏编辑器

### Android 设置
- 码率调节
- 分辨率限制
- 编解码器选择

### 工具链设置
- 自定义 adb 路径
- 自定义 scrcpy 路径
- 自定义 scrcpy-server 路径
- 权限检查与授予

## 🚀 构建运行

1. 使用 Xcode 15+ 打开 `ScreenPresenter.xcodeproj`
2. 选择 `My Mac` 作为目标设备
3. 点击运行

### 首次使用

**iOS 设备**:
1. 授予摄像头权限（系统会弹窗，用于捕获 iOS 设备）
2. 通过 USB 连接 iOS 设备
3. 在 iOS 设备上点击"信任此电脑"
4. 解锁设备屏幕

**Android 设备**:
1. 在设置中开启"USB 调试"
2. 通过 USB 连接 Android 设备
3. 在设备上点击"允许 USB 调试"

## 📦 打包发布

使用内置脚本构建 DMG：

```bash
./build_dmg.sh
```

输出: `build/ScreenPresenter_<版本号>_<构建号>.dmg`

## 📄 许可证

内部工具，仅供内部使用。
