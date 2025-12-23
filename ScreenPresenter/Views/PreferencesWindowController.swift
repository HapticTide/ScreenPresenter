//
//  PreferencesWindowController.swift
//  ScreenPresenter
//
//  Created by Sun on 2025/12/22.
//
//  偏好设置窗口控制器
//  包含四个 Tab：
//  - 通用（语言、外观、布局、连接）
//  - 捕获（帧率设置）
//  - Scrcpy（视频、显示、高级）
//  - 权限（系统权限、工具链）
//

import AppKit
import SnapKit

// MARK: - 偏好设置窗口控制器

final class PreferencesWindowController: NSWindowController {
    // MARK: - 单例

    static let shared: PreferencesWindowController = {
        let controller = PreferencesWindowController()
        return controller
    }()

    // MARK: - 初始化

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 480),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = L10n.window.preferences
        window.titlebarSeparatorStyle = .none
        window.center()

        self.init(window: window)

        window.contentViewController = PreferencesViewController()
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        window?.center()
        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: - 偏好设置视图控制器

final class PreferencesViewController: NSViewController {
    // MARK: - UI 组件

    private var tabView: NSTabView!

    // MARK: - 生命周期

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 520, height: 450))
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
    }

    // MARK: - UI 设置

    private func setupUI() {
        tabView = NSTabView()
        view.addSubview(tabView)
        tabView.snp.makeConstraints { make in
            make.edges.equalToSuperview().inset(8)
        }

        // 通用设置标签页
        let generalTab = NSTabViewItem(identifier: "general")
        generalTab.label = L10n.prefs.tab.general
        generalTab.view = createGeneralView()
        tabView.addTabViewItem(generalTab)

        // 捕获设置标签页
        let captureTab = NSTabViewItem(identifier: "capture")
        captureTab.label = L10n.prefs.tab.capture
        captureTab.view = createCaptureView()
        tabView.addTabViewItem(captureTab)

        // Scrcpy 设置标签页
        let scrcpyTab = NSTabViewItem(identifier: "scrcpy")
        scrcpyTab.label = L10n.prefs.tab.scrcpy
        scrcpyTab.view = createScrcpyView()
        tabView.addTabViewItem(scrcpyTab)

        // 权限标签页
        let permissionsTab = NSTabViewItem(identifier: "permissions")
        permissionsTab.label = L10n.prefs.tab.permissions
        permissionsTab.view = createPermissionsView()
        tabView.addTabViewItem(permissionsTab)
    }

    // MARK: - 通用设置

    private func createGeneralView() -> NSView {
        let scrollView = createScrollView()
        let stackView = createVerticalStack()

        // 语言设置组
        let languageGroup = createSettingsGroup(title: L10n.prefs.section.language, icon: "globe")
        languageGroup.addArrangedSubview(createLabeledRow(label: L10n.prefs.general.language) {
            let popup = NSPopUpButton()
            for language in AppLanguage.allCases {
                popup.addItem(withTitle: language.nativeName)
            }
            let currentIndex = AppLanguage.allCases.firstIndex(of: LocalizationManager.shared.currentLanguage) ?? 0
            popup.selectItem(at: currentIndex)
            popup.target = self
            popup.action = #selector(languageChanged(_:))
            return popup
        })
        let languageNote = NSTextField(labelWithString: L10n.prefs.general.languageNote)
        languageNote.font = NSFont.systemFont(ofSize: 11)
        languageNote.textColor = .secondaryLabelColor
        languageGroup.addArrangedSubview(languageNote)
        stackView.addArrangedSubview(languageGroup)

        // 外观设置组
        let appearanceGroup = createSettingsGroup(title: L10n.prefs.section.appearance, icon: "paintbrush")
        appearanceGroup.addArrangedSubview(createLabeledRow(label: L10n.prefs.appearance.backgroundOpacity) {
            let stack = NSStackView()
            stack.orientation = .horizontal
            stack.spacing = 8

            let slider = NSSlider(
                value: UserPreferences.shared.backgroundOpacity,
                minValue: 0,
                maxValue: 1,
                target: self,
                action: #selector(backgroundOpacityChanged(_:))
            )
            slider.snp.makeConstraints { make in
                make.width.equalTo(150)
            }
            stack.addArrangedSubview(slider)

            let valueLabel = NSTextField(labelWithString: String(
                format: "%.0f%%",
                UserPreferences.shared.backgroundOpacity * 100
            ))
            valueLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
            valueLabel.tag = 1001 // 用于后续更新
            stack.addArrangedSubview(valueLabel)

            return stack
        })
        stackView.addArrangedSubview(appearanceGroup)

        // 布局设置组
        let layoutGroup = createSettingsGroup(title: L10n.prefs.section.layout, icon: "rectangle.split.2x1")
        layoutGroup.addArrangedSubview(createLabeledRow(label: L10n.prefs.layoutPref.defaultLayout) {
            let segmented = NSSegmentedControl(
                labels: [L10n.prefs.layoutPref.sideBySide, L10n.prefs.layoutPref.topBottom],
                trackingMode: .selectOne,
                target: nil,
                action: nil
            )
            segmented.selectedSegment = UserPreferences.shared.defaultLayout == .sideBySide ? 0 : 1
            return segmented
        })
        stackView.addArrangedSubview(layoutGroup)

        // 连接设置组
        let connectionGroup = createSettingsGroup(title: L10n.prefs.section.connection, icon: "cable.connector")
        let autoReconnectCheckbox = NSButton(
            checkboxWithTitle: L10n.prefs.connectionPref.autoReconnect,
            target: nil,
            action: nil
        )
        autoReconnectCheckbox.state = UserPreferences.shared.autoReconnect ? .on : .off
        connectionGroup.addArrangedSubview(autoReconnectCheckbox)
        connectionGroup.addArrangedSubview(createLabeledRow(label: L10n.prefs.connectionPref.reconnectDelay) {
            let stack = NSStackView()
            stack.orientation = .horizontal
            stack.spacing = 8
            let stepper = NSStepper()
            stepper.minValue = 1
            stepper.maxValue = 30
            stepper.intValue = Int32(UserPreferences.shared.reconnectDelay)
            stack.addArrangedSubview(stepper)
            let label = NSTextField(labelWithString: L10n.prefs.connectionPref
                .seconds(Int(UserPreferences.shared.reconnectDelay)))
            stack.addArrangedSubview(label)
            return stack
        })
        connectionGroup.addArrangedSubview(createLabeledRow(label: L10n.prefs.connectionPref.maxAttempts) {
            let stack = NSStackView()
            stack.orientation = .horizontal
            stack.spacing = 8
            let stepper = NSStepper()
            stepper.minValue = 1
            stepper.maxValue = 20
            stepper.intValue = Int32(UserPreferences.shared.maxReconnectAttempts)
            stack.addArrangedSubview(stepper)
            let label = NSTextField(labelWithString: L10n.prefs.connectionPref
                .times(UserPreferences.shared.maxReconnectAttempts))
            stack.addArrangedSubview(label)
            return stack
        })
        stackView.addArrangedSubview(connectionGroup)

        // 底部空间
        stackView.addArrangedSubview(NSView())

        scrollView.documentView = stackView
        setupScrollViewConstraints(scrollView: scrollView, contentView: stackView)
        return scrollView
    }

    // MARK: - 捕获设置

    private func createCaptureView() -> NSView {
        let scrollView = createScrollView()
        let stackView = createVerticalStack()

        // 帧率设置组
        let frameRateGroup = createSettingsGroup(title: L10n.prefs.section.frameRate, icon: "speedometer")
        frameRateGroup.addArrangedSubview(createLabeledRow(label: L10n.prefs.capturePref.frameRate) {
            let segmented = NSSegmentedControl(
                labels: ["30 FPS", "60 FPS", "120 FPS"],
                trackingMode: .selectOne,
                target: nil,
                action: nil
            )
            switch UserPreferences.shared.captureFrameRate {
            case 30: segmented.selectedSegment = 0
            case 60: segmented.selectedSegment = 1
            default: segmented.selectedSegment = 2
            }
            return segmented
        })
        let note = NSTextField(labelWithString: L10n.prefs.capturePref.frameRateNote)
        note.font = NSFont.systemFont(ofSize: 11)
        note.textColor = .secondaryLabelColor
        frameRateGroup.addArrangedSubview(note)
        stackView.addArrangedSubview(frameRateGroup)

        stackView.addArrangedSubview(NSView())

        scrollView.documentView = stackView
        setupScrollViewConstraints(scrollView: scrollView, contentView: stackView)
        return scrollView
    }

    // MARK: - Scrcpy 设置

    private func createScrcpyView() -> NSView {
        let scrollView = createScrollView()
        let stackView = createVerticalStack()

        // 视频设置组
        let videoGroup = createSettingsGroup(title: L10n.prefs.section.video, icon: "video")
        videoGroup.addArrangedSubview(createLabeledRow(label: L10n.prefs.scrcpyPref.bitrate) {
            let popup = NSPopUpButton()
            popup.addItems(withTitles: [
                L10n.prefs.scrcpyPref.mbps(4),
                L10n.prefs.scrcpyPref.mbps(8),
                L10n.prefs.scrcpyPref.mbps(16),
                L10n.prefs.scrcpyPref.mbps(32),
            ])
            switch UserPreferences.shared.scrcpyBitrate {
            case 4: popup.selectItem(at: 0)
            case 8: popup.selectItem(at: 1)
            case 16: popup.selectItem(at: 2)
            default: popup.selectItem(at: 3)
            }
            return popup
        })
        videoGroup.addArrangedSubview(createLabeledRow(label: L10n.prefs.scrcpyPref.maxSize) {
            let popup = NSPopUpButton()
            popup.addItems(withTitles: [
                L10n.prefs.scrcpyPref.noLimit,
                L10n.prefs.scrcpyPref.pixels(1280),
                L10n.prefs.scrcpyPref.pixels(1920),
                L10n.prefs.scrcpyPref.pixels(2560),
            ])
            switch UserPreferences.shared.scrcpyMaxSize {
            case 0: popup.selectItem(at: 0)
            case 1280: popup.selectItem(at: 1)
            case 1920: popup.selectItem(at: 2)
            default: popup.selectItem(at: 3)
            }
            return popup
        })
        let videoNote = NSTextField(labelWithString: L10n.prefs.scrcpyPref.maxSizeNote)
        videoNote.font = NSFont.systemFont(ofSize: 11)
        videoNote.textColor = .secondaryLabelColor
        videoGroup.addArrangedSubview(videoNote)
        stackView.addArrangedSubview(videoGroup)

        // 显示设置组
        let displayGroup = createSettingsGroup(title: L10n.prefs.section.display, icon: "hand.tap")
        let showTouchesCheckbox = NSButton(
            checkboxWithTitle: L10n.prefs.scrcpyPref.showTouches,
            target: nil,
            action: nil
        )
        showTouchesCheckbox.state = UserPreferences.shared.scrcpyShowTouches ? .on : .off
        displayGroup.addArrangedSubview(showTouchesCheckbox)
        stackView.addArrangedSubview(displayGroup)

        // 高级设置组
        let advancedGroup = createSettingsGroup(title: L10n.prefs.section.advanced, icon: "gearshape.2")
        let advancedNote = NSTextField(labelWithString: L10n.prefs.scrcpyPref.advancedNote)
        advancedNote.font = NSFont.systemFont(ofSize: 11)
        advancedNote.textColor = .secondaryLabelColor
        advancedGroup.addArrangedSubview(advancedNote)
        let linkButton = NSButton(
            title: L10n.prefs.scrcpyPref.github,
            target: self,
            action: #selector(openScrcpyGitHub)
        )
        linkButton.bezelStyle = .inline
        advancedGroup.addArrangedSubview(linkButton)
        stackView.addArrangedSubview(advancedGroup)

        stackView.addArrangedSubview(NSView())

        scrollView.documentView = stackView
        setupScrollViewConstraints(scrollView: scrollView, contentView: stackView)
        return scrollView
    }

    // MARK: - 权限设置

    private func createPermissionsView() -> NSView {
        let scrollView = createScrollView()
        let stackView = createVerticalStack()

        // 系统权限组
        let systemPermGroup = createSettingsGroup(title: L10n.prefs.section.systemPermissions, icon: "lock.shield")
        systemPermGroup.addArrangedSubview(createPermissionRow(
            name: L10n.permission.screenRecordingName,
            description: L10n.permission.screenRecordingDesc,
            permissionType: .screenRecording
        ))
        stackView.addArrangedSubview(systemPermGroup)

        // Android 工具链组
        let toolchainGroup = createSettingsGroup(title: L10n.prefs.section.androidToolchain, icon: "apps.iphone")
        toolchainGroup.addArrangedSubview(createToolchainRow(name: "adb", description: L10n.prefs.toolchain.adbDesc))
        let divider = NSBox()
        divider.boxType = .separator
        toolchainGroup.addArrangedSubview(divider)
        toolchainGroup.addArrangedSubview(createToolchainRow(
            name: "scrcpy",
            description: L10n.prefs.toolchain.scrcpyDesc
        ))
        stackView.addArrangedSubview(toolchainGroup)

        // 刷新按钮
        let refreshButton = NSButton(
            title: L10n.prefs.toolchain.refreshStatus,
            target: self,
            action: #selector(refreshToolchain)
        )
        refreshButton.bezelStyle = .rounded
        refreshButton.image = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: nil)
        refreshButton.imagePosition = .imageLeading
        let buttonContainer = NSStackView()
        buttonContainer.orientation = .horizontal
        buttonContainer.addArrangedSubview(NSView()) // 占位
        buttonContainer.addArrangedSubview(refreshButton)
        stackView.addArrangedSubview(buttonContainer)

        stackView.addArrangedSubview(NSView())

        scrollView.documentView = stackView
        setupScrollViewConstraints(scrollView: scrollView, contentView: stackView)
        return scrollView
    }

    // MARK: - 辅助方法

    private func createScrollView() -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        return scrollView
    }

    private func createVerticalStack() -> NSStackView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 16
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        return stack
    }

    private func setupScrollViewConstraints(scrollView: NSScrollView, contentView: NSStackView) {
        guard let documentView = scrollView.documentView else { return }
        documentView.snp.makeConstraints { make in
            make.leading.trailing.top.equalTo(scrollView.contentView)
            make.width.equalTo(scrollView.contentView)
        }
    }

    private func createSettingsGroup(title: String, icon: String) -> NSStackView {
        let groupStack = NSStackView()
        groupStack.orientation = .vertical
        groupStack.alignment = .leading
        groupStack.spacing = 12

        // 标题行
        let titleStack = NSStackView()
        titleStack.orientation = .horizontal
        titleStack.spacing = 6
        let iconView = NSImageView()
        iconView.image = NSImage(systemSymbolName: icon, accessibilityDescription: nil)
        iconView.contentTintColor = .labelColor
        iconView.snp.makeConstraints { make in
            make.size.equalTo(16)
        }
        titleStack.addArrangedSubview(iconView)
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        titleStack.addArrangedSubview(titleLabel)
        groupStack.addArrangedSubview(titleStack)

        // 内容容器
        let contentBox = NSStackView()
        contentBox.orientation = .vertical
        contentBox.alignment = .leading
        contentBox.spacing = 10
        contentBox.wantsLayer = true
        contentBox.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        contentBox.layer?.cornerRadius = 8
        contentBox.edgeInsets = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        contentBox.snp.makeConstraints { make in
            make.width.equalTo(440).priority(.high)
        }
        groupStack.addArrangedSubview(contentBox)

        return contentBox
    }

    private func createLabeledRow(label: String, controlBuilder: () -> NSView) -> NSStackView {
        let rowStack = NSStackView()
        rowStack.orientation = .horizontal
        rowStack.alignment = .centerY
        rowStack.spacing = 12

        let labelView = NSTextField(labelWithString: label)
        labelView.font = NSFont.systemFont(ofSize: 13)
        labelView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        labelView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        labelView.snp.makeConstraints { make in
            make.width.equalTo(100).priority(.high)
        }
        rowStack.addArrangedSubview(labelView)

        let control = controlBuilder()
        rowStack.addArrangedSubview(control)

        return rowStack
    }

    private func createToolchainRow(name: String, description: String) -> NSStackView {
        let rowStack = NSStackView()
        rowStack.orientation = .horizontal
        rowStack.alignment = .centerY
        rowStack.spacing = 8

        // 状态图标
        let statusIcon = NSImageView()
        statusIcon.image = NSImage(systemSymbolName: "circle", accessibilityDescription: nil)
        statusIcon.contentTintColor = .secondaryLabelColor
        statusIcon.snp.makeConstraints { make in
            make.size.equalTo(18)
        }
        rowStack.addArrangedSubview(statusIcon)

        // 名称和描述
        let infoStack = NSStackView()
        infoStack.orientation = .vertical
        infoStack.alignment = .leading
        infoStack.spacing = 2
        let nameLabel = NSTextField(labelWithString: name)
        nameLabel.font = NSFont.systemFont(ofSize: 13)
        infoStack.addArrangedSubview(nameLabel)
        let descLabel = NSTextField(labelWithString: description)
        descLabel.font = NSFont.systemFont(ofSize: 11)
        descLabel.textColor = .secondaryLabelColor
        infoStack.addArrangedSubview(descLabel)
        infoStack.snp.makeConstraints { make in
            make.width.equalTo(200).priority(.high)
        }
        rowStack.addArrangedSubview(infoStack)

        // 占位
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        rowStack.addArrangedSubview(spacer)

        // 状态文本
        let statusLabel = NSTextField(labelWithString: L10n.common.checking)
        statusLabel.font = NSFont.systemFont(ofSize: 11)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.alignment = .right
        rowStack.addArrangedSubview(statusLabel)

        // 更新状态
        Task { @MainActor in
            let toolchain = AppState.shared.toolchainManager
            let status: ToolchainStatus
            let version: String

            if name == "adb" {
                status = toolchain.adbStatus
                version = toolchain.adbVersionDescription
            } else {
                status = toolchain.scrcpyStatus
                version = toolchain.scrcpyVersionDescription
            }

            switch status {
            case .installed:
                statusIcon.image = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: nil)
                statusIcon.contentTintColor = .systemGreen
                statusLabel.stringValue = version
                statusLabel.textColor = .systemGreen
            case .notInstalled:
                statusIcon.image = NSImage(systemSymbolName: "xmark.circle", accessibilityDescription: nil)
                statusIcon.contentTintColor = .systemOrange
                statusLabel.stringValue = L10n.prefs.toolchain.notInstalled
                statusLabel.textColor = .systemOrange
            case .installing:
                statusIcon.image = NSImage(systemSymbolName: "arrow.down.circle", accessibilityDescription: nil)
                statusIcon.contentTintColor = .systemBlue
                statusLabel.stringValue = L10n.common.checking
            case let .error(message):
                statusIcon.image = NSImage(
                    systemSymbolName: "exclamationmark.circle.fill",
                    accessibilityDescription: nil
                )
                statusIcon.contentTintColor = .systemRed
                statusLabel.stringValue = message
                statusLabel.textColor = .systemRed
            }
        }

        return rowStack
    }

    private enum PermissionType {
        case screenRecording
    }

    private func createPermissionRow(name: String, description: String, permissionType: PermissionType) -> NSStackView {
        let rowStack = NSStackView()
        rowStack.orientation = .horizontal
        rowStack.alignment = .centerY
        rowStack.spacing = 8

        // 状态图标
        let statusIcon = NSImageView()
        statusIcon.image = NSImage(systemSymbolName: "circle", accessibilityDescription: nil)
        statusIcon.contentTintColor = .secondaryLabelColor
        statusIcon.snp.makeConstraints { make in
            make.size.equalTo(18)
        }
        rowStack.addArrangedSubview(statusIcon)

        // 名称和描述
        let infoStack = NSStackView()
        infoStack.orientation = .vertical
        infoStack.alignment = .leading
        infoStack.spacing = 2
        let nameLabel = NSTextField(labelWithString: name)
        nameLabel.font = NSFont.systemFont(ofSize: 13)
        infoStack.addArrangedSubview(nameLabel)
        let descLabel = NSTextField(labelWithString: description)
        descLabel.font = NSFont.systemFont(ofSize: 11)
        descLabel.textColor = .secondaryLabelColor
        infoStack.addArrangedSubview(descLabel)
        rowStack.addArrangedSubview(infoStack)

        // 占位
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        rowStack.addArrangedSubview(spacer)

        // 状态文本
        let statusLabel = NSTextField(labelWithString: L10n.common.checking)
        statusLabel.font = NSFont.systemFont(ofSize: 11)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.alignment = .right
        rowStack.addArrangedSubview(statusLabel)

        // 打开设置按钮
        let openButton = NSButton(
            title: L10n.permission.openSystemPrefs,
            target: self,
            action: #selector(openSystemPreferences(_:))
        )
        openButton.bezelStyle = .rounded
        openButton.controlSize = .small
        openButton.tag = permissionType == .screenRecording ? 0 : 1
        rowStack.addArrangedSubview(openButton)

        // 检查权限状态
        Task { @MainActor in
            let granted = checkScreenRecordingPermission()
            if granted {
                statusIcon.image = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: nil)
                statusIcon.contentTintColor = .systemGreen
                statusLabel.stringValue = L10n.permission.granted
                statusLabel.textColor = .systemGreen
            } else {
                statusIcon.image = NSImage(systemSymbolName: "xmark.circle", accessibilityDescription: nil)
                statusIcon.contentTintColor = .systemOrange
                statusLabel.stringValue = L10n.permission.denied
                statusLabel.textColor = .systemOrange
            }
        }

        return rowStack
    }

    private func checkScreenRecordingPermission() -> Bool {
        // 检查屏幕录制权限
        // 通过尝试获取窗口列表来判断是否有权限
        let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]]
        return windowList != nil && !windowList!.isEmpty
    }

    // MARK: - 操作

    @objc private func languageChanged(_ sender: NSPopUpButton) {
        let index = sender.indexOfSelectedItem
        guard index >= 0, index < AppLanguage.allCases.count else { return }
        let language = AppLanguage.allCases[index]
        LocalizationManager.shared.setLanguage(language)
    }

    @objc private func backgroundOpacityChanged(_ sender: NSSlider) {
        UserPreferences.shared.backgroundOpacity = CGFloat(sender.doubleValue)

        // 更新标签显示
        if let valueLabel = sender.superview?.subviews.first(where: { $0.tag == 1001 }) as? NSTextField {
            valueLabel.stringValue = String(format: "%.0f%%", sender.doubleValue * 100)
        }

        // 发送通知更新背景色
        NotificationCenter.default.post(name: .backgroundColorDidChange, object: nil)
    }

    @objc private func refreshToolchain() {
        Task {
            await AppState.shared.toolchainManager.refresh()
        }
    }

    @objc private func openScrcpyGitHub() {
        if let url = URL(string: "https://github.com/Genymobile/scrcpy") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func openSystemPreferences(_ sender: NSButton) {
        // 打开系统偏好设置 - 隐私 - 屏幕录制
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: - 通知名称

extension Notification.Name {
    static let backgroundColorDidChange = Notification.Name("backgroundColorDidChange")
}
