## ScreenPresenter：Android 投屏（scrcpy-server）实现 Prompt（项目级）

你是资深 macOS/iOS 工程师，请在现有 macOS 工程 **ScreenPresenter** 中实现 Android 设备投屏能力。投屏基于 **scrcpy-server** 在 Android 端抓屏并编码为 H.264/H.265 码流，通过 ADB 建立的 reverse/forward 通道回传到 macOS。macOS 端必须使用 **VideoToolbox 解码**并将输出 `CVPixelBuffer` 交给现有 **MetalRenderer / CapturedFrame** 渲染显示。禁止使用 FFmpeg、禁止引入 SDL 渲染。只聚焦“显示与通信”，不实现键鼠控制注入（control channel 可以禁用或忽略）。

### 0. 当前项目结构（必须遵守）

现有目录关键点：

- `ScreenPresenter/Core/DeviceDiscovery/`
  - `AndroidDevice.swift`
  - `AndroidDeviceProvider.swift`
- `ScreenPresenter/Core/DeviceSource/`
  - `DeviceSource.swift`（统一源抽象）
  - `ScrcpyDeviceSource.swift`（已存在但当前未完成/需重构）
  - `IOSDeviceSource.swift`（参考其风格）
- `ScreenPresenter/Core/Process/`
  - `ProcessRunner.swift`（命令执行封装）
  - `ToolchainManager.swift`（工具链路径管理）
- `ScreenPresenter/Core/Rendering/`
  - `CapturedFrame.swift`
  - `MetalRenderer.swift`
  - `SingleDeviceRenderView.swift`
- 工具资源：
  - `ScreenPresenter/Resources/Tools/platform-tools/adb`（内置 adb）
  - `ScreenPresenter/Resources/Tools/scrcpy-server`（内置 scrcpy-server.jar 或相关资源）
  - `ScreenPresenter/Resources/Tools/scrcpy`（客户端，不要使用）

实现时优先复用现有 `ToolchainManager` 获取 adb / server 路径，复用 `ProcessRunner` 执行 adb 命令，复用 `Logger` 输出日志。

### 1. 最终用户体验（验收标准）

- App 左侧设备列表能列出 Android 设备（已存在 AndroidDeviceProvider，若不足需增强）。
- 选择某台 Android 设备，点击连接/投屏后：
  - 自动 push scrcpy-server
  - 自动建立 adb reverse（失败 fallback forward）
  - 自动启动 scrcpy-server 并接收 video 流
  - 画面在 `SingleDeviceRenderView` 正确显示
- 断开连接能停止流、释放端口、清理 reverse/forward、避免下次连接失败
- 不支持控制注入也没关系，但必须稳定显示画面
- 需要可观测性：日志中能看到 adb 命令、端口、连接状态、fps/码率（至少基础统计）

### 2. 代码分层与新增/改造文件（必须按此落位）

#### 2.1 Toolchain：scrcpy-server 与 adb 路径

- 修改 `ScreenPresenter/Core/Process/ToolchainManager.swift`
  - 新增 API：
    - `func adbPath() throws -> String`（已有就复用）
    - `func scrcpyServerJarPath() throws -> String`（指向 Resources/Tools/scrcpy-server 下的 jar）
  - 如果 `Resources/Tools/scrcpy-server` 不是 jar 文件而是目录，必须找到真实 jar 路径并校验存在

#### 2.2 ADB 命令层（复用 ProcessRunner）

- 在 `ScreenPresenter/Core/DeviceDiscovery/DeviceControl/` 下新增：
  - `AndroidADBService.swift`
    - 依赖 `ProcessRunner`、`ToolchainManager`
    - 提供：
      - `listDevices()`
      - `push(local:remote:)`
      - `reverse(localAbstract:tcpPort:)` 与 `removeReverse(...)`
      - `forward(tcpPort:localAbstract:)` 与 `removeForward(...)`
      - `shell(_ command: String)`（启动 server）
      - `killScrcpyServerIfNeeded()`（可选）
    - 必须支持指定 deviceId（`adb -s <serial>`）
    - 每条命令必须有结构化日志（耗时、stdout、stderr）

#### 2.3 Scrcpy 投屏源（核心）

- 改造或重写 `ScreenPresenter/Core/DeviceSource/ScrcpyDeviceSource.swift`，让它成为 Android 投屏的唯一入口。
- `ScrcpyDeviceSource` 必须实现 `DeviceSource` 协议（参考 `IOSDeviceSource.swift` 的生命周期与状态回调风格）
- 内部实现分三块（可同文件或拆文件，优先拆分便于测试）：
  1. `ScrcpyServerLauncher`
     - push server jar 到 `/data/local/tmp/scrcpy-server.jar`
     - 建立 reverse：`adb reverse localabstract:scrcpy tcp:<port>`
       - reverse 失败则 fallback forward（并走另一套连接策略）
     - 启动：
       - `adb shell CLASSPATH=/data/local/tmp/scrcpy-server.jar app_process / com.genymobile.scrcpy.Server <version> <args...>`
     - 参数必须配置：仅 video 开启、audio/control 关闭（如果协议允许），并指定 codec h264（先固定，后续扩展）
  2. `ScrcpySocketAcceptor`
     - macOS 端启动 TCP listener（使用 Network.framework：`NWListener`）
     - 先 listener start，再启动 server
     - accept 第一条连接作为 video socket
     - 后续连接（control/audio）直接 cancel/ignore
  3. `ScrcpyVideoStreamParser + VideoSampleProducer`
     - 解析 scrcpy video 协议：
       - 读取初始 meta（codec id / width / height / device name 如有）
       - 之后每帧解析 12-byte frame header + payload
     - 处理粘包/半包：流式缓存 + while 循环产出完整帧
     - scrcpy payload 为 AnnexB elementary stream：
       - 实现 AnnexB NALU split
       - AnnexB → AVCC（length-prefixed）
       - 从 config packet 提取 SPS/PPS（H.264），创建 `CMVideoFormatDescription`
     - 每个 access unit 组装为编码 `CMSampleBuffer`
       - 设置 timing：统一用 microseconds timescale
       - 标记 keyframe（attachments）
     - 将 `CMSampleBuffer` 输出给下游解码器

#### 2.4 VideoToolbox 解码与渲染接入

- 若项目已有统一的解码入口（比如 `CapturedFrame` 内部已包含解码），则：
  - 在 `ScrcpyDeviceSource` 输出统一帧类型（优先 `CVPixelBuffer`）
  - 如果 pipeline 只接受 pixel buffer，则在 `ScrcpyDeviceSource` 内部加入 `VideoToolboxDecoder`（新建 `ScreenPresenter/Core/Rendering/VideoToolboxDecoder.swift`）
- 目标：最终进入 `CapturedFrame` 的必须是你现有渲染链路能消费的帧（例如 `CVPixelBuffer`）
- `MetalRenderer` 不改或尽量少改

### 3. 协议细节与兼容性要求

- scrcpy 协议解析必须参考官方 `doc/develop.md` 当前版本：
  - meta 结构（codec id、size 等）
  - frame header 的 bit 与 endian 必须正确
- 需要兼容 scrcpy 2.x 的常见变化：
  - 如果遇到解析失败，必须在日志里输出“当前解析期望 vs 实际 bytes”
  - 提供“协议版本不匹配”的错误提示（包括 server 版本与客户端版本号）

### 4. 线程模型与性能要求

- IO：单独队列读 socket（不要堵主线程）
- Parser：必须是可重入/可持续 append 的流式 parser
- 解码：VideoToolbox 在专用队列，输出 pixel buffer 后回到渲染队列（或你现有渲染调度方式）
- 低延迟策略：
  - 不堆帧：如果渲染/解码忙，允许丢弃旧帧，只保留最新帧（必须实现一个简单的丢帧策略）
  - 分辨率变化：重建 formatDesc / 解码 session

### 5. UI 接入点（最少改动）

- `Views/MainViewController.swift` / `DevicePanelView.swift`：
  - 当选择 AndroidDevice 时，创建 `ScrcpyDeviceSource(device: AndroidDevice)`
  - start 后把其输出接到 `SingleDeviceRenderView`（参考 iOS 设备的接入方式）
- 不需要新增复杂 UI，只要能切换设备并展示画面

### 6. 测试与调试能力（必须交付）

- 新增单元测试（放在现有 test target 下）：
  - AnnexB split
  - AnnexB→AVCC
  - frame header parser（用固定二进制样本）
- 新增一个 Debug 开关（`UserPreferences`）：
  - `useBundledAdb: Bool`（默认 true）
  - `scrcpyPort: Int`（默认 27183，可修改）
  - `scrcpyCodec: h264/hevc`（先只实现 h264，hevc 留 TODO 但接口预留）

### 7. 输出要求

你需要输出：

1. 文件清单（新增/修改）
2. 每个文件的完整代码（可编译）
3. 关键实现说明（尤其是 scrcpy header / meta 的解析）
4. 如何本地验证（步骤 + 预期日志）

------

### 额外说明（重要）

- 项目里已经内置 `Resources/Tools/platform-tools/adb`，优先用它，避免用户环境差异。
- 如果 `Resources/Tools/scrcpy-server` 不是 jar，请确认其内容并调整 `ToolchainManager.scrcpyServerJarPath()`。
- 不实现控制注入，但必须确保“忽略 control socket 连接”不会导致 server 卡死；如 server 必须建立多个连接才能开始发视频，则必须 accept 这些连接并丢弃读取（也要记录到日志）。