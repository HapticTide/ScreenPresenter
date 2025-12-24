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
import SnapKit

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
    private let stackView: NSStackView

    // MARK: - 属性

    private let message: String
    private let style: ToastStyle
    private let copyable: Bool

    // MARK: - 计时器相关

    private var duration: TimeInterval = 2.5
    private var dismissWorkItem: DispatchWorkItem?
    private var trackingArea: NSTrackingArea?
    private var isMouseInside = false

    // MARK: - 初始化

    init(message: String, style: ToastStyle = .info, copyable: Bool = false) {
        self.message = message
        self.style = style
        self.copyable = copyable

        // 初始化 UI 组件
        iconView = NSImageView()
        label = NSTextField(labelWithString: message)
        copyButton = NSButton()
        stackView = NSStackView()

        super.init(frame: .zero)

        setupUI()

        // 只有 error 类型才启用鼠标追踪（悬停时暂停消失计时）
        if style == .error {
            setupTrackingArea()
        }
    }

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

        // 堆栈布局
        stackView.orientation = .horizontal
        stackView.spacing = 10
        stackView.alignment = .centerY
        stackView.edgeInsets = NSEdgeInsets(top: 12, left: 14, bottom: 12, right: 14)
        stackView.addArrangedSubview(iconView)
        stackView.addArrangedSubview(label)
        if copyable {
            stackView.addArrangedSubview(copyButton)
        }

        addSubview(stackView)

        // 约束
        stackView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        iconView.snp.makeConstraints { make in
            make.size.equalTo(18)
        }
        copyButton.snp.makeConstraints { make in
            make.size.equalTo(20)
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
        addTrackingArea(trackingArea!)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        // 只有 error 类型才需要更新追踪区域
        guard style == .error else { return }

        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea!)
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
        in view: NSView?
    ) {
        guard let view else { return }

        let toast = ToastView(message: message, style: style, copyable: copyable)
        toast.duration = duration
        toast.alphaValue = 0
        view.addSubview(toast)

        // 约束
        toast.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.top.equalToSuperview().offset(44)
            make.width.lessThanOrEqualToSuperview().multipliedBy(0.8)
            make.width.greaterThanOrEqualTo(200)
        }

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
