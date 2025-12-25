//
//  DeviceStatusView.swift
//  ScreenPresenter
//
//  Created by Sun on 2025/12/25.
//
//  设备状态视图
//  显示设备连接状态、操作按钮等信息
//

import AppKit
import SnapKit

// MARK: - 设备状态视图

final class DeviceStatusView: NSView {
    // MARK: - 颜色定义（适配黑色背景的屏幕区域）

    private enum Colors {
        /// 主标题颜色（白色）
        static let title = NSColor.white
        /// 次要标题颜色（浅灰色）
        static let titleSecondary = NSColor(white: 0.6, alpha: 1.0)
        /// 状态文字颜色（中灰色）
        static let status = NSColor(white: 0.7, alpha: 1.0)
        /// 提示文字颜色（深灰色）
        static let hint = NSColor(white: 0.5, alpha: 1.0)
        /// 次要按钮文字颜色（中灰色）
        static let actionSecondary = NSColor(white: 0.7, alpha: 1.0)
    }

    // MARK: - UI 组件

    /// 内容居中容器
    private var contentContainer: NSView!
    /// 加载指示器（菊花）
    private var loadingIndicator: NSProgressIndicator!
    /// 标题（设备名称或提示文案）
    private var titleLabel: NSTextField!
    /// 状态栏容器
    private var statusStackView: NSStackView!
    /// 状态指示灯
    private var statusIndicator: NSView!
    /// 状态文本
    private var statusLabel: NSTextField!
    /// 操作按钮
    private var actionButton: PaddedButton!
    /// 操作按钮加载指示器
    private var actionLoadingIndicator: NSProgressIndicator!
    /// 副标题/提示
    private var subtitleLabel: NSTextField!
    /// 刷新按钮
    private var refreshButton: PaddedButton!
    /// 刷新加载指示器
    private var refreshLoadingIndicator: NSProgressIndicator!

    // MARK: - 字体配置

    /// 标题标签的基准字体大小
    private let titleBaseFontSize: CGFloat = 28
    /// 标题标签的最小字体大小
    private let titleMinFontSize: CGFloat = 16
    /// 副标题标签的基准字体大小
    private let subtitleBaseFontSize: CGFloat = 14
    /// 副标题标签的最小字体大小
    private let subtitleMinFontSize: CGFloat = 10

    // MARK: - 回调

    var onActionTapped: (() -> Void)?
    var onRefreshTapped: ((@escaping () -> Void) -> Void)?
    var onStatusTapped: (() -> Void)?

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
        layer?.backgroundColor = NSColor(white: 0.05, alpha: 1.0).cgColor

        setupContentContainer()
        setupLoadingIndicator()
        setupTitleLabel()
        setupStatusStack()
        setupActionButton()
        setupSubtitleLabel()
        setupRefreshButton()
        setupStatusGesture()
    }

    private func setupContentContainer() {
        contentContainer = NSView()
        addSubview(contentContainer)
        contentContainer.snp.makeConstraints { make in
            // 降低所有约束优先级，避免父视图宽度为 0 时产生冲突
            make.center.equalToSuperview()
            make.leading.greaterThanOrEqualToSuperview().offset(20)
            make.trailing.lessThanOrEqualToSuperview().offset(-20)
        }
    }

    private func setupLoadingIndicator() {
        loadingIndicator = NSProgressIndicator()
        loadingIndicator.style = .spinning
        loadingIndicator.controlSize = .regular
        loadingIndicator.isIndeterminate = true
        loadingIndicator.isHidden = true
        // 强制使用 darkAqua 外观，确保在深色背景下菊花图标可见（白色）
        loadingIndicator.appearance = NSAppearance(named: .darkAqua)
        contentContainer.addSubview(loadingIndicator)
        loadingIndicator.snp.makeConstraints { make in
            make.top.equalToSuperview()
            make.centerX.equalToSuperview()
            make.size.equalTo(32)
        }
    }

    private func setupTitleLabel() {
        titleLabel = NSTextField(labelWithString: "")
        titleLabel.font = NSFont.systemFont(ofSize: 28, weight: .semibold)
        titleLabel.textColor = Colors.title
        titleLabel.alignment = .center
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1
        contentContainer.addSubview(titleLabel)
        titleLabel.snp.makeConstraints { make in
            make.top.equalTo(loadingIndicator.snp.bottom).offset(16)
            make.centerX.equalToSuperview()
            make.leading.greaterThanOrEqualToSuperview()
            make.trailing.lessThanOrEqualToSuperview()
        }
    }

    private func setupStatusStack() {
        statusStackView = NSStackView()
        statusStackView.orientation = .horizontal
        statusStackView.spacing = 8
        statusStackView.alignment = .centerY
        contentContainer.addSubview(statusStackView)
        statusStackView.snp.makeConstraints { make in
            make.top.equalTo(titleLabel.snp.bottom).offset(12)
            make.centerX.equalToSuperview()
        }

        // 状态指示灯
        statusIndicator = NSView()
        statusIndicator.wantsLayer = true
        statusIndicator.layer?.cornerRadius = 5
        statusIndicator.layer?.backgroundColor = NSColor.systemGray.cgColor
        statusStackView.addArrangedSubview(statusIndicator)
        statusIndicator.snp.makeConstraints { make in
            make.size.equalTo(10)
        }

        // 状态文本
        statusLabel = NSTextField(labelWithString: "")
        statusLabel.font = NSFont.systemFont(ofSize: 16)
        statusLabel.textColor = Colors.status
        statusStackView.addArrangedSubview(statusLabel)
    }

    private func setupActionButton() {
        actionButton = PaddedButton(horizontalPadding: 20, verticalPadding: 12)
        actionButton.target = self
        actionButton.action = #selector(actionTapped)
        actionButton.wantsLayer = true
        actionButton.isBordered = false
        actionButton.layer?.cornerRadius = 8
        actionButton.layer?.backgroundColor = NSColor.appAccent.cgColor
        actionButton.focusRingType = .none
        actionButton.refusesFirstResponder = true
        setActionButtonTitle(L10n.overlayUI.startCapture)
        contentContainer.addSubview(actionButton)
        actionButton.snp.makeConstraints { make in
            make.top.equalTo(statusStackView.snp.bottom).offset(24)
            make.centerX.equalToSuperview()
        }

        // 操作按钮加载指示器
        actionLoadingIndicator = NSProgressIndicator()
        actionLoadingIndicator.style = .spinning
        actionLoadingIndicator.controlSize = .small
        actionLoadingIndicator.isIndeterminate = true
        actionLoadingIndicator.isHidden = true
        actionLoadingIndicator.appearance = NSAppearance(named: .darkAqua)
        actionButton.addSubview(actionLoadingIndicator)
        actionLoadingIndicator.snp.makeConstraints { make in
            make.center.equalToSuperview()
        }
    }

    private func setupSubtitleLabel() {
        subtitleLabel = NSTextField(labelWithString: "")
        subtitleLabel.font = NSFont.systemFont(ofSize: 14)
        subtitleLabel.textColor = Colors.hint
        subtitleLabel.alignment = .center
        subtitleLabel.lineBreakMode = .byWordWrapping
        subtitleLabel.maximumNumberOfLines = 2
        contentContainer.addSubview(subtitleLabel)
        subtitleLabel.snp.makeConstraints { make in
            make.top.equalTo(actionButton.snp.bottom).offset(16)
            make.centerX.equalToSuperview()
            make.leading.greaterThanOrEqualToSuperview()
            make.trailing.lessThanOrEqualToSuperview()
        }
    }

    private func setupRefreshButton() {
        refreshButton = PaddedButton(horizontalPadding: 8, verticalPadding: 4)
        refreshButton.wantsLayer = true
        refreshButton.isBordered = false
        refreshButton.layer?.cornerRadius = 6
        refreshButton.layer?.backgroundColor = Colors.actionSecondary.withAlphaComponent(0.2).cgColor
        refreshButton.focusRingType = .none
        refreshButton.refusesFirstResponder = true
        refreshButton.target = self
        refreshButton.action = #selector(refreshTapped)
        updateRefreshButtonTitle()
        contentContainer.addSubview(refreshButton)
        refreshButton.snp.makeConstraints { make in
            make.top.equalTo(subtitleLabel.snp.bottom).offset(12)
            make.centerX.equalToSuperview()
            make.bottom.equalToSuperview()
        }

        // 刷新加载指示器
        refreshLoadingIndicator = NSProgressIndicator()
        refreshLoadingIndicator.style = .spinning
        refreshLoadingIndicator.controlSize = .small
        refreshLoadingIndicator.isIndeterminate = true
        refreshLoadingIndicator.isHidden = true
        refreshLoadingIndicator.appearance = NSAppearance(named: .darkAqua)
        refreshButton.addSubview(refreshLoadingIndicator)
        refreshLoadingIndicator.snp.makeConstraints { make in
            make.center.equalToSuperview()
        }
    }

    private func setupStatusGesture() {
        let tapGesture = NSClickGestureRecognizer(target: self, action: #selector(statusAreaTapped))
        statusStackView.addGestureRecognizer(tapGesture)
    }

    // MARK: - 公开方法

    /// 显示加载状态
    func showLoading(title: String) {
        loadingIndicator.isHidden = false
        loadingIndicator.startAnimation(nil)

        titleLabel.stringValue = title
        titleLabel.textColor = Colors.titleSecondary

        statusStackView.isHidden = true
        actionButton.isHidden = true
        subtitleLabel.isHidden = true
        refreshButton.isHidden = true

        needsLayout = true
    }

    /// 显示断开状态
    func showDisconnected(title: String, subtitle: String) {
        loadingIndicator.stopAnimation(nil)
        loadingIndicator.isHidden = true

        titleLabel.stringValue = title
        titleLabel.textColor = Colors.titleSecondary

        statusIndicator.isHidden = true
        statusLabel.stringValue = ""
        statusStackView.isHidden = true

        actionButton.isHidden = true

        subtitleLabel.stringValue = subtitle
        subtitleLabel.textColor = Colors.hint
        subtitleLabel.isHidden = false

        refreshButton.isHidden = true

        needsLayout = true
    }

    /// 显示已连接状态
    func showConnected(
        deviceName: String,
        statusText: String,
        statusColor: NSColor,
        hasWarning: Bool,
        subtitle: String,
        showRefresh: Bool
    ) {
        loadingIndicator.stopAnimation(nil)
        loadingIndicator.isHidden = true

        titleLabel.stringValue = deviceName
        titleLabel.textColor = Colors.title

        statusStackView.isHidden = false
        statusIndicator.isHidden = false
        statusIndicator.layer?.backgroundColor = statusColor.cgColor
        statusLabel.stringValue = hasWarning ? "⚠️ \(statusText)" : statusText
        statusLabel.textColor = hasWarning ? statusColor : Colors.status

        setActionButtonTitle(L10n.overlayUI.startCapture)
        actionButton.isEnabled = true
        actionButton.isHidden = false

        subtitleLabel.stringValue = subtitle
        subtitleLabel.textColor = Colors.hint
        subtitleLabel.isHidden = false

        refreshButton.isHidden = !showRefresh
        stopRefreshLoading()

        needsLayout = true
    }

    /// 显示工具链缺失状态
    func showToolchainMissing(toolName: String, hint: String) {
        loadingIndicator.stopAnimation(nil)
        loadingIndicator.isHidden = true

        titleLabel.stringValue = L10n.overlayUI.toolNotInstalled(toolName)
        titleLabel.textColor = .systemOrange

        statusStackView.isHidden = false
        statusIndicator.isHidden = false
        statusIndicator.layer?.backgroundColor = NSColor.systemOrange.cgColor
        statusLabel.stringValue = L10n.overlayUI.needInstall(toolName)
        statusLabel.textColor = .systemOrange

        setActionButtonTitle(L10n.overlayUI.installTool(toolName))
        actionButton.isEnabled = true
        actionButton.isHidden = false

        subtitleLabel.stringValue = hint
        subtitleLabel.textColor = Colors.hint
        subtitleLabel.isHidden = false

        refreshButton.isHidden = true

        needsLayout = true
    }

    /// 设置操作按钮的启用状态
    func setActionButtonEnabled(_ enabled: Bool) {
        actionButton.isEnabled = enabled
        actionButton.alphaValue = enabled ? 1.0 : 0.7
    }

    /// 开始操作按钮加载状态
    func startActionLoading() {
        actionButton.isEnabled = false
        actionButton.alphaValue = 0.7
        actionButton.attributedTitle = NSAttributedString(string: "")
        actionLoadingIndicator.isHidden = false
        actionLoadingIndicator.startAnimation(nil)
    }

    /// 停止操作按钮加载状态
    func stopActionLoading() {
        actionButton.isEnabled = true
        actionButton.alphaValue = 1.0
        actionLoadingIndicator.stopAnimation(nil)
        actionLoadingIndicator.isHidden = true
        setActionButtonTitle(L10n.overlayUI.startCapture)
    }

    // MARK: - 私有方法

    private func setActionButtonTitle(_ title: String) {
        let buttonFont = NSFont.systemFont(ofSize: 16, weight: .medium)
        let attributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor.white,
            .font: buttonFont,
        ]
        actionButton.attributedTitle = NSAttributedString(string: title, attributes: attributes)
    }

    private func updateRefreshButtonTitle() {
        let buttonFont = NSFont.systemFont(ofSize: 12, weight: .regular)
        let attributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: Colors.actionSecondary,
            .font: buttonFont,
        ]
        refreshButton.attributedTitle = NSAttributedString(
            string: L10n.common.refresh,
            attributes: attributes
        )
    }

    private func startRefreshLoading() {
        refreshButton.isEnabled = false
        refreshLoadingIndicator.isHidden = false
        refreshLoadingIndicator.startAnimation(nil)
    }

    private func stopRefreshLoading() {
        refreshButton.isEnabled = true
        refreshLoadingIndicator.stopAnimation(nil)
        refreshLoadingIndicator.isHidden = true
    }

    // MARK: - 操作

    @objc private func actionTapped() {
        onActionTapped?()
    }

    @objc private func refreshTapped() {
        startRefreshLoading()
        onRefreshTapped? { [weak self] in
            DispatchQueue.main.async {
                self?.stopRefreshLoading()
            }
        }
    }

    @objc private func statusAreaTapped() {
        onStatusTapped?()
    }

    // MARK: - 本地化

    /// 更新本地化文本
    func updateLocalizedTexts() {
        updateRefreshButtonTitle()
    }

    // MARK: - 布局

    override func layout() {
        super.layout()
        updateFontsForWidth()
    }

    // MARK: - 字体自适应

    /// 根据可用宽度更新字体大小
    private func updateFontsForWidth() {
        let availableWidth = contentContainer.bounds.width
        guard availableWidth > 0 else { return }

        // 更新标题标签字体
        let titleFont = titleLabel.stringValue.calculateFittingFont(
            baseSize: titleBaseFontSize,
            minSize: titleMinFontSize,
            weight: .semibold,
            availableWidth: availableWidth
        )
        titleLabel.font = titleFont

        // 更新副标题标签字体
        let subtitleFont = subtitleLabel.stringValue.calculateFittingFont(
            baseSize: subtitleBaseFontSize,
            minSize: subtitleMinFontSize,
            weight: .regular,
            availableWidth: availableWidth
        )
        subtitleLabel.font = subtitleFont
    }

}

extension String {
    
    /// 计算适合可用宽度的字体大小
    func calculateFittingFont(
        baseSize: CGFloat,
        minSize: CGFloat,
        weight: NSFont.Weight,
        availableWidth: CGFloat
    ) -> NSFont {
        guard !self.isEmpty else {
            return NSFont.systemFont(ofSize: baseSize, weight: weight)
        }

        var fontSize = baseSize
        var font = NSFont.systemFont(ofSize: fontSize, weight: weight)

        // 逐步减小字体直到文本适合或达到最小值
        while fontSize > minSize {
            let attributes: [NSAttributedString.Key: Any] = [.font: font]
            let textWidth = (self as NSString).size(withAttributes: attributes).width

            if textWidth <= availableWidth {
                break
            }

            fontSize -= 1
            font = NSFont.systemFont(ofSize: fontSize, weight: weight)
        }

        return font
    }
}
