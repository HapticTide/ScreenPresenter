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
import AVFoundation

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
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = L10n.window.preferences
        window.titlebarSeparatorStyle = .none
        window.titlebarAppearsTransparent = true
        window.center()
        // 禁用初始焦点，避免显示 tab 焦点环
        window.initialFirstResponder = nil
        window.autorecalculatesKeyViewLoop = false

        // 添加空 toolbar 以匹配主窗口风格（影响 titlebar 和圆角）
        let toolbar = NSToolbar(identifier: "PreferencesToolbar")
        toolbar.displayMode = .iconOnly
        toolbar.showsBaselineSeparator = false
        window.toolbar = toolbar

        self.init(window: window)

        window.contentViewController = PreferencesViewController()
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        window?.center()
        // 清除焦点，避免显示焦点环
        window?.makeFirstResponder(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: - Flipped View（坐标系从上向下）

private class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

private final class FlexibleSpacerView: NSView {
    var minLength: CGFloat = 0
}

private final class FixedSizeTextField: NSTextField {
    var preferredWidth: CGFloat = 0

    override var intrinsicContentSize: NSSize {
        let size = super.intrinsicContentSize
        guard preferredWidth > 0 else { return size }
        return NSSize(width: preferredWidth, height: size.height)
    }
}

private enum LayoutMetrics {
    static let rowMinHeight: CGFloat = 40
    static let rowVerticalPadding: CGFloat = 8
}

private final class PaddingView: NSView {
    private let contentView: NSView
    private let insets: NSEdgeInsets
    private var _tag: Int = 0

    override var tag: Int {
        get { _tag }
        set { _tag = newValue }
    }

    init(contentView: NSView, insets: NSEdgeInsets) {
        self.contentView = contentView
        self.insets = insets
        super.init(frame: .zero)
        addSubview(contentView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool { true }

    func requiredSize(for width: CGFloat) -> CGSize {
        let contentWidth = max(0, width - insets.left - insets.right)
        let contentSize = sizeForView(contentView, maxWidth: contentWidth)
        let totalWidth = width > 0 ? width : contentSize.width + insets.left + insets.right
        return CGSize(
            width: totalWidth,
            height: contentSize.height + insets.top + insets.bottom
        )
    }

    override func layout() {
        super.layout()
        let contentWidth = max(0, bounds.width - insets.left - insets.right)
        let contentHeight = max(0, bounds.height - insets.top - insets.bottom)
        contentView.frame = CGRect(
            x: insets.left,
            y: insets.top,
            width: contentWidth,
            height: contentHeight
        )
        contentView.needsLayout = true
        contentView.layoutSubtreeIfNeeded()
    }

    private func sizeForView(_ view: NSView, maxWidth: CGFloat) -> CGSize {
        if let labeledRow = view as? LabeledRowView {
            return labeledRow.requiredSize(for: maxWidth)
        }
        if let stackView = view as? StackContainerView {
            let size = stackView.requiredSize(for: maxWidth)
            let width = stackView.fillsCrossAxis ? maxWidth : size.width
            return CGSize(width: width, height: size.height)
        }
        if let textField = view as? NSTextField {
            let bounds = NSRect(x: 0, y: 0, width: maxWidth, height: .greatestFiniteMagnitude)
            if let size = textField.cell?.cellSize(forBounds: bounds) {
                // 添加少量余量，避免文本被裁剪
                let paddedWidth = min(maxWidth, ceil(size.width) + 2)
                return CGSize(width: paddedWidth, height: size.height)
            }
        }
        let intrinsic = view.intrinsicContentSize
        if intrinsic.width > 0, intrinsic.height > 0 {
            return CGSize(width: min(maxWidth, intrinsic.width), height: intrinsic.height)
        }
        let fitting = view.fittingSize
        return CGSize(width: min(maxWidth, fitting.width), height: fitting.height)
    }
}

private final class StackContainerView: NSView {
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
            return CGSize(width: maxWidth + edgeInsets.left + edgeInsets.right, height: totalHeight)
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
                let x = alignedX(for: size.width, availableWidth: availableWidth)
                view.frame = CGRect(
                    x: edgeInsets.left + x,
                    y: y,
                    width: size.width,
                    height: size.height
                )
                // 只标记需要布局，由系统统一处理
                view.needsLayout = true
                y += size.height
                if index < visible.count - 1 {
                    y += spacing
                }
            }
        case .horizontal:
            let visible = arrangedSubviews.filter { !$0.isHidden }
            var sizes: [CGSize] = []
            var totalPreferredWidth: CGFloat = 0
            var totalPreferredHeight: CGFloat = 0
            var shrinkableIndices: [Int] = []
            var spacerIndices: [Int] = []

            for (index, view) in visible.enumerated() {
                let size = sizeForView(view, maxWidth: availableWidth)
                sizes.append(size)
                totalPreferredWidth += size.width
                totalPreferredHeight = max(totalPreferredHeight, size.height)

                if view is FlexibleSpacerView {
                    spacerIndices.append(index)
                } else if flexibleViews.contains(ObjectIdentifier(view)) {
                    shrinkableIndices.append(index)
                }
            }

            let totalSpacing = spacing * CGFloat(max(0, visible.count - 1))
            let totalWidthWithSpacing = totalPreferredWidth + totalSpacing

            if totalWidthWithSpacing > availableWidth, !shrinkableIndices.isEmpty {
                let overflow = totalWidthWithSpacing - availableWidth
                let shrinkableWidth = shrinkableIndices.reduce(CGFloat(0)) { $0 + sizes[$1].width }
                let shrinkRatio = shrinkableWidth > 0 ? max(0, (shrinkableWidth - overflow) / shrinkableWidth) : 0
                for index in shrinkableIndices {
                    sizes[index].width = max(0, sizes[index].width * shrinkRatio)
                }
            }

            var adjustedWidth: CGFloat = sizes.reduce(0) { $0 + $1.width } + totalSpacing
            if adjustedWidth < availableWidth, !spacerIndices.isEmpty {
                let remaining = availableWidth - adjustedWidth
                let extraPerSpacer = remaining / CGFloat(spacerIndices.count)
                for index in spacerIndices {
                    sizes[index].width = max(
                        (visible[index] as? FlexibleSpacerView)?.minLength ?? 0,
                        sizes[index].width + extraPerSpacer
                    )
                }
                adjustedWidth = sizes.reduce(0) { $0 + $1.width } + totalSpacing
            }

            if adjustedWidth < availableWidth, spacerIndices.isEmpty, !shrinkableIndices.isEmpty {
                let remaining = availableWidth - adjustedWidth
                let extraPerFlexible = remaining / CGFloat(shrinkableIndices.count)
                for index in shrinkableIndices {
                    sizes[index].width = max(0, sizes[index].width + extraPerFlexible)
                }
                adjustedWidth = sizes.reduce(0) { $0 + $1.width } + totalSpacing
            }

            var x = edgeInsets.left
            for (index, view) in visible.enumerated() {
                let size = sizes[index]
                let y = alignedY(for: size.height, availableHeight: availableHeight)
                view.frame = CGRect(
                    x: x,
                    y: edgeInsets.top + y,
                    width: size.width,
                    height: size.height
                )
                // 只标记需要布局，由系统统一处理
                view.needsLayout = true
                x += size.width
                if index < visible.count - 1 {
                    x += spacing
                }
            }
        }
    }

    private func alignedX(for width: CGFloat, availableWidth: CGFloat) -> CGFloat {
        switch alignment {
        case .leading, .top, .centerY, .bottom:
            0
        case .center:
            max(0, (availableWidth - width) / 2)
        case .trailing:
            max(0, availableWidth - width)
        }
    }

    private func alignedY(for height: CGFloat, availableHeight: CGFloat) -> CGFloat {
        switch alignment {
        case .top:
            0
        case .centerY, .center:
            max(0, (availableHeight - height) / 2)
        case .bottom:
            max(0, availableHeight - height)
        case .leading, .trailing:
            0
        }
    }

    private func sizeForView(_ view: NSView, maxWidth: CGFloat) -> CGSize {
        if let labeledRow = view as? LabeledRowView {
            return labeledRow.requiredSize(for: maxWidth)
        }
        if let paddingView = view as? PaddingView {
            return paddingView.requiredSize(for: maxWidth)
        }
        if let box = view as? NSBox, box.boxType == .separator {
            let height = max(1, box.frame.height)
            return CGSize(width: maxWidth, height: height)
        }
        if let textField = view as? FixedSizeTextField, textField.preferredWidth > 0 {
            let height = max(0, textField.intrinsicContentSize.height)
            return CGSize(width: min(maxWidth, textField.preferredWidth), height: height)
        }
        if view is NSSlider, view.frame.width > 0 {
            return CGSize(width: min(maxWidth, view.frame.width), height: max(0, view.frame.height))
        }
        if let imageView = view as? NSImageView {
            let imageSize = imageView.image?.size ?? .zero
            let width = max(imageView.frame.width, imageSize.width)
            let height = max(imageView.frame.height, imageSize.height)
            if width > 0 || height > 0 {
                return CGSize(width: min(maxWidth, max(0, width)), height: max(0, height))
            }
        }
        if let stackView = view as? StackContainerView {
            let baseWidth = view.frame.width > 0 ? min(view.frame.width, maxWidth) : maxWidth
            let size = stackView.requiredSize(for: baseWidth)
            let finalWidth: CGFloat = if stackView.fillsCrossAxis {
                maxWidth
            } else if view.frame.width > 0 {
                baseWidth
            } else {
                size.width
            }
            return CGSize(width: finalWidth, height: size.height)
        }
        // NSTextField 必须在 NSControl 之前检查，因为 NSTextField 继承自 NSControl
        if let textField = view as? NSTextField {
            let bounds = NSRect(x: 0, y: 0, width: maxWidth, height: .greatestFiniteMagnitude)
            if let size = textField.cell?.cellSize(forBounds: bounds) {
                // 添加少量余量，避免文本被裁剪
                let paddedWidth = min(maxWidth, ceil(size.width) + 2)
                return CGSize(width: paddedWidth, height: size.height)
            }
        }
        // NSButton 需要在通用 NSControl 之前检查，添加余量确保按钮文字不被裁剪
        if let button = view as? NSButton {
            var size = button.intrinsicContentSize
            if size.width <= 0 || size.height <= 0 {
                button.sizeToFit()
                size = button.frame.size
            }
            if size.width <= 0 || size.height <= 0 {
                size = button.fittingSize
            }
            // 添加少量余量，避免按钮文字被裁剪
            let paddedWidth = min(maxWidth, ceil(size.width) + 4)
            return CGSize(width: paddedWidth, height: max(0, size.height))
        }
        if let control = view as? NSControl {
            var size = control.intrinsicContentSize
            if size.width <= 0 || size.height <= 0 {
                control.sizeToFit()
                size = control.frame.size
            }
            if size.width <= 0 || size.height <= 0 {
                size = control.fittingSize
            }
            let width = min(maxWidth, max(0, size.width))
            let height = max(0, size.height)
            return CGSize(width: width, height: height)
        }
        let intrinsic = view.intrinsicContentSize
        if intrinsic.width > 0, intrinsic.height > 0 {
            return CGSize(width: min(maxWidth, intrinsic.width), height: intrinsic.height)
        }
        let fitting = view.fittingSize
        if fitting.width > 0 || fitting.height > 0 {
            return CGSize(width: min(maxWidth, fitting.width), height: fitting.height)
        }
        return CGSize(width: min(maxWidth, view.frame.width), height: view.frame.height)
    }
}

private final class LabeledRowView: NSView {
    private let labelView: NSView
    private let controlView: NSView
    private let spacing: CGFloat = 12
    private let minRowHeight: CGFloat = LayoutMetrics.rowMinHeight
    private let verticalPadding: CGFloat = LayoutMetrics.rowVerticalPadding

    /// 使用 NSTextField 作为标签
    init(label: NSTextField, control: NSView) {
        labelView = label
        controlView = control
        super.init(frame: .zero)
        addSubview(labelView)
        addSubview(controlView)
    }

    /// 使用任意视图作为标签（用于复杂的左侧布局，如权限行）
    init(labelView: NSView, control: NSView) {
        self.labelView = labelView
        controlView = control
        super.init(frame: .zero)
        addSubview(labelView)
        addSubview(controlView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool { true }

    func requiredSize(for width: CGFloat) -> CGSize {
        let availableWidth = max(0, width)
        let controlSize = sizeForView(controlView, maxWidth: .greatestFiniteMagnitude)
        let labelMaxWidth = max(0, availableWidth - controlSize.width - spacing)
        let labelSize = labelSizeForWidth(labelMaxWidth)
        let contentHeight = max(labelSize.height, controlSize.height)
        let height = max(minRowHeight, contentHeight + verticalPadding * 2)
        return CGSize(width: availableWidth, height: height)
    }

    override func layout() {
        super.layout()
        let availableWidth = bounds.width
        let controlSize = sizeForView(controlView, maxWidth: .greatestFiniteMagnitude)
        let labelWidth = max(0, availableWidth - controlSize.width - spacing)
        let labelSize = labelSizeForWidth(labelWidth)
        let contentHeight = max(0, bounds.height - verticalPadding * 2)
        let labelY = verticalPadding + max(0, (contentHeight - labelSize.height) / 2)
        let controlY = verticalPadding + max(0, (contentHeight - controlSize.height) / 2)

        labelView.frame = CGRect(x: 0, y: labelY, width: labelWidth, height: labelSize.height)
        let controlX = max(0, availableWidth - controlSize.width)
        controlView.frame = CGRect(
            x: controlX,
            y: controlY,
            width: controlSize.width,
            height: controlSize.height
        )
        labelView.needsLayout = true
        labelView.layoutSubtreeIfNeeded()
        controlView.needsLayout = true
        controlView.layoutSubtreeIfNeeded()
    }

    private func labelSizeForWidth(_ width: CGFloat) -> CGSize {
        guard width > 0 else { return .zero }
        // 处理 StackContainerView
        if let stackView = labelView as? StackContainerView {
            return stackView.requiredSize(for: width)
        }
        // 处理 NSTextField
        if let textField = labelView as? NSTextField {
            let bounds = NSRect(x: 0, y: 0, width: width, height: .greatestFiniteMagnitude)
            if let size = textField.cell?.cellSize(forBounds: bounds) {
                return CGSize(width: min(width, size.width), height: size.height)
            }
            let size = textField.intrinsicContentSize
            return CGSize(width: min(width, size.width), height: size.height)
        }
        // 通用处理
        let intrinsic = labelView.intrinsicContentSize
        if intrinsic.width > 0, intrinsic.height > 0 {
            return CGSize(width: min(width, intrinsic.width), height: intrinsic.height)
        }
        let fitting = labelView.fittingSize
        return CGSize(width: min(width, fitting.width), height: fitting.height)
    }

    private func sizeForView(_ view: NSView, maxWidth: CGFloat) -> CGSize {
        if let stackView = view as? StackContainerView {
            return stackView.requiredSize(for: maxWidth)
        }
        if let textField = view as? FixedSizeTextField, textField.preferredWidth > 0 {
            let height = max(0, textField.intrinsicContentSize.height)
            return CGSize(width: min(maxWidth, textField.preferredWidth), height: height)
        }
        if view is NSSlider, view.frame.width > 0 {
            return CGSize(width: min(maxWidth, view.frame.width), height: max(0, view.frame.height))
        }
        if let imageView = view as? NSImageView {
            let imageSize = imageView.image?.size ?? .zero
            let width = max(imageView.frame.width, imageSize.width)
            let height = max(imageView.frame.height, imageSize.height)
            if width > 0 || height > 0 {
                return CGSize(width: min(maxWidth, max(0, width)), height: max(0, height))
            }
        }
        if let textField = view as? NSTextField {
            let bounds = NSRect(x: 0, y: 0, width: maxWidth, height: .greatestFiniteMagnitude)
            if let size = textField.cell?.cellSize(forBounds: bounds) {
                // 添加少量余量，避免文本被裁剪
                let paddedWidth = min(maxWidth, ceil(size.width) + 2)
                return CGSize(width: paddedWidth, height: size.height)
            }
        }
        // NSButton 需要在通用 NSControl 之前检查，添加余量确保按钮文字不被裁剪
        if let button = view as? NSButton {
            var size = button.intrinsicContentSize
            if size.width <= 0 || size.height <= 0 {
                button.sizeToFit()
                size = button.frame.size
            }
            if size.width <= 0 || size.height <= 0 {
                size = button.fittingSize
            }
            // 添加少量余量，避免按钮文字被裁剪
            let paddedWidth = min(maxWidth, ceil(size.width) + 4)
            return CGSize(width: paddedWidth, height: max(0, size.height))
        }
        if let control = view as? NSControl {
            var size = control.intrinsicContentSize
            if size.width <= 0 || size.height <= 0 {
                control.sizeToFit()
                size = control.frame.size
            }
            if size.width <= 0 || size.height <= 0 {
                size = control.fittingSize
            }
            return CGSize(width: min(maxWidth, max(0, size.width)), height: max(0, size.height))
        }
        let intrinsic = view.intrinsicContentSize
        if intrinsic.width > 0, intrinsic.height > 0 {
            return CGSize(width: min(maxWidth, intrinsic.width), height: intrinsic.height)
        }
        let fitting = view.fittingSize
        return CGSize(width: min(maxWidth, fitting.width), height: fitting.height)
    }
}

// MARK: - 偏好设置视图控制器

final class PreferencesViewController: NSViewController {
    // MARK: - UI 组件

    private let segmentedControl = NSSegmentedControl()
    private let contentContainer = NSView()
    private var tabViews: [NSView] = []
    private var currentTabIndex: Int = 0
    private var scrollViewLayouts: [(NSScrollView, StackContainerView)] = []
    private let valueLabelFont = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)

    // MARK: - 生命周期

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 520, height: 450))
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupLanguageObserver()
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        layoutRootViews()
        layoutCurrentTab()
        // 只更新当前显示的 Tab 的 ScrollView 布局
        updateCurrentTabScrollViewLayout()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private func setupLanguageObserver() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleLanguageChange),
            name: LocalizationManager.languageDidChangeNotification,
            object: nil
        )
    }

    @objc private func handleLanguageChange() {
        // 保存当前选中的 tab
        let selectedTab = currentTabIndex

        // 移除所有子视图
        view.subviews.forEach { $0.removeFromSuperview() }
        tabViews.removeAll()

        // 重建 UI
        setupUI()

        // 恢复选中的 tab
        segmentedControl.selectedSegment = selectedTab
        showTab(at: selectedTab)

        // 更新窗口标题
        view.window?.title = L10n.window.preferences
    }

    // MARK: - UI 设置

    private func setupUI() {
        // 创建分段控件
        let labels = [
            L10n.prefs.tab.general,
            L10n.prefs.tab.capture,
            L10n.prefs.tab.permissions,
        ]
        segmentedControl.segmentCount = labels.count
        for (index, label) in labels.enumerated() {
            segmentedControl.setLabel(label, forSegment: index)
        }
        segmentedControl.trackingMode = .selectOne
        segmentedControl.target = self
        segmentedControl.action = #selector(tabChanged(_:))
        segmentedControl.selectedSegment = 0
        segmentedControl.segmentStyle = .automatic
        segmentedControl.focusRingType = .none
        view.addSubview(segmentedControl)

        // 创建内容容器
        view.addSubview(contentContainer)
        layoutRootViews()

        // 创建各个 tab 的视图
        tabViews = [
            createGeneralView(),
            createCaptureView(),
            createPermissionsView(),
        ]

        // 显示第一个 tab
        showTab(at: 0)
    }

    @objc private func tabChanged(_ sender: NSSegmentedControl) {
        showTab(at: sender.selectedSegment)
    }

    private func showTab(at index: Int) {
        guard index >= 0, index < tabViews.count else { return }

        // 移除当前显示的视图
        contentContainer.subviews.forEach { $0.removeFromSuperview() }

        // 添加新视图
        let newView = tabViews[index]
        contentContainer.addSubview(newView)
        newView.frame = contentContainer.bounds
        newView.autoresizingMask = [.width, .height]

        currentTabIndex = index

        // 只更新当前显示的 Tab 的 ScrollView 布局
        updateCurrentTabScrollViewLayout()
    }

    private func layoutRootViews() {
        let segmentedSize = segmentedControl.intrinsicContentSize
        let y = view.bounds.height - 52 - segmentedSize.height
        segmentedControl.frame = CGRect(
            x: (view.bounds.width - segmentedSize.width) / 2,
            y: max(0, y),
            width: segmentedSize.width,
            height: segmentedSize.height
        )
        let contentTop = segmentedControl.frame.minY - 16
        contentContainer.frame = CGRect(
            x: 0,
            y: 0,
            width: view.bounds.width,
            height: max(0, contentTop)
        )
    }

    private func layoutCurrentTab() {
        guard currentTabIndex >= 0, currentTabIndex < tabViews.count else { return }
        let currentView = tabViews[currentTabIndex]
        currentView.frame = contentContainer.bounds
    }

    private func preferredValueWidth(_ text: String, font: NSFont) -> CGFloat {
        let width = (text as NSString).size(withAttributes: [.font: font]).width
        return ceil(width + 6)
    }

    // MARK: - 通用设置

    private func createGeneralView() -> NSView {
        let scrollView = createScrollView()
        let stackView = createVerticalStack()

        // 语言设置组
        let languageGroup = createSettingsGroup(title: L10n.prefs.section.language, icon: "globe")
        addGroupRow(languageGroup, createLabeledRow(label: L10n.prefs.general.language) {
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
        addSettingsGroup(languageGroup, to: stackView)

        // 外观设置组
        let appearanceGroup = createSettingsGroup(title: L10n.prefs.section.appearance, icon: "paintbrush")
        addGroupRow(appearanceGroup, createLabeledRow(label: L10n.prefs.appearance.backgroundOpacity) {
            let stack = StackContainerView()
            stack.axis = .horizontal
            stack.alignment = .centerY
            stack.spacing = 8

            let slider = NSSlider(
                value: UserPreferences.shared.backgroundOpacity,
                minValue: 0,
                maxValue: 1,
                target: self,
                action: #selector(backgroundOpacityChanged(_:))
            )
            slider.setFrameSize(NSSize(width: 200, height: slider.intrinsicContentSize.height))
            slider.setContentHuggingPriority(.defaultHigh, for: .horizontal)
            stack.addArrangedSubview(slider)

            let valueLabel = FixedSizeTextField(labelWithString: String(
                format: "%.0f%%",
                UserPreferences.shared.backgroundOpacity * 100
            ))
            valueLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
            valueLabel.tag = 1001 // 用于后续更新
            valueLabel.preferredWidth = 40
            stack.addArrangedSubview(valueLabel)

            return stack
        })

        addGroupRow(appearanceGroup, createCheckboxRow(
            label: L10n.prefs.appearance.showDeviceBezel,
            isOn: UserPreferences.shared.showDeviceBezel,
            action: #selector(showDeviceBezelChanged(_:))
        ))

        addSettingsGroup(appearanceGroup, to: stackView)

        // 电源管理设置组
        let powerGroup = createSettingsGroup(title: L10n.prefs.power.sectionTitle, icon: "moon.zzz")

        addGroupRow(powerGroup, createCheckboxRow(
            label: L10n.prefs.power.preventAutoLock,
            isOn: UserPreferences.shared.preventAutoLockDuringCapture,
            action: #selector(preventAutoLockChanged(_:))
        ))
        // 添加帮助文本（与帧率备注样式一致）
        let powerNote = NSTextField(labelWithString: L10n.prefs.power.preventAutoLockHelp)
        powerNote.font = NSFont.systemFont(ofSize: 11)
        powerNote.textColor = .secondaryLabelColor
        let powerNoteContainer = PaddingView(
            contentView: powerNote,
            insets: NSEdgeInsets(
                top: 0,
                left: 0,
                bottom: LayoutMetrics.rowVerticalPadding * 1.5,
                right: 0
            )
        )
        addGroupRow(powerGroup, powerNoteContainer, addDivider: false)

        addSettingsGroup(powerGroup, to: stackView)

        // 颜色补偿设置组
        let colorCompGroup = createSettingsGroup(title: L10n.prefs.colorCompensationPref.sectionTitle, icon: "paintpalette")

        // 单行：标签 + 按钮 + 开关
        addGroupRow(colorCompGroup, createLabeledRow(label: L10n.prefs.colorCompensationPref.enableSwitch) {
            let container = StackContainerView()
            container.axis = .horizontal
            container.alignment = .centerY
            container.spacing = 8

            let button = NSButton(title: L10n.prefs.colorCompensationPref.openPanel, target: self, action: #selector(self.openColorCompensationPanel(_:)))
            button.bezelStyle = .rounded
            container.addArrangedSubview(button)

            let checkbox = NSButton(checkboxWithTitle: "", target: self, action: #selector(self.colorCompensationEnabledChanged(_:)))
            checkbox.state = ColorProfileManager.shared.isEnabled ? .on : .off
            checkbox.setContentHuggingPriority(.required, for: .horizontal)
            checkbox.setContentCompressionResistancePriority(.required, for: .horizontal)
            container.addArrangedSubview(checkbox)

            return container
        })

        // 说明文字
        let colorCompDescContainer = StackContainerView()
        colorCompDescContainer.axis = .vertical
        colorCompDescContainer.alignment = .leading
        colorCompDescContainer.edgeInsets = NSEdgeInsets(top: 8, left: 0, bottom: 8, right: 0)
        colorCompDescContainer.fillsCrossAxis = true

        let colorCompDescLabel = NSTextField(wrappingLabelWithString: L10n.prefs.colorCompensationPref.description)
        colorCompDescLabel.font = NSFont.systemFont(ofSize: 11)
        colorCompDescLabel.textColor = .secondaryLabelColor
        colorCompDescLabel.isSelectable = false
        colorCompDescContainer.addArrangedSubview(colorCompDescLabel)
        addGroupRow(colorCompGroup, colorCompDescContainer, addDivider: false)

        addSettingsGroup(colorCompGroup, to: stackView)

        // 布局设置组
        let layoutGroup = createSettingsGroup(title: L10n.prefs.section.layout, icon: "rectangle.split.2x1")

        // 布局模式
        addGroupRow(layoutGroup, createLabeledRow(label: L10n.toolbar.layoutMode) {
            let segmented = NSSegmentedControl(frame: .zero)
            segmented.segmentCount = PreviewLayoutMode.allCases.count
            segmented.trackingMode = .selectOne
            segmented.segmentStyle = .separated

            for (index, mode) in PreviewLayoutMode.allCases.enumerated() {
                segmented.setImage(
                    NSImage(systemSymbolName: mode.iconName, accessibilityDescription: mode.displayName),
                    forSegment: index
                )
                segmented.setToolTip(mode.displayName, forSegment: index)
                segmented.setWidth(32, forSegment: index)
            }

            if let index = PreviewLayoutMode.allCases.firstIndex(of: UserPreferences.shared.layoutMode) {
                segmented.selectedSegment = index
            }
            segmented.target = self
            segmented.action = #selector(layoutModeChanged(_:))
            return segmented
        })

        // 默认设备位置
        addGroupRow(layoutGroup, createLabeledRow(label: L10n.prefs.layoutPref.devicePosition) {
            let segmented = NSSegmentedControl(
                labels: [
                    L10n.prefs.layoutPref.iosOnLeft,
                    L10n.prefs.layoutPref.androidOnLeft,
                ],
                trackingMode: .selectOne,
                target: self,
                action: #selector(devicePositionChanged(_:))
            )
            segmented.selectedSegment = UserPreferences.shared.iosOnLeft ? 0 : 1
            return segmented
        })
        addSettingsGroup(layoutGroup, to: stackView)

        // 连接设置组
        let connectionGroup = createSettingsGroup(title: L10n.prefs.section.connection, icon: "cable.connector")
        addGroupRow(connectionGroup, createCheckboxRow(
            label: L10n.prefs.connectionPref.autoReconnect,
            isOn: UserPreferences.shared.autoReconnect,
            action: #selector(autoReconnectChanged(_:))
        ))
        addGroupRow(connectionGroup, createLabeledRow(label: L10n.prefs.connectionPref.reconnectDelay) {
            let stack = StackContainerView()
            stack.axis = .horizontal
            stack.alignment = .centerY
            stack.spacing = 8
            let stepper = NSStepper()
            stepper.minValue = 1
            stepper.maxValue = 30
            stepper.intValue = Int32(UserPreferences.shared.reconnectDelay)
            stepper.target = self
            stepper.action = #selector(reconnectDelayChanged(_:))
            stepper.tag = 2001 // 用于查找关联的 label
            stack.addArrangedSubview(stepper)
            let label = FixedSizeTextField(labelWithString: L10n.prefs.connectionPref
                .seconds(Int(UserPreferences.shared.reconnectDelay)))
            label.font = valueLabelFont
            label.tag = 2001
            label.preferredWidth = preferredValueWidth(label.stringValue, font: valueLabelFont)
            stack.addArrangedSubview(label)
            return stack
        })
        addGroupRow(connectionGroup, createLabeledRow(label: L10n.prefs.connectionPref.maxAttempts) {
            let stack = StackContainerView()
            stack.axis = .horizontal
            stack.alignment = .centerY
            stack.spacing = 8
            let stepper = NSStepper()
            stepper.minValue = 1
            stepper.maxValue = 20
            stepper.intValue = Int32(UserPreferences.shared.maxReconnectAttempts)
            stepper.target = self
            stepper.action = #selector(maxAttemptsChanged(_:))
            stepper.tag = 2002 // 用于查找关联的 label
            stack.addArrangedSubview(stepper)
            let label = FixedSizeTextField(labelWithString: L10n.prefs.connectionPref
                .times(UserPreferences.shared.maxReconnectAttempts))
            label.font = valueLabelFont
            label.tag = 2002
            label.preferredWidth = preferredValueWidth(label.stringValue, font: valueLabelFont)
            stack.addArrangedSubview(label)
            return stack
        })
        addSettingsGroup(connectionGroup, to: stackView)

        setupScrollViewLayout(scrollView: scrollView, contentView: stackView)
        return scrollView
    }

    // MARK: - 捕获设置

    private func createCaptureView() -> NSView {
        let scrollView = createScrollView()
        let stackView = createVerticalStack()

        // 帧率设置组
        let frameRateGroup = createSettingsGroup(title: L10n.prefs.section.frameRate, icon: "speedometer")
        addGroupRow(frameRateGroup, createLabeledRow(label: L10n.prefs.capturePref.frameRate) {
            let segmented = NSSegmentedControl(
                labels: ["30 FPS", "60 FPS", "120 FPS"],
                trackingMode: .selectOne,
                target: self,
                action: #selector(frameRateChanged(_:))
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
        let noteContainer = PaddingView(
            contentView: note,
            insets: NSEdgeInsets(
                top: 0,
                left: 0,
                bottom: LayoutMetrics.rowVerticalPadding * 1.5,
                right: 0
            )
        )
        addGroupRow(frameRateGroup, noteContainer, addDivider: false)
        addSettingsGroup(frameRateGroup, to: stackView)

        // Android (Scrcpy) 设置组
        let androidGroup = createSettingsGroup(title: L10n.prefs.section.android, icon: "apps.iphone")

        // 码率设置
        addGroupRow(androidGroup, createLabeledRow(label: L10n.prefs.scrcpyPref.bitrate) {
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
            popup.target = self
            popup.action = #selector(scrcpyBitrateChanged(_:))
            return popup
        })

        // 最大分辨率
        addGroupRow(androidGroup, createLabeledRow(label: L10n.prefs.scrcpyPref.maxSize) {
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
            popup.target = self
            popup.action = #selector(scrcpyMaxSizeChanged(_:))
            return popup
        })

        // 显示触摸点
        addGroupRow(androidGroup, createCheckboxRow(
            label: L10n.prefs.scrcpyPref.showTouches,
            isOn: UserPreferences.shared.scrcpyShowTouches,
            action: #selector(scrcpyShowTouchesChanged(_:))
        ))

        // 连接端口
        addGroupRow(androidGroup, createLabeledRow(label: L10n.prefs.scrcpyPref.port) {
            let stack = StackContainerView()
            stack.axis = .horizontal
            stack.alignment = .centerY
            stack.spacing = 8
            let textField = FixedSizeTextField()
            textField.stringValue = String(UserPreferences.shared.scrcpyPort)
            textField.font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .regular)
            textField.alignment = .center
            textField.preferredWidth = 70
            textField.target = self
            textField.action = #selector(scrcpyPortChanged(_:))
            textField.tag = 3001
            stack.addArrangedSubview(textField)

            let stepper = NSStepper()
            stepper.minValue = 1024
            stepper.maxValue = 65535
            stepper.intValue = Int32(UserPreferences.shared.scrcpyPort)
            stepper.target = self
            stepper.action = #selector(scrcpyPortStepperChanged(_:))
            stepper.tag = 3001
            stack.addArrangedSubview(stepper)
            return stack
        })

        // 视频编解码器
        addGroupRow(androidGroup, createLabeledRow(label: L10n.prefs.scrcpyPref.codec) {
            let popup = NSPopUpButton()
            for codec in ScrcpyCodecType.allCases {
                popup.addItem(withTitle: codec.displayName)
            }
            let currentIndex = ScrcpyCodecType.allCases.firstIndex(of: UserPreferences.shared.scrcpyCodec) ?? 0
            popup.selectItem(at: currentIndex)
            popup.target = self
            popup.action = #selector(scrcpyCodecChanged(_:))
            return popup
        })

        // Android 配置说明
        let androidNote = NSTextField(labelWithString: L10n.prefs.scrcpyPref.maxSizeNote)
        androidNote.font = NSFont.systemFont(ofSize: 11)
        androidNote.textColor = .secondaryLabelColor
        let androidNoteContainer = PaddingView(
            contentView: androidNote,
            insets: NSEdgeInsets(
                top: 0,
                left: 0,
                bottom: LayoutMetrics.rowVerticalPadding * 1.5,
                right: 0
            )
        )
        addGroupRow(androidGroup, androidNoteContainer, addDivider: false)
        addSettingsGroup(androidGroup, to: stackView)

        setupScrollViewLayout(scrollView: scrollView, contentView: stackView)
        return scrollView
    }

    // MARK: - 权限设置

    private func createPermissionsView() -> NSView {
        let scrollView = createScrollView()
        let stackView = createVerticalStack()

        // iOS 权限组
        let iosPermGroup = createSettingsGroup(title: L10n.prefs.section.iosPermissions, icon: "apple.logo")
        addGroupRow(iosPermGroup, createPermissionRow(
            name: L10n.permission.cameraName,
            description: L10n.permission.cameraDesc,
            permissionType: .camera
        ), addDivider: false)
        addSettingsGroup(iosPermGroup, to: stackView)

        // Android 权限组
        let androidPermGroup = createSettingsGroup(title: L10n.prefs.section.androidPermissions, icon: "apps.iphone")
        addGroupRow(androidPermGroup, createPermissionRow(
            name: L10n.permission.screenRecordingName,
            description: L10n.permission.screenRecordingDesc,
            permissionType: .screenRecording
        ), addDivider: false)
        addSettingsGroup(androidPermGroup, to: stackView)

        // 权限管理说明
        let permNoteLabel = NSTextField(wrappingLabelWithString: L10n.permission.revokeNote)
        permNoteLabel.font = NSFont.systemFont(ofSize: 11)
        permNoteLabel.textColor = .secondaryLabelColor
        stackView.addArrangedSubview(permNoteLabel)

        // Android 工具链组
        let toolchainGroup = createSettingsGroup(
            title: L10n.prefs.section.androidToolchain,
            icon: "wrench.and.screwdriver"
        )

        let adbRow = createToolchainRowWithPath(
            name: "adb",
            description: L10n.prefs.toolchain.adbDesc,
            toolType: .adb
        )
        toolchainGroup.addArrangedSubview(adbRow)

        let divider1 = NSBox()
        divider1.boxType = .separator
        toolchainGroup.addArrangedSubview(divider1)

        let scrcpyRow = createToolchainRowWithPath(
            name: "scrcpy",
            description: L10n.prefs.toolchain.scrcpyDesc,
            toolType: .scrcpy
        )
        toolchainGroup.addArrangedSubview(scrcpyRow)

        let divider2 = NSBox()
        divider2.boxType = .separator
        toolchainGroup.addArrangedSubview(divider2)

        let scrcpyServerRow = createToolchainRowWithPath(
            name: "scrcpy-server",
            description: L10n.prefs.toolchain.scrcpyServerDesc,
            toolType: .scrcpyServer
        )
        toolchainGroup.addArrangedSubview(scrcpyServerRow)

        addSettingsGroup(toolchainGroup, to: stackView)

        // 刷新按钮
        let refreshButton = NSButton(
            title: L10n.prefs.toolchain.refreshStatus,
            target: self,
            action: #selector(refreshToolchain)
        )
        refreshButton.bezelStyle = .rounded
        refreshButton.image = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: nil)
        refreshButton.imagePosition = .imageLeading
        let buttonContainer = StackContainerView()
        buttonContainer.axis = .horizontal
        buttonContainer.alignment = .centerY
        buttonContainer.fillsCrossAxis = true
        buttonContainer.addArrangedSubview(FlexibleSpacerView())
        buttonContainer.addArrangedSubview(refreshButton)
        stackView.addArrangedSubview(buttonContainer)

        setupScrollViewLayout(scrollView: scrollView, contentView: stackView)
        return scrollView
    }

    // MARK: - 辅助方法

    private func createScrollView() -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        // 使用 flipped 的 documentView，让内容从顶部开始排列
        scrollView.documentView = FlippedView()
        return scrollView
    }

    private func createVerticalStack() -> StackContainerView {
        let stack = StackContainerView()
        stack.axis = .vertical
        stack.alignment = .leading
        stack.spacing = 16
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        stack.fillsCrossAxis = true
        return stack
    }

    private func setupScrollViewLayout(scrollView: NSScrollView, contentView: StackContainerView) {
        guard let documentView = scrollView.documentView else { return }

        // 将 stackView 添加到 documentView（FlippedView）中
        documentView.addSubview(contentView)
        registerScrollViewLayout(scrollView: scrollView, contentView: contentView)
        updateScrollViewLayout(scrollView: scrollView, contentView: contentView)
    }

    private func registerScrollViewLayout(scrollView: NSScrollView, contentView: StackContainerView) {
        if scrollViewLayouts.contains(where: { $0.0 === scrollView }) {
            return
        }
        scrollViewLayouts.append((scrollView, contentView))
    }

    private func updateScrollViewLayouts() {
        for (scrollView, contentView) in scrollViewLayouts {
            updateScrollViewLayout(scrollView: scrollView, contentView: contentView)
        }
    }

    /// 只更新当前显示的 Tab 的 ScrollView 布局
    private func updateCurrentTabScrollViewLayout() {
        guard currentTabIndex >= 0, currentTabIndex < tabViews.count else { return }
        let currentView = tabViews[currentTabIndex]

        // 查找当前 Tab 内的 ScrollView
        for (scrollView, contentView) in scrollViewLayouts {
            if isDescendant(scrollView, of: currentView) {
                updateScrollViewLayout(scrollView: scrollView, contentView: contentView)
            }
        }
    }

    /// 检查视图是否是另一个视图的子视图
    private func isDescendant(_ view: NSView, of ancestor: NSView) -> Bool {
        var current: NSView? = view
        while let parent = current {
            if parent === ancestor {
                return true
            }
            current = parent.superview
        }
        return false
    }

    private func updateScrollViewLayout(scrollView: NSScrollView, contentView: StackContainerView) {
        guard let documentView = scrollView.documentView else { return }
        let contentWidth = scrollView.contentView.bounds.width
        let size = contentView.requiredSize(for: contentWidth)
        documentView.frame = CGRect(x: 0, y: 0, width: contentWidth, height: size.height)
        contentView.frame = documentView.bounds
        contentView.layoutSubtreeIfNeeded()
    }

    /// 创建设置分组，返回内容容器（contentBox）
    /// 注意：groupStack 会通过 contentBox.superview 访问
    private func createSettingsGroup(title: String, icon: String) -> StackContainerView {
        let groupStack = StackContainerView()
        groupStack.axis = .vertical
        groupStack.alignment = .leading
        groupStack.spacing = 8

        // 标题行
        let titleStack = StackContainerView()
        titleStack.axis = .horizontal
        titleStack.alignment = .centerY
        titleStack.spacing = 6
        titleStack.fillsCrossAxis = true
        let iconView = NSImageView()
        let iconConfig = NSImage.SymbolConfiguration(pointSize: 16, weight: .regular)
        iconView.image = NSImage(systemSymbolName: icon, accessibilityDescription: nil)?
            .withSymbolConfiguration(iconConfig)
        iconView.contentTintColor = .labelColor
        iconView.imageScaling = .scaleProportionallyUpOrDown
        // 使用 frame 设置固定大小，避免约束冲突
        iconView.setFrameSize(NSSize(width: 18, height: 18))
        iconView.setContentHuggingPriority(.required, for: .horizontal)
        iconView.setContentHuggingPriority(.required, for: .vertical)
        titleStack.addArrangedSubview(iconView)
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        titleLabel.lineBreakMode = .byWordWrapping
        titleLabel.maximumNumberOfLines = 2
        titleLabel.usesSingleLineMode = false
        titleLabel.cell?.wraps = true
        titleLabel.cell?.isScrollable = false
        titleStack.addArrangedSubview(titleLabel)
        titleStack.setFlexible(titleLabel, isFlexible: true)
        groupStack.addArrangedSubview(titleStack)

        // 内容容器
        let contentBox = StackContainerView()
        contentBox.axis = .vertical
        contentBox.alignment = .leading
        contentBox.spacing = 0
        contentBox.fillsCrossAxis = true
        contentBox.wantsLayer = true
        // 使用半透明的颜色来区分卡片和背景
        contentBox.layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.05).cgColor
        contentBox.layer?.cornerRadius = 8
        contentBox.edgeInsets = NSEdgeInsets(top: 0, left: 12, bottom: 0, right: 12)
        groupStack.addArrangedSubview(contentBox)

        return contentBox
    }

    /// 将设置分组添加到父 stackView，并设置宽度约束
    private func addSettingsGroup(_ contentBox: StackContainerView, to parentStack: StackContainerView) {
        guard let groupStack = contentBox.superview as? StackContainerView else { return }
        groupStack.fillsCrossAxis = true
        parentStack.addArrangedSubview(groupStack)
    }

    private func createLabeledRow(label: String, controlBuilder: () -> NSView) -> NSView {
        let labelView = NSTextField(labelWithString: label)
        labelView.font = NSFont.systemFont(ofSize: 13)
        labelView.lineBreakMode = .byWordWrapping
        labelView.maximumNumberOfLines = 0
        labelView.usesSingleLineMode = false
        labelView.cell?.wraps = true
        labelView.cell?.isScrollable = false
        labelView.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        labelView.setContentCompressionResistancePriority(.required, for: .horizontal)

        let control = controlBuilder()
        control.setContentHuggingPriority(.defaultHigh, for: .horizontal)

        return LabeledRowView(label: labelView, control: control)
    }

    private func addGroupRow(_ contentBox: StackContainerView, _ row: NSView, addDivider: Bool = true) {
        if addDivider, !contentBox.arrangedSubviews.isEmpty {
            let divider = NSBox()
            divider.boxType = .separator
            divider.setFrameSize(NSSize(width: 0, height: 1))
            contentBox.addArrangedSubview(divider)
        }
        contentBox.addArrangedSubview(row)
    }

    private func createCheckboxRow(
        label: String,
        isOn: Bool,
        action: Selector,
        helpText: String? = nil,
        configure: ((NSButton) -> Void)? = nil
    ) -> NSView {
        if let helpText = helpText {
            // 带帮助文本的版本
            let container = StackContainerView()
            container.axis = .vertical
            container.alignment = .leading
            container.spacing = 4

            let row = createLabeledRow(label: label) {
                let checkbox = NSButton(checkboxWithTitle: "", target: self, action: action)
                checkbox.state = isOn ? .on : .off
                checkbox.setContentHuggingPriority(.required, for: .horizontal)
                checkbox.setContentCompressionResistancePriority(.required, for: .horizontal)
                configure?(checkbox)
                return checkbox
            }
            container.addArrangedSubview(row)

            let helpLabel = NSTextField(wrappingLabelWithString: helpText)
            helpLabel.font = NSFont.systemFont(ofSize: 11)
            helpLabel.textColor = .secondaryLabelColor
            container.addArrangedSubview(helpLabel)

            return container
        } else {
            // 原有版本
            return createLabeledRow(label: label) {
                let checkbox = NSButton(checkboxWithTitle: "", target: self, action: action)
                checkbox.state = isOn ? .on : .off
                checkbox.setContentHuggingPriority(.required, for: .horizontal)
                checkbox.setContentCompressionResistancePriority(.required, for: .horizontal)
                configure?(checkbox)
                return checkbox
            }
        }
    }

    private func createButtonRow(label: String, action: Selector) -> NSView {
        let container = StackContainerView()
        container.axis = .horizontal
        container.alignment = .centerY
        container.spacing = 8
        container.edgeInsets = NSEdgeInsets(top: 8, left: 0, bottom: 8, right: 0)

        let button = NSButton(title: label, target: self, action: action)
        button.bezelStyle = .rounded
        container.addArrangedSubview(button)

        return container
    }

    private func createToolchainRow(name: String, description: String) -> NSView {
        let rowStack = StackContainerView()
        rowStack.axis = .horizontal
        rowStack.alignment = .centerY
        rowStack.spacing = 8
        rowStack.fillsCrossAxis = true

        // 状态图标
        let statusIcon = NSImageView()
        statusIcon.image = NSImage(systemSymbolName: "circle", accessibilityDescription: nil)
        statusIcon.contentTintColor = .secondaryLabelColor
        statusIcon.setFrameSize(NSSize(width: 18, height: 18))
        rowStack.addArrangedSubview(statusIcon)

        // 名称和描述
        let infoStack = StackContainerView()
        infoStack.axis = .vertical
        infoStack.alignment = .leading
        infoStack.spacing = 4
        let nameLabel = NSTextField(labelWithString: name)
        nameLabel.font = NSFont.systemFont(ofSize: 13)
        infoStack.addArrangedSubview(nameLabel)
        let descLabel = NSTextField(labelWithString: description)
        descLabel.font = NSFont.systemFont(ofSize: 11)
        descLabel.textColor = .secondaryLabelColor
        infoStack.addArrangedSubview(descLabel)
        infoStack.setFrameSize(NSSize(width: 200, height: infoStack.fittingSize.height))
        rowStack.addArrangedSubview(infoStack)

        // 占位
        let spacer = FlexibleSpacerView()
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
                statusIcon.contentTintColor = .appAccent
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

        return PaddingView(
            contentView: rowStack,
            insets: NSEdgeInsets(
                top: LayoutMetrics.rowVerticalPadding,
                left: 0,
                bottom: LayoutMetrics.rowVerticalPadding,
                right: 0
            )
        )
    }

    private func createToolchainRowWithPath(name: String, description: String, toolType: ToolType) -> NSView {
        let containerStack = StackContainerView()
        containerStack.axis = .vertical
        containerStack.alignment = .leading
        containerStack.spacing = 0
        containerStack.fillsCrossAxis = true

        // 第一行：状态显示（使用 LabeledRowView 布局）
        // 左侧：状态图标 + 名称和描述
        let leftStack = StackContainerView()
        leftStack.axis = .horizontal
        leftStack.alignment = .top
        leftStack.spacing = 8

        // 状态图标
        let statusIcon = NSImageView()
        statusIcon.image = NSImage(systemSymbolName: "circle", accessibilityDescription: nil)
        statusIcon.contentTintColor = .secondaryLabelColor
        statusIcon.setFrameSize(NSSize(width: 18, height: 18))
        leftStack.addArrangedSubview(statusIcon)

        // 名称和描述
        let infoStack = StackContainerView()
        infoStack.axis = .vertical
        infoStack.alignment = .leading
        infoStack.spacing = 4
        let nameLabel = NSTextField(labelWithString: name)
        nameLabel.font = NSFont.systemFont(ofSize: 13)
        infoStack.addArrangedSubview(nameLabel)
        let descLabel = NSTextField(wrappingLabelWithString: description)
        descLabel.font = NSFont.systemFont(ofSize: 11)
        descLabel.textColor = .secondaryLabelColor
        infoStack.addArrangedSubview(descLabel)
        leftStack.addArrangedSubview(infoStack)

        // 右侧：状态文本
        let statusLabel = NSTextField(labelWithString: L10n.common.checking)
        statusLabel.font = NSFont.systemFont(ofSize: 11)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.alignment = .right

        let statusRow = LabeledRowView(labelView: leftStack, control: statusLabel)
        containerStack.addArrangedSubview(statusRow)

        // 第二行：自定义路径
        let customPathRow = createCheckboxRow(
            label: L10n.prefs.toolchain.useCustomPath,
            isOn: useCustomPathForToolType(toolType),
            action: #selector(useCustomPathChanged(_:))
        ) { checkbox in
            checkbox.tag = self.tagForToolType(toolType, base: 4001)
        }
        containerStack.addArrangedSubview(customPathRow)

        // 第三行：路径输入（仅在启用自定义路径时显示）
        let pathInputStack = StackContainerView()
        pathInputStack.axis = .horizontal
        pathInputStack.alignment = .centerY
        pathInputStack.spacing = 8

        let pathTextField = FixedSizeTextField()
        pathTextField.placeholderString = L10n.prefs.toolchain.pathPlaceholder
        pathTextField.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        pathTextField.tag = tagForToolType(toolType, base: 4011)
        pathTextField.stringValue = customPathForToolType(toolType) ?? ""
        pathTextField.target = self
        pathTextField.action = #selector(customPathChanged(_:))
        pathInputStack.addArrangedSubview(pathTextField)
        pathTextField.preferredWidth = 200

        // 浏览按钮
        let browseButton = NSButton(
            title: L10n.prefs.toolchain.browse,
            target: self,
            action: #selector(browseToolPath(_:))
        )
        browseButton.bezelStyle = .rounded
        browseButton.controlSize = .small
        browseButton.tag = tagForToolType(toolType, base: 4021)
        pathInputStack.addArrangedSubview(browseButton)

        // 清空按钮
        let clearButton = NSButton(
            image: NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: nil)!,
            target: self,
            action: #selector(clearToolPath(_:))
        )
        clearButton.bezelStyle = .regularSquare
        clearButton.isBordered = false
        clearButton.tag = tagForToolType(toolType, base: 4051)
        pathInputStack.addArrangedSubview(clearButton)

        // 验证图标
        let validationIcon = NSImageView()
        validationIcon.image = NSImage(systemSymbolName: "questionmark.circle", accessibilityDescription: nil)
        validationIcon.contentTintColor = .secondaryLabelColor
        validationIcon.tag = tagForToolType(toolType, base: 4031)
        validationIcon.setFrameSize(NSSize(width: 16, height: 16))
        pathInputStack.addArrangedSubview(validationIcon)

        // 使用 PaddingView 包装路径输入行，保持左对齐
        let pathInputRow = PaddingView(
            contentView: pathInputStack,
            insets: NSEdgeInsets(
                top: LayoutMetrics.rowVerticalPadding,
                left: 0,
                bottom: LayoutMetrics.rowVerticalPadding,
                right: 0
            )
        )
        pathInputRow.tag = tagForToolType(toolType, base: 4041)
        pathInputRow.isHidden = !useCustomPathForToolType(toolType)
        containerStack.addArrangedSubview(pathInputRow)

        // 更新状态
        Task { @MainActor in
            let toolchain = AppState.shared.toolchainManager
            let status: ToolchainStatus
            let version: String

            switch toolType {
            case .adb:
                status = toolchain.adbStatus
                version = toolchain.adbVersionDescription
            case .scrcpy:
                status = toolchain.scrcpyStatus
                version = toolchain.scrcpyVersionDescription
            case .scrcpyServer:
                // scrcpy-server 使用 scrcpy 的状态，但显示路径信息
                if let serverPath = toolchain.scrcpyServerPath {
                    statusIcon.image = NSImage(
                        systemSymbolName: "checkmark.circle.fill",
                        accessibilityDescription: nil
                    )
                    statusIcon.contentTintColor = .systemGreen
                    let fileName = (serverPath as NSString).lastPathComponent
                    statusLabel.stringValue = fileName
                    statusLabel.textColor = .systemGreen
                } else {
                    statusIcon.image = NSImage(systemSymbolName: "xmark.circle", accessibilityDescription: nil)
                    statusIcon.contentTintColor = .systemOrange
                    statusLabel.stringValue = L10n.prefs.toolchain.notInstalled
                    statusLabel.textColor = .systemOrange
                }
                updatePathValidation(toolType: toolType, validationIcon: validationIcon)
                return
            }

            switch status {
            case .installed:
                statusIcon.image = NSImage(
                    systemSymbolName: "checkmark.circle.fill",
                    accessibilityDescription: nil
                )
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
                statusIcon.contentTintColor = .appAccent
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

            // 验证自定义路径
            updatePathValidation(toolType: toolType, validationIcon: validationIcon)
        }

        return containerStack
    }

    // MARK: - ToolType 辅助方法

    private func tagForToolType(_ toolType: ToolType, base: Int) -> Int {
        switch toolType {
        case .adb: base
        case .scrcpy: base + 1
        case .scrcpyServer: base + 2
        }
    }

    private func useCustomPathForToolType(_ toolType: ToolType) -> Bool {
        switch toolType {
        case .adb: UserPreferences.shared.useCustomAdbPath
        case .scrcpy: UserPreferences.shared.useCustomScrcpyPath
        case .scrcpyServer: UserPreferences.shared.useCustomScrcpyServerPath
        }
    }

    private func customPathForToolType(_ toolType: ToolType) -> String? {
        switch toolType {
        case .adb: UserPreferences.shared.customAdbPath
        case .scrcpy: UserPreferences.shared.customScrcpyPath
        case .scrcpyServer: UserPreferences.shared.customScrcpyServerPath
        }
    }

    private func toolTypeFromTag(_ tag: Int) -> ToolType? {
        let offset = tag % 10
        switch offset {
        case 1: return .adb
        case 2: return .scrcpy
        case 3: return .scrcpyServer
        default: return nil
        }
    }

    private func updatePathValidation(toolType: ToolType, validationIcon: NSImageView) {
        let useCustom = useCustomPathForToolType(toolType)
        let customPath = customPathForToolType(toolType)

        guard useCustom, let path = customPath, !path.isEmpty else {
            validationIcon.image = NSImage(systemSymbolName: "questionmark.circle", accessibilityDescription: nil)
            validationIcon.contentTintColor = .secondaryLabelColor
            validationIcon.toolTip = nil
            return
        }

        // 检查文件是否存在
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        let exists = fileManager.fileExists(atPath: path, isDirectory: &isDirectory)

        // scrcpy-server 不需要检查可执行权限，它是 DEX 文件
        if toolType == .scrcpyServer {
            if exists, !isDirectory.boolValue {
                validationIcon.image = NSImage(
                    systemSymbolName: "checkmark.circle.fill",
                    accessibilityDescription: nil
                )
                validationIcon.contentTintColor = .systemGreen
                validationIcon.toolTip = L10n.prefs.toolchain.pathValid
            } else if !exists {
                validationIcon.image = NSImage(
                    systemSymbolName: "xmark.circle.fill",
                    accessibilityDescription: nil
                )
                validationIcon.contentTintColor = .systemRed
                validationIcon.toolTip = L10n.prefs.toolchain.pathNotFound
            } else {
                validationIcon.image = NSImage(
                    systemSymbolName: "xmark.circle.fill",
                    accessibilityDescription: nil
                )
                validationIcon.contentTintColor = .systemRed
                validationIcon.toolTip = L10n.prefs.toolchain.pathIsDirectory
            }
            return
        }

        // adb 和 scrcpy 需要检查可执行权限
        let isExecutable = fileManager.isExecutableFile(atPath: path)

        if exists, !isDirectory.boolValue, isExecutable {
            validationIcon.image = NSImage(
                systemSymbolName: "checkmark.circle.fill",
                accessibilityDescription: nil
            )
            validationIcon.contentTintColor = .systemGreen
            validationIcon.toolTip = L10n.prefs.toolchain.pathValid
        } else if !exists {
            validationIcon.image = NSImage(
                systemSymbolName: "xmark.circle.fill",
                accessibilityDescription: nil
            )
            validationIcon.contentTintColor = .systemRed
            validationIcon.toolTip = L10n.prefs.toolchain.pathNotFound
        } else if isDirectory.boolValue {
            validationIcon.image = NSImage(
                systemSymbolName: "xmark.circle.fill",
                accessibilityDescription: nil
            )
            validationIcon.contentTintColor = .systemRed
            validationIcon.toolTip = L10n.prefs.toolchain.pathIsDirectory
        } else {
            validationIcon.image = NSImage(
                systemSymbolName: "exclamationmark.circle.fill",
                accessibilityDescription: nil
            )
            validationIcon.contentTintColor = .systemOrange
            validationIcon.toolTip = L10n.prefs.toolchain.pathNotExecutable
        }
    }

    private enum PermissionType {
        case screenRecording
        case camera
    }

    private enum ToolType {
        case adb
        case scrcpy
        case scrcpyServer
    }

    private func createPermissionRow(name: String, description: String, permissionType: PermissionType) -> NSView {
        // 左侧：状态图标 + 名称和描述
        let leftStack = StackContainerView()
        leftStack.axis = .horizontal
        leftStack.alignment = .top
        leftStack.spacing = 8

        // 状态图标
        let statusIcon = NSImageView()
        statusIcon.image = NSImage(systemSymbolName: "circle", accessibilityDescription: nil)
        statusIcon.contentTintColor = .secondaryLabelColor
        statusIcon.setFrameSize(NSSize(width: 18, height: 18))
        leftStack.addArrangedSubview(statusIcon)

        // 名称和描述
        let infoStack = StackContainerView()
        infoStack.axis = .vertical
        infoStack.alignment = .leading
        infoStack.spacing = 4
        let nameLabel = NSTextField(labelWithString: name)
        nameLabel.font = NSFont.systemFont(ofSize: 13)
        infoStack.addArrangedSubview(nameLabel)
        let descLabel = NSTextField(wrappingLabelWithString: description)
        descLabel.font = NSFont.systemFont(ofSize: 11)
        descLabel.textColor = .secondaryLabelColor
        infoStack.addArrangedSubview(descLabel)
        leftStack.addArrangedSubview(infoStack)

        // 右侧：状态文本 + 按钮
        let rightStack = StackContainerView()
        rightStack.axis = .horizontal
        rightStack.alignment = .centerY
        rightStack.spacing = 8

        // 状态文本
        let statusLabel = NSTextField(labelWithString: L10n.common.checking)
        statusLabel.font = NSFont.systemFont(ofSize: 11)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.alignment = .right
        rightStack.addArrangedSubview(statusLabel)

        // 打开设置按钮
        let openButton = NSButton(
            title: L10n.permission.openSystemPrefs,
            target: self,
            action: #selector(openSystemPreferences(_:))
        )
        openButton.bezelStyle = .rounded
        openButton.controlSize = .small
        switch permissionType {
        case .screenRecording:
            openButton.tag = 0
        case .camera:
            openButton.tag = 1
        }
        rightStack.addArrangedSubview(openButton)

        // 撤销按钮（已授权时显示）
        let revokeButton = NSButton(
            title: L10n.permission.revoke,
            target: self,
            action: #selector(revokePermission(_:))
        )
        revokeButton.bezelStyle = .rounded
        revokeButton.controlSize = .small
        revokeButton.isHidden = true
        switch permissionType {
        case .screenRecording:
            revokeButton.tag = 10
        case .camera:
            revokeButton.tag = 11
        }
        rightStack.addArrangedSubview(revokeButton)

        // 检查权限状态
        Task { @MainActor in
            let granted: Bool = switch permissionType {
            case .screenRecording:
                checkScreenRecordingPermission()
            case .camera:
                checkCameraPermission()
            }

            if granted {
                statusIcon.image = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: nil)
                statusIcon.contentTintColor = .systemGreen
                statusLabel.stringValue = L10n.permission.granted
                statusLabel.textColor = .systemGreen
                openButton.isHidden = true
                revokeButton.isHidden = false
            } else {
                statusIcon.image = NSImage(systemSymbolName: "xmark.circle", accessibilityDescription: nil)
                statusIcon.contentTintColor = .systemOrange
                statusLabel.stringValue = L10n.permission.denied
                statusLabel.textColor = .systemOrange
                openButton.isHidden = false
                revokeButton.isHidden = true
            }
        }

        return LabeledRowView(labelView: leftStack, control: rightStack)
    }

    private func checkScreenRecordingPermission() -> Bool {
        // 检查屏幕录制权限
        // macOS 10.15+ 使用 CGPreflightScreenCaptureAccess 准确检查权限状态
        CGPreflightScreenCaptureAccess()
    }

    private func checkCameraPermission() -> Bool {
        // 检查摄像头权限
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        return status == .authorized
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

    @objc private func showDeviceBezelChanged(_ sender: NSButton) {
        UserPreferences.shared.showDeviceBezel = sender.state == .on
    }

    @objc private func preventAutoLockChanged(_ sender: NSButton) {
        UserPreferences.shared.preventAutoLockDuringCapture = sender.state == .on
    }

    @objc private func colorCompensationEnabledChanged(_ sender: NSButton) {
        ColorProfileManager.shared.isEnabled = sender.state == .on
    }

    @objc private func openColorCompensationPanel(_ sender: NSButton) {
        ColorCompensationPanel.shared.showWindow(nil)
    }

    @objc private func layoutModeChanged(_ sender: NSSegmentedControl) {
        let index = sender.selectedSegment
        guard index >= 0, index < PreviewLayoutMode.allCases.count else { return }
        UserPreferences.shared.layoutMode = PreviewLayoutMode.allCases[index]
    }

    @objc private func devicePositionChanged(_ sender: NSSegmentedControl) {
        UserPreferences.shared.iosOnLeft = sender.selectedSegment == 0
    }

    @objc private func autoReconnectChanged(_ sender: NSButton) {
        UserPreferences.shared.autoReconnect = sender.state == .on
    }

    @objc private func reconnectDelayChanged(_ sender: NSStepper) {
        UserPreferences.shared.reconnectDelay = sender.doubleValue
        // 更新关联的标签
        if
            let label = sender.superview?.subviews
                .first(where: { $0.tag == 2001 && $0 is NSTextField }) as? NSTextField {
            label.stringValue = L10n.prefs.connectionPref.seconds(Int(sender.intValue))
            if let fixedLabel = label as? FixedSizeTextField {
                fixedLabel.preferredWidth = preferredValueWidth(
                    label.stringValue,
                    font: fixedLabel.font ?? valueLabelFont
                )
            }
        }
        view.needsLayout = true
    }

    @objc private func maxAttemptsChanged(_ sender: NSStepper) {
        UserPreferences.shared.maxReconnectAttempts = Int(sender.intValue)
        // 更新关联的标签
        if
            let label = sender.superview?.subviews
                .first(where: { $0.tag == 2002 && $0 is NSTextField }) as? NSTextField {
            label.stringValue = L10n.prefs.connectionPref.times(Int(sender.intValue))
            if let fixedLabel = label as? FixedSizeTextField {
                fixedLabel.preferredWidth = preferredValueWidth(
                    label.stringValue,
                    font: fixedLabel.font ?? valueLabelFont
                )
            }
        }
        view.needsLayout = true
    }

    @objc private func frameRateChanged(_ sender: NSSegmentedControl) {
        let frameRates = [30, 60, 120]
        UserPreferences.shared.captureFrameRate = frameRates[sender.selectedSegment]
    }

    @objc private func scrcpyBitrateChanged(_ sender: NSPopUpButton) {
        let bitrates = [4, 8, 16, 32]
        let index = sender.indexOfSelectedItem
        if index >= 0, index < bitrates.count {
            UserPreferences.shared.scrcpyBitrate = bitrates[index]
        }
    }

    @objc private func scrcpyMaxSizeChanged(_ sender: NSPopUpButton) {
        let sizes = [0, 1280, 1920, 2560]
        let index = sender.indexOfSelectedItem
        if index >= 0, index < sizes.count {
            UserPreferences.shared.scrcpyMaxSize = sizes[index]
        }
    }

    @objc private func scrcpyShowTouchesChanged(_ sender: NSButton) {
        UserPreferences.shared.scrcpyShowTouches = sender.state == .on
    }

    @objc private func scrcpyPortChanged(_ sender: NSTextField) {
        guard let port = Int(sender.stringValue), port >= 1024, port <= 65535 else {
            // 恢复为当前值
            sender.stringValue = String(UserPreferences.shared.scrcpyPort)
            return
        }
        UserPreferences.shared.scrcpyPort = port
        // 同步更新 stepper
        if let stepper = sender.superview?.subviews.first(where: { $0.tag == 3001 && $0 is NSStepper }) as? NSStepper {
            stepper.intValue = Int32(port)
        }
    }

    @objc private func scrcpyPortStepperChanged(_ sender: NSStepper) {
        let port = Int(sender.intValue)
        UserPreferences.shared.scrcpyPort = port
        // 同步更新文本框
        if
            let textField = sender.superview?.subviews
                .first(where: { $0.tag == 3001 && $0 is NSTextField }) as? NSTextField {
            textField.stringValue = String(port)
        }
    }

    @objc private func scrcpyCodecChanged(_ sender: NSPopUpButton) {
        let index = sender.indexOfSelectedItem
        guard index >= 0, index < ScrcpyCodecType.allCases.count else { return }
        UserPreferences.shared.scrcpyCodec = ScrcpyCodecType.allCases[index]
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
        let urlString: String
        switch sender.tag {
        case 0:
            // 打开系统偏好设置 - 隐私 - 屏幕录制
            urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
        case 1:
            // 打开系统偏好设置 - 隐私 - 摄像头
            urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera"
        default:
            return
        }
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func revokePermission(_ sender: NSButton) {
        let urlString: String
        let alertMessage: String

        switch sender.tag {
        case 10:
            // 屏幕录制权限
            urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
            alertMessage = L10n.permission.revokeScreenRecordingHint
        case 11:
            // 摄像头权限
            urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera"
            alertMessage = L10n.permission.revokeCameraHint
        default:
            return
        }

        // 显示提示
        let alert = NSAlert()
        alert.messageText = L10n.permission.revokeTitle
        alert.informativeText = alertMessage
        alert.alertStyle = .informational
        alert.addButton(withTitle: L10n.permission.openSystemPrefs)
        alert.addButton(withTitle: L10n.common.cancel)

        if alert.runModal() == .alertFirstButtonReturn {
            if let url = URL(string: urlString) {
                NSWorkspace.shared.open(url)
            }
        }
    }

    // MARK: - 工具链路径设置

    @objc private func useCustomPathChanged(_ sender: NSButton) {
        guard let toolType = toolTypeFromTag(sender.tag) else { return }
        let useCustom = sender.state == .on

        switch toolType {
        case .adb:
            UserPreferences.shared.useCustomAdbPath = useCustom
        case .scrcpy:
            UserPreferences.shared.useCustomScrcpyPath = useCustom
        case .scrcpyServer:
            UserPreferences.shared.useCustomScrcpyServerPath = useCustom
        }

        // 查找对应的路径输入行并更新显示
        // 视图层级：checkbox -> LabeledRowView(customPathRow) -> containerStack
        let pathInputRowTag = tagForToolType(toolType, base: 4041)
        if
            let customPathRow = sender.superview,
            let containerStack = customPathRow.superview as? StackContainerView {
            for arrangedSubview in containerStack.arrangedSubviews {
                // pathInputRow 是 PaddingView，有专门的 tag
                if arrangedSubview.tag == pathInputRowTag {
                    arrangedSubview.isHidden = !useCustom
                    // 触发布局更新
                    containerStack.needsLayout = true
                    containerStack.layoutSubtreeIfNeeded()
                    // 通知父视图重新布局
                    containerStack.superview?.needsLayout = true
                    containerStack.superview?.layoutSubtreeIfNeeded()
                    break
                }
            }
        }

        // 刷新工具链状态
        Task {
            await AppState.shared.toolchainManager.refresh()
        }
    }

    @objc private func customPathChanged(_ sender: NSTextField) {
        guard let toolType = toolTypeFromTag(sender.tag) else { return }
        let path = sender.stringValue

        switch toolType {
        case .adb:
            UserPreferences.shared.customAdbPath = path.isEmpty ? nil : path
        case .scrcpy:
            UserPreferences.shared.customScrcpyPath = path.isEmpty ? nil : path
        case .scrcpyServer:
            UserPreferences.shared.customScrcpyServerPath = path.isEmpty ? nil : path
        }

        // 更新验证图标
        let validationTag = tagForToolType(toolType, base: 4031)
        if let parentStack = sender.superview as? StackContainerView {
            for subview in parentStack.arrangedSubviews {
                if let icon = subview as? NSImageView, icon.tag == validationTag {
                    updatePathValidation(toolType: toolType, validationIcon: icon)
                    break
                }
            }
        }

        // 刷新工具链状态
        Task {
            await AppState.shared.toolchainManager.refresh()
        }
    }

    @objc private func browseToolPath(_ sender: NSButton) {
        guard let toolType = toolTypeFromTag(sender.tag) else { return }
        let toolName = switch toolType {
        case .adb: "adb"
        case .scrcpy: "scrcpy"
        case .scrcpyServer: "scrcpy-server"
        }

        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = L10n.prefs.toolchain.selectTool(toolName)
        panel.prompt = L10n.common.ok

        // 设置初始目录
        if let currentPath = customPathForToolType(toolType), !currentPath.isEmpty {
            panel.directoryURL = URL(fileURLWithPath: currentPath).deletingLastPathComponent()
        } else {
            panel.directoryURL = URL(fileURLWithPath: "/usr/local/bin")
        }

        if panel.runModal() == .OK, let url = panel.url {
            let path = url.path

            // 更新 UserPreferences
            switch toolType {
            case .adb:
                UserPreferences.shared.customAdbPath = path
            case .scrcpy:
                UserPreferences.shared.customScrcpyPath = path
            case .scrcpyServer:
                UserPreferences.shared.customScrcpyServerPath = path
            }

            // 更新文本框
            // 视图层级：browseButton -> pathInputStack (StackContainerView)
            let textFieldTag = tagForToolType(toolType, base: 4011)
            if let pathInputStack = sender.superview as? StackContainerView {
                for subview in pathInputStack.arrangedSubviews {
                    if let textField = subview as? NSTextField, textField.tag == textFieldTag {
                        textField.stringValue = path
                        break
                    }
                }

                // 更新验证图标
                let validationTag = tagForToolType(toolType, base: 4031)
                for subview in pathInputStack.arrangedSubviews {
                    if let icon = subview as? NSImageView, icon.tag == validationTag {
                        updatePathValidation(toolType: toolType, validationIcon: icon)
                        break
                    }
                }
            }

            // 刷新工具链状态
            Task {
                await AppState.shared.toolchainManager.refresh()
            }
        }
    }

    @objc private func clearToolPath(_ sender: NSButton) {
        guard let toolType = toolTypeFromTag(sender.tag) else { return }

        // 清空 UserPreferences
        switch toolType {
        case .adb:
            UserPreferences.shared.customAdbPath = nil
        case .scrcpy:
            UserPreferences.shared.customScrcpyPath = nil
        case .scrcpyServer:
            UserPreferences.shared.customScrcpyServerPath = nil
        }

        // 清空文本框并更新验证图标
        // 视图层级：clearButton -> pathInputStack (StackContainerView)
        if let pathInputStack = sender.superview as? StackContainerView {
            let textFieldTag = tagForToolType(toolType, base: 4011)
            let validationTag = tagForToolType(toolType, base: 4031)

            for subview in pathInputStack.arrangedSubviews {
                if let textField = subview as? NSTextField, textField.tag == textFieldTag {
                    textField.stringValue = ""
                }
                if let icon = subview as? NSImageView, icon.tag == validationTag {
                    updatePathValidation(toolType: toolType, validationIcon: icon)
                }
            }
        }

        // 刷新工具链状态
        Task {
            await AppState.shared.toolchainManager.refresh()
        }
    }
}

// MARK: - 通知名称

extension Notification.Name {
    static let backgroundColorDidChange = Notification.Name("backgroundColorDidChange")
    static let deviceBezelVisibilityDidChange = Notification.Name("deviceBezelVisibilityDidChange")
    static let layoutModeDidChange = Notification.Name("layoutModeDidChange")
    static let preventAutoLockSettingDidChange = Notification.Name("preventAutoLockSettingDidChange")
}
