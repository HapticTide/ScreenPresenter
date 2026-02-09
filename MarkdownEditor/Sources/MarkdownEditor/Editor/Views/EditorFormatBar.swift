//
//  EditorFormatBar.swift
//  MarkdownEditor
//
//  Created by Sun on 2026/02/06.
//
//  嵌入模式下的格式工具栏
//  使用系统标准 NSSegmentedControl 提供格式化操作按钮
//

import AppKit

/// 嵌入模式下的内联格式工具栏
///
/// 在编辑器顶部显示常用的格式化按钮（加粗、斜体、标题等）
/// 使用 NSSegmentedControl 实现系统标准的分组按钮样式
final class EditorFormatBar: NSView {
    // MARK: - Properties

    /// 工具栏高度
    static let height: CGFloat = 32

    /// 按钮点击回调
    weak var delegate: EditorFormatBarDelegate?

    /// 格式相关控件（预览模式下需要禁用）
    private var formatControls: [NSControl] = []

    /// 预览按钮所在的 segment control
    private var rightSegmentedControl: NSSegmentedControl?

    // MARK: - Actions

    private enum FormatAction: Int {
        case bold = 0, italic, strikethrough
    }

    private enum InsertAction: Int {
        case header = 0, link, image, horizontalRule
    }

    private enum ListAction: Int {
        case bullet = 0, numbering, blockquote
    }

    private enum CodeAction: Int {
        case code = 0, table
    }

    private enum RightAction: Int {
        case preview = 0, toc
    }

    // MARK: - 子视图

    private lazy var stackView: NSStackView = {
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.spacing = 8
        stack.alignment = .centerY
        stack.distribution = .fill
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 8, bottom: 0, right: 8)
        // 使用 Auto Layout 避免手动布局时零尺寸导致的约束冲突
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    private lazy var backgroundView: NSVisualEffectView = {
        let view = NSVisualEffectView()
        view.material = .headerView
        view.blendingMode = .withinWindow
        view.state = .active
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var dividerView: NSView = {
        let view = NSView()
        view.wantsLayer = true
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    // MARK: - Initialization

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupUI()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Layout

    override func layout() {
        super.layout()
        // 子视图使用 Auto Layout，无需手动设置 frame
    }

    override var isHidden: Bool {
        didSet {
            if !isHidden {
                // 当视图从隐藏状态变为可见时，强制重新布局
                needsLayout = true
            }
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // 当视图添加到窗口时，强制重新布局
        if window != nil {
            needsLayout = true
            layoutSubtreeIfNeeded()
        }
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        needsLayout = true
    }

    override func updateLayer() {
        super.updateLayer()
        dividerView.layer?.backgroundColor = NSColor.separatorColor.cgColor
    }

    // MARK: - Setup

    private func setupUI() {
        wantsLayer = true
        addSubview(backgroundView)
        addSubview(stackView)
        addSubview(dividerView)

        // 使用 Auto Layout 约束
        NSLayoutConstraint.activate([
            // backgroundView 填满整个视图
            backgroundView.topAnchor.constraint(equalTo: topAnchor),
            backgroundView.bottomAnchor.constraint(equalTo: bottomAnchor),
            backgroundView.leadingAnchor.constraint(equalTo: leadingAnchor),
            backgroundView.trailingAnchor.constraint(equalTo: trailingAnchor),

            // stackView 位于顶部，底部留 1px 给分隔线
            stackView.topAnchor.constraint(equalTo: topAnchor),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -1),
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor),

            // dividerView 在底部，高度 1px
            dividerView.bottomAnchor.constraint(equalTo: bottomAnchor),
            dividerView.leadingAnchor.constraint(equalTo: leadingAnchor),
            dividerView.trailingAnchor.constraint(equalTo: trailingAnchor),
            dividerView.heightAnchor.constraint(equalToConstant: 1),
        ])

        // 格式组：粗体、斜体、删除线
        let formatControl = makeSegmentedControl(
            images: ["bold", "italic", "strikethrough"],
            tooltips: [
                Localized.Toolbar.toggleBold,
                Localized.Toolbar.toggleItalic,
                Localized.Toolbar.toggleStrikethrough
            ],
            action: #selector(formatAction(_:))
        )
        stackView.addArrangedSubview(formatControl)
        formatControls.append(formatControl)

        // 插入组：标题、链接、图片、分割线
        let insertControl = makeSegmentedControl(
            images: ["number", "link", "photo", "minus"],
            tooltips: [
                Localized.Toolbar.formatHeaders,
                Localized.Toolbar.insertLink,
                Localized.Toolbar.insertImage,
                Localized.Toolbar.horizontalRule
            ],
            action: #selector(insertAction(_:))
        )
        stackView.addArrangedSubview(insertControl)
        formatControls.append(insertControl)

        // 列表组：无序列表、有序列表、引用
        let listControl = makeSegmentedControl(
            images: ["list.bullet", "list.number", "text.quote"],
            tooltips: [
                Localized.Toolbar.toggleBullet,
                Localized.Toolbar.toggleNumbering,
                Localized.Toolbar.toggleBlockquote
            ],
            action: #selector(listAction(_:))
        )
        stackView.addArrangedSubview(listControl)
        formatControls.append(listControl)

        // 代码组：代码、表格
        let codeControl = makeSegmentedControl(
            images: ["chevron.left.forwardslash.chevron.right", "tablecells"],
            tooltips: [
                Localized.Toolbar.insertCode,
                Localized.Toolbar.insertTable
            ],
            action: #selector(codeAction(_:))
        )
        stackView.addArrangedSubview(codeControl)
        formatControls.append(codeControl)

        // 弹性空间
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        stackView.addArrangedSubview(spacer)

        // 右侧组：预览、大纲（这两个按钮不禁用）
        let rightControl = makeSegmentedControl(
            images: ["eye", "list.bullet.indent"],
            tooltips: [
                Localized.Toolbar.preview,
                Localized.Toolbar.tableOfContents
            ],
            action: #selector(rightAction(_:))
        )
        stackView.addArrangedSubview(rightControl)
        rightSegmentedControl = rightControl
    }

    // MARK: - 创建控件

    private func makeSegmentedControl(
        images: [String],
        tooltips: [String],
        action: Selector
    ) -> NSSegmentedControl {
        let control = NSSegmentedControl()
        control.segmentCount = images.count
        control.segmentStyle = .separated
        control.trackingMode = .momentary
        control.target = self
        control.action = action

        for (index, imageName) in images.enumerated() {
            let image = NSImage(systemSymbolName: imageName, accessibilityDescription: tooltips[index])
            control.setImage(image, forSegment: index)
            control.setToolTip(tooltips[index], forSegment: index)
            control.setWidth(0, forSegment: index) // 自动宽度
        }

        control.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        return control
    }

    // MARK: - Actions

    @objc private func formatAction(_ sender: NSSegmentedControl) {
        guard let action = FormatAction(rawValue: sender.selectedSegment) else { return }
        switch action {
        case .bold: delegate?.formatBarDidToggleBold()
        case .italic: delegate?.formatBarDidToggleItalic()
        case .strikethrough: delegate?.formatBarDidToggleStrikethrough()
        }
    }

    @objc private func insertAction(_ sender: NSSegmentedControl) {
        guard let action = InsertAction(rawValue: sender.selectedSegment) else { return }
        switch action {
        case .header: delegate?.formatBarDidRequestHeaders()
        case .link: delegate?.formatBarDidInsertLink()
        case .image: delegate?.formatBarDidInsertImage()
        case .horizontalRule: delegate?.formatBarDidInsertHorizontalRule()
        }
    }

    @objc private func listAction(_ sender: NSSegmentedControl) {
        guard let action = ListAction(rawValue: sender.selectedSegment) else { return }
        switch action {
        case .bullet: delegate?.formatBarDidToggleBullet()
        case .numbering: delegate?.formatBarDidToggleNumbering()
        case .blockquote: delegate?.formatBarDidToggleBlockquote()
        }
    }

    @objc private func codeAction(_ sender: NSSegmentedControl) {
        guard let action = CodeAction(rawValue: sender.selectedSegment) else { return }
        switch action {
        case .code: delegate?.formatBarDidInsertCode()
        case .table: delegate?.formatBarDidInsertTable()
        }
    }

    @objc private func rightAction(_ sender: NSSegmentedControl) {
        guard let action = RightAction(rawValue: sender.selectedSegment) else { return }
        switch action {
        case .preview: delegate?.formatBarDidTogglePreview()
        case .toc: delegate?.formatBarDidShowTableOfContents()
        }
    }

    // MARK: - 预览模式状态管理

    /// 设置预览模式状态，禁用/启用格式按钮
    func setPreviewMode(_ isPreviewMode: Bool) {
        // 禁用/启用所有格式控件
        for control in formatControls {
            control.isEnabled = !isPreviewMode
        }

        // 更新预览按钮图标
        let iconName = isPreviewMode ? "pencil" : "eye"
        let tooltip = isPreviewMode ? Localized.Toolbar.edit : Localized.Toolbar.preview
        rightSegmentedControl?.setImage(
            NSImage(systemSymbolName: iconName, accessibilityDescription: tooltip),
            forSegment: RightAction.preview.rawValue
        )
        rightSegmentedControl?.setToolTip(tooltip, forSegment: RightAction.preview.rawValue)
    }
}

// MARK: - Delegate Protocol

/// 格式工具栏代理协议
@MainActor
protocol EditorFormatBarDelegate: AnyObject {
    func formatBarDidToggleBold()
    func formatBarDidToggleItalic()
    func formatBarDidToggleStrikethrough()
    func formatBarDidRequestHeaders()
    func formatBarDidInsertLink()
    func formatBarDidInsertImage()
    func formatBarDidInsertHorizontalRule()
    func formatBarDidToggleBullet()
    func formatBarDidToggleNumbering()
    func formatBarDidToggleBlockquote()
    func formatBarDidInsertCode()
    func formatBarDidInsertTable()
    func formatBarDidTogglePreview()
    func formatBarDidShowTableOfContents()
}
