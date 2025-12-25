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
import SnapKit

// MARK: - 布局模式

enum PreviewLayoutMode {
    /// 双设备并排显示（默认）
    case dual
    /// 仅显示左侧设备
    case leftOnly
    /// 仅显示右侧设备
    case rightOnly
}

// MARK: - 预览容器视图

final class PreviewContainerView: NSView {
    // MARK: - UI 组件

    /// 左侧区域容器
    private var leftAreaView: NSView!
    /// 右侧区域容器
    private var rightAreaView: NSView!

    /// iOS 设备面板（默认在左侧）
    private(set) var iosPanelView: DevicePanelView!
    /// Android 设备面板（默认在右侧）
    private(set) var androidPanelView: DevicePanelView!

    /// 交换按钮
    private(set) var swapButton: NSButton!
    private var swapButtonIconLayer: CALayer!

    // MARK: - 状态

    /// 当前布局模式
    private(set) var layoutMode: PreviewLayoutMode = .dual

    /// 是否交换了左右面板
    private(set) var isSwapped: Bool = false

    /// 是否全屏模式
    var isFullScreen: Bool = false {
        didSet {
            if oldValue != isFullScreen {
                updateLayout(animated: false)
            }
        }
    }

    /// 是否首次布局
    private var isInitialLayout: Bool = true

    // MARK: - 常量

    /// 面板之间的间隔
    private let panelGap: CGFloat = 8

    /// 非全屏时的垂直内边距
    private let verticalPadding: CGFloat = 24

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

    // MARK: - UI 设置

    private func setupUI() {
        wantsLayer = true

        setupAreaViews()
        setupDevicePanels()
        setupSwapButton()
    }

    private func setupAreaViews() {
        // 左侧区域容器
        leftAreaView = NSView()
        addSubview(leftAreaView)
        leftAreaView.snp.makeConstraints { make in
            make.top.bottom.leading.equalToSuperview()
            make.width.equalToSuperview().multipliedBy(0.5)
        }

        // 右侧区域容器
        rightAreaView = NSView()
        addSubview(rightAreaView)
        rightAreaView.snp.makeConstraints { make in
            make.top.bottom.trailing.equalToSuperview()
            make.width.equalToSuperview().multipliedBy(0.5)
        }
    }

    private func setupDevicePanels() {
        // iOS 面板（默认在左侧）
        iosPanelView = DevicePanelView()
        leftAreaView.addSubview(iosPanelView)

        // Android 面板（默认在右侧）
        androidPanelView = DevicePanelView()
        rightAreaView.addSubview(androidPanelView)
    }

    private func setupSwapButton() {
        swapButton = NSButton(title: "", target: self, action: #selector(swapTapped))
        swapButton.bezelStyle = .circular
        swapButton.isBordered = false
        swapButton.wantsLayer = true
        swapButton.layer?.cornerRadius = 16
        swapButton.toolTip = L10n.toolbar.swapTooltip
        swapButton.focusRingType = .none
        swapButton.refusesFirstResponder = true
        addSubview(swapButton)

        // 添加图标图层
        swapButtonIconLayer = CALayer()
        swapButtonIconLayer.contents = NSImage(
            systemSymbolName: "arrow.left.arrow.right",
            accessibilityDescription: L10n.toolbar.swapTooltip
        )
        swapButtonIconLayer.contentsGravity = .resizeAspect
        swapButton.layer?.addSublayer(swapButtonIconLayer)

        // 设置图标大小和位置
        let iconSize: CGFloat = 16
        let buttonSize: CGFloat = 32
        let iconOffset = (buttonSize - iconSize) / 2
        swapButtonIconLayer.frame = CGRect(x: iconOffset, y: iconOffset, width: iconSize, height: iconSize)

        // 设置初始样式
        updateSwapButtonStyle()

        // 交换按钮约束
        swapButton.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.centerY.equalToSuperview()
            make.width.height.equalTo(32)
        }
    }

    private func updateSwapButtonStyle() {
        guard let layer = swapButton.layer else { return }

        if isFullScreen {
            // 全屏时使用暗色样式
            layer.backgroundColor = NSColor.black.withAlphaComponent(0.6).cgColor
            layer.borderColor = NSColor.white.withAlphaComponent(0.2).cgColor
            layer.borderWidth = 1
            layer.shadowColor = NSColor.black.cgColor
            layer.shadowOpacity = 0.5
            layer.shadowOffset = CGSize(width: 0, height: -1)
            layer.shadowRadius = 4
            swapButtonIconLayer.backgroundColor = NSColor.white.cgColor
        } else {
            // 非全屏时使用浅色样式
            layer.backgroundColor = NSColor(white: 0.9, alpha: 1.0).cgColor
            layer.borderColor = NSColor(white: 0.8, alpha: 1.0).cgColor
            layer.borderWidth = 1
            layer.shadowColor = NSColor.black.cgColor
            layer.shadowOpacity = 0.1
            layer.shadowOffset = CGSize(width: 0, height: -1)
            layer.shadowRadius = 2
            swapButtonIconLayer.backgroundColor = NSColor(white: 0.3, alpha: 1.0).cgColor
        }
    }

    // MARK: - 公开方法

    /// 设置布局模式
    func setLayoutMode(_ mode: PreviewLayoutMode, animated: Bool = true) {
        guard layoutMode != mode else { return }
        layoutMode = mode
        updateLayout(animated: animated)
    }

    /// 交换左右面板
    func swapPanels(animated: Bool = true) {
        isSwapped.toggle()
        updateLayout(animated: animated)
    }

    /// 更新布局
    func updateLayout(animated: Bool = true) {
        // 更新按钮样式
        updateSwapButtonStyle()

        // 根据交换状态决定哪个面板在哪个区域
        // 默认 (isSwapped=false): iOS 在左侧，Android 在右侧
        // 交换后 (isSwapped=true): Android 在左侧，iOS 在右侧
        let currentLeftPanel = isSwapped ? androidPanelView! : iosPanelView!
        let currentRightPanel = isSwapped ? iosPanelView! : androidPanelView!

        // 将面板移动到对应的区域容器
        currentLeftPanel.removeFromSuperview()
        leftAreaView.addSubview(currentLeftPanel)

        currentRightPanel.removeFromSuperview()
        rightAreaView.addSubview(currentRightPanel)

        // 重置面板约束
        currentLeftPanel.snp.removeConstraints()
        currentRightPanel.snp.removeConstraints()

        // 更新区域可见性
        updateAreaVisibility()

        // 计算垂直内边距
        let vPadding: CGFloat = isFullScreen ? 0 : verticalPadding
        let showBezel = UserPreferences.shared.showDeviceBezel
        let shouldFillHeight = isFullScreen && !showBezel

        // 获取设备的 aspectRatio（宽/高）
        let leftAspectRatio = currentLeftPanel.deviceAspectRatio
        let rightAspectRatio = currentRightPanel.deviceAspectRatio

        // 左面板约束：在左侧区域内居中
        currentLeftPanel.snp.makeConstraints { make in
            if shouldFillHeight {
                make.top.bottom.equalToSuperview()
            } else {
                make.top.equalToSuperview().offset(vPadding)
                make.bottom.equalToSuperview().offset(-vPadding)
            }
            // 宽度 = 高度 * aspectRatio
            make.width.equalTo(currentLeftPanel.snp.height).multipliedBy(leftAspectRatio)
            // 在区域内水平居中，右侧留出 gap/2 的间隔
            make.centerX.equalToSuperview().offset(-panelGap / 2)
            // 确保不超出区域边界
            make.leading.greaterThanOrEqualToSuperview()
            make.trailing.lessThanOrEqualToSuperview().offset(-panelGap / 2)
        }

        // 右面板约束：在右侧区域内居中
        currentRightPanel.snp.makeConstraints { make in
            if shouldFillHeight {
                make.top.bottom.equalToSuperview()
            } else {
                make.top.equalToSuperview().offset(vPadding)
                make.bottom.equalToSuperview().offset(-vPadding)
            }
            // 宽度 = 高度 * aspectRatio
            make.width.equalTo(currentRightPanel.snp.height).multipliedBy(rightAspectRatio)
            // 在区域内水平居中，左侧留出 gap/2 的间隔
            make.centerX.equalToSuperview().offset(panelGap / 2)
            // 确保不超出区域边界
            make.leading.greaterThanOrEqualToSuperview().offset(panelGap / 2)
            make.trailing.lessThanOrEqualToSuperview()
        }

        // 执行布局更新
        if isInitialLayout || !animated {
            isInitialLayout = false
            layoutSubtreeIfNeeded()
        } else {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.3
                context.allowsImplicitAnimation = true
                layoutSubtreeIfNeeded()
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
        swapButtonIconLayer.contents = NSImage(
            systemSymbolName: "arrow.left.arrow.right",
            accessibilityDescription: L10n.toolbar.swapTooltip
        )
        iosPanelView.updateLocalizedTexts()
        androidPanelView.updateLocalizedTexts()
    }

    // MARK: - 私有方法

    private func updateAreaVisibility() {
        switch layoutMode {
        case .dual:
            leftAreaView.isHidden = false
            rightAreaView.isHidden = false
            swapButton.isHidden = false
            // 恢复左右各占一半的布局
            leftAreaView.snp.remakeConstraints { make in
                make.top.bottom.leading.equalToSuperview()
                make.width.equalToSuperview().multipliedBy(0.5)
            }
            rightAreaView.snp.remakeConstraints { make in
                make.top.bottom.trailing.equalToSuperview()
                make.width.equalToSuperview().multipliedBy(0.5)
            }

        case .leftOnly:
            leftAreaView.isHidden = false
            rightAreaView.isHidden = true
            swapButton.isHidden = true
            // 左侧区域占满整个容器
            leftAreaView.snp.remakeConstraints { make in
                make.edges.equalToSuperview()
            }

        case .rightOnly:
            leftAreaView.isHidden = true
            rightAreaView.isHidden = false
            swapButton.isHidden = true
            // 右侧区域占满整个容器
            rightAreaView.snp.remakeConstraints { make in
                make.edges.equalToSuperview()
            }
        }
    }

    @objc private func swapTapped() {
        swapPanels()
        onSwapTapped?()
    }
}
