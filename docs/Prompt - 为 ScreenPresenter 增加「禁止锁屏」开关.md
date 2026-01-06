## Prompt：为 ScreenPresenter 增加「禁止锁屏」开关（Toolbar + 偏好设置 + 捕获会话联动）

你正在为 macOS App **ScreenPresenter** 增加一个用户可控的设置：**"捕获期间禁止自动锁屏/休眠"**。该设置需要同时出现在：

1. **主窗口工具栏（NSToolbar）** —— 作为一个可快速切换的按钮
2. **偏好设置窗口（PreferencesWindowController）** —— 作为持久化设置项

并且两处 UI 必须绑定同一份状态，做到**双向同步**和**跨窗口一致**。

------

### 一、项目现状分析

#### 1.1 架构概览

```
ScreenPresenter/
├── AppDelegate.swift              # 应用入口，已有 Toolbar 实现
├── Core/
│   ├── AppState.swift             # 全局状态单例，管理设备与捕获
│   ├── Preferences/
│   │   └── UserPreferences.swift  # 已有设置类，使用 UserDefaults
│   ├── DeviceSource/              # 设备源：iOS/Android 捕获
│   └── Utilities/
│       └── Logger.swift           # 日志框架 AppLogger
└── Views/
    ├── MainViewController.swift
    └── PreferencesWindowController.swift  # 已有偏好设置窗口（AppKit）
```

#### 1.2 现有模式

- **设置管理**：`UserPreferences.shared`（单例 + UserDefaults）
- **工具栏**：`AppDelegate` 实现 `NSToolbarDelegate`，已有 `refresh`、`toggleBezel`、`preferences`、`layoutMode` 等按钮
- **偏好设置**：`PreferencesWindowController`（AppKit 实现，非 SwiftUI Settings Scene）
- **状态通知**：使用 `NotificationCenter`（如 `.deviceBezelVisibilityDidChange`）
- **日志**：`AppLogger.app`、`AppLogger.device` 等分类日志

#### 1.3 捕获状态判断

- `AppState.shared.iosCapturing` → iOS 是否正在捕获
- `AppState.shared.androidCapturing` → Android 是否正在捕获
- 源状态：`DeviceSourceState.capturing`

------

### 二、行为定义

| 项目 | 值 |
|------|-----|
| **设置项名称** | `preventAutoLockDuringCapture` |
| **显示名称** | 捕获期间禁止自动锁屏 |
| **英文** | Prevent Auto-Lock During Capture |
| **默认值** | `true` |
| **UserDefaults Key** | `"preventAutoLockDuringCapture"` |

**行为规则**：
- 当开关为 `ON` 且 **任一设备正在捕获**（`iosCapturing || androidCapturing`）时：
  - 调用 `SystemSleepBlocker.shared.enable(reason:)`
- 当开关为 `OFF` 或**无设备捕获**时：
  - 调用 `SystemSleepBlocker.shared.disable()`

> ⚠️ 该功能仅阻止**自动**锁屏/休眠，不阻止用户手动锁屏（⌘+Ctrl+Q）。

------

### 三、架构要求：复用现有模式

#### 3.1 扩展 UserPreferences

在 `Core/Preferences/UserPreferences.swift` 中新增属性：

```swift
// MARK: - Keys（追加）
private enum Keys {
    // ...existing keys...
    static let preventAutoLockDuringCapture = "preventAutoLockDuringCapture"
}

// MARK: - Power Settings（新增 section）

/// 捕获期间禁止自动锁屏（默认 true）
var preventAutoLockDuringCapture: Bool {
    get {
        if defaults.object(forKey: Keys.preventAutoLockDuringCapture) == nil {
            return true  // 默认启用
        }
        return defaults.bool(forKey: Keys.preventAutoLockDuringCapture)
    }
    set {
        defaults.set(newValue, forKey: Keys.preventAutoLockDuringCapture)
        NotificationCenter.default.post(name: .preventAutoLockSettingDidChange, object: nil)
    }
}
```

#### 3.2 新增 Notification Name

在 `Core/Utilities/` 或 `UserPreferences.swift` 底部追加：

```swift
extension Notification.Name {
    static let preventAutoLockSettingDidChange = Notification.Name("preventAutoLockSettingDidChange")
}
```

------

### 四、SystemSleepBlocker 实现

新建文件：`Core/Utilities/SystemSleepBlocker.swift`

```swift
//
//  SystemSleepBlocker.swift
//  ScreenPresenter
//
//  禁止系统自动休眠/锁屏
//  使用 IOKit 的 IOPMAssertion API
//

import Foundation
import IOKit.pwr_mgt

/// 系统休眠阻止器
final class SystemSleepBlocker {
    
    // MARK: - Singleton
    
    static let shared = SystemSleepBlocker()
    
    private init() {}
    
    // MARK: - Properties
    
    /// 当前 assertion ID（0 表示未激活）
    private var assertionID: IOPMAssertionID = 0
    
    /// 是否已启用
    private(set) var isEnabled: Bool = false
    
    // MARK: - Public Methods
    
    /// 启用休眠阻止
    /// - Parameter reason: 阻止原因（显示在 Activity Monitor 中）
    func enable(reason: String = "ScreenPresenter capturing screen") {
        // 幂等：已启用则不重复操作
        guard !isEnabled else {
            AppLogger.app.debug("SystemSleepBlocker 已处于启用状态，跳过")
            return
        }
        
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason as CFString,
            &assertionID
        )
        
        if result == kIOReturnSuccess {
            isEnabled = true
            AppLogger.app.info("SystemSleepBlocker 已启用: \(reason)")
        } else {
            AppLogger.app.error("SystemSleepBlocker 启用失败: \(result)")
        }
    }
    
    /// 禁用休眠阻止
    func disable() {
        // 幂等：未启用则不操作
        guard isEnabled, assertionID != 0 else {
            AppLogger.app.debug("SystemSleepBlocker 已处于禁用状态，跳过")
            return
        }
        
        let result = IOPMAssertionRelease(assertionID)
        
        if result == kIOReturnSuccess {
            isEnabled = false
            assertionID = 0
            AppLogger.app.info("SystemSleepBlocker 已禁用")
        } else {
            AppLogger.app.error("SystemSleepBlocker 禁用失败: \(result)")
        }
    }
}
```

------

### 五、CapturePowerCoordinator 实现

新建文件：`Core/Utilities/CapturePowerCoordinator.swift`

负责监听设置变化与捕获状态，协调 `SystemSleepBlocker`。

```swift
//
//  CapturePowerCoordinator.swift
//  ScreenPresenter
//
//  协调捕获状态与休眠阻止
//

import Combine
import Foundation

/// 捕获电源协调器
/// 监听设置与捕获状态，自动管理 SystemSleepBlocker
@MainActor
final class CapturePowerCoordinator {
    
    // MARK: - Singleton
    
    static let shared = CapturePowerCoordinator()
    
    // MARK: - Properties
    
    private var cancellables = Set<AnyCancellable>()
    private let blocker = SystemSleepBlocker.shared
    private let preferences = UserPreferences.shared
    
    // MARK: - Init
    
    private init() {
        setupObservers()
    }
    
    // MARK: - Setup
    
    private func setupObservers() {
        // 监听设置变化
        NotificationCenter.default.publisher(for: .preventAutoLockSettingDidChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.evaluateAndUpdate()
            }
            .store(in: &cancellables)
        
        // 监听 AppState 状态变化（包含捕获状态变化）
        AppState.shared.stateChangedPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                self?.evaluateAndUpdate()
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Core Logic
    
    /// 评估当前状态并更新 blocker
    func evaluateAndUpdate() {
        let shouldBlock = preferences.preventAutoLockDuringCapture && isAnyDeviceCapturing
        
        if shouldBlock {
            blocker.enable(reason: "ScreenPresenter 正在捕获画面")
        } else {
            blocker.disable()
        }
    }
    
    /// 是否有任一设备正在捕获
    private var isAnyDeviceCapturing: Bool {
        AppState.shared.iosCapturing || AppState.shared.androidCapturing
    }
    
    // MARK: - Lifecycle
    
    /// 应用启动时调用
    func start() {
        evaluateAndUpdate()
        AppLogger.app.info("CapturePowerCoordinator 已启动")
    }
    
    /// 应用退出时调用
    func stop() {
        blocker.disable()
        AppLogger.app.info("CapturePowerCoordinator 已停止")
    }
}
```

------

### 六、Toolbar 按钮实现

#### 6.1 在 AppDelegate 中添加

```swift
// MARK: - Properties（追加）
private var preventSleepToolbarItem: NSToolbarItem?

// MARK: - ToolbarItemIdentifier（追加）
private enum ToolbarItemIdentifier {
    // ...existing identifiers...
    static let preventSleep = NSToolbarItem.Identifier("preventSleep")
}

// MARK: - toolbarDefaultItemIdentifiers（修改）
func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
    [
        ToolbarItemIdentifier.layoutMode,
        .flexibleSpace,
        ToolbarItemIdentifier.preventSleep,  // 新增
        ToolbarItemIdentifier.refresh,
        ToolbarItemIdentifier.toggleBezel,
        ToolbarItemIdentifier.preferences,
    ]
}

// MARK: - toolbar(_:itemForItemIdentifier:)（追加 case）
case ToolbarItemIdentifier.preventSleep:
    let item = NSToolbarItem(itemIdentifier: itemIdentifier)
    item.label = L10n.toolbar.preventSleep
    item.paletteLabel = L10n.toolbar.preventSleep
    item.toolTip = L10n.toolbar.preventSleepTooltip
    updatePreventSleepToolbarItemImage(item)
    item.target = self
    item.action = #selector(togglePreventSleep(_:))
    preventSleepToolbarItem = item
    return item

// MARK: - Actions（新增）
@IBAction func togglePreventSleep(_ sender: Any?) {
    UserPreferences.shared.preventAutoLockDuringCapture.toggle()
    if let item = preventSleepToolbarItem {
        updatePreventSleepToolbarItemImage(item)
    }
}

// MARK: - Helper（新增）
private func updatePreventSleepToolbarItemImage(_ item: NSToolbarItem) {
    let enabled = UserPreferences.shared.preventAutoLockDuringCapture
    // moon.zzz.fill = 阻止休眠（启用）；moon.zzz = 允许休眠（禁用）
    let symbolName = enabled ? "moon.zzz.fill" : "moon.zzz"
    item.image = NSImage(
        systemSymbolName: symbolName,
        accessibilityDescription: enabled ? L10n.toolbar.preventSleepOn : L10n.toolbar.preventSleepOff
    )
}

// MARK: - setupLanguageObserver（追加监听）
NotificationCenter.default.addObserver(
    self,
    selector: #selector(handlePreventSleepSettingChange),
    name: .preventAutoLockSettingDidChange,
    object: nil
)

@objc private func handlePreventSleepSettingChange() {
    if let item = preventSleepToolbarItem {
        updatePreventSleepToolbarItemImage(item)
    }
}
```

------

### 七、偏好设置 UI 实现

在 `PreferencesWindowController.swift` 的**通用（General）Tab** 中添加一行：

#### 7.1 定位插入点

在现有 `showDeviceBezel` 设置行附近（属于"显示设置"或单独一个"电源设置"分组）添加：

```swift
// MARK: - Power Settings Section

let preventSleepRow = createLabeledRow(
    label: L10n.preferences.preventAutoLock,
    control: createToggle(
        isOn: UserPreferences.shared.preventAutoLockDuringCapture,
        action: #selector(togglePreventAutoLock(_:))
    ),
    helpText: L10n.preferences.preventAutoLockHelp
)

@objc private func togglePreventAutoLock(_ sender: NSSwitch) {
    UserPreferences.shared.preventAutoLockDuringCapture = (sender.state == .on)
}
```

#### 7.2 监听外部变化更新 UI

```swift
// 在 viewDidLoad 或 init 中
NotificationCenter.default.addObserver(
    self,
    selector: #selector(handlePreventSleepSettingChange),
    name: .preventAutoLockSettingDidChange,
    object: nil
)

@objc private func handlePreventSleepSettingChange() {
    // 找到对应的 NSSwitch 并更新状态
    preventSleepSwitch?.state = UserPreferences.shared.preventAutoLockDuringCapture ? .on : .off
}
```

------

### 八、本地化字符串

在 `Core/Utilities/Localization.swift` 中追加：

```swift
// MARK: - Toolbar
enum toolbar {
    // ...existing...
    static var preventSleep: String { NSLocalizedString("toolbar.preventSleep", value: "防休眠", comment: "") }
    static var preventSleepTooltip: String { NSLocalizedString("toolbar.preventSleepTooltip", value: "捕获期间阻止系统自动休眠/锁屏", comment: "") }
    static var preventSleepOn: String { NSLocalizedString("toolbar.preventSleepOn", value: "防休眠已启用", comment: "") }
    static var preventSleepOff: String { NSLocalizedString("toolbar.preventSleepOff", value: "防休眠已禁用", comment: "") }
}

// MARK: - Preferences
enum preferences {
    // ...existing...
    static var preventAutoLock: String { NSLocalizedString("preferences.preventAutoLock", value: "捕获期间禁止自动锁屏", comment: "") }
    static var preventAutoLockHelp: String { NSLocalizedString("preferences.preventAutoLockHelp", value: "仅阻止系统自动休眠/锁屏，不影响手动锁屏", comment: "") }
}
```

------

### 九、集成到应用启动

在 `AppDelegate.applicationDidFinishLaunching(_:)` 中添加：

```swift
func applicationDidFinishLaunching(_ notification: Notification) {
    // ...existing code...
    
    // 启动捕获电源协调器
    CapturePowerCoordinator.shared.start()
    
    // ...existing code...
}

func applicationWillTerminate(_ notification: Notification) {
    // ...existing code...
    
    // 停止协调器（确保释放 assertion）
    CapturePowerCoordinator.shared.stop()
}
```

------

### 十、输出文件清单

| 文件 | 操作 |
|------|------|
| `Core/Utilities/SystemSleepBlocker.swift` | 新建 |
| `Core/Utilities/CapturePowerCoordinator.swift` | 新建 |
| `Core/Preferences/UserPreferences.swift` | 追加属性 + Key + Notification |
| `Core/Utilities/Localization.swift` | 追加本地化字符串 |
| `AppDelegate.swift` | 追加 Toolbar 按钮 + 集成协调器 |
| `Views/PreferencesWindowController.swift` | 追加设置行 |

------

### 十一、边界与注意事项

- ✅ 使用 `IOPMAssertionTypePreventUserIdleDisplaySleep`：阻止显示器自动休眠
- ✅ 不修改任何系统设置，仅在 app 运行期间生效
- ✅ 不阻止用户手动锁屏（⌘+Ctrl+Q）
- ✅ IOPMAssertion 在进程结束时自动回收
- ✅ 可在 Activity Monitor → Energy 中观察 "Preventing Sleep" 状态
- ✅ 幂等设计：`enable()` / `disable()` 重复调用安全

------

### 十二、代码质量约束

- Swift 5.9+（与项目一致）
- 遵循现有代码风格：单例模式、Combine 订阅、AppLogger 日志
- 业务逻辑不写在 ViewController 中
- 所有字符串使用 `L10n` 本地化
- Key 使用 enum 常量，不硬编码

------

### 十三、验证清单

- [ ] Toolbar 按钮点击后图标切换正确
- [ ] Preferences 中开关与 Toolbar 双向同步
- [ ] 开启开关后，开始捕获 → Activity Monitor 显示 "Preventing Sleep"
- [ ] 停止捕获 → "Preventing Sleep" 消失
- [ ] 关闭开关（即使捕获中）→ "Preventing Sleep" 立即消失
- [ ] 应用退出 → assertion 自动释放

现在开始实现，给出可直接落地的代码与集成点。
