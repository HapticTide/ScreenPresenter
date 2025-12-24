## Prompt：在 ScreenPresenter 现有工程中集成 FBDeviceControl（设备信息 + 状态机 + UI 接入）

### 0. 你正在修改的工程（目录约束）

工程现有核心结构如下（必须遵守，不要自创大模块）：

- 设备发现：`ScreenPresenter/Core/DeviceDiscovery/`
  - `IOSDevice.swift`
  - `IOSDeviceProvider.swift`
- 设备洞察/信息汇总：`ScreenPresenter/Core/DeviceInsight/DeviceInsightService.swift`
- 数据源：`ScreenPresenter/Core/DeviceSource/IOSDeviceSource.swift`（不要求改投屏链路）
- UI：
  - `ScreenPresenter/Views/Components/DevicePanelView.swift`
  - `ScreenPresenter/Views/Components/DeviceModel.swift`
- 全局状态：`ScreenPresenter/Core/AppState.swift`
- 渲染：`ScreenPresenter/Core/Rendering/*`（**禁止改 Metal 渲染**）

目标是：**只增强 iOS 设备信息与状态逻辑，并贯通到 UI**。

------

### 1. 目标能力

#### 1.1 iOS 设备“详细信息”（从 FBDeviceControl 获取）

对每台 iOS 真机（至少 USB）读取并展示：

- `udid`（稳定主键）
- `deviceName`：用户在 iPhone「设置-关于本机-名称」设置的设备名
- `productVersion`：iOS 版本（如 18.2）
- `productType`：机型标识（如 iPhone17,1）
- `buildVersion`：系统 build（如 22Cxxx）
- （可选）`serialNumber / modelNumber / hardwareModel / battery`：能拿到就加

#### 1.2 设备状态机（工程可解释）

把常见失败原因映射为明确状态，并给 UI 文案：

- available
- notTrusted（未信任此电脑）
- notPaired（未配对）
- locked（设备锁屏/未解锁）
- developerModeOff（iOS 16+ Developer Mode 关闭）
- busy（会话繁忙/恢复中）
- unavailable(reason, underlying)

#### 1.3 事件流（插拔/状态变化）

支持设备插拔与状态变化更新 UI：

- 优先用 FBDeviceControl 的监听机制
- 若监听实现成本高，允许 polling（1~2s）+ diff，但必须可取消、不卡主线程

#### 1.4 与现有结构融合（必须）

- `IOSDeviceProvider` 仍然是 iOS 设备发现入口
- `IOSDevice` 仍然是项目内部的 iOS 设备模型（但需要扩展字段）
- `DeviceInsightService` 负责整合“设备信息/状态”的查询与缓存
- `DevicePanelView` 在列表中展示更全信息 + 状态文案

------

### 2. 集成方式（FBDeviceControl 作为 ThirdParty 源码）

#### 2.1 新增第三方目录

在工程根目录新增：`ThirdParty/FBDeviceControl`

源码在 `../idb/FBDeviceControl` 下

要求：不引入 idb_companion，不跑 gRPC，只用 FBDeviceControl 作为本地库。

#### 2.2 Xcode 集成要求

将 `ThirdParty/FBDeviceControl` 对应的 Xcode 工程加入 workspace 或 project，使其能构建出 FBDeviceControl 及其依赖（例如 FBControlCore/FBFuture 等，按实际依赖树补全）。

> 注意：FBDeviceControl 多为 ObjC，Swift 侧通过桥接封装隔离。

------

### 3. 代码落点（必须按工程风格放文件）

#### 3.1 新增目录：iOS 设备增强（放在现有 Core 下）

在 `ScreenPresenter/Core/DeviceDiscovery/` 新增：

```
FBDeviceControlBridge/
  FBDeviceControlBridge.h
  FBDeviceControlBridge.mm
  FBDeviceInfoDTO.swift
  FBDeviceStateDTO.swift
```

桥接层职责：

- ObjC++ 内部 `@import FBDeviceControl;`
- 暴露 Swift 可调用的最小 API（不要把 FBDeviceControl 类型抛到 Swift/UI）
- 输出纯 Swift DTO（字典或 struct 均可）

桥接层必须提供：

1. `listDevices() -> [FBDeviceInfoDTO]`
2. `fetchDeviceInfo(udid) -> FBDeviceInfoDTO`
3. `startObserving(callback)` 或者由 Swift polling（任选其一，但要实现 observeDevices 的效果）

DTO 字段建议：

- udid, deviceName, productVersion, productType, buildVersion, connectionType
- rawErrorDomain/rawErrorCode（若失败）
- rawStatusHint（字符串，用于 debug）

#### 3.2 扩展现有 IOSDevice 模型（最小侵入）

修改 `ScreenPresenter/Core/DeviceDiscovery/IOSDevice.swift`：

新增字段（可选值即可）：

- `deviceName`
- `productVersion`
- `productType`
- `buildVersion`
- `state: IOSDevice.State`（新增 enum）
- `lastSeenAt`

并实现 `displayTitle`/`subtitle` 这类 UI 友好字段（现在 `DeviceModel.swift` 里如果有也可放那边）。

#### 3.3 改造 IOSDeviceProvider：双层数据源合并

修改 `ScreenPresenter/Core/DeviceDiscovery/IOSDeviceProvider.swift`：

现状可能只做“可投屏 iOS 设备发现”（例如 Continuity/屏幕镜像入口、或简单枚举）。
现在要求：

- 保留现有发现逻辑（不要破坏投屏功能）
- 新增 FBDeviceControl 的设备信息补全：
  - 以现有 iOS 设备列表为基准
  - 对每台设备尝试用 `udid` 进行 enrich
  - enrich 不成功也不能丢设备，只是 state 变成 unavailable

必须实现：

- `refresh()`：返回 `[IOSDevice]`（带上 enrich 后的信息）
- `observe()`：异步流/回调，把变化推给 `AppState`

#### 3.4 新增状态映射器（强制）

在 `ScreenPresenter/Core/DeviceDiscovery/` 新增：

```
IOSDeviceStateMapper.swift
```

将桥接层的 error domain/code/hint 映射为 `IOSDevice.State`：

- notTrusted：提示「在 iPhone 上点击‘信任此电脑’」
- locked：提示「请解锁 iPhone」
- developerModeOff：提示「请在设置中开启开发者模式（Developer Mode）」
- busy：提示「设备繁忙，稍后重试」
- unavailable：展示简短 reason（带 error code 便于排查）

要求：映射必须集中统一，禁止 UI 层自己猜。

#### 3.5 DeviceInsightService：统一查询入口

修改 `ScreenPresenter/Core/DeviceInsight/DeviceInsightService.swift`：

新增能力：

- 输入 `IOSDevice` 或 `udid` → 输出完整 `DeviceInsight`（包含上面字段与状态）
- 做缓存（避免 UI 每帧刷新都触发底层查询）
- 提供 `refresh(udid)` 与 `refreshAll()`，用于 UI 的“刷新”按钮

------

### 4. UI 接入（对齐现在的 View 结构）

#### 4.1 DeviceModel 扩展

修改 `ScreenPresenter/Views/Components/DeviceModel.swift`：

- 为 iOS 设备新增展示字段：iOS 版本、机型标识、build、状态 badge 文案
- 增加状态颜色/图标（若已有 `Colors.swift` 就复用）

#### 4.2 DevicePanelView 展示与交互

修改 `ScreenPresenter/Views/Components/DevicePanelView.swift`：

列表每行 iOS 设备展示：

- 第一行：`deviceName`（fallback：已有的名称）
- 第二行：`iOS \(productVersion)` + `productType` + `(\(buildVersion))`
- 右侧：状态 badge（available / locked / notTrusted / …）

并支持：

- “刷新设备信息”按钮（调用 `DeviceInsightService.refreshAll()` 或 provider refresh）
- 对于 notTrusted/locked/developerModeOff：点击设备时弹 toast/提示（已有 `ToastView.swift`）

**注意**：无设备/信息缺失时 UI 必须优雅降级，不许崩。

------

### 5. AppState 接线（让数据真的流起来）

修改 `ScreenPresenter/Core/AppState.swift`：

- 增加 `@Published var iosDevices: [IOSDevice]`（如果已有则复用）
- 在 app 启动时初始化并启动：
  - `IOSDeviceProvider.observe()` 订阅
  - 将更新写入 `AppState`

App 启动入口在 `ScreenPresenter/AppDelegate.swift` 或 `main.swift`，按当前架构放置（不要引入全新 DI 框架，保持现有风格）。

------

### 6. 并发与性能要求（硬性）

- 底层 FBDeviceControl 调用不得阻塞主线程
- polling 若存在：1~2 秒即可，必须 diff，变化才推 UI
- refresh 同一 udid 必须串行化（避免并发打爆 MobileDevice session）
- 所有后台任务支持取消（例如 view 消失/应用退出）

------

### 7. 交付物（输出格式要求）

请输出：

1. 需要新增/修改的文件清单（按工程路径）
2. 每个文件的完整代码（能编译为主；若某些 FBDeviceControl API 需从源码确认，可用 `TODO(VERIFY_API)` 标注并写清“去哪个 header 查哪个符号”）
3. 一个简短 Mermaid 图：`IOSDeviceProvider -> DeviceInsightService -> AppState -> DevicePanelView` 的数据流
4. `README` 增补段落：如何引入 ThirdParty/idb、构建 FBDeviceControl、运行前置条件（信任/解锁/Developer Mode）与常见排错提示

禁止输出长篇科普。

------

### 8. 验收标准（必须逐条满足）

- 插入 1 台 iPhone（USB）：iOS 列表出现，能显示 deviceName/iOS版本/productType/buildVersion
- 锁屏：状态变 locked，UI 提示“请解锁 iPhone”
- 未信任：状态变 notTrusted，UI 提示“在 iPhone 上点信任”
- 拔设备：列表实时移除或状态变 unavailable（按当前策略），不会崩
- 全程无明显卡顿（Metal 渲染不受影响）