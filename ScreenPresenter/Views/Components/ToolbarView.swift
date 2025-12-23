//
//  ToolbarView.swift
//  ScreenPresenter
//
//  Created by Sun on 2025/12/22.
//
//  工具栏视图
//  包含布局切换、交换、刷新、偏好设置按钮
//

import AppKit
import SnapKit

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

    private var layoutLabel: NSTextField!
    private var layoutSegmentedControl: NSSegmentedControl!
    private var swapButton: NSButton!
    private var refreshButton: NSButton!
    private var refreshSpinner: NSProgressIndicator!
    private var preferencesButton: NSButton!
    private var divider: NSBox!

    // MARK: - 状态

    private var isSwapped = false
    private var currentLayout: LayoutMode = .sideBySide
    private var isRefreshing = false

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

        setupLayoutSection()
        setupSwapButton()
        setupRefreshButton()
        setupPreferencesButton()
        setupDividers()
        setupConstraints()
    }

    private func setupLayoutSection() {
        layoutLabel = NSTextField(labelWithString: L10n.toolbar.layout)
        layoutLabel.font = NSFont.systemFont(ofSize: 11)
        layoutLabel.textColor = .secondaryLabelColor
        addSubview(layoutLabel)

        layoutSegmentedControl = NSSegmentedControl(
            images: [
                NSImage(systemSymbolName: "rectangle.split.2x1", accessibilityDescription: L10n.layout.sideBySide)!,
                NSImage(systemSymbolName: "rectangle.split.1x2", accessibilityDescription: L10n.layout.topBottom)!,
            ],
            trackingMode: .selectOne,
            target: self,
            action: #selector(layoutChanged)
        )
        layoutSegmentedControl.selectedSegment = 0
        layoutSegmentedControl.setLabel(L10n.toolbar.sideBySide, forSegment: 0)
        layoutSegmentedControl.setLabel(L10n.toolbar.topBottom, forSegment: 1)
        addSubview(layoutSegmentedControl)
    }

    private func setupSwapButton() {
        swapButton = NSButton(title: "", target: self, action: #selector(swapTapped))
        swapButton.image = NSImage(
            systemSymbolName: "arrow.left.arrow.right",
            accessibilityDescription: L10n.toolbar.swap
        )
        swapButton.title = L10n.toolbar.swap
        swapButton.imagePosition = .imageLeading
        swapButton.bezelStyle = .rounded
        swapButton.font = NSFont.systemFont(ofSize: 11)
        swapButton.toolTip = L10n.toolbar.swapTooltip
        addSubview(swapButton)
    }

    private func setupRefreshButton() {
        refreshButton = NSButton(title: "", target: self, action: #selector(refreshTapped))
        refreshButton.image = NSImage(
            systemSymbolName: "arrow.clockwise",
            accessibilityDescription: L10n.toolbar.refresh
        )
        refreshButton.title = L10n.toolbar.refresh
        refreshButton.imagePosition = .imageLeading
        refreshButton.bezelStyle = .rounded
        refreshButton.font = NSFont.systemFont(ofSize: 11)
        refreshButton.toolTip = L10n.toolbar.refreshTooltip
        addSubview(refreshButton)

        refreshSpinner = NSProgressIndicator()
        refreshSpinner.style = .spinning
        refreshSpinner.controlSize = .small
        refreshSpinner.isHidden = true
        addSubview(refreshSpinner)
    }

    private func setupPreferencesButton() {
        preferencesButton = NSButton(title: "", target: self, action: #selector(preferencesTapped))
        preferencesButton.image = NSImage(systemSymbolName: "gear", accessibilityDescription: L10n.toolbar.preferences)
        preferencesButton.title = L10n.toolbar.preferences
        preferencesButton.imagePosition = .imageLeading
        preferencesButton.bezelStyle = .rounded
        preferencesButton.font = NSFont.systemFont(ofSize: 11)
        preferencesButton.toolTip = L10n.toolbar.preferencesTooltip
        addSubview(preferencesButton)
    }

    private func setupDividers() {
        divider = NSBox()
        divider.boxType = .separator
        addSubview(divider)

        let bottomSeparator = NSBox()
        bottomSeparator.boxType = .separator
        addSubview(bottomSeparator)
        bottomSeparator.snp.makeConstraints { make in
            make.leading.trailing.bottom.equalToSuperview()
            make.height.equalTo(1)
        }
    }

    private func setupConstraints() {
        layoutLabel.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(16)
            make.centerY.equalToSuperview()
        }

        layoutSegmentedControl.snp.makeConstraints { make in
            make.leading.equalTo(layoutLabel.snp.trailing).offset(6)
            make.centerY.equalToSuperview()
        }

        divider.snp.makeConstraints { make in
            make.leading.equalTo(layoutSegmentedControl.snp.trailing).offset(12)
            make.centerY.equalToSuperview()
            make.width.equalTo(1)
            make.height.equalTo(20)
        }

        swapButton.snp.makeConstraints { make in
            make.leading.equalTo(divider.snp.trailing).offset(12)
            make.centerY.equalToSuperview()
        }

        preferencesButton.snp.makeConstraints { make in
            make.trailing.equalToSuperview().offset(-16)
            make.centerY.equalToSuperview()
        }

        refreshButton.snp.makeConstraints { make in
            make.trailing.equalTo(preferencesButton.snp.leading).offset(-8)
            make.centerY.equalToSuperview()
        }

        refreshSpinner.snp.makeConstraints { make in
            make.center.equalTo(refreshButton)
        }
    }

    // MARK: - 操作

    @objc private func layoutChanged() {
        let layouts: [LayoutMode] = [.sideBySide, .topBottom]
        currentLayout = layouts[layoutSegmentedControl.selectedSegment]
        delegate?.toolbarDidChangeLayout(currentLayout)
    }

    @objc private func swapTapped() {
        isSwapped.toggle()
        delegate?.toolbarDidToggleSwap(isSwapped)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            context.allowsImplicitAnimation = true
            if isSwapped {
                swapButton.contentTintColor = .controlAccentColor
            } else {
                swapButton.contentTintColor = .labelColor
            }
        }
    }

    @objc private func refreshTapped() {
        guard !isRefreshing else { return }

        setRefreshing(true)
        delegate?.toolbarDidRequestRefresh()

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.setRefreshing(false)
        }
    }

    @objc private func preferencesTapped() {
        delegate?.toolbarDidRequestPreferences()
    }

    // MARK: - 公开方法

    func setRefreshing(_ refreshing: Bool) {
        isRefreshing = refreshing

        if refreshing {
            refreshButton.title = L10n.toolbar.refreshing
            refreshButton.isEnabled = false
            refreshSpinner.startAnimation(nil)
            refreshSpinner.isHidden = false
        } else {
            refreshButton.title = L10n.toolbar.refresh
            refreshButton.isEnabled = true
            refreshSpinner.stopAnimation(nil)
            refreshSpinner.isHidden = true
        }
    }
}
