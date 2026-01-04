//
//  ColorCompensationPanel.swift
//  ScreenPresenter
//
//  Created by Sun on 2026/1/4.
//
//  颜色补偿控制面板
//  UI 风格与偏好设置窗口保持一致
//

import AppKit
import Combine

// MARK: - 颜色补偿窗口控制器

/// 颜色补偿窗口控制器
/// 单例模式，风格与偏好设置窗口一致
final class ColorCompensationPanel: NSWindowController {
    // MARK: - 单例

    static let shared: ColorCompensationPanel = {
        let controller = ColorCompensationPanel()
        return controller
    }()

    // MARK: - 初始化

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 520),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = L10n.colorCompensation.title
        window.titlebarSeparatorStyle = .none
        window.titlebarAppearsTransparent = true
        window.center()
        window.initialFirstResponder = nil
        window.autorecalculatesKeyViewLoop = false
        window.isReleasedWhenClosed = false

        // 添加空 toolbar 以匹配主窗口风格
        let toolbar = NSToolbar(identifier: "ColorCompensationToolbar")
        toolbar.displayMode = .iconOnly
        toolbar.showsBaselineSeparator = false
        window.toolbar = toolbar

        self.init(window: window)

        window.contentViewController = ColorCompensationViewController()
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        window?.center()
        window?.makeFirstResponder(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// 切换显示/隐藏
    func togglePanel() {
        if window?.isVisible == true {
            close()
        } else {
            showWindow(nil)
        }
    }
}

// MARK: - 颜色补偿视图控制器

private final class ColorCompensationViewController: NSViewController {
    // MARK: - UI 组件

    private var contentContainer = NSView()
    private var scrollView: NSScrollView?
    private var stackView: CCStackContainerView?
    private let valueLabelFont = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)

    // MARK: - 设备选择器

    private var deviceSegmentedControl: NSSegmentedControl?
    private var modePopUp: NSPopUpButton?

    // MARK: - 滑块引用

    private var sliders: [String: NSSlider] = [:]
    private var valueLabels: [String: NSTextField] = [:]
    private var presetPopUp: NSPopUpButton?
    private var deletePresetButton: NSButton?
    private var enableSwitch: NSSwitch?

    // MARK: - A/B 对比控件

    private var compareSegmentedControl: NSSegmentedControl?
    private var isShowingOriginal: Bool = false

    // MARK: - 当前编辑目标

    /// 当前选中的设备（nil 表示全局设置）
    private var selectedDevice: DevicePlatform? = nil

    // MARK: - 属性

    private let manager = ColorProfileManager.shared
    private var cancellables = Set<AnyCancellable>()

    // MARK: - 滑块配置

    private struct SliderConfig {
        let key: String
        let title: String
        let minValue: Double
        let maxValue: Double
        let defaultValue: Double
        let format: String
    }

    private let sliderConfigs: [SliderConfig] = [
        SliderConfig(key: "gamma", title: "Gamma", minValue: 0.5, maxValue: 3.0, defaultValue: 1.0, format: "%.2f"),
        SliderConfig(key: "blackLift", title: L10n.colorCompensation.params.blackLift, minValue: -0.3, maxValue: 0.3, defaultValue: 0.0, format: "%+.3f"),
        SliderConfig(key: "whiteClip", title: L10n.colorCompensation.params.whiteClip, minValue: 0.7, maxValue: 1.0, defaultValue: 1.0, format: "%.3f"),
        SliderConfig(key: "highlightRollOff", title: L10n.colorCompensation.params.highlightRollOff, minValue: 0.0, maxValue: 0.5, defaultValue: 0.0, format: "%.3f"),
        SliderConfig(key: "temperature", title: L10n.colorCompensation.params.temperature, minValue: -1.0, maxValue: 1.0, defaultValue: 0.0, format: "%+.2f"),
        SliderConfig(key: "tint", title: L10n.colorCompensation.params.tint, minValue: -1.0, maxValue: 1.0, defaultValue: 0.0, format: "%+.2f"),
        SliderConfig(key: "saturation", title: L10n.colorCompensation.params.saturation, minValue: 0.0, maxValue: 2.0, defaultValue: 1.0, format: "%.2f")
    ]

    // MARK: - 生命周期

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 500))
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupBindings()
        updateUI()
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        updateScrollViewLayout()
    }

    // MARK: - UI 设置

    private func setupUI() {
        contentContainer.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(contentContainer)

        NSLayoutConstraint.activate([
            contentContainer.topAnchor.constraint(equalTo: view.topAnchor, constant: 52),
            contentContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            contentContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            contentContainer.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        scrollView = createScrollView()
        guard let scrollView = scrollView else { return }

        let documentView = CCFlippedView()
        scrollView.documentView = documentView

        stackView = CCStackContainerView()
        guard let stackView = stackView else { return }
        stackView.axis = .vertical
        stackView.alignment = .leading
        stackView.spacing = 20
        stackView.edgeInsets = NSEdgeInsets(top: 16, left: 20, bottom: 20, right: 20)
        stackView.fillsCrossAxis = true
        documentView.addSubview(stackView)

        // 设备选择组
        let deviceGroup = createSettingsGroup(title: L10n.colorCompensation.deviceSelector, icon: "rectangle.on.rectangle")
        addGroupRow(deviceGroup, createDeviceSelectorRow())
        addGroupRow(deviceGroup, createDeviceModeRow())
        addSettingsGroup(deviceGroup, to: stackView)

        // 启用设置组
        let enableGroup = createSettingsGroup(title: L10n.colorCompensation.section.enable, icon: "power")
        addGroupRow(enableGroup, createSwitchRow(
            label: L10n.colorCompensation.enabled,
            action: #selector(enableSwitchChanged(_:))
        ))
        addSettingsGroup(enableGroup, to: stackView)

        // 预设设置组
        let presetGroup = createSettingsGroup(title: L10n.colorCompensation.section.preset, icon: "list.bullet")
        addGroupRow(presetGroup, createPresetRow())
        addSettingsGroup(presetGroup, to: stackView)

        // 亮度曲线设置组
        let brightnessGroup = createSettingsGroup(title: L10n.colorCompensation.section.brightness, icon: "sun.max")
        for config in sliderConfigs.filter({ ["gamma", "blackLift", "whiteClip", "highlightRollOff"].contains($0.key) }) {
            addGroupRow(brightnessGroup, createSliderRow(config: config))
        }
        addSettingsGroup(brightnessGroup, to: stackView)

        // 色彩设置组
        let colorGroup = createSettingsGroup(title: L10n.colorCompensation.section.color, icon: "paintpalette")
        for config in sliderConfigs.filter({ ["temperature", "tint", "saturation"].contains($0.key) }) {
            addGroupRow(colorGroup, createSliderRow(config: config))
        }
        addSettingsGroup(colorGroup, to: stackView)

        // 操作按钮组
        let actionGroup = createSettingsGroup(title: L10n.colorCompensation.section.actions, icon: "wand.and.rays")
        addGroupRow(actionGroup, createButtonRow())
        addSettingsGroup(actionGroup, to: stackView)

        contentContainer.addSubview(scrollView)
        scrollView.frame = contentContainer.bounds
        scrollView.autoresizingMask = [.width, .height]
    }

    // MARK: - 当前配置访问器

    /// 获取当前编辑的配置
    private var currentProfile: ColorProfile {
        get {
            if let device = selectedDevice {
                return manager.deviceSettings[device].profile
            }
            return manager.currentProfile
        }
        set {
            if let device = selectedDevice {
                manager.setProfile(newValue, for: device)
            } else {
                manager.currentProfile = newValue
            }
        }
    }

    /// 获取当前编辑的启用状态
    private var currentIsEnabled: Bool {
        get {
            if let device = selectedDevice {
                let settings = manager.deviceSettings[device]
                if settings.mode == .useGlobal {
                    return manager.isEnabled
                }
                return settings.isEnabled
            }
            return manager.isEnabled
        }
        set {
            if let device = selectedDevice {
                manager.setEnabled(newValue, for: device)
            } else {
                manager.isEnabled = newValue
            }
        }
    }

    /// 获取当前设备的模式
    private var currentDeviceMode: DeviceColorMode {
        get {
            if let device = selectedDevice {
                return manager.deviceSettings[device].mode
            }
            return .useGlobal
        }
        set {
            if let device = selectedDevice {
                manager.setMode(newValue, for: device)
            }
        }
    }

    // MARK: - 绑定

    private func setupBindings() {
        manager.$currentProfile
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateUI()
            }
            .store(in: &cancellables)

        manager.$isEnabled
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateUI()
            }
            .store(in: &cancellables)

        manager.$customProfiles
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let popup = self?.presetPopUp else { return }
                self?.populatePresetMenu(popup)
            }
            .store(in: &cancellables)

        manager.$deviceSettings
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateUI()
            }
            .store(in: &cancellables)
    }

    // MARK: - UI 更新

    private func updateUI() {
        let profile = currentProfile

        enableSwitch?.state = currentIsEnabled ? .on : .off

        // 更新模式选择器
        if selectedDevice != nil {
            modePopUp?.isEnabled = true
            modePopUp?.selectItem(at: currentDeviceMode == .useGlobal ? 0 : 1)
        } else {
            modePopUp?.isEnabled = false
            modePopUp?.selectItem(at: 0)
        }

        // 判断控件是否可编辑
        let canEdit = selectedDevice == nil || currentDeviceMode == .independent
        updateSlidersEnabled(canEdit)
        enableSwitch?.isEnabled = canEdit
        presetPopUp?.isEnabled = canEdit

        // 刷新预设菜单并选择当前项
        if let popup = presetPopUp {
            populatePresetMenu(popup)
        }

        for config in sliderConfigs {
            guard let slider = sliders[config.key],
                  let valueLabel = valueLabels[config.key] else { continue }

            let value: Double
            switch config.key {
            case "gamma": value = Double(profile.gamma)
            case "blackLift": value = Double(profile.blackLift)
            case "whiteClip": value = Double(profile.whiteClip)
            case "highlightRollOff": value = Double(profile.highlightRollOff)
            case "temperature": value = Double(profile.temperature)
            case "tint": value = Double(profile.tint)
            case "saturation": value = Double(profile.saturation)
            default: continue
            }

            slider.doubleValue = value
            valueLabel.stringValue = String(format: config.format, value)
        }
    }

    private func updateSlidersEnabled(_ enabled: Bool) {
        for slider in sliders.values {
            slider.isEnabled = enabled
        }
        presetPopUp?.isEnabled = enabled
    }

    // MARK: - 布局辅助

    private func updateScrollViewLayout() {
        guard let scrollView = scrollView,
              let stackView = stackView,
              let documentView = scrollView.documentView else { return }
        let contentWidth = scrollView.contentView.bounds.width
        let size = stackView.requiredSize(for: contentWidth)
        documentView.frame = CGRect(x: 0, y: 0, width: contentWidth, height: size.height)
        stackView.frame = documentView.bounds
    }

    // MARK: - 创建 UI 元素（风格与偏好设置一致）

    private func createScrollView() -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        return scrollView
    }

    private func createSettingsGroup(title: String, icon: String) -> CCStackContainerView {
        let groupStack = CCStackContainerView()
        groupStack.axis = .vertical
        groupStack.alignment = .leading
        groupStack.spacing = 8

        // 标题行
        let titleStack = CCStackContainerView()
        titleStack.axis = .horizontal
        titleStack.alignment = .centerY
        titleStack.spacing = 6
        titleStack.fillsCrossAxis = true

        let iconView = NSImageView()
        let iconConfig = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        iconView.image = NSImage(systemSymbolName: icon, accessibilityDescription: nil)?
            .withSymbolConfiguration(iconConfig)
        iconView.contentTintColor = .secondaryLabelColor
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.setFrameSize(NSSize(width: 18, height: 18))
        titleStack.addArrangedSubview(iconView)

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        titleLabel.textColor = .secondaryLabelColor
        titleStack.addArrangedSubview(titleLabel)
        groupStack.addArrangedSubview(titleStack)

        // 内容容器
        let contentBox = CCStackContainerView()
        contentBox.axis = .vertical
        contentBox.alignment = .leading
        contentBox.spacing = 0
        contentBox.fillsCrossAxis = true
        contentBox.wantsLayer = true
        contentBox.layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.05).cgColor
        contentBox.layer?.cornerRadius = 8
        contentBox.edgeInsets = NSEdgeInsets(top: 0, left: 12, bottom: 0, right: 12)
        groupStack.addArrangedSubview(contentBox)

        return contentBox
    }

    private func addSettingsGroup(_ contentBox: CCStackContainerView, to parentStack: CCStackContainerView) {
        guard let groupStack = contentBox.superview as? CCStackContainerView else { return }
        groupStack.fillsCrossAxis = true
        parentStack.addArrangedSubview(groupStack)
    }

    private func addGroupRow(_ group: CCStackContainerView, _ row: NSView, addDivider: Bool = true) {
        if addDivider && !group.arrangedSubviews.isEmpty {
            let divider = NSBox()
            divider.boxType = .separator
            group.addArrangedSubview(divider)
        }
        group.addArrangedSubview(row)
    }

    private func createDeviceSelectorRow() -> NSView {
        let row = CCLabeledRowView(label: L10n.colorCompensation.deviceSelector, alignment: .trailing) {
            let segmented = NSSegmentedControl(labels: [
                L10n.colorCompensation.globalSettings,
                "iOS",
                "Android",
            ], trackingMode: .selectOne, target: self, action: #selector(self.deviceSegmentChanged(_:)))
            segmented.selectedSegment = 0 // 默认选择全局
            self.deviceSegmentedControl = segmented
            return segmented
        }
        return row
    }

    private func createDeviceModeRow() -> NSView {
        let row = CCLabeledRowView(label: L10n.colorCompensation.section.deviceMode, alignment: .trailing) {
            let popup = NSPopUpButton()
            popup.removeAllItems()
            for mode in DeviceColorMode.allCases {
                popup.addItem(withTitle: mode.displayName)
            }
            popup.target = self
            popup.action = #selector(self.deviceModeChanged(_:))
            popup.isEnabled = false // 初始禁用（全局模式下不可编辑）
            self.modePopUp = popup
            return popup
        }
        return row
    }

    private func createSwitchRow(label: String, action: Selector) -> NSView {
        let row = CCLabeledRowView(label: label, alignment: .trailing) {
            let switchControl = NSSwitch()
            switchControl.target = self
            switchControl.action = action
            switchControl.state = self.currentIsEnabled ? .on : .off
            self.enableSwitch = switchControl
            return switchControl
        }
        return row
    }

    private func createPresetRow() -> NSView {
        let row = CCLabeledRowView(label: L10n.colorCompensation.presetLabel, alignment: .trailing) {
            let stack = CCStackContainerView()
            stack.axis = .horizontal
            stack.alignment = .centerY
            stack.spacing = 8
            stack.fillsCrossAxis = true

            let popup = NSPopUpButton()
            popup.removeAllItems()
            self.populatePresetMenu(popup)
            popup.target = self
            popup.action = #selector(self.presetChanged(_:))
            self.presetPopUp = popup
            stack.addArrangedSubview(popup)
            stack.setFlexible(popup, isFlexible: true)

            let deleteButton = NSButton(image: NSImage(systemSymbolName: "trash", accessibilityDescription: L10n.colorCompensation.deletePreset)!, target: self, action: #selector(self.deletePresetPressed))
            deleteButton.bezelStyle = .inline
            deleteButton.isBordered = false
            deleteButton.toolTip = L10n.colorCompensation.deletePreset
            deleteButton.isHidden = true
            self.deletePresetButton = deleteButton
            stack.addArrangedSubview(deleteButton)

            return stack
        }
        return row
    }

    /// 填充预设菜单
    private func populatePresetMenu(_ popup: NSPopUpButton) {
        popup.removeAllItems()

        // 添加内置预设
        for profile in manager.presetProfiles {
            popup.addItem(withTitle: profile.localizedName)
        }

        // 添加分隔符和自定义预设
        if !manager.customProfiles.isEmpty {
            popup.menu?.addItem(.separator())
            let customHeader = NSMenuItem(title: L10n.colorCompensation.customPresets, action: nil, keyEquivalent: "")
            customHeader.isEnabled = false
            popup.menu?.addItem(customHeader)

            for profile in manager.customProfiles {
                popup.addItem(withTitle: profile.name)
            }
        }

        // 选择当前配置
        selectCurrentPresetInPopup(popup)
    }

    /// 选择当前预设
    private func selectCurrentPresetInPopup(_ popup: NSPopUpButton) {
        let currentName = currentProfile.name

        // 先检查内置预设
        if let index = manager.presetProfiles.firstIndex(where: { $0.name == currentName }) {
            popup.selectItem(at: index)
            deletePresetButton?.isHidden = true
            return
        }

        // 再检查自定义预设
        if let customIndex = manager.customProfiles.firstIndex(where: { $0.name == currentName }) {
            // 内置预设数 + 分隔符 + 自定义标题 + 实际索引
            let menuIndex = manager.presetProfiles.count + 2 + customIndex
            popup.selectItem(at: menuIndex)
            deletePresetButton?.isHidden = false
            return
        }

        // 默认选第一个
        popup.selectItem(at: 0)
        deletePresetButton?.isHidden = true
    }

    private func createSliderRow(config: SliderConfig) -> NSView {
        let row = CCLabeledRowView(label: config.title) {
            let stack = CCStackContainerView()
            stack.axis = .horizontal
            stack.alignment = .centerY
            stack.spacing = 8
            stack.fillsCrossAxis = true

            let slider = NSSlider(
                value: config.defaultValue,
                minValue: config.minValue,
                maxValue: config.maxValue,
                target: self,
                action: #selector(self.sliderChanged(_:))
            )
            slider.isContinuous = true
            stack.addArrangedSubview(slider)
            stack.setFlexible(slider, isFlexible: true)
            self.sliders[config.key] = slider

            let valueLabel = CCFixedSizeTextField(labelWithString: String(format: config.format, config.defaultValue))
            valueLabel.font = self.valueLabelFont
            valueLabel.alignment = .right
            valueLabel.preferredWidth = 50
            stack.addArrangedSubview(valueLabel)
            self.valueLabels[config.key] = valueLabel

            return stack
        }
        return row
    }

    private func createButtonRow() -> NSView {
        let stack = CCStackContainerView()
        stack.axis = .horizontal
        stack.alignment = .centerY
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 8, left: 0, bottom: 8, right: 0)

        let savePresetButton = NSButton(title: L10n.colorCompensation.savePreset, target: self, action: #selector(savePresetPressed))
        savePresetButton.bezelStyle = .rounded
        stack.addArrangedSubview(savePresetButton)

        // A/B 对比分段控件
        let compareSegment = NSSegmentedControl(labels: [
            L10n.colorCompensation.compareCompensated,
            L10n.colorCompensation.compareOriginal
        ], trackingMode: .selectOne, target: self, action: #selector(compareSegmentChanged(_:)))
        compareSegment.selectedSegment = 0
        compareSegment.segmentStyle = .rounded
        compareSegmentedControl = compareSegment
        stack.addArrangedSubview(compareSegment)

        let resetButton = NSButton(title: L10n.colorCompensation.reset, target: self, action: #selector(resetPressed))
        resetButton.bezelStyle = .rounded
        stack.addArrangedSubview(resetButton)

        return stack
    }

    // MARK: - Actions

    @objc private func deviceSegmentChanged(_ sender: NSSegmentedControl) {
        switch sender.selectedSegment {
        case 0: selectedDevice = nil // 全局设置
        case 1: selectedDevice = .ios
        case 2: selectedDevice = .android
        default: selectedDevice = nil
        }
        updateUI()
    }

    @objc private func deviceModeChanged(_ sender: NSPopUpButton) {
        let mode: DeviceColorMode = sender.indexOfSelectedItem == 0 ? .useGlobal : .independent
        currentDeviceMode = mode
        updateUI()
    }

    @objc private func enableSwitchChanged(_ sender: NSSwitch) {
        currentIsEnabled = sender.state == .on
    }

    @objc private func presetChanged(_ sender: NSPopUpButton) {
        let index = sender.indexOfSelectedItem
        guard index >= 0 else { return }

        let presetCount = manager.presetProfiles.count

        // 内置预设
        if index < presetCount {
            let preset = manager.presetProfiles[index]
            if let device = selectedDevice {
                manager.setProfile(preset, for: device)
            } else {
                manager.selectPreset(preset)
            }
            deletePresetButton?.isHidden = true
            return
        }

        // 跳过分隔符和标题
        let customIndex = index - presetCount - 2

        // 自定义预设
        if customIndex >= 0, customIndex < manager.customProfiles.count {
            let profile = manager.customProfiles[customIndex]
            if let device = selectedDevice {
                manager.setProfile(profile, for: device)
            } else {
                manager.currentProfile = profile
            }
            deletePresetButton?.isHidden = false
        }
    }

    @objc private func savePresetPressed() {
        let alert = NSAlert()
        alert.messageText = L10n.colorCompensation.savePresetTitle
        alert.informativeText = L10n.colorCompensation.savePresetMessage
        alert.alertStyle = .informational
        alert.addButton(withTitle: L10n.common.ok)
        alert.addButton(withTitle: L10n.common.cancel)

        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        textField.placeholderString = L10n.colorCompensation.savePresetPlaceholder
        textField.stringValue = ""
        alert.accessoryView = textField

        guard let window = view.window else { return }

        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            let name = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return }

            self?.savePresetWithName(name)
        }
    }

    private func savePresetWithName(_ name: String) {
        // 检查是否与内置预设重名
        if manager.presetProfiles.contains(where: { $0.name == name }) {
            showPresetNameExistsAlert()
            return
        }

        // 检查是否与已有自定义预设重名
        if manager.customProfiles.contains(where: { $0.name == name }) {
            showPresetNameExistsAlert()
            return
        }

        // 保存预设
        manager.createCustomProfile(name: name)

        // 刷新 UI
        if let popup = presetPopUp {
            populatePresetMenu(popup)
        }
    }

    private func showPresetNameExistsAlert() {
        guard let window = view.window else { return }

        let alert = NSAlert()
        alert.messageText = L10n.colorCompensation.presetNameExists
        alert.alertStyle = .warning
        alert.addButton(withTitle: L10n.common.ok)
        alert.beginSheetModal(for: window)
    }

    @objc private func deletePresetPressed() {
        let currentName = currentProfile.name
        guard let index = manager.customProfiles.firstIndex(where: { $0.name == currentName }) else { return }

        // 删除预设
        manager.deleteCustomProfile(at: index)

        // 刷新 UI
        if let popup = presetPopUp {
            populatePresetMenu(popup)
        }
    }

    @objc private func sliderChanged(_ sender: NSSlider) {
        guard let key = sliders.first(where: { $0.value === sender })?.key else { return }
        guard let config = sliderConfigs.first(where: { $0.key == key }) else { return }

        let value = Float(sender.doubleValue)

        if let valueLabel = valueLabels[key] {
            valueLabel.stringValue = String(format: config.format, value)
        }

        // 根据当前选中的设备更新对应的配置
        if let device = selectedDevice {
            let keyPath: WritableKeyPath<ColorProfile, Float>
            switch key {
            case "gamma": keyPath = \.gamma
            case "blackLift": keyPath = \.blackLift
            case "whiteClip": keyPath = \.whiteClip
            case "highlightRollOff": keyPath = \.highlightRollOff
            case "temperature": keyPath = \.temperature
            case "tint": keyPath = \.tint
            case "saturation": keyPath = \.saturation
            default: return
            }
            manager.adjustParameter(for: device, keyPath: keyPath, value: value)
        } else {
            // 全局设置
            switch key {
            case "gamma": manager.adjustGamma(value)
            case "blackLift": manager.adjustBlackLift(value)
            case "whiteClip": manager.adjustWhiteClip(value)
            case "highlightRollOff": manager.adjustHighlightRollOff(value)
            case "temperature": manager.adjustTemperature(value)
            case "tint": manager.adjustTint(value)
            case "saturation": manager.adjustSaturation(value)
            default: break
            }
        }
    }

    @objc private func compareSegmentChanged(_ sender: NSSegmentedControl) {
        isShowingOriginal = sender.selectedSegment == 1
        let bypass = isShowingOriginal

        if let device = selectedDevice {
            // 仅切换当前选中设备的滤镜
            manager.filter(for: device).setTemporaryBypass(bypass)
        } else {
            // 全局模式下切换所有滤镜
            manager.iosFilter.setTemporaryBypass(bypass)
            manager.androidFilter.setTemporaryBypass(bypass)
        }
    }

    @objc private func resetPressed() {
        // 重置 A/B 对比状态
        compareSegmentedControl?.selectedSegment = 0
        if isShowingOriginal {
            isShowingOriginal = false
            if let device = selectedDevice {
                manager.filter(for: device).setTemporaryBypass(false)
            } else {
                manager.iosFilter.setTemporaryBypass(false)
                manager.androidFilter.setTemporaryBypass(false)
            }
        }

        if let device = selectedDevice {
            // 重置设备独立设置为中性
            manager.setProfile(.neutral, for: device)
        } else {
            // 重置全局设置
            manager.resetToNeutral()
        }
    }
}

// MARK: - CC Flipped View

private class CCFlippedView: NSView {
    override var isFlipped: Bool { true }
}

// MARK: - CC Fixed Size Text Field

private final class CCFixedSizeTextField: NSTextField {
    var preferredWidth: CGFloat = 0

    override var intrinsicContentSize: NSSize {
        let size = super.intrinsicContentSize
        guard preferredWidth > 0 else { return size }
        return NSSize(width: preferredWidth, height: size.height)
    }
}

// MARK: - CC Labeled Row View

private final class CCLabeledRowView: NSView {
    enum ControlAlignment {
        case leading
        case trailing
    }

    private let labelView: NSTextField
    private let controlView: NSView
    private let controlAlignment: ControlAlignment
    private let minRowHeight: CGFloat = 36
    private let verticalPadding: CGFloat = 6

    override var isFlipped: Bool { true }

    init(label: String, alignment: ControlAlignment = .leading, control: NSView) {
        labelView = NSTextField(labelWithString: label)
        labelView.font = NSFont.systemFont(ofSize: 13)
        labelView.lineBreakMode = .byWordWrapping
        labelView.maximumNumberOfLines = 0
        labelView.usesSingleLineMode = false
        labelView.cell?.wraps = true
        labelView.cell?.isScrollable = false

        controlView = control
        controlAlignment = alignment

        super.init(frame: .zero)

        addSubview(labelView)
        addSubview(controlView)
    }

    convenience init(label: String, alignment: ControlAlignment = .leading, controlBuilder: () -> NSView) {
        self.init(label: label, alignment: alignment, control: controlBuilder())
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func requiredSize(for width: CGFloat) -> CGSize {
        let labelWidth = width * 0.35
        let controlWidth = width * 0.65
        let labelFitting = labelView.sizeThatFits(NSSize(width: labelWidth, height: .greatestFiniteMagnitude))
        let controlFitting = sizeForControl(controlView, maxWidth: controlWidth)
        let contentHeight = max(labelFitting.height, controlFitting.height)
        let totalHeight = max(minRowHeight, contentHeight + verticalPadding * 2)
        return CGSize(width: width, height: totalHeight)
    }

    override func layout() {
        super.layout()
        let width = bounds.width
        let labelWidth = width * 0.35
        let controlWidth = width * 0.65
        let labelFitting = labelView.sizeThatFits(NSSize(width: labelWidth, height: .greatestFiniteMagnitude))
        let controlFitting = sizeForControl(controlView, maxWidth: controlWidth)
        let contentHeight = max(labelFitting.height, controlFitting.height)
        let rowHeight = max(minRowHeight, contentHeight + verticalPadding * 2)
        let labelY = (rowHeight - labelFitting.height) / 2
        let controlY = (rowHeight - controlFitting.height) / 2

        labelView.frame = CGRect(x: 0, y: labelY, width: labelWidth, height: labelFitting.height)

        // 根据对齐方式计算控件 X 位置和宽度
        let controlX: CGFloat
        let actualControlWidth: CGFloat
        switch controlAlignment {
        case .leading:
            controlX = labelWidth
            actualControlWidth = controlWidth  // 使用完整的控件区域宽度
        case .trailing:
            controlX = width - controlFitting.width
            actualControlWidth = controlFitting.width
        }
        controlView.frame = CGRect(x: controlX, y: controlY, width: actualControlWidth, height: controlFitting.height)

        // 强制 controlView 重新布局
        controlView.needsLayout = true
    }

    private func sizeForControl(_ view: NSView, maxWidth: CGFloat) -> CGSize {
        if let stackContainer = view as? CCStackContainerView {
            return stackContainer.requiredSize(for: maxWidth)
        }
        let fitting = view.fittingSize
        return CGSize(width: min(maxWidth, fitting.width), height: fitting.height)
    }
}

// MARK: - CC Stack Container View

private final class CCStackContainerView: NSView {
    enum Axis {
        case vertical
        case horizontal
    }

    enum Alignment {
        case leading
        case center
        case trailing
        case top
        case centerY
        case bottom
    }

    var axis: Axis = .vertical
    var alignment: Alignment = .leading
    var spacing: CGFloat = 0
    var edgeInsets: NSEdgeInsets = .init(top: 0, left: 0, bottom: 0, right: 0)
    var fillsCrossAxis: Bool = false
    private(set) var arrangedSubviews: [NSView] = []
    private var flexibleViews: Set<ObjectIdentifier> = []

    override var isFlipped: Bool { true }

    func addArrangedSubview(_ view: NSView) {
        arrangedSubviews.append(view)
        addSubview(view)
        needsLayout = true
    }

    func setFlexible(_ view: NSView, isFlexible: Bool) {
        let identifier = ObjectIdentifier(view)
        if isFlexible {
            flexibleViews.insert(identifier)
        } else {
            flexibleViews.remove(identifier)
        }
        needsLayout = true
    }

    private func isFlexible(_ view: NSView) -> Bool {
        flexibleViews.contains(ObjectIdentifier(view))
    }

    func requiredSize(for width: CGFloat) -> CGSize {
        let availableWidth = max(0, width - edgeInsets.left - edgeInsets.right)
        switch axis {
        case .vertical:
            var totalHeight: CGFloat = edgeInsets.top + edgeInsets.bottom
            var maxWidth: CGFloat = 0
            var visibleCount = 0
            for view in arrangedSubviews where !view.isHidden {
                let size = sizeForView(view, maxWidth: availableWidth)
                totalHeight += size.height
                maxWidth = max(maxWidth, size.width)
                visibleCount += 1
            }
            if visibleCount > 1 {
                totalHeight += spacing * CGFloat(visibleCount - 1)
            }
            let resultWidth = fillsCrossAxis ? width : min(width, maxWidth + edgeInsets.left + edgeInsets.right)
            return CGSize(width: resultWidth, height: totalHeight)
        case .horizontal:
            var totalWidth: CGFloat = edgeInsets.left + edgeInsets.right
            var maxHeight: CGFloat = 0
            var visibleCount = 0
            for view in arrangedSubviews where !view.isHidden {
                let size = sizeForView(view, maxWidth: availableWidth)
                totalWidth += size.width
                maxHeight = max(maxHeight, size.height)
                visibleCount += 1
            }
            if visibleCount > 1 {
                totalWidth += spacing * CGFloat(visibleCount - 1)
            }
            return CGSize(width: totalWidth, height: maxHeight + edgeInsets.top + edgeInsets.bottom)
        }
    }

    override func layout() {
        super.layout()
        layoutArrangedSubviews()
    }

    private func layoutArrangedSubviews() {
        let availableWidth = max(0, bounds.width - edgeInsets.left - edgeInsets.right)
        let availableHeight = max(0, bounds.height - edgeInsets.top - edgeInsets.bottom)

        switch axis {
        case .vertical:
            var y = edgeInsets.top
            let visible = arrangedSubviews.filter { !$0.isHidden }
            for (index, view) in visible.enumerated() {
                let size = sizeForView(view, maxWidth: availableWidth)
                let width = fillsCrossAxis ? availableWidth : size.width
                let x = alignedX(for: width, availableWidth: availableWidth)
                view.frame = CGRect(
                    x: edgeInsets.left + x,
                    y: y,
                    width: width,
                    height: size.height
                )
                view.needsLayout = true
                y += size.height
                if index < visible.count - 1 {
                    y += spacing
                }
            }
        case .horizontal:
            let visible = arrangedSubviews.filter { !$0.isHidden }

            // 计算固定元素的总宽度和灵活元素数量
            var fixedWidth: CGFloat = 0
            var flexibleCount = 0
            for view in visible {
                if isFlexible(view) {
                    flexibleCount += 1
                } else {
                    let size = sizeForView(view, maxWidth: availableWidth)
                    fixedWidth += size.width
                }
            }
            if visible.count > 1 {
                fixedWidth += spacing * CGFloat(visible.count - 1)
            }

            // 计算灵活元素的宽度
            let remainingWidth = max(0, availableWidth - fixedWidth)
            let flexibleWidth = flexibleCount > 0 ? remainingWidth / CGFloat(flexibleCount) : 0

            var x = edgeInsets.left
            for (index, view) in visible.enumerated() {
                let viewWidth: CGFloat
                if isFlexible(view) {
                    viewWidth = flexibleWidth
                } else {
                    let size = sizeForView(view, maxWidth: availableWidth)
                    viewWidth = size.width
                }
                let size = sizeForView(view, maxWidth: viewWidth)
                let y = alignedY(for: size.height, availableHeight: availableHeight)
                view.frame = CGRect(
                    x: x,
                    y: edgeInsets.top + y,
                    width: viewWidth,
                    height: size.height
                )
                view.needsLayout = true
                x += viewWidth
                if index < visible.count - 1 {
                    x += spacing
                }
            }
        }
    }

    private func alignedX(for width: CGFloat, availableWidth: CGFloat) -> CGFloat {
        switch alignment {
        case .leading, .top, .centerY, .bottom: 0
        case .center: max(0, (availableWidth - width) / 2)
        case .trailing: max(0, availableWidth - width)
        }
    }

    private func alignedY(for height: CGFloat, availableHeight: CGFloat) -> CGFloat {
        switch alignment {
        case .top: 0
        case .centerY, .center: max(0, (availableHeight - height) / 2)
        case .bottom: max(0, availableHeight - height)
        case .leading, .trailing: 0
        }
    }

    private func sizeForView(_ view: NSView, maxWidth: CGFloat) -> CGSize {
        if let labeledRow = view as? CCLabeledRowView {
            return labeledRow.requiredSize(for: maxWidth)
        }
        if let box = view as? NSBox, box.boxType == .separator {
            return CGSize(width: maxWidth, height: 1)
        }
        if let stackContainer = view as? CCStackContainerView {
            return stackContainer.requiredSize(for: maxWidth)
        }
        let fitting = view.fittingSize
        return CGSize(width: min(maxWidth, fitting.width), height: fitting.height)
    }
}

// MARK: - ColorProfile 扩展

extension ColorProfile {
    /// 本地化名称
    var localizedName: String {
        NSLocalizedString("color.preset.\(name)", value: name, comment: "Color preset name")
    }
}
