//
//  ToastView.swift
//  ScreenPresenter
//
//  Created by Sun on 2025/12/23.
//
//  Toast 提示视图
//  支持成功、失败、警告、信息等状态
//  支持复制按钮
//

import AppKit

// MARK: - Toast 样式

enum ToastStyle {
    case success
    case error
    case warning
    case info

    var icon: String {
        switch self {
        case .success: "checkmark.circle.fill"
        case .error: "xmark.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .info: "info.circle.fill"
        }
    }

    var iconColor: NSColor {
        switch self {
        case .success: .systemGreen
        case .error: .systemRed
        case .warning: .systemOrange
        case .info: .systemBlue
        }
    }
}

// MARK: - Toast 视图

final class ToastView: NSView {
    // MARK: - UI 组件

    private let iconView: NSImageView
    private let label: NSTextField
    private let copyButton: NSButton
    private let actionButton: NSButton

    // MARK: - 属性

    private let message: String
    private let style: ToastStyle
    private let copyable: Bool
    /// 尾部动作按钮标题；为 nil 时不展示。
    private let actionTitle: String?
    /// 点击动作按钮后的回调。执行后 Toast 立即消失。
    private var actionHandler: (() -> Void)?
    private let contentInsets = NSEdgeInsets(top: 12, left: 14, bottom: 12, right: 14)
    private let iconSize: CGFloat = 18
    private let copySize: CGFloat = 20
    private let spacing: CGFloat = 10

    // MARK: - 计时器相关

    private var duration: TimeInterval = 2.5
    private var dismissWorkItem: DispatchWorkItem?
    private var trackingArea: NSTrackingArea?
    private var isMouseInside = false

    // MARK: - 初始化

    init(
        message: String,
        style: ToastStyle = .info,
        copyable: Bool = false,
        actionTitle: String? = nil,
        actionHandler: (() -> Void)? = nil
    ) {
        self.message = message
        self.style = style
        self.copyable = copyable
        self.actionTitle = actionTitle
        self.actionHandler = actionHandler

        // 初始化 UI 组件
        iconView = NSImageView()
        label = NSTextField(labelWithString: message)
        copyButton = NSButton()
        actionButton = NSButton()
        super.init(frame: .zero)

        setupUI()

        // error 类型，或带动作按钮时，启用鼠标追踪（悬停暂停消失计时，给用户点击时间）
        if style == .error || hasAction {
            setupTrackingArea()
        }
    }

    /// 是否展示尾部动作按钮。
    private var hasAction: Bool { actionTitle?.isEmpty == false }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - UI 设置

    private func setupUI() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        layer?.cornerRadius = 10
        // 添加细边框（在深色背景下可见）
        layer?.borderWidth = 0.5
        layer?.borderColor = NSColor.labelColor.withAlphaComponent(0.15).cgColor
        // 添加阴影（在浅色背景下可见）
        shadow = NSShadow()
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.4
        layer?.shadowOffset = CGSize(width: 0, height: -2)
        layer?.shadowRadius = 10

        // 图标
        let iconImage = NSImage(systemSymbolName: style.icon, accessibilityDescription: nil)
        iconView.image = iconImage
        iconView.contentTintColor = style.iconColor
        iconView.setContentHuggingPriority(.required, for: .horizontal)

        // 文本
        label.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        label.textColor = .labelColor
        label.alignment = .left
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 2
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        // 复制按钮
        copyButton.image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: L10n.common.copy)
        copyButton.bezelStyle = .inline
        copyButton.isBordered = false
        copyButton.contentTintColor = .secondaryLabelColor
        copyButton.target = self
        copyButton.action = #selector(copyTapped)
        copyButton.toolTip = L10n.common.copy
        copyButton.isHidden = !copyable
        copyButton.setContentHuggingPriority(.required, for: .horizontal)

        // 动作按钮：链接样式的文字按钮，点击执行回调并消失
        actionButton.title = actionTitle ?? ""
        actionButton.bezelStyle = .inline
        actionButton.isBordered = false
        actionButton.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        actionButton.contentTintColor = style.iconColor
        actionButton.target = self
        actionButton.action = #selector(actionTapped)
        actionButton.isHidden = !hasAction
        actionButton.setContentHuggingPriority(.required, for: .horizontal)

        addSubview(iconView)
        addSubview(label)
        if copyable {
            addSubview(copyButton)
        }
        if hasAction {
            addSubview(actionButton)
        }
    }

    // MARK: - 鼠标追踪

    private func setupTrackingArea() {
        trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        if let trackingArea {
            addTrackingArea(trackingArea)
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        // error 类型或带动作按钮时才需要更新追踪区域
        guard style == .error || hasAction else { return }

        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        if let trackingArea {
            addTrackingArea(trackingArea)
        }
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        isMouseInside = true
        // 取消消失计时器
        dismissWorkItem?.cancel()
        dismissWorkItem = nil
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        isMouseInside = false
        // 重新开始消失计时
        scheduleDismiss()
    }

    // MARK: - 消失计时

    private func scheduleDismiss() {
        dismissWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.dismiss()
        }
        dismissWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: workItem)
    }

    private func dismiss() {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            self.animator().alphaValue = 0.0
        } completionHandler: { [weak self] in
            self?.removeFromSuperview()
        }
    }

    override func layout() {
        super.layout()
        layoutContent()
    }

    private func layoutContent() {
        let availableWidth = bounds.width - contentInsets.left - contentInsets.right
        let copyWidth = copyable ? copySize : 0
        let actionWidth = hasAction ? actionButtonSize().width : 0
        let trailingWidth = (copyable ? (spacing + copyWidth) : 0) + (hasAction ? (spacing + actionWidth) : 0)
        let labelWidth = max(0, availableWidth - iconSize - spacing - trailingWidth)
        let labelSize = labelSize(maxWidth: labelWidth)

        let contentHeight = max(iconSize, labelSize.height, copyWidth)
        let y = contentInsets.bottom + (contentHeight - iconSize) / 2
        iconView.frame = CGRect(x: contentInsets.left, y: y, width: iconSize, height: iconSize)

        let labelX = iconView.frame.maxX + spacing
        let labelY = contentInsets.bottom + (contentHeight - labelSize.height) / 2
        label.frame = CGRect(x: labelX, y: labelY, width: labelWidth, height: labelSize.height)

        var trailingX = label.frame.maxX
        if copyable {
            let copyX = trailingX + spacing
            let copyY = contentInsets.bottom + (contentHeight - copySize) / 2
            copyButton.frame = CGRect(x: copyX, y: copyY, width: copySize, height: copySize)
            trailingX = copyButton.frame.maxX
        }
        if hasAction {
            let actionHeight = actionButtonSize().height
            let actionX = trailingX + spacing
            let actionY = contentInsets.bottom + (contentHeight - actionHeight) / 2
            actionButton.frame = CGRect(x: actionX, y: actionY, width: actionWidth, height: actionHeight)
        }
    }

    /// 动作按钮的内在尺寸（用于布局与宽度预算）。
    private func actionButtonSize() -> CGSize {
        guard hasAction else { return .zero }
        return actionButton.intrinsicContentSize
    }

    private func preferredSize(maxWidth: CGFloat) -> CGSize {
        // 计算内容区域的最大可用宽度
        let availableContentWidth = maxWidth - contentInsets.left - contentInsets.right
        let copyWidth = copyable ? copySize : 0
        let actionWidth = hasAction ? actionButtonSize().width : 0
        let trailingWidth = (copyable ? (spacing + copyWidth) : 0) + (hasAction ? (spacing + actionWidth) : 0)
        let maxLabelWidth = max(0, availableContentWidth - iconSize - spacing - trailingWidth)

        // 获取文本实际需要的尺寸
        let labelSize = labelSize(maxWidth: maxLabelWidth)
        let contentHeight = max(iconSize, labelSize.height, copyWidth, hasAction ? actionButtonSize().height : 0)
        let height = contentInsets.top + contentHeight + contentInsets.bottom

        // 根据实际文本宽度计算总宽度
        let actualContentWidth = iconSize + spacing + labelSize.width + trailingWidth
        let actualWidth = contentInsets.left + actualContentWidth + contentInsets.right

        // 返回实际需要的宽度，但不超过最大宽度
        return CGSize(width: min(actualWidth, maxWidth), height: height)
    }

    private func labelSize(maxWidth: CGFloat) -> CGSize {
        guard maxWidth > 0 else { return .zero }
        let bounds = NSRect(x: 0, y: 0, width: maxWidth, height: .greatestFiniteMagnitude)
        if let size = label.cell?.cellSize(forBounds: bounds) {
            return CGSize(width: min(maxWidth, size.width), height: size.height)
        }
        let size = label.intrinsicContentSize
        return CGSize(width: min(maxWidth, size.width), height: size.height)
    }

    // MARK: - 操作

    @objc private func copyTapped() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(message, forType: .string)

        // 复制成功反馈：图标临时变成勾
        let originalImage = copyButton.image
        copyButton.image = NSImage(systemSymbolName: "checkmark", accessibilityDescription: nil)
        copyButton.contentTintColor = .systemGreen

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.copyButton.image = originalImage
            self?.copyButton.contentTintColor = .secondaryLabelColor
        }
    }

    @objc private func actionTapped() {
        // 先取消消失计时，执行回调后立即消失。
        dismissWorkItem?.cancel()
        dismissWorkItem = nil
        actionHandler?()
        dismiss()
    }

    // MARK: - 静态方法

    /// 在指定视图中显示 Toast
    /// - Parameters:
    ///   - message: 提示信息
    ///   - style: 样式（默认 .info）
    ///   - copyable: 是否可复制（默认 false）
    ///   - duration: 显示时长（默认 2.5 秒）
    ///   - view: 目标视图
    @MainActor
    static func show(
        _ message: String,
        style: ToastStyle = .info,
        copyable: Bool = false,
        duration: TimeInterval = 2.5,
        actionTitle: String? = nil,
        actionHandler: (() -> Void)? = nil,
        in view: NSView?
    ) {
        guard let view else { return }

        let toast = ToastView(
            message: message,
            style: style,
            copyable: copyable,
            actionTitle: actionTitle,
            actionHandler: actionHandler
        )
        toast.duration = duration
        toast.alphaValue = 0
        view.addSubview(toast)

        // 最大宽度 = 父视图宽度 - 左右边距（各 20）
        let horizontalMargin: CGFloat = 20
        let maxWidth = max(200, view.bounds.width - horizontalMargin * 2)
        let size = toast.preferredSize(maxWidth: maxWidth)
        toast.frame = CGRect(
            x: (view.bounds.width - size.width) / 2,
            y: view.bounds.height - 44 - size.height,
            width: size.width,
            height: size.height
        )

        // 淡入动画
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            toast.animator().alphaValue = 1.0
        }

        // 开始消失计时（鼠标悬停时会暂停）
        toast.scheduleDismiss()
    }

    /// 在指定窗口显示 Toast（便捷方法）
    /// - Parameters:
    ///   - message: 提示信息
    ///   - style: 样式（默认 .info）
    ///   - copyable: 是否可复制（默认 false）
    ///   - duration: 显示时长（默认 2.5 秒）
    ///   - window: 目标窗口
    @MainActor
    static func show(
        _ message: String,
        style: ToastStyle = .info,
        copyable: Bool = false,
        duration: TimeInterval = 2.5,
        in window: NSWindow?
    ) {
        show(message, style: style, copyable: copyable, duration: duration, in: window?.contentView)
    }

    // MARK: - 便捷方法（NSView）

    /// 显示成功提示
    @MainActor
    static func success(_ message: String, in view: NSView?) {
        show(message, style: .success, in: view)
    }

    /// 显示错误提示
    @MainActor
    static func error(_ message: String, copyable: Bool = true, in view: NSView?) {
        show(message, style: .error, copyable: copyable, duration: 4.0, in: view)
    }

    /// 显示警告提示
    @MainActor
    static func warning(_ message: String, in view: NSView?) {
        show(message, style: .warning, duration: 3.0, in: view)
    }

    /// 显示信息提示
    @MainActor
    static func info(_ message: String, in view: NSView?) {
        show(message, style: .info, in: view)
    }

    // MARK: - 便捷方法（NSWindow）

    /// 显示成功提示
    @MainActor
    static func success(_ message: String, in window: NSWindow?) {
        show(message, style: .success, in: window)
    }

    /// 显示带动作按钮的成功提示（延长展示时长，悬停暂停消失，留出点击时间）。
    @MainActor
    static func success(
        _ message: String,
        actionTitle: String,
        duration: TimeInterval = 5.0,
        in window: NSWindow?,
        actionHandler: @escaping () -> Void
    ) {
        show(
            message,
            style: .success,
            duration: duration,
            actionTitle: actionTitle,
            actionHandler: actionHandler,
            in: window?.contentView
        )
    }

    /// 显示错误提示
    @MainActor
    static func error(_ message: String, copyable: Bool = true, in window: NSWindow?) {
        show(message, style: .error, copyable: copyable, duration: 4.0, in: window)
    }

    /// 显示警告提示
    @MainActor
    static func warning(_ message: String, in window: NSWindow?) {
        show(message, style: .warning, duration: 3.0, in: window)
    }

    /// 显示信息提示
    @MainActor
    static func info(_ message: String, in window: NSWindow?) {
        show(message, style: .info, in: window)
    }
}
