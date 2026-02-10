//
//  PreviewContainerView.swift
//  ScreenPresenter
//
//  Created by Sun on 2025/12/25.
//
//  预览容器视图
//  管理设备面板的布局，支持多种布局模式
//

import AppKit
import MarkdownEditor

private final class MarkdownTabButtonView: NSView {
    var onSelect: (() -> Void)?
    var onClose: (() -> Void)?
    var menuProvider: (() -> NSMenu?)?

    private let titleField = NSTextField(labelWithString: "")
    private let closeButton = NSButton()
    private var trackingArea: NSTrackingArea?
    private var isHovering = false {
        didSet { updateAppearance() }
    }

    var isSelected = false {
        didSet { updateAppearance() }
    }

    var title: String = "" {
        didSet {
            titleField.stringValue = title
        }
    }

    func refreshAppearance() {
        updateAppearance()
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupUI()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        isHovering = true
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        isHovering = false
    }

    override func mouseDown(with event: NSEvent) {
        onSelect?()
    }

    override func layout() {
        super.layout()
        layer?.cornerRadius = bounds.height * 0.5
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        menuProvider?()
    }

    @objc private func closeButtonClicked(_ sender: Any?) {
        onClose?()
    }

    private func setupUI() {
        wantsLayer = true
        layer?.borderWidth = 1

        titleField.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        titleField.lineBreakMode = .byTruncatingMiddle
        titleField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        closeButton.isBordered = false
        closeButton.setButtonType(.momentaryChange)
        closeButton.bezelStyle = .shadowlessSquare
        closeButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: nil)
        closeButton.contentTintColor = .secondaryLabelColor
        closeButton.target = self
        closeButton.action = #selector(closeButtonClicked(_:))
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.isHidden = true

        titleField.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleField)
        addSubview(closeButton)

        // 使用 defaultHigh 优先级，允许在空间不足时压缩
        let heightConstraint = heightAnchor.constraint(equalToConstant: 26)
        heightConstraint.priority = .defaultHigh

        let minWidthConstraint = widthAnchor.constraint(greaterThanOrEqualToConstant: 108)
        minWidthConstraint.priority = .defaultHigh

        let closeWidthConstraint = closeButton.widthAnchor.constraint(equalToConstant: 14)
        closeWidthConstraint.priority = .defaultHigh

        let closeHeightConstraint = closeButton.heightAnchor.constraint(equalToConstant: 14)
        closeHeightConstraint.priority = .defaultHigh

        NSLayoutConstraint.activate([
            heightConstraint,
            minWidthConstraint,
            widthAnchor.constraint(lessThanOrEqualToConstant: 240),

            titleField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            titleField.centerYAnchor.constraint(equalTo: centerYAnchor),
            titleField.trailingAnchor.constraint(equalTo: closeButton.leadingAnchor, constant: -6),

            closeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            closeButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            closeWidthConstraint,
            closeHeightConstraint,
        ])

        updateAppearance()
    }

    private func updateAppearance() {
        let showsClose = isSelected || isHovering
        closeButton.isHidden = !showsClose

        let activeColor = NSColor.controlAccentColor.withAlphaComponent(0.14)
        let hoverColor = NSColor.quaternaryLabelColor.withAlphaComponent(0.22)
        let idleColor = NSColor.clear
        let borderColor = isSelected
            ? NSColor.controlAccentColor.withAlphaComponent(0.5)
            : NSColor.separatorColor.withAlphaComponent(0.65)

        layer?.backgroundColor = (isSelected ? activeColor : (isHovering ? hoverColor : idleColor)).cgColor
        layer?.borderColor = borderColor.cgColor
        titleField.textColor = isSelected ? .labelColor : .secondaryLabelColor
        closeButton.contentTintColor = isSelected ? .labelColor : .secondaryLabelColor
    }
}

/// 消除 NSTabView 即使在 .noTabsNoBorder 模式下仍保留的内部 content inset
private final class FullBoundsTabView: NSTabView {
    override var contentRect: NSRect {
        bounds
    }

    override func layout() {
        super.layout()
        // 强制选中的 tab item 视图填满整个 bounds
        if let selectedView = selectedTabViewItem?.view, selectedView.frame != bounds {
            selectedView.frame = bounds
        }
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }
}

// MARK: - 布局模式

enum PreviewLayoutMode: String, CaseIterable {
    /// 双设备并排显示（默认）
    case dual
    /// 仅显示左侧设备
    case leftOnly
    /// 仅显示右侧设备
    case rightOnly

    /// 显示名称
    var displayName: String {
        switch self {
        case .dual: L10n.layout.dual
        case .leftOnly: L10n.layout.leftOnly
        case .rightOnly: L10n.layout.rightOnly
        }
    }

    /// SF Symbol 图标名称
    var iconName: String {
        switch self {
        case .dual: "rectangle.split.2x1"
        case .leftOnly: "rectangle.lefthalf.filled"
        case .rightOnly: "rectangle.righthalf.filled"
        }
    }
}

// MARK: - 预览容器视图

final class PreviewContainerView: NSView, NSTabViewDelegate {
    private struct MarkdownTab {
        let id: UUID
        let item: NSTabViewItem
        let editor: MarkdownEditorView
        let buttonView: MarkdownTabButtonView
    }

    // MARK: - UI 组件

    /// 左侧区域容器
    private let leftAreaView = NSView()
    /// 中间编辑器区域容器
    private let centerEditorAreaView = NSView()
    /// 右侧区域容器
    private let rightAreaView = NSView()

    /// iOS 设备面板（默认在左侧）
    private(set) var iosPanelView = DevicePanelView()
    /// Android 设备面板（默认在右侧）
    private(set) var androidPanelView = DevicePanelView()

    /// Markdown 编辑器视图控制器
    private(set) var markdownEditorView: MarkdownEditorView?
    private let markdownTabBarView = NSVisualEffectView()
    private let markdownTabButtonsStack = NSStackView()
    private let markdownAddTabButton = NSButton()
    private let markdownTabView = FullBoundsTabView()
    private var markdownTabBarHeightConstraint: NSLayoutConstraint?
    private var markdownTabs: [MarkdownTab] = []
    private var contextMenuTabID: UUID?
    private var markdownUnsavedStateTimer: Timer?

    /// 交换按钮
    private(set) var swapButton = NSButton(title: "", target: nil, action: nil)
    private let swapButtonIconLayer = CALayer()

    /// 全屏模式下的预览/编辑切换按钮
    private let previewToggleButton: NSButton = {
        let button = NSButton()
        button.isBordered = false
        button.setButtonType(.momentaryChange)
        button.bezelStyle = .shadowlessSquare
        button.wantsLayer = true
        button.layer?.cornerRadius = 6
        button.isHidden = true
        return button
    }()

    // MARK: - 状态

    /// 当前布局模式
    private(set) var layoutMode: PreviewLayoutMode = UserPreferences.shared.layoutMode

    /// 是否交换了左右面板
    private(set) var isSwapped: Bool = false

    /// 是否显示 Markdown 编辑器
    private(set) var isMarkdownEditorVisible: Bool = false

    /// Markdown 编辑器位置
    private(set) var markdownEditorPosition: MarkdownEditorPosition = UserPreferences.shared.markdownEditorPosition

    /// 是否全屏模式
    var isFullScreen: Bool = false {
        didSet {
            if oldValue != isFullScreen {
                updateMarkdownTabBarVisibilityForCurrentMode()
                updateMarkdownEditorsFullScreenState()
                updatePreviewToggleButton()
                updateLayout(animated: false)
            }
        }
    }

    /// 是否首次布局
    private var isInitialLayout: Bool = true
    private var swapButtonAppearWorkItem: DispatchWorkItem?
    private var isAnimatingManualLayout: Bool = false

    // MARK: - 常量

    /// 非全屏时的垂直内边距
    private let verticalPadding: CGFloat = 24

    /// 编辑器占总宽度的比例（显示时）
    private let editorWidthRatio: CGFloat = 0.38
    private let markdownTabBarHeight: CGFloat = 26
    private let markdownUnsavedTabSuffix = " *"

    // MARK: - 回调

    /// 交换按钮点击回调
    var onSwapTapped: (() -> Void)?

    // MARK: - 初始化

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupUI()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
    }

    deinit {
        markdownUnsavedStateTimer?.invalidate()
    }

    // MARK: - UI 设置

    private func setupUI() {
        wantsLayer = true

        setupAreaViews()
        setupMarkdownTabView()
        setupDevicePanels()
        setupSwapButton()
        setupPreviewToggleButton()
        updateMarkdownTabBarVisibilityForCurrentMode()
        startMarkdownUnsavedStateTimer()

        // 根据初始 layoutMode 设置 UI 状态
        updateAreaVisibility()
    }

    private func setupAreaViews() {
        // 左侧区域容器
        addSubview(leftAreaView)

        // 中间编辑器区域容器
        centerEditorAreaView.isHidden = true
        addSubview(centerEditorAreaView)

        // 右侧区域容器
        addSubview(rightAreaView)
    }

    private func setupMarkdownTabView() {
        markdownTabBarView.material = .headerView
        markdownTabBarView.blendingMode = .withinWindow
        markdownTabBarView.state = .active
        markdownTabBarView.wantsLayer = true
        markdownTabBarView.layer?.borderWidth = 0
        markdownTabBarView.translatesAutoresizingMaskIntoConstraints = false
        centerEditorAreaView.addSubview(markdownTabBarView)

        markdownTabButtonsStack.orientation = .horizontal
        markdownTabButtonsStack.alignment = .centerY
        markdownTabButtonsStack.distribution = .fill
        markdownTabButtonsStack.spacing = 6
        markdownTabButtonsStack.translatesAutoresizingMaskIntoConstraints = false
        markdownTabBarView.addSubview(markdownTabButtonsStack)

        markdownAddTabButton.isBordered = false
        markdownAddTabButton.setButtonType(.momentaryChange)
        markdownAddTabButton.bezelStyle = .shadowlessSquare
        markdownAddTabButton.image = NSImage(
            systemSymbolName: "plus",
            accessibilityDescription: L10n.markdown.newTab
        )
        markdownAddTabButton.contentTintColor = .secondaryLabelColor
        markdownAddTabButton.target = self
        markdownAddTabButton.action = #selector(newTabButtonClicked(_:))
        markdownAddTabButton.translatesAutoresizingMaskIntoConstraints = false
        markdownTabBarView.addSubview(markdownAddTabButton)

        markdownTabView.delegate = self
        markdownTabView.drawsBackground = false
        markdownTabView.tabViewType = .noTabsNoBorder
        markdownTabView.translatesAutoresizingMaskIntoConstraints = false
        centerEditorAreaView.addSubview(markdownTabView)

        let tabBarHeightConstraint = markdownTabBarView.heightAnchor.constraint(equalToConstant: markdownTabBarHeight)
        markdownTabBarHeightConstraint = tabBarHeightConstraint

        // 使用 defaultHigh 优先级，允许在父视图尺寸为零时打破约束（避免 Auto Layout 警告）
        // centerEditorAreaView 使用 frame 布局，初始 frame 为零会导致 autoresizing mask 与子视图约束冲突
        let tabBarLeading = markdownTabBarView.leadingAnchor.constraint(equalTo: centerEditorAreaView.leadingAnchor)
        let tabBarTrailing = markdownTabBarView.trailingAnchor.constraint(equalTo: centerEditorAreaView.trailingAnchor)
        let tabBarTop = markdownTabBarView.topAnchor.constraint(equalTo: centerEditorAreaView.topAnchor)
        tabBarLeading.priority = .defaultHigh
        tabBarTrailing.priority = .defaultHigh
        tabBarTop.priority = .defaultHigh
        tabBarHeightConstraint.priority = .defaultHigh

        let addButtonWidth = markdownAddTabButton.widthAnchor.constraint(equalToConstant: 18)
        let addButtonHeight = markdownAddTabButton.heightAnchor.constraint(equalToConstant: 18)
        addButtonWidth.priority = .defaultHigh
        addButtonHeight.priority = .defaultHigh

        let stackBottom = markdownTabButtonsStack.bottomAnchor.constraint(equalTo: markdownTabBarView.bottomAnchor)
        stackBottom.priority = .defaultHigh

        let tabViewLeading = markdownTabView.leadingAnchor.constraint(equalTo: centerEditorAreaView.leadingAnchor)
        let tabViewTrailing = markdownTabView.trailingAnchor.constraint(equalTo: centerEditorAreaView.trailingAnchor)
        let tabViewTop = markdownTabView.topAnchor.constraint(equalTo: markdownTabBarView.bottomAnchor)
        let tabViewBottom = markdownTabView.bottomAnchor.constraint(equalTo: centerEditorAreaView.bottomAnchor)
        tabViewLeading.priority = .defaultHigh
        tabViewTrailing.priority = .defaultHigh
        tabViewTop.priority = .defaultHigh
        tabViewBottom.priority = .defaultHigh

        NSLayoutConstraint.activate([
            tabBarLeading,
            tabBarTrailing,
            tabBarTop,
            tabBarHeightConstraint,

            markdownAddTabButton.trailingAnchor.constraint(equalTo: markdownTabBarView.trailingAnchor),
            markdownAddTabButton.centerYAnchor.constraint(equalTo: markdownTabBarView.centerYAnchor),
            addButtonWidth,
            addButtonHeight,

            markdownTabButtonsStack.leadingAnchor.constraint(equalTo: markdownTabBarView.leadingAnchor),
            markdownTabButtonsStack.trailingAnchor.constraint(lessThanOrEqualTo: markdownAddTabButton.leadingAnchor),
            markdownTabButtonsStack.topAnchor.constraint(equalTo: markdownTabBarView.topAnchor),
            stackBottom,

            tabViewLeading,
            tabViewTrailing,
            tabViewTop,
            tabViewBottom,
        ])
    }

    private func setupDevicePanels() {
        // iOS 面板（默认在左侧）
        addSubview(iosPanelView)

        // Android 面板（默认在右侧）
        addSubview(androidPanelView)
    }

    private func setupSwapButton() {
        // 悬浮 swap 按钮已移至 toolbar，不再在设备视图中间显示
        // swapButton 相关代码已禁用
    }

    private func updateSwapButtonStyle() {
        guard let layer = swapButton.layer else { return }

        // 检测是否需要使用暗色样式（全屏或系统深色模式）
        let isDarkAppearance = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let useDarkStyle = isFullScreen || isDarkAppearance

        // 根据样式确定图标颜色
        let iconColor: NSColor = useDarkStyle ? .white : NSColor(white: 0.3, alpha: 1.0)
        let swapIconConfig = NSImage.SymbolConfiguration(pointSize: 16, weight: .regular)
            .applying(.init(paletteColors: [iconColor]))

        if useDarkStyle {
            // 全屏或深色模式时使用暗色样式
            layer.backgroundColor = NSColor.white.withAlphaComponent(0.2).cgColor
            layer.borderColor = NSColor.white.withAlphaComponent(0.4).cgColor
            layer.borderWidth = 1
            layer.shadowColor = NSColor.black.cgColor
            layer.shadowOpacity = 0.5
            layer.shadowOffset = CGSize(width: 0, height: -1)
            layer.shadowRadius = 4
        } else {
            // 亮色模式时使用浅色样式
            layer.backgroundColor = NSColor(white: 0.95, alpha: 1.0).cgColor
            layer.borderColor = NSColor(white: 0.8, alpha: 1.0).cgColor
            layer.borderWidth = 1
            layer.shadowColor = NSColor.black.cgColor
            layer.shadowOpacity = 0.1
            layer.shadowOffset = CGSize(width: 0, height: -1)
            layer.shadowRadius = 2
        }

        swapButtonIconLayer.contents = NSImage(
            systemSymbolName: "arrow.left.arrow.right",
            accessibilityDescription: L10n.toolbar.swapTooltip
        )?.withSymbolConfiguration(swapIconConfig)
    }

    // MARK: - 公开方法

    /// 设置布局模式
    func setLayoutMode(_ mode: PreviewLayoutMode, animated: Bool = true) {
        guard layoutMode != mode else { return }
        let oldMode = layoutMode
        layoutMode = mode
        updateLayoutWithModeTransition(from: oldMode, to: mode, animated: animated)
    }

    /// 交换左右面板
    func swapPanels(animated: Bool = true) {
        isSwapped.toggle()
        swapButton.alphaValue = 0
        updateLayout(animated: animated)
    }

    /// 更新布局
    func updateLayout(animated: Bool = true) {
        // 更新按钮样式
        updateSwapButtonStyle()

        // 更新区域可见性和位置
        updateAreaVisibility()
        updateSwapButtonFrame()

        // 根据交换状态决定哪个面板在哪个区域
        // 默认 (isSwapped=false): iOS 在左侧，Android 在右侧
        // 交换后 (isSwapped=true): Android 在左侧，iOS 在右侧
        let currentLeftPanel = isSwapped ? androidPanelView : iosPanelView
        let currentRightPanel = isSwapped ? iosPanelView : androidPanelView

        let leftAreaRect = leftAreaView.frame
        let rightAreaRect = rightAreaView.frame
        let leftPanelFrame = calculatePanelFrame(for: currentLeftPanel, in: leftAreaRect)
        let rightPanelFrame = calculatePanelFrame(for: currentRightPanel, in: rightAreaRect)

        // 执行布局更新
        if isInitialLayout || !animated {
            isInitialLayout = false
            swapButton.alphaValue = 1
            currentLeftPanel.frame = leftPanelFrame
            currentRightPanel.frame = rightPanelFrame
        } else {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.35
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                context.allowsImplicitAnimation = true
                context.completionHandler = { [weak self] in
                    NSAnimationContext.runAnimationGroup { swapContext in
                        swapContext.duration = 0.3
                        swapContext.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                        swapContext.allowsImplicitAnimation = true
                        self?.swapButton.alphaValue = 1
                    }
                }
                currentLeftPanel.animator().frame = leftPanelFrame
                currentRightPanel.animator().frame = rightPanelFrame
            }
        }
    }

    /// 更新 bezel 可见性
    func updateBezelVisibility() {
        let showBezel = UserPreferences.shared.showDeviceBezel
        iosPanelView.setBezelVisible(showBezel)
        androidPanelView.setBezelVisible(showBezel)
        updateLayout(animated: false)
    }

    /// 更新本地化文本
    func updateLocalizedTexts() {
        swapButton.toolTip = L10n.toolbar.swapTooltip

        // 根据全屏状态确定图标颜色
        let iconColor: NSColor = isFullScreen ? .white : NSColor(white: 0.3, alpha: 1.0)
        let swapIconConfig = NSImage.SymbolConfiguration(pointSize: 16, weight: .regular)
            .applying(.init(paletteColors: [iconColor]))

        swapButtonIconLayer.contents = NSImage(
            systemSymbolName: "arrow.left.arrow.right",
            accessibilityDescription: L10n.toolbar.swapTooltip
        )?.withSymbolConfiguration(swapIconConfig)

        iosPanelView.updateLocalizedTexts()
        androidPanelView.updateLocalizedTexts()
    }

    // MARK: - 私有方法

    /// 更新区域可见性和约束（无动画时使用）
    private func updateAreaVisibility() {
        updateAreaConstraints()
        updatePanelVisibility()
    }

    /// 仅更新区域约束（动画时使用，不修改 isHidden）
    private func updateAreaConstraints() {
        if layoutMode != .dual {
            cancelSwapButtonAppearance()
        }
        switch layoutMode {
        case .dual:
            leftAreaView.isHidden = false
            rightAreaView.isHidden = false
            swapButton.isHidden = false
            updateAreaFrames()

        case .leftOnly:
            leftAreaView.isHidden = false
            rightAreaView.isHidden = true
            swapButton.isHidden = true
            updateAreaFrames()

        case .rightOnly:
            leftAreaView.isHidden = true
            rightAreaView.isHidden = false
            swapButton.isHidden = true
            updateAreaFrames()
        }
    }

    /// 仅更新面板可见性（根据当前 layoutMode）
    private func updatePanelVisibility() {
        let leftPanel = isSwapped ? androidPanelView : iosPanelView
        let rightPanel = isSwapped ? iosPanelView : androidPanelView

        switch layoutMode {
        case .dual:
            leftPanel.isHidden = false
            rightPanel.isHidden = false
        case .leftOnly:
            leftPanel.isHidden = false
            rightPanel.isHidden = true
        case .rightOnly:
            leftPanel.isHidden = true
            rightPanel.isHidden = false
        }
    }

    @objc private func swapTapped() {
        swapPanels()
        onSwapTapped?()
    }

    /// 处理布局模式切换的动画
    private func updateLayoutWithModeTransition(
        from oldMode: PreviewLayoutMode,
        to newMode: PreviewLayoutMode,
        animated: Bool
    ) {
        // 根据交换状态确定哪个面板在左侧/右侧
        let leftPanel = isSwapped ? androidPanelView : iosPanelView
        let rightPanel = isSwapped ? iosPanelView : androidPanelView

        if !animated {
            updateLayout(animated: false)
            return
        }

        // 动画参数
        let duration: TimeInterval = 0.3
        let offsetDistance: CGFloat = min(180, max(80, bounds.width * 0.15))

        switch (oldMode, newMode) {
        case (.dual, .leftOnly):
            // 双设备 -> 仅左侧：右侧面板滑出淡出，左侧面板移动到居中
            animateDualToSingle(
                hidingPanel: rightPanel,
                stayingPanel: leftPanel,
                hideToRight: true,
                duration: duration,
                offsetDistance: offsetDistance
            )

        case (.dual, .rightOnly):
            // 双设备 -> 仅右侧：左侧面板滑出淡出，右侧面板移动到居中
            animateDualToSingle(
                hidingPanel: leftPanel,
                stayingPanel: rightPanel,
                hideToRight: false,
                duration: duration,
                offsetDistance: offsetDistance
            )

        case (.leftOnly, .dual):
            // 仅左侧 -> 双设备：左侧面板移动到半边，右侧面板滑入淡入
            animateSingleToDual(
                stayingPanel: leftPanel,
                enteringPanel: rightPanel,
                enterFromRight: true,
                duration: duration,
                offsetDistance: offsetDistance,
                swapButtonDelay: 0.12
            )

        case (.rightOnly, .dual):
            // 仅右侧 -> 双设备：右侧面板移动到半边，左侧面板滑入淡入
            animateSingleToDual(
                stayingPanel: rightPanel,
                enteringPanel: leftPanel,
                enterFromRight: false,
                duration: duration,
                offsetDistance: offsetDistance,
                swapButtonDelay: 0.12
            )

        case (.leftOnly, .rightOnly):
            // 仅左侧 -> 仅右侧：左侧滑出淡出，右侧滑入淡入（同时）
            animateSingleToSingle(
                hidingPanel: leftPanel,
                showingPanel: rightPanel,
                hideToRight: oldMode == .rightOnly,
                showFromRight: newMode == .rightOnly,
                duration: duration,
                offsetDistance: offsetDistance
            )

        case (.rightOnly, .leftOnly):
            // 仅右侧 -> 仅左侧：右侧滑出淡出，左侧滑入淡入（同时）
            animateSingleToSingle(
                hidingPanel: rightPanel,
                showingPanel: leftPanel,
                hideToRight: oldMode == .rightOnly,
                showFromRight: newMode == .rightOnly,
                duration: duration,
                offsetDistance: offsetDistance
            )

        default:
            updateLayout(animated: animated)
        }
    }

    // MARK: - 手动计算面板 Frame

    /// 计算面板在指定区域内居中的 frame
    /// - Parameters:
    ///   - panel: 面板视图
    ///   - areaRect: 区域矩形
    /// - Returns: 计算后的 frame
    private func calculatePanelFrame(for panel: DevicePanelView, in areaRect: CGRect) -> CGRect {
        let vPadding: CGFloat = isFullScreen ? 0 : verticalPadding
        let showBezel = UserPreferences.shared.showDeviceBezel
        let shouldFillHeight = isFullScreen && !showBezel

        // 计算可用高度
        let availableHeight = shouldFillHeight ? areaRect.height : (areaRect.height - vPadding * 2)

        // 计算面板尺寸（基于高度和宽高比）
        let aspectRatio = panel.deviceAspectRatio
        let panelHeight = availableHeight
        let panelWidth = panelHeight * aspectRatio

        // 确保不超出区域宽度
        let finalWidth = min(panelWidth, areaRect.width)
        let finalHeight = finalWidth / aspectRatio

        // 计算居中位置
        let x = areaRect.origin.x + (areaRect.width - finalWidth) / 2
        let y = areaRect.origin.y + (areaRect.height - finalHeight) / 2

        return CGRect(x: x, y: y, width: finalWidth, height: finalHeight)
    }

    /// 计算双设备模式下左侧区域的矩形
    private func leftAreaRectForDualMode() -> CGRect {
        CGRect(x: 0, y: 0, width: bounds.width / 2, height: bounds.height)
    }

    /// 计算双设备模式下右侧区域的矩形
    private func rightAreaRectForDualMode() -> CGRect {
        CGRect(x: bounds.width / 2, y: 0, width: bounds.width / 2, height: bounds.height)
    }

    /// 计算单设备模式下的区域矩形（占满整个容器）
    private func areaRectForSingleMode() -> CGRect {
        bounds
    }

    // MARK: - 动画方法

    /// 双设备 -> 单设备的动画
    /// - hidingPanel: 要隐藏的面板（位移+淡出）
    /// - stayingPanel: 保留的面板（位移）
    private func animateDualToSingle(
        hidingPanel: DevicePanelView,
        stayingPanel: DevicePanelView,
        hideToRight: Bool,
        duration: TimeInterval,
        offsetDistance: CGFloat
    ) {
        cancelSwapButtonAppearance()
        swapButton.isHidden = true
        swapButton.alphaValue = 0

        preparePanelsForManualAnimation()

        // 1. 记录初始位置
        let hidingPanelStartFrame = hidingPanel.frame
        let stayingPanelStartFrame = stayingPanel.frame

        // 2. 手动计算目标位置
        // 保留面板的目标位置：在整个容器内居中
        let stayingPanelEndFrame = calculatePanelFrame(for: stayingPanel, in: areaRectForSingleMode())

        // 隐藏面板的目标位置：从初始位置向外滑出
        let hideOffset = hideToRight ? offsetDistance : -offsetDistance
        let hidingPanelEndFrame = hidingPanelStartFrame.offsetBy(dx: hideOffset, dy: 0)

        // 3. 更新 swapButton 样式
        updateSwapButtonStyle()

        // 4. 使用 CATransaction 确保 frame 立即生效
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        hidingPanel.frame = hidingPanelStartFrame
        stayingPanel.frame = stayingPanelStartFrame
        CATransaction.commit()

        // 5. 执行动画
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            context.allowsImplicitAnimation = true

            // 隐藏面板：位移 + 淡出
            hidingPanel.animator().frame = hidingPanelEndFrame
            hidingPanel.animator().alphaValue = 0

            // 保留面板：位移
            stayingPanel.animator().frame = stayingPanelEndFrame
        } completionHandler: {
            hidingPanel.isHidden = true
            hidingPanel.alphaValue = 1
            self.isAnimatingManualLayout = false
            // 动画完成后更新约束
            self.updateAreaConstraints()
            self.updatePanelFrames()
        }
    }

    /// 单设备 -> 双设备的动画
    /// - stayingPanel: 当前显示的面板（位移）
    /// - enteringPanel: 要进入的面板（位移+淡入）
    private func animateSingleToDual(
        stayingPanel: DevicePanelView,
        enteringPanel: DevicePanelView,
        enterFromRight: Bool,
        duration: TimeInterval,
        offsetDistance: CGFloat,
        swapButtonDelay: TimeInterval
    ) {
        // 1. 准备动画状态
        preparePanelsForManualAnimation()

        // 2. 计算保留面板的初始位置（单设备中心位置）
        let stayingPanelStartFrame = calculatePanelFrame(
            for: stayingPanel,
            in: areaRectForSingleMode()
        )

        // 3. 计算目标位置
        let leftAreaRect = leftAreaRectForDualMode()
        let rightAreaRect = rightAreaRectForDualMode()

        let stayingPanelEndFrame: CGRect
        let enteringPanelEndFrame: CGRect

        if enterFromRight {
            stayingPanelEndFrame = calculatePanelFrame(for: stayingPanel, in: leftAreaRect)
            enteringPanelEndFrame = calculatePanelFrame(for: enteringPanel, in: rightAreaRect)
        } else {
            stayingPanelEndFrame = calculatePanelFrame(for: stayingPanel, in: rightAreaRect)
            enteringPanelEndFrame = calculatePanelFrame(for: enteringPanel, in: leftAreaRect)
        }

        // 4. 计算进入面板的初始位置
        // 初始位置：X 在目标位置的外侧（偏移 offsetDistance），Y 与目标位置相同
        let enterOffset = enterFromRight ? offsetDistance : -offsetDistance
        let enteringPanelStartFrame = CGRect(
            x: enteringPanelEndFrame.origin.x + enterOffset,
            y: enteringPanelEndFrame.origin.y, // Y 与目标相同，确保纯水平移动
            width: enteringPanelEndFrame.width,
            height: enteringPanelEndFrame.height
        )

        // 5. 更新 swapButton 样式
        updateSwapButtonStyle()

        // 6. 先调整层级（这可能触发布局）
        elevatePanel(enteringPanel, above: stayingPanel)

        // 7. 使用 CATransaction 设置初始状态并强制布局
        CATransaction.begin()
        CATransaction.setDisableActions(true)

        // 设置 staying panel
        stayingPanel.frame = stayingPanelStartFrame

        // 设置 entering panel 的最终尺寸（不是起始位置）
        // 这确保了子视图（如 bezelView）按最终尺寸布局
        enteringPanel.frame = enteringPanelEndFrame
        // 强制立即布局所有子视图
        enteringPanel.layoutSubtreeIfNeeded()
        // 再次确保禁用动画
        CATransaction.flush()

        // 现在将 entering panel 移到起始位置
        // 由于子视图已经布局好了，这只会改变 panel 的位置，不会触发子视图重新布局
        enteringPanel.frame = enteringPanelStartFrame

        // 设置可见性
        enteringPanel.isHidden = false
        enteringPanel.alphaValue = 0

        CATransaction.commit()

        // 8. 执行动画
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            // 禁用隐式动画，只使用显式 animator() 调用
            // 这可以防止子视图的 frame 变化产生意外的动画效果
            context.allowsImplicitAnimation = false

            // 存在的面板：仅水平位移
            let stayingEndFrame = CGRect(
                x: stayingPanelEndFrame.origin.x,
                y: stayingPanelStartFrame.origin.y,
                width: stayingPanelStartFrame.width,
                height: stayingPanelStartFrame.height
            )
            stayingPanel.animator().frame = stayingEndFrame

            // 出现的面板：仅水平位移（Y 和尺寸不变）+ 淡入
            let enteringEndFrame = CGRect(
                x: enteringPanelEndFrame.origin.x,
                y: enteringPanelStartFrame.origin.y, // 保持 Y 不变
                width: enteringPanelStartFrame.width,
                height: enteringPanelStartFrame.height
            )
            enteringPanel.animator().frame = enteringEndFrame
            enteringPanel.animator().alphaValue = 1
        } completionHandler: {
            self.isAnimatingManualLayout = false
            // 动画完成后更新约束
            self.updateAreaConstraints()
            self.updatePanelFrames()
            self.scheduleSwapButtonAppearance(after: swapButtonDelay)
        }
    }

    /// 单设备 -> 另一个单设备的动画
    /// - hidingPanel: 消失的面板（位移+淡出）
    /// - showingPanel: 出现的面板（位移+淡入）
    private func animateSingleToSingle(
        hidingPanel: DevicePanelView,
        showingPanel: DevicePanelView,
        hideToRight: Bool,
        showFromRight: Bool,
        duration: TimeInterval,
        offsetDistance: CGFloat
    ) {
        preparePanelsForManualAnimation()
        elevatePanel(showingPanel, above: hidingPanel)

        // 1. 记录隐藏面板的初始位置（单设备中心位置，避免从(0,0)跳入）
        let hidingPanelStartFrame = calculatePanelFrame(
            for: hidingPanel,
            in: areaRectForSingleMode()
        )

        // 2. 手动计算目标位置
        // 显示面板的目标位置：在整个容器内居中
        let showingPanelEndFrame = calculatePanelFrame(for: showingPanel, in: areaRectForSingleMode())

        // 隐藏面板的目标位置：从初始位置向外滑出
        let hideOffset = hideToRight ? offsetDistance : -offsetDistance
        let hidingPanelEndFrame = hidingPanelStartFrame.offsetBy(dx: hideOffset, dy: 0)

        // 显示面板的初始位置：从外部滑入（Y 与目标位置相同，确保纯水平移动）
        let showOffset = showFromRight ? offsetDistance : -offsetDistance
        var showingPanelStartFrame = showingPanelEndFrame
        showingPanelStartFrame.origin.x += showOffset

        // 3. 更新 swapButton 样式
        updateSwapButtonStyle()

        // 4. 使用 CATransaction 设置初始状态并强制布局
        CATransaction.begin()
        CATransaction.setDisableActions(true)

        // 设置 hiding panel
        hidingPanel.frame = hidingPanelStartFrame

        // 设置 showing panel 的最终尺寸（确保子视图按最终尺寸布局）
        showingPanel.frame = showingPanelEndFrame
        // 强制立即布局所有子视图
        showingPanel.layoutSubtreeIfNeeded()
        // 确保布局完成
        CATransaction.flush()

        // 将 showing panel 移到起始位置
        showingPanel.frame = showingPanelStartFrame

        // 设置可见性
        showingPanel.isHidden = false
        showingPanel.alphaValue = 0

        CATransaction.commit()

        // 5. 执行动画
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            context.allowsImplicitAnimation = false

            // 消失的面板：仅水平位移 + 淡出（Y 保持初始位置不变）
            let hidingEndFrame = CGRect(
                x: hidingPanelEndFrame.origin.x,
                y: hidingPanelStartFrame.origin.y,
                width: hidingPanelStartFrame.width,
                height: hidingPanelStartFrame.height
            )
            hidingPanel.animator().frame = hidingEndFrame
            hidingPanel.animator().alphaValue = 0

            // 出现的面板：仅水平位移 + 淡入（Y 保持不变）
            let showingEndFrame = CGRect(
                x: showingPanelEndFrame.origin.x,
                y: showingPanelStartFrame.origin.y,
                width: showingPanelStartFrame.width,
                height: showingPanelStartFrame.height
            )
            showingPanel.animator().frame = showingEndFrame
            showingPanel.animator().alphaValue = 1
        } completionHandler: {
            hidingPanel.isHidden = true
            hidingPanel.alphaValue = 1
            self.isAnimatingManualLayout = false
            // 动画完成后更新约束
            self.updateAreaConstraints()
            self.updatePanelFrames()
        }
    }

    /// 更新面板约束（不执行布局）
    private func updatePanelFrames() {
        let currentLeftPanel = isSwapped ? androidPanelView : iosPanelView
        let currentRightPanel = isSwapped ? iosPanelView : androidPanelView

        let leftAreaRect = leftAreaView.frame
        let rightAreaRect = rightAreaView.frame
        currentLeftPanel.frame = calculatePanelFrame(for: currentLeftPanel, in: leftAreaRect)
        currentRightPanel.frame = calculatePanelFrame(for: currentRightPanel, in: rightAreaRect)
    }

    private func preparePanelsForManualAnimation() {
        isAnimatingManualLayout = true
        layoutSubtreeIfNeeded()
    }

    private func elevatePanel(_ panel: DevicePanelView, above sibling: DevicePanelView) {
        guard let superview = panel.superview, panel !== sibling else { return }
        superview.addSubview(panel, positioned: .above, relativeTo: sibling)
    }

    private func scheduleSwapButtonAppearance(after delay: TimeInterval) {
        cancelSwapButtonAppearance()
        guard layoutMode == .dual else { return }
        swapButton.isHidden = false
        swapButton.alphaValue = 0

        let workItem = DispatchWorkItem { [weak self] in
            guard let self, layoutMode == .dual else { return }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.25
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                context.allowsImplicitAnimation = true
                self.swapButton.animator().alphaValue = 1
            }
        }
        swapButtonAppearWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func cancelSwapButtonAppearance() {
        swapButtonAppearWorkItem?.cancel()
        swapButtonAppearWorkItem = nil
    }

    private func updateAreaFrames() {
        let fullBounds = bounds

        // 如果编辑器可见，使用三区域布局
        if isMarkdownEditorVisible {
            updateAreaFramesWithEditor(fullBounds)
            return
        }

        // 标准双设备布局（无编辑器）
        // 注意：不再将 centerEditorAreaView.frame 设为 .zero
        // 因为子视图（如 EditorFormatBar 的 NSStackView）有内部 Auto Layout 约束，
        // 零尺寸会导致约束冲突。隐藏状态下保持原有 frame 即可。

        switch layoutMode {
        case .dual:
            let halfWidth = fullBounds.width / 2
            leftAreaView.frame = CGRect(x: 0, y: 0, width: halfWidth, height: fullBounds.height)
            rightAreaView.frame = CGRect(x: halfWidth, y: 0, width: halfWidth, height: fullBounds.height)
        case .leftOnly:
            leftAreaView.frame = fullBounds
            rightAreaView.frame = .zero
        case .rightOnly:
            rightAreaView.frame = fullBounds
            leftAreaView.frame = .zero
        }
    }

    /// 编辑器可见时的三区域布局计算
    private func updateAreaFramesWithEditor(_ fullBounds: CGRect) {
        let editorWidth = fullBounds.width * editorWidthRatio
        let deviceWidth = (fullBounds.width - editorWidth) / 2

        switch markdownEditorPosition {
        case .center:
            // |  Device (31%)  |  Editor (38%)  |  Device (31%)  |
            leftAreaView.frame = CGRect(x: 0, y: 0, width: deviceWidth, height: fullBounds.height)
            centerEditorAreaView.frame = CGRect(x: deviceWidth, y: 0, width: editorWidth, height: fullBounds.height)
            rightAreaView.frame = CGRect(x: deviceWidth + editorWidth, y: 0, width: deviceWidth, height: fullBounds.height)

        case .left:
            // |  Editor (38%)  |  Device (31%)  |  Device (31%)  |
            centerEditorAreaView.frame = CGRect(x: 0, y: 0, width: editorWidth, height: fullBounds.height)
            leftAreaView.frame = CGRect(x: editorWidth, y: 0, width: deviceWidth, height: fullBounds.height)
            rightAreaView.frame = CGRect(x: editorWidth + deviceWidth, y: 0, width: deviceWidth, height: fullBounds.height)

        case .right:
            // |  Device (31%)  |  Device (31%)  |  Editor (38%)  |
            leftAreaView.frame = CGRect(x: 0, y: 0, width: deviceWidth, height: fullBounds.height)
            rightAreaView.frame = CGRect(x: deviceWidth, y: 0, width: deviceWidth, height: fullBounds.height)
            centerEditorAreaView.frame = CGRect(x: deviceWidth * 2, y: 0, width: editorWidth, height: fullBounds.height)
        }
    }

    private func updateSwapButtonFrame() {
        let size: CGFloat = 32
        swapButton.frame = CGRect(
            x: (bounds.width - size) / 2,
            y: (bounds.height - size) / 2,
            width: size,
            height: size
        )
        let iconSize: CGFloat = 16
        let iconOffset = (size - iconSize) / 2
        swapButtonIconLayer.frame = CGRect(x: iconOffset, y: iconOffset, width: iconSize, height: iconSize)
    }

    override func layout() {
        super.layout()
        // 动画期间不更新区域帧，避免覆盖动画初始状态
        if !isAnimatingManualLayout {
            updateAreaFrames()
        }
        updateSwapButtonFrame()
        if !isInitialLayout, !isAnimatingManualLayout {
            updatePanelFrames()
        }
        // 全屏时更新预览切换按钮位置
        if isFullScreen, !previewToggleButton.isHidden {
            layoutPreviewToggleButton()
        }
    }

    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        // 点击设备预览区域时，让编辑器失去焦点
        // 检查点击位置是否在编辑器外部
        let clickPoint = convert(event.locationInWindow, from: nil)
        if isMarkdownEditorVisible, !centerEditorAreaView.frame.contains(clickPoint) {
            window?.makeFirstResponder(nil)
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        // 系统外观变化时更新交换按钮样式
        updateSwapButtonStyle()
        updateMarkdownTabBarAppearance()
        for tab in markdownTabs {
            tab.buttonView.refreshAppearance()
        }
    }

    // MARK: - Markdown 编辑器

    /// 切换 Markdown 编辑器显示/隐藏
    func toggleMarkdownEditor(animated: Bool = true) {
        isMarkdownEditorVisible.toggle()
        UserPreferences.shared.markdownEditorVisible = isMarkdownEditorVisible

        if isMarkdownEditorVisible {
            showMarkdownEditor(animated: animated)
        } else {
            hideMarkdownEditor(animated: animated)
        }
        updatePreviewToggleButton()
    }

    /// 设置 Markdown 编辑器位置
    func setMarkdownEditorPosition(_ position: MarkdownEditorPosition, animated: Bool = true) {
        guard markdownEditorPosition != position else { return }
        markdownEditorPosition = position
        UserPreferences.shared.markdownEditorPosition = position

        if isMarkdownEditorVisible {
            updateLayout(animated: animated)
        }
    }

    /// 新建 Markdown 文件（清空当前内容）
    func newMarkdownFile() {
        newMarkdownTab()
    }

    /// 新建 Markdown 标签页
    func newMarkdownTab() {
        ensureMarkdownEditorVisible(createInitialTab: false)
        let tab = createMarkdownTab(title: L10n.markdown.untitled)
        tab.editor.setContent("")
        refreshTabTitle(for: tab, fallbackTitle: L10n.markdown.untitled)
        persistOpenedMarkdownFilePaths()
    }

    /// 从剪切板新建 Markdown 文件
    func newMarkdownFromClipboard() {
        ensureMarkdownEditorVisible(createInitialTab: false)
        let tab = createMarkdownTab(title: L10n.markdown.untitled)

        // 从剪切板获取文本
        let pasteboard = NSPasteboard.general
        if let text = pasteboard.string(forType: .string) {
            tab.editor.setContent(text)
        }
        refreshTabTitle(for: tab, fallbackTitle: L10n.markdown.untitled)
        persistOpenedMarkdownFilePaths()
    }

    /// 打开 Markdown 文件
    func openMarkdownFile(at url: URL) {
        ensureMarkdownEditorVisible(createInitialTab: false)
        if let reusableTab = reusableSingleEmptyMarkdownTab() {
            _ = openMarkdownFile(at: url, in: reusableTab, removeTabOnFailure: false)
        } else {
            let tab = createMarkdownTab(title: url.lastPathComponent)
            _ = openMarkdownFile(at: url, in: tab, removeTabOnFailure: true)
        }
        persistOpenedMarkdownFilePaths()
    }

    /// 关闭当前 Markdown 标签页
    func closeCurrentMarkdownTab() {
        guard let tab = currentMarkdownTab() else { return }
        closeMarkdownTab(withID: tab.id)
    }

    /// 保存当前 Markdown 文件
    func saveMarkdownFile() {
        guard let tab = currentMarkdownTab() else {
            let newTab = createMarkdownTab(title: L10n.markdown.untitled)
            do {
                try newTab.editor.save()
            } catch {
                presentMarkdownSaveError(error)
            }
            return
        }

        do {
            try tab.editor.save()
        } catch {
            presentMarkdownSaveError(error)
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.refreshTabTitle(for: tab)
            self?.persistOpenedMarkdownFilePaths()
        }
    }

    /// 触发系统“另存为”面板（遵循 MarkdownEditor 的保存逻辑）
    func saveMarkdownFileAs(completion: ((URL?) -> Void)? = nil) {
        guard let tab = currentMarkdownTab() else {
            completion?(nil)
            return
        }

        let previousURL = tab.editor.fileURL
        tab.editor.saveAs()
        waitForSaveAsResult(for: tab.id, previousURL: previousURL, warmupAttempts: 12, completion: completion)
    }

    /// 另存为 Markdown 文件
    func saveMarkdownFile(to url: URL) {
        guard let tab = currentMarkdownTab() else { return }
        tab.editor.save(to: url) { [weak self] success in
            guard success else {
                self?.presentMarkdownSaveError(nil)
                return
            }
            let fallbackName = tab.editor.fileURL?.lastPathComponent ?? url.lastPathComponent
            self?.refreshTabTitle(for: tab, fallbackTitle: fallbackName)
            self?.persistOpenedMarkdownFilePaths()
        }
    }

    /// 请求关闭 Markdown（有未保存内容时触发保存确认）
    func requestCloseMarkdownIfNeeded(completion: @escaping (Bool) -> Void) {
        let tabs = markdownTabs
        guard !tabs.isEmpty else {
            completion(true)
            return
        }
        requestCloseForTabs(ArraySlice(tabs), completion: completion)
    }

    /// 是否存在“未保存到磁盘且有改动”的文档
    func hasUnsavedNewMarkdownDocuments() -> Bool {
        markdownTabs.contains { $0.editor.fileURL == nil && $0.editor.hasUnsavedChanges }
    }

    /// 是否存在“已落盘但有改动未保存”的文档
    func hasUnsavedFileBackedMarkdownDocuments() -> Bool {
        markdownTabs.contains { $0.editor.fileURL != nil && $0.editor.hasUnsavedChanges }
    }

    /// 对“已落盘但有改动未保存”的文档执行自动保存
    func autoSaveUnsavedFileBackedMarkdownDocuments(completion: @escaping (Bool) -> Void) {
        let tabsToSave = markdownTabs.filter { $0.editor.fileURL != nil && $0.editor.hasUnsavedChanges }
        guard !tabsToSave.isEmpty else {
            completion(true)
            return
        }
        saveFileBackedMarkdownTabs(ArraySlice(tabsToSave), completion: completion)
    }

    /// 对“未保存到磁盘且有改动”的文档逐个触发保存提示（不负责退出应用）
    func promptSaveForUnsavedNewMarkdownDocuments(completion: @escaping () -> Void) {
        let tabsToPrompt = markdownTabs.filter { $0.editor.fileURL == nil && $0.editor.hasUnsavedChanges }
        guard !tabsToPrompt.isEmpty else {
            completion()
            return
        }
        promptSaveForNewMarkdownTabs(ArraySlice(tabsToPrompt), completion: completion)
    }

    /// 设置 Markdown 主题模式
    func setMarkdownThemeMode(_ mode: MarkdownEditorThemeMode) {
        UserPreferences.shared.markdownThemeMode = mode
        for tab in markdownTabs {
            tab.editor.setThemeMode(mode)
        }
    }

    /// Markdown 放大
    func zoomInMarkdownEditor() {
        currentMarkdownTab()?.editor.zoomIn()
    }

    /// Markdown 缩小
    func zoomOutMarkdownEditor() {
        currentMarkdownTab()?.editor.zoomOut()
    }

    /// 恢复编辑器可见性状态（应用启动时调用）
    func restoreMarkdownEditorVisibility() {
        if restorePreviouslyOpenedMarkdownFilesIfNeeded() {
            return
        }
        if UserPreferences.shared.markdownEditorVisible {
            isMarkdownEditorVisible = true
            showMarkdownEditor(animated: false)
        }
    }

    private func showMarkdownEditor(animated: Bool, createInitialTab: Bool = true) {
        // 计算目标布局
        let targetFrames = calculateTargetFramesWithEditor()

        // 先设置 frame，确保子视图能获得正确的尺寸
        leftAreaView.frame = targetFrames.left
        centerEditorAreaView.frame = targetFrames.editor
        rightAreaView.frame = targetFrames.right
        // 强制 Auto Layout 立即更新子视图布局
        centerEditorAreaView.layoutSubtreeIfNeeded()

        // 现在创建标签页 - 此时 markdownTabView 已有正确尺寸
        if createInitialTab, markdownTabs.isEmpty {
            _ = createMarkdownTab(title: L10n.markdown.untitled)
        }

        if animated {
            isAnimatingManualLayout = true

            centerEditorAreaView.alphaValue = 0
            centerEditorAreaView.isHidden = false
            updatePanelFrames()

            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.22
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                context.allowsImplicitAnimation = true

                centerEditorAreaView.animator().alphaValue = 1

                updatePanelFrames()
            }, completionHandler: { [weak self] in
                self?.isAnimatingManualLayout = false
                // 动画完成后再次强制布局，确保所有视图状态正确
                self?.centerEditorAreaView.layoutSubtreeIfNeeded()
            })
        } else {
            // 显示中间区域
            centerEditorAreaView.isHidden = false
            centerEditorAreaView.alphaValue = 1
            updatePanelFrames()
        }
    }

    private func hideMarkdownEditor(animated: Bool) {
        if animated {
            isAnimatingManualLayout = true
            let targetFrames = calculateTargetFramesWithoutEditor()

            // 设备区域直接切到目标位置，编辑器仅淡出
            leftAreaView.frame = targetFrames.left
            rightAreaView.frame = targetFrames.right
            updatePanelFrames()

            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.2
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                context.allowsImplicitAnimation = true

                centerEditorAreaView.animator().alphaValue = 0

                updatePanelFrames()
            }, completionHandler: { [weak self] in
                guard let self else { return }
                self.centerEditorAreaView.isHidden = true
                self.centerEditorAreaView.alphaValue = 1
                self.isAnimatingManualLayout = false
                self.updateLayout(animated: false)
            })
        } else {
            centerEditorAreaView.isHidden = true
            updateLayout(animated: false)
        }
    }

    private func ensureMarkdownEditorVisible(createInitialTab: Bool) {
        if !isMarkdownEditorVisible {
            isMarkdownEditorVisible = true
            UserPreferences.shared.markdownEditorVisible = true
            showMarkdownEditor(animated: true, createInitialTab: createInitialTab)
        }
    }

    private func updateMarkdownTabBarVisibilityForCurrentMode() {
        let shouldHideTabBar = isFullScreen
        markdownTabBarHeightConstraint?.constant = shouldHideTabBar ? 0 : markdownTabBarHeight
        markdownTabBarView.isHidden = shouldHideTabBar
        markdownAddTabButton.isHidden = shouldHideTabBar
        updateMarkdownTabBarAppearance()
        centerEditorAreaView.needsLayout = true
        centerEditorAreaView.layoutSubtreeIfNeeded()
    }

    private func updateMarkdownTabBarAppearance() {
        markdownTabBarView.layer?.borderWidth = 0
        markdownTabBarView.layer?.borderColor = nil
    }

    private func startMarkdownUnsavedStateTimer() {
        guard markdownUnsavedStateTimer == nil else { return }
        markdownUnsavedStateTimer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: true) { [weak self] _ in
            self?.refreshMarkdownTabUnsavedIndicators()
        }
        if let markdownUnsavedStateTimer {
            RunLoop.main.add(markdownUnsavedStateTimer, forMode: .common)
        }
    }

    private func refreshMarkdownTabUnsavedIndicators() {
        guard !markdownTabs.isEmpty else { return }
        for tab in markdownTabs {
            refreshTabTitle(for: tab)
        }
    }

    // MARK: - 预览切换按钮

    private func setupPreviewToggleButton() {
        previewToggleButton.target = self
        previewToggleButton.action = #selector(previewToggleButtonClicked(_:))
        previewToggleButton.toolTip = L10n.markdown.preview
        centerEditorAreaView.addSubview(previewToggleButton)
    }

    @objc private func previewToggleButtonClicked(_ sender: Any?) {
        guard let editor = currentMarkdownTab()?.editor else { return }
        editor.togglePreview()
        updatePreviewToggleButtonIcon()
    }

    /// 更新预览切换按钮的显示状态（全屏 + 编辑器可见时显示）
    private func updatePreviewToggleButton() {
        let shouldShow = isFullScreen && isMarkdownEditorVisible
        previewToggleButton.isHidden = !shouldShow
        if shouldShow {
            updatePreviewToggleButtonIcon()
            updatePreviewToggleButtonStyle()
            layoutPreviewToggleButton()
        }
    }

    /// 根据当前预览模式状态更新按钮图标
    private func updatePreviewToggleButtonIcon() {
        let isPreview = currentMarkdownTab()?.editor.isPreviewMode ?? false
        let iconName = isPreview ? "pencil" : "eye"
        let tooltip = isPreview ? L10n.toolbar.markdownEditor : L10n.markdown.preview
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        previewToggleButton.image = NSImage(
            systemSymbolName: iconName,
            accessibilityDescription: tooltip
        )?.withSymbolConfiguration(config)
        previewToggleButton.toolTip = tooltip
        previewToggleButton.contentTintColor = .white
    }

    /// 更新预览切换按钮样式（全屏暗色风格）
    private func updatePreviewToggleButtonStyle() {
        guard let layer = previewToggleButton.layer else { return }
        layer.backgroundColor = NSColor.white.withAlphaComponent(0.15).cgColor
        layer.borderColor = NSColor.white.withAlphaComponent(0.3).cgColor
        layer.borderWidth = 1
        layer.cornerRadius = 6
    }

    /// 布局预览切换按钮（编辑器区域右上角）
    private func layoutPreviewToggleButton() {
        let size: CGFloat = 28
        let margin: CGFloat = 8
        let editorFrame = centerEditorAreaView.frame
        // 相对于 centerEditorAreaView 内部的右上角
        previewToggleButton.frame = CGRect(
            x: editorFrame.width - size - margin,
            y: editorFrame.height - size - margin,
            width: size,
            height: size
        )
    }

    /// 将 isFullScreen 状态传播到所有 Markdown 编辑器
    private func updateMarkdownEditorsFullScreenState() {
        for tab in markdownTabs {
            tab.editor.isFullScreen = isFullScreen
        }
    }

    @objc private func newTabButtonClicked(_ sender: Any?) {
        newMarkdownTab()
    }

    @objc private func contextMenuNewTab(_ sender: Any?) {
        newMarkdownTab()
    }

    @objc private func contextMenuCloseTab(_ sender: Any?) {
        guard let tab = contextMenuTab else { return }
        closeMarkdownTab(withID: tab.id)
    }

    @objc private func contextMenuCloseOtherTabs(_ sender: Any?) {
        guard let contextTab = contextMenuTab else { return }
        let tabsToClose = markdownTabs.filter { $0.id != contextTab.id }
        closeTabsAfterConfirmation(tabsToClose)
    }

    @objc private func contextMenuCloseTabsToRight(_ sender: Any?) {
        guard let contextTab = contextMenuTab,
              let contextIndex = markdownTabs.firstIndex(where: { $0.id == contextTab.id }) else {
            return
        }
        guard contextIndex + 1 < markdownTabs.count else { return }
        let tabsToClose = Array(markdownTabs[(contextIndex + 1)...])
        closeTabsAfterConfirmation(tabsToClose)
    }

    @objc private func contextMenuRevealInFinder(_ sender: Any?) {
        guard let url = contextMenuTab?.editor.fileURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    @objc private func contextMenuCopyFilePath(_ sender: Any?) {
        guard let path = contextMenuTab?.editor.fileURL?.path else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(path, forType: .string)
    }

    @objc private func contextMenuRenameFile(_ sender: Any?) {
        guard let tab = contextMenuTab,
              let originalURL = tab.editor.fileURL,
              let window else {
            return
        }
        guard !tab.editor.hasUnsavedChanges else {
            NSSound.beep()
            return
        }

        let textField = NSTextField(string: originalURL.deletingPathExtension().lastPathComponent)
        textField.frame = NSRect(x: 0, y: 0, width: 320, height: 24)
        textField.placeholderString = originalURL.lastPathComponent

        let alert = NSAlert()
        alert.messageText = L10n.markdown.rename
        alert.informativeText = L10n.markdown.renamePrompt
        alert.alertStyle = .informational
        alert.accessoryView = textField
        alert.addButton(withTitle: L10n.common.ok)
        alert.addButton(withTitle: L10n.common.cancel)

        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            self?.renameMarkdownFile(tabID: tab.id, originalURL: originalURL, newBaseName: textField.stringValue)
        }
    }

    private func renameMarkdownFile(tabID: UUID, originalURL: URL, newBaseName: String) {
        let trimmed = newBaseName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard let tab = tab(for: tabID) else { return }

        var destinationURL = originalURL.deletingLastPathComponent().appendingPathComponent(trimmed)
        if !originalURL.pathExtension.isEmpty {
            destinationURL.appendPathExtension(originalURL.pathExtension)
        }

        guard destinationURL != originalURL else { return }

        let fileManager = FileManager.default
        guard !fileManager.fileExists(atPath: destinationURL.path) else {
            NSSound.beep()
            return
        }

        do {
            try fileManager.moveItem(at: originalURL, to: destinationURL)
            try tab.editor.open(url: destinationURL)
            refreshTabTitle(for: tab, fallbackTitle: destinationURL.lastPathComponent)
            syncRecentMarkdownPathsAfterRename(from: originalURL.path, to: destinationURL.path)
            persistOpenedMarkdownFilePaths()
        } catch {
            NSSound.beep()
            AppLogger.app.error("重命名 Markdown 文件失败: \(error.localizedDescription)")
        }
    }

    private func syncRecentMarkdownPathsAfterRename(from oldPath: String, to newPath: String) {
        if UserPreferences.shared.markdownLastFilePath == oldPath {
            UserPreferences.shared.markdownLastFilePath = newPath
        }

        var recents = UserPreferences.shared.recentMarkdownFiles
        recents.removeAll { $0 == oldPath || $0 == newPath }
        recents.insert(newPath, at: 0)
        UserPreferences.shared.recentMarkdownFiles = recents
    }

    private func persistOpenedMarkdownFilePaths() {
        let paths = markdownTabs.compactMap { $0.editor.fileURL?.path }
        UserPreferences.shared.markdownOpenedFilePaths = paths
    }

    private func reusableSingleEmptyMarkdownTab() -> MarkdownTab? {
        guard markdownTabs.count == 1, let onlyTab = markdownTabs.first else {
            return nil
        }
        guard onlyTab.editor.fileURL == nil else {
            return nil
        }
        guard !onlyTab.editor.hasUnsavedChanges else {
            return nil
        }
        return onlyTab
    }

    @discardableResult
    private func openMarkdownFile(at url: URL, in tab: MarkdownTab, removeTabOnFailure: Bool) -> Bool {
        do {
            try tab.editor.open(url: url)
            refreshTabTitle(for: tab, fallbackTitle: url.lastPathComponent)
            return true
        } catch {
            if removeTabOnFailure {
                removeMarkdownTab(tab)
            }
            AppLogger.app.error("打开 Markdown 文件失败: \(error.localizedDescription)")
            return false
        }
    }

    private func restorePreviouslyOpenedMarkdownFilesIfNeeded() -> Bool {
        let existingURLs = resolveExistingMarkdownFileURLs(from: UserPreferences.shared.markdownOpenedFilePaths)
        guard !existingURLs.isEmpty else {
            UserPreferences.shared.markdownOpenedFilePaths = []
            return false
        }

        isMarkdownEditorVisible = true
        UserPreferences.shared.markdownEditorVisible = true
        showMarkdownEditor(animated: false, createInitialTab: false)

        for url in existingURLs {
            let tab = createMarkdownTab(title: url.lastPathComponent)
            _ = openMarkdownFile(at: url, in: tab, removeTabOnFailure: true)
        }

        if let lastURL = existingURLs.last {
            UserPreferences.shared.markdownLastFilePath = lastURL.path
        }
        persistOpenedMarkdownFilePaths()
        return !markdownTabs.isEmpty
    }

    private func resolveExistingMarkdownFileURLs(from paths: [String]) -> [URL] {
        let fileManager = FileManager.default
        return paths.compactMap { path in
            guard !path.isEmpty, fileManager.fileExists(atPath: path) else {
                return nil
            }
            return URL(fileURLWithPath: path)
        }
    }

    private func closeMarkdownTab(withID tabID: UUID) {
        guard let tab = tab(for: tabID) else { return }
        tab.editor.requestCloseIfNeeded { [weak self] shouldClose in
            guard let self, shouldClose else { return }
            self.removeMarkdownTab(tab)
            if self.markdownTabs.isEmpty {
                let newTab = self.createMarkdownTab(title: L10n.markdown.untitled)
                newTab.editor.setContent("")
                self.refreshTabTitle(for: newTab, fallbackTitle: L10n.markdown.untitled)
            }
        }
    }

    private func closeTabsAfterConfirmation(_ tabs: [MarkdownTab]) {
        guard !tabs.isEmpty else { return }
        requestCloseForTabs(ArraySlice(tabs)) { [weak self] shouldClose in
            guard let self, shouldClose else { return }
            for tab in tabs {
                if let latestTab = self.tab(for: tab.id) {
                    self.removeMarkdownTab(latestTab)
                }
            }
            if self.markdownTabs.isEmpty {
                let newTab = self.createMarkdownTab(title: L10n.markdown.untitled)
                newTab.editor.setContent("")
                self.refreshTabTitle(for: newTab, fallbackTitle: L10n.markdown.untitled)
            }
        }
    }

    private func tab(for id: UUID) -> MarkdownTab? {
        markdownTabs.first { $0.id == id }
    }

    private var contextMenuTab: MarkdownTab? {
        guard let contextMenuTabID else { return nil }
        return tab(for: contextMenuTabID)
    }

    private func makeTabContextMenu(for tabID: UUID) -> NSMenu {
        contextMenuTabID = tabID
        if let tab = tab(for: tabID) {
            markdownTabView.selectTabViewItem(tab.item)
        }
        let hasFileURL = contextMenuTab?.editor.fileURL != nil
        let canRenameFile = hasFileURL && !(contextMenuTab?.editor.hasUnsavedChanges ?? true)

        let menu = NSMenu()
        menu.autoenablesItems = false

        let newTabItem = menu.addItem(
            withTitle: L10n.markdown.newTab,
            action: #selector(contextMenuNewTab(_:)),
            keyEquivalent: ""
        )
        newTabItem.target = self
        newTabItem.image = NSImage(systemSymbolName: "plus", accessibilityDescription: nil)

        let closeTabItem = menu.addItem(
            withTitle: L10n.markdown.closeTab,
            action: #selector(contextMenuCloseTab(_:)),
            keyEquivalent: ""
        )
        closeTabItem.target = self
        closeTabItem.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: nil)

        let closeOtherTabsItem = menu.addItem(
            withTitle: L10n.markdown.closeOtherTabs,
            action: #selector(contextMenuCloseOtherTabs(_:)),
            keyEquivalent: ""
        )
        closeOtherTabsItem.target = self
        closeOtherTabsItem.isEnabled = markdownTabs.count > 1
        closeOtherTabsItem.image = NSImage(systemSymbolName: "xmark.circle", accessibilityDescription: nil)

        let closeTabsToRightItem = menu.addItem(
            withTitle: L10n.markdown.closeTabsToRight,
            action: #selector(contextMenuCloseTabsToRight(_:)),
            keyEquivalent: ""
        )
        closeTabsToRightItem.target = self
        if let contextIndex = markdownTabs.firstIndex(where: { $0.id == tabID }) {
            closeTabsToRightItem.isEnabled = contextIndex < markdownTabs.count - 1
        } else {
            closeTabsToRightItem.isEnabled = false
        }
        closeTabsToRightItem.image = NSImage(systemSymbolName: "arrow.right.circle", accessibilityDescription: nil)

        menu.addItem(NSMenuItem.separator())

        let revealInFinderItem = menu.addItem(
            withTitle: L10n.markdown.revealInFinder,
            action: #selector(contextMenuRevealInFinder(_:)),
            keyEquivalent: ""
        )
        revealInFinderItem.target = self
        revealInFinderItem.image = NSImage(systemSymbolName: "folder", accessibilityDescription: nil)
        revealInFinderItem.isEnabled = hasFileURL

        let copyFilePathItem = menu.addItem(
            withTitle: L10n.markdown.copyFilePath,
            action: #selector(contextMenuCopyFilePath(_:)),
            keyEquivalent: ""
        )
        copyFilePathItem.target = self
        copyFilePathItem.image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: nil)
        copyFilePathItem.isEnabled = hasFileURL

        let renameFileItem = menu.addItem(
            withTitle: L10n.markdown.rename,
            action: #selector(contextMenuRenameFile(_:)),
            keyEquivalent: ""
        )
        renameFileItem.target = self
        renameFileItem.image = NSImage(systemSymbolName: "pencil", accessibilityDescription: nil)
        renameFileItem.isEnabled = canRenameFile

        return menu
    }

    private func syncTabSelectionAppearance() {
        let selectedTabID = currentMarkdownTab()?.id
        for tab in markdownTabs {
            tab.buttonView.isSelected = (tab.id == selectedTabID)
        }
    }

    @discardableResult
    private func createMarkdownTab(title: String) -> MarkdownTab {
        let editorVC = MarkdownEditorView()
        editorVC.setThemeMode(UserPreferences.shared.markdownThemeMode, animated: false)

        let tabID = UUID()
        let item = NSTabViewItem(identifier: UUID())
        item.label = title
        item.view = editorVC.view
        markdownTabView.addTabViewItem(item)

        let buttonView = MarkdownTabButtonView()
        buttonView.title = title
        buttonView.onSelect = { [weak self, weak item] in
            guard let self, let item else { return }
            self.markdownTabView.selectTabViewItem(item)
        }
        buttonView.onClose = { [weak self] in
            self?.closeMarkdownTab(withID: tabID)
        }
        buttonView.menuProvider = { [weak self] in
            self?.makeTabContextMenu(for: tabID)
        }
        markdownTabButtonsStack.addArrangedSubview(buttonView)

        let tab = MarkdownTab(id: tabID, item: item, editor: editorVC, buttonView: buttonView)
        markdownTabs.append(tab)
        markdownTabView.selectTabViewItem(item)
        markdownEditorView = editorVC
        syncTabSelectionAppearance()

        // 传播全屏状态到新建的编辑器
        editorVC.isFullScreen = isFullScreen

        // 监听文档标题变化，自动更新标签页标题（仅对未保存文档生效）
        editorVC.onSuggestedTitleChange = { [weak self] title in
            guard let self, let tab = self.markdownTabs.first(where: { $0.id == tabID }) else { return }
            self.refreshTabTitle(for: tab, fallbackTitle: title ?? L10n.markdown.untitled)
        }

        // 监听预览模式变化，同步全屏预览/编辑切换按钮图标
        editorVC.onPreviewModeChange = { [weak self] _ in
            self?.updatePreviewToggleButtonIcon()
        }

        // 强制编辑器视图立即布局，确保 formatBar 获得正确的 bounds
        // 这在首次创建标签页时尤其重要，因为此时 tab view 的尺寸可能还未确定
        DispatchQueue.main.async { [weak editorVC] in
            editorVC?.view.layoutSubtreeIfNeeded()
        }

        return tab
    }

    private func removeMarkdownTab(_ tab: MarkdownTab) {
        markdownTabButtonsStack.removeArrangedSubview(tab.buttonView)
        tab.buttonView.removeFromSuperview()
        markdownTabView.removeTabViewItem(tab.item)
        markdownTabs.removeAll { $0.id == tab.id }
        markdownEditorView = currentMarkdownTab()?.editor
        syncTabSelectionAppearance()
        persistOpenedMarkdownFilePaths()
    }

    private func currentMarkdownTab() -> MarkdownTab? {
        guard let selectedItem = markdownTabView.selectedTabViewItem else {
            return markdownTabs.first
        }
        return markdownTabs.first { $0.item === selectedItem }
    }

    private func refreshTabTitle(for tab: MarkdownTab, fallbackTitle: String? = nil) {
        let baseTitle: String = {
            // 对于未保存的文档，优先使用文档标题（来自第一个标题）
            if tab.editor.fileURL == nil, let suggestedTitle = tab.editor.suggestedTitle, !suggestedTitle.isEmpty {
                return suggestedTitle
            }
            let resolved = tab.editor.fileURL?.lastPathComponent ?? fallbackTitle ?? tab.item.label
            return resolved.isEmpty ? L10n.markdown.untitled : resolved
        }()

        let finalTitle = decorateMarkdownTabTitle(baseTitle: baseTitle, editor: tab.editor)
        tab.item.label = finalTitle
        tab.buttonView.title = finalTitle
    }

    private func decorateMarkdownTabTitle(baseTitle: String, editor: MarkdownEditorView) -> String {
        let needsUnsavedMarker = (editor.fileURL == nil) || editor.hasUnsavedChanges
        guard needsUnsavedMarker else {
            return baseTitle
        }
        return baseTitle.hasSuffix(markdownUnsavedTabSuffix) ? baseTitle : (baseTitle + markdownUnsavedTabSuffix)
    }

    private func waitForSaveAsResult(
        for tabID: UUID,
        previousURL: URL?,
        warmupAttempts: Int,
        completion: ((URL?) -> Void)?
    ) {
        guard let tab = tab(for: tabID) else {
            completion?(nil)
            return
        }

        let currentURL = tab.editor.fileURL
        if let currentURL, currentURL != previousURL {
            refreshTabTitle(for: tab, fallbackTitle: currentURL.lastPathComponent)
            persistOpenedMarkdownFilePaths()
            completion?(currentURL)
            return
        }

        let hasAttachedSheet = window?.attachedSheet != nil
        if !hasAttachedSheet {
            if warmupAttempts > 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
                    self?.waitForSaveAsResult(
                        for: tabID,
                        previousURL: previousURL,
                        warmupAttempts: warmupAttempts - 1,
                        completion: completion
                    )
                }
                return
            }
            completion?(nil)
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
            self?.waitForSaveAsResult(
                for: tabID,
                previousURL: previousURL,
                warmupAttempts: warmupAttempts,
                completion: completion
            )
        }
    }

    private func presentMarkdownSaveError(_ error: Error?) {
        let detail = error?.localizedDescription ?? L10n.common.error
        AppLogger.app.error("Markdown 保存失败: \(detail)")
        NSSound.beep()

        guard let window else { return }
        let alert = NSAlert()
        alert.messageText = L10n.common.error
        alert.informativeText = detail
        alert.alertStyle = .warning
        alert.addButton(withTitle: L10n.common.ok)
        alert.beginSheetModal(for: window)
    }

    private func requestCloseForTabs(_ tabs: ArraySlice<MarkdownTab>, completion: @escaping (Bool) -> Void) {
        guard let first = tabs.first else {
            completion(true)
            return
        }

        first.editor.requestCloseIfNeeded { [weak self] shouldClose in
            guard let self else { return }
            guard shouldClose else {
                completion(false)
                return
            }
            self.requestCloseForTabs(tabs.dropFirst(), completion: completion)
        }
    }

    private func promptSaveForNewMarkdownTabs(_ tabs: ArraySlice<MarkdownTab>, completion: @escaping () -> Void) {
        guard let first = tabs.first else {
            completion()
            return
        }

        first.editor.requestCloseIfNeeded { [weak self] shouldContinue in
            guard let self else {
                completion()
                return
            }
            self.refreshTabTitle(for: first)
            self.persistOpenedMarkdownFilePaths()

            guard shouldContinue else {
                completion()
                return
            }
            self.promptSaveForNewMarkdownTabs(tabs.dropFirst(), completion: completion)
        }
    }

    private func saveFileBackedMarkdownTabs(_ tabs: ArraySlice<MarkdownTab>, completion: @escaping (Bool) -> Void) {
        guard let first = tabs.first else {
            completion(true)
            return
        }

        do {
            try first.editor.save()
        } catch {
            AppLogger.app.error("自动保存 Markdown 文件失败: \(error.localizedDescription)")
            completion(false)
            return
        }

        waitUntilMarkdownTabSaved(first.id, remainingAttempts: 80) { [weak self] saved in
            guard let self else {
                completion(false)
                return
            }
            guard saved else {
                AppLogger.app.error("自动保存 Markdown 文件超时: \(first.item.label)")
                completion(false)
                return
            }
            self.refreshTabTitle(for: first)
            self.persistOpenedMarkdownFilePaths()
            self.saveFileBackedMarkdownTabs(tabs.dropFirst(), completion: completion)
        }
    }

    private func waitUntilMarkdownTabSaved(_ tabID: UUID, remainingAttempts: Int, completion: @escaping (Bool) -> Void) {
        guard let tab = tab(for: tabID) else {
            completion(false)
            return
        }
        if !tab.editor.hasUnsavedChanges {
            completion(true)
            return
        }
        guard remainingAttempts > 0 else {
            completion(false)
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.waitUntilMarkdownTabSaved(tabID, remainingAttempts: remainingAttempts - 1, completion: completion)
        }
    }

    func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
        guard tabView === markdownTabView else { return }
        markdownEditorView = currentMarkdownTab()?.editor
        syncTabSelectionAppearance()
        // 切换标签页后更新预览切换按钮图标
        if !previewToggleButton.isHidden {
            updatePreviewToggleButtonIcon()
        }
    }

    /// 计算编辑器可见时的目标布局
    private func calculateTargetFramesWithEditor() -> (left: CGRect, editor: CGRect, right: CGRect) {
        let fullBounds = bounds

        // 单设备模式特殊处理
        if layoutMode == .leftOnly || layoutMode == .rightOnly {
            let singleDeviceWidth = fullBounds.width * 0.55
            let editorWidth = fullBounds.width - singleDeviceWidth

            if layoutMode == .leftOnly {
                // 仅左设备时：设备在左，编辑器在右
                return (
                    left: CGRect(x: 0, y: 0, width: singleDeviceWidth, height: fullBounds.height),
                    editor: CGRect(x: singleDeviceWidth, y: 0, width: editorWidth, height: fullBounds.height),
                    right: .zero
                )
            } else {
                // 仅右设备时：编辑器在左，设备在右
                return (
                    left: .zero,
                    editor: CGRect(x: 0, y: 0, width: editorWidth, height: fullBounds.height),
                    right: CGRect(x: editorWidth, y: 0, width: singleDeviceWidth, height: fullBounds.height)
                )
            }
        }

        // 双设备模式
        let editorWidth = fullBounds.width * editorWidthRatio
        let deviceWidth = (fullBounds.width - editorWidth) / 2

        switch markdownEditorPosition {
        case .center:
            return (
                left: CGRect(x: 0, y: 0, width: deviceWidth, height: fullBounds.height),
                editor: CGRect(x: deviceWidth, y: 0, width: editorWidth, height: fullBounds.height),
                right: CGRect(x: deviceWidth + editorWidth, y: 0, width: deviceWidth, height: fullBounds.height)
            )
        case .left:
            return (
                left: CGRect(x: editorWidth, y: 0, width: deviceWidth, height: fullBounds.height),
                editor: CGRect(x: 0, y: 0, width: editorWidth, height: fullBounds.height),
                right: CGRect(x: editorWidth + deviceWidth, y: 0, width: deviceWidth, height: fullBounds.height)
            )
        case .right:
            return (
                left: CGRect(x: 0, y: 0, width: deviceWidth, height: fullBounds.height),
                editor: CGRect(x: deviceWidth * 2, y: 0, width: editorWidth, height: fullBounds.height),
                right: CGRect(x: deviceWidth, y: 0, width: deviceWidth, height: fullBounds.height)
            )
        }
    }

    /// 计算无编辑器时的目标布局
    private func calculateTargetFramesWithoutEditor() -> (left: CGRect, right: CGRect) {
        let fullBounds = bounds

        switch layoutMode {
        case .dual:
            let halfWidth = fullBounds.width / 2
            return (
                left: CGRect(x: 0, y: 0, width: halfWidth, height: fullBounds.height),
                right: CGRect(x: halfWidth, y: 0, width: halfWidth, height: fullBounds.height)
            )
        case .leftOnly:
            return (
                left: fullBounds,
                right: .zero
            )
        case .rightOnly:
            return (
                left: .zero,
                right: fullBounds
            )
        }
    }
}
