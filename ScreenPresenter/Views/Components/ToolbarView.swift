//
//  ToolbarView.swift
//  ScreenPresenter
//
//  Created by Sun on 2025/12/22.
//
//  工具栏视图（纯 AppKit）
//  包含布局切换、刷新等操作按钮
//

import AppKit

// MARK: - 工具栏代理协议

protocol ToolbarViewDelegate: AnyObject {
    func toolbarDidRequestRefresh()
    func toolbarDidChangeLayout(_ layout: LayoutMode)
    func toolbarDidToggleSwap(_ swapped: Bool)
    func toolbarDidRequestPreferences()
}

// MARK: - 工具栏视图

final class ToolbarView: NSView {
    // MARK: - 代理

    weak var delegate: ToolbarViewDelegate?

    // MARK: - UI 组件

    private var layoutSegmentedControl: NSSegmentedControl!
    private var swapButton: NSButton!
    private var refreshButton: NSButton!
    private var preferencesButton: NSButton!

    // MARK: - 状态

    private var isSwapped = false
    private var currentLayout: LayoutMode = .sideBySide

    // MARK: - 初始化

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupUI()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
    }

    // MARK: - UI 设置

    private func setupUI() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor

        // 布局分段控件
        layoutSegmentedControl = NSSegmentedControl(
            labels: ["左右", "上下", "单屏"],
            trackingMode: .selectOne,
            target: self,
            action: #selector(layoutChanged)
        )
        layoutSegmentedControl.selectedSegment = 0
        layoutSegmentedControl.translatesAutoresizingMaskIntoConstraints = false

        // 设置图标
        layoutSegmentedControl.setImage(
            NSImage(systemSymbolName: "rectangle.split.2x1", accessibilityDescription: nil),
            forSegment: 0
        )
        layoutSegmentedControl.setImage(
            NSImage(systemSymbolName: "rectangle.split.1x2", accessibilityDescription: nil),
            forSegment: 1
        )
        layoutSegmentedControl.setImage(
            NSImage(systemSymbolName: "rectangle", accessibilityDescription: nil),
            forSegment: 2
        )

        addSubview(layoutSegmentedControl)

        // 交换按钮
        swapButton = NSButton(
            title: "",
            image: NSImage(systemSymbolName: "arrow.left.arrow.right", accessibilityDescription: "交换")!,
            target: self,
            action: #selector(swapTapped)
        )
        swapButton.bezelStyle = .rounded
        swapButton.toolTip = "交换设备位置"
        swapButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(swapButton)

        // 刷新按钮
        refreshButton = NSButton(
            title: "",
            image: NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: "刷新")!,
            target: self,
            action: #selector(refreshTapped)
        )
        refreshButton.bezelStyle = .rounded
        refreshButton.toolTip = "刷新设备列表"
        refreshButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(refreshButton)

        // 偏好设置按钮
        preferencesButton = NSButton(
            title: "",
            image: NSImage(systemSymbolName: "gear", accessibilityDescription: "设置")!,
            target: self,
            action: #selector(preferencesTapped)
        )
        preferencesButton.bezelStyle = .rounded
        preferencesButton.toolTip = "偏好设置"
        preferencesButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(preferencesButton)

        // 分隔线
        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        addSubview(separator)

        // 约束
        NSLayoutConstraint.activate([
            // 布局控件
            layoutSegmentedControl.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            layoutSegmentedControl.centerYAnchor.constraint(equalTo: centerYAnchor),

            // 交换按钮
            swapButton.leadingAnchor.constraint(equalTo: layoutSegmentedControl.trailingAnchor, constant: 12),
            swapButton.centerYAnchor.constraint(equalTo: centerYAnchor),

            // 刷新按钮
            refreshButton.trailingAnchor.constraint(equalTo: preferencesButton.leadingAnchor, constant: -8),
            refreshButton.centerYAnchor.constraint(equalTo: centerYAnchor),

            // 偏好设置按钮
            preferencesButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            preferencesButton.centerYAnchor.constraint(equalTo: centerYAnchor),

            // 分隔线
            separator.leadingAnchor.constraint(equalTo: leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: trailingAnchor),
            separator.bottomAnchor.constraint(equalTo: bottomAnchor),
            separator.heightAnchor.constraint(equalToConstant: 1),
        ])
    }

    // MARK: - 操作

    @objc private func layoutChanged() {
        let layouts: [LayoutMode] = [.sideBySide, .topBottom, .single]
        currentLayout = layouts[layoutSegmentedControl.selectedSegment]
        delegate?.toolbarDidChangeLayout(currentLayout)
    }

    @objc private func swapTapped() {
        isSwapped.toggle()
        delegate?.toolbarDidToggleSwap(isSwapped)

        // 更新按钮状态
        if isSwapped {
            swapButton.contentTintColor = .controlAccentColor
        } else {
            swapButton.contentTintColor = .labelColor
        }
    }

    @objc private func refreshTapped() {
        delegate?.toolbarDidRequestRefresh()

        // 添加旋转动画
        let animation = CABasicAnimation(keyPath: "transform.rotation.z")
        animation.fromValue = 0
        animation.toValue = CGFloat.pi * 2
        animation.duration = 0.5
        refreshButton.layer?.add(animation, forKey: "rotation")
    }

    @objc private func preferencesTapped() {
        delegate?.toolbarDidRequestPreferences()
    }
}
