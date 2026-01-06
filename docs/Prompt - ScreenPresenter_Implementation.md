# 1) 屏幕演示台 Prompt

## 产品：演示台

## 工程名：ScreenPresenter

## 平台：macOS 14+

## UI：AppKit（禁止 SwiftUI）

## 渲染：Metal（CAMetalLayer）

## 性质：内部工具（不进 App Store，允许私有 API / 私有框架）

------

## 0. 你的身份与目标（必须理解）

你是 Claude Code · Opus。你要交付的是一个“产品/设计/测试每天能直接用”的 macOS 工具，不是 Demo。

成功标准：

1. 插上设备就能用
2. 画面稳定、清晰、流畅
3. 多台设备同窗展示
4. 出问题能解释（可诊断、可恢复）

优先级：稳定性 > 可维护性 > 性能 > 技巧

------

## 1. 产品目标（不可偏离）

在 macOS 上实现「演示台」（ScreenPresenter）：

- 同一窗口内同时展示至少两路真实设备屏幕流：
  - 1 台 iOS（USB）
  - 1 台 Android（USB）
- 目标 60fps（允许适度降分辨率换稳定）
- 只展示，不要求控制（控制仅预留接口）

**用户机器没有统一安装 Android Studio / platform-tools。工具必须“自带依赖、零配置可用”。**

------

## 2. 强制技术约束（MUST / MUST NOT）

### MUST（必须）

1. UI 使用 AppKit：`NSApplication / NSWindow / NSView`
2. 渲染主链路使用 Metal：
   - 使用 `CAMetalLayer`
   - 视频帧最终以 `MTLTexture` 进入渲染管线
   - 通过 `CVMetalTextureCache` 将 `CVPixelBuffer` 转纹理
   - 在 Metal 内完成缩放/保持纵横比/合成
3. iOS 屏幕捕获主线必须是 QuickTime 同款路径：
   - CoreMediaIO（启用屏幕捕获设备）
   - AVFoundation（AVCaptureSession）获取实时 `CMSampleBuffer`
4. Android 屏幕捕获必须是：
   - scrcpy（USB）输出码流 → 应用内接收
   - VideoToolbox 硬解 → 输出 `CVPixelBuffer` → Metal
5. 工具内置依赖（App bundle 内必须自带）：
   - `scrcpy`
   - `platform-tools/adb`
6. 必须有稳定性机制与诊断：
   - 插拔、断连、锁屏/解锁恢复或明确提示
   - 结构化日志（含工具版本/路径）
   - fps/丢帧统计

### MUST NOT（禁止）

- 禁止 qvh/libusb 直连 iOS
- 禁止 ReplayKit/iOS 端 App 作为主路径
- 禁止 AirPlay/无线投屏作为主路径
- 禁止“只拉起 scrcpy 窗口”冒充集成
- 禁止截图轮询/录屏文件冒充实时流
- 禁止 SwiftUI

------

## 3. iOS：主线（必须可落地）

### 3.1 CoreMediaIO：启用屏幕捕获设备枚举

必须设置：

- `kCMIOHardwarePropertyAllowScreenCaptureDevices = true`

### 3.2 AVFoundation：捕获实时 sample buffer

- `AVCaptureSession` 捕获 iOS 屏幕设备
- 输出实时 `CMSampleBuffer`
- 处理方向/分辨率变化
- 提供 fps 统计

### 3.3 进入 Metal

- `CMSampleBuffer → CVPixelBuffer`
- `CVPixelBuffer → MTLTexture`（CVMetalTextureCache）
- 推入渲染队列

------

## 4. iOS：增强层（MobileDevice.framework 必须接入，但不得绑架主线）

### 4.1 目的（必须理解）

引入 **MobileDevice.framework（私有框架）** 用于提升“产品体验”与“诊断能力”，包括：

- 设备发现（更早更语义化）
- 读取设备元信息（用户设置的设备名、型号、iOS 版本、UDID/标识等）
- 判断配对/信任状态（未信任给用户提示）
- 占用检测（设备被 QuickTime/Xcode/Instruments 占用时给明确提示）
- 设备插拔事件（用于 UI/状态机提示）

### 4.2 关键铁律（强制）

> MobileDevice.framework 只能作为 **DeviceInsight（感知/解释）层**。
>  屏幕采集与视频流关键路径 **不得依赖** MobileDevice 成功与否。
>  即：MobileDevice 失效时，CMIO+AVFoundation 仍必须尽可能工作；最多损失的是“信息与提示”，不能让投屏能力瘫痪。

### 4.3 具体要求（必须实现）

- 设计 `DeviceInsightService(iOS)`：
  - 可用时提供：名称/型号/系统版本/信任状态/占用状态
  - 不可用时：返回降级结果（unknown + 解释），并记录日志
- 将其输出用于 UI 文案与错误分类，但不得作为采集启动的硬门槛（只可影响“提示/重试策略”，不可“一票否决”）。

------

## 5. Android：必须可落地

### 5.1 内置工具

Bundle 内必须包含：

- `Tools/scrcpy`
- `Tools/platform-tools/adb`

必须支持“零配置”：

- 优先使用内置 adb/scrcpy（默认）
- 可选高级开关允许使用系统 adb/scrcpy（默认关闭）

### 5.2 启动前自检（必须）

- `adb version`
- `adb start-server`
- `adb devices`（识别 unauthorized）
- scrcpy 可执行性与参数可用性检测

失败必须用户可读提示：

- 未开启开发者选项
- 未开启 USB 调试
- 未点允许授权（unauthorized）
- 线材/连接异常
- adb server 启动失败

### 5.3 应用内接收码流 + VideoToolbox 解码

- scrcpy 输出 H.264/H.265 码流进入应用
- VideoToolbox 硬解，输出 `CVPixelBuffer`
- `CVPixelBuffer → MTLTexture → Metal`

禁止仅弹 scrcpy 窗口。

------

## 6. Metal 渲染要求（核心）

- `CAMetalLayer` 作为渲染表面
- 每路流维护一个最新纹理（线程安全更新）
- 每帧 render pass：
  - 对每路纹理做 aspect-fit
  - 默认左右并排布局（可扩展多设备）
  - 叠加基础信息 HUD（设备名、fps、状态）（可用 Metal/或上层 NSView overlay）
- UI 主线程不得参与解码或纹理创建

------

## 7. 并发模型（必须）

- 每路流独立队列：
  - iOS：采集队列 + 纹理上传队列
  - Android：scrcpy IO 队列 + 解码队列 + 纹理上传队列
- 渲染使用固定 tick（如 CADisplayLink 替代方案 / CVDisplayLink / 定时器）或按帧触发，但必须避免阻塞 UI。

------

## 8. 验收标准（必须实测）

- macOS 26 连续运行 ≥ 30 分钟（iOS+Android 同时 streaming）
- 插拔各 10 次不崩溃，能恢复或明确提示
- 锁屏/解锁能恢复或明确提示
- 日志打印：
  - scrcpy/adb 的路径与版本
  - iOS 设备信息（能取则取）
  - 每路 fps/丢帧
  - 错误分类（未信任/未授权/被占用/解码失败等）

------

## 9. 最终交付物（必须）

- 可运行工程：ScreenPresenter（AppKit + Metal）
- 架构说明（模块职责 + 数据流）
- iOS 主线（CMIO+AVF）说明 + MobileDevice 增强层说明（含降级策略）
- Android 内置 scrcpy/adb 说明（含自检与提示）
- 稳定性测试记录与结果
- 风险列表（若有）