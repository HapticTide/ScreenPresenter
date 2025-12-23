//
//  DevicePanelView.swift
//  ScreenPresenter
//
//  Created by Sun on 2025/12/23.
//
//  设备面板视图
//  包含设备边框和状态信息的完整设备展示
//

import AppKit
import SnapKit

// MARK: - 设备面板视图

final class DevicePanelView: NSView {
    // MARK: - UI 组件

    /// 设备边框视图
    private var bezelView: DeviceBezelView!

    /// 状态内容容器（显示在边框屏幕区域内）
    private var statusContainerView: NSView!

    // 状态 UI 组件
    private var iconImageView: NSImageView!
    private var titleLabel: NSTextField!
    private var statusStackView: NSStackView!
    private var statusIndicator: NSView!
    private var statusLabel: NSTextField!
    private var actionButton: NSButton!
    private var subtitleLabel: NSTextField!

    // 捕获中的悬浮栏
    private var captureBarView: NSView!
    private var captureIndicator: NSView!
    private var captureStatusLabel: NSTextField!
    private var resolutionLabel: NSTextField!
    private var fpsLabel: NSTextField!
    private var stopButton: NSButton!

    // MARK: - 回调

    private var onStartAction: (() -> Void)?
    private var onStopAction: (() -> Void)?
    private var onInstallAction: (() -> Void)?

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
        /// 图标颜色（灰色）
        static let icon = NSColor(white: 0.55, alpha: 1.0)
        /// 图标高亮颜色
        static let iconHighlight = NSColor(white: 0.7, alpha: 1.0)
    }

    // MARK: - 状态

    private enum PanelState {
        case disconnected
        case connected
        case capturing
        case toolchainMissing
    }

    private var currentState: PanelState = .disconnected
    private var currentPlatform: DevicePlatform = .ios

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
        layer?.backgroundColor = NSColor.clear.cgColor

        setupBezelView()
        setupStatusContent()
        setupCaptureBar()
    }

    private func setupBezelView() {
        bezelView = DeviceBezelView()
        addSubview(bezelView)
        bezelView.snp.makeConstraints { make in
            make.edges.equalToSuperview().inset(8)
        }
    }

    private func setupStatusContent() {
        // 状态内容容器（覆盖整个屏幕区域，带有暗色背景）
        statusContainerView = NSView()
        statusContainerView.wantsLayer = true
        // 深色背景，用于非捕获状态时显示
        statusContainerView.layer?.backgroundColor = NSColor(white: 0.05, alpha: 1.0).cgColor
        bezelView.screenContentView.addSubview(statusContainerView)
        statusContainerView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }

        // 内容居中容器
        let contentContainer = NSView()
        statusContainerView.addSubview(contentContainer)
        contentContainer.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.leading.greaterThanOrEqualToSuperview().offset(16)
            make.trailing.lessThanOrEqualToSuperview().offset(-16)
        }

        // 图标
        iconImageView = NSImageView()
        iconImageView.imageScaling = .scaleProportionallyUpOrDown
        iconImageView.contentTintColor = Colors.icon
        contentContainer.addSubview(iconImageView)
        iconImageView.snp.makeConstraints { make in
            make.top.equalToSuperview()
            make.centerX.equalToSuperview()
            make.size.equalTo(60)
        }

        // 标题
        titleLabel = NSTextField(labelWithString: "")
        titleLabel.font = NSFont.systemFont(ofSize: 16, weight: .semibold)
        titleLabel.textColor = Colors.title
        titleLabel.alignment = .center
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1
        contentContainer.addSubview(titleLabel)
        titleLabel.snp.makeConstraints { make in
            make.top.equalTo(iconImageView.snp.bottom).offset(12)
            make.centerX.equalToSuperview()
            make.leading.greaterThanOrEqualToSuperview()
            make.trailing.lessThanOrEqualToSuperview()
        }

        // 状态栏
        statusStackView = NSStackView()
        statusStackView.orientation = .horizontal
        statusStackView.spacing = 6
        statusStackView.alignment = .centerY
        contentContainer.addSubview(statusStackView)
        statusStackView.snp.makeConstraints { make in
            make.top.equalTo(titleLabel.snp.bottom).offset(6)
            make.centerX.equalToSuperview()
        }

        // 状态指示灯
        statusIndicator = NSView()
        statusIndicator.wantsLayer = true
        statusIndicator.layer?.cornerRadius = 3
        statusIndicator.layer?.backgroundColor = NSColor.systemGray.cgColor
        statusStackView.addArrangedSubview(statusIndicator)
        statusIndicator.snp.makeConstraints { make in
            make.size.equalTo(6)
        }

        // 状态文本
        statusLabel = NSTextField(labelWithString: "")
        statusLabel.font = NSFont.systemFont(ofSize: 11)
        statusLabel.textColor = Colors.status
        statusStackView.addArrangedSubview(statusLabel)

        // 操作按钮
        actionButton = NSButton(title: L10n.overlayUI.startCapture, target: self, action: #selector(actionTapped))
        actionButton.bezelStyle = .rounded
        actionButton.controlSize = .regular
        actionButton.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        contentContainer.addSubview(actionButton)
        actionButton.snp.makeConstraints { make in
            make.top.equalTo(statusStackView.snp.bottom).offset(12)
            make.centerX.equalToSuperview()
            make.width.greaterThanOrEqualTo(100)
        }

        // 副标题/提示
        subtitleLabel = NSTextField(labelWithString: "")
        subtitleLabel.font = NSFont.systemFont(ofSize: 10)
        subtitleLabel.textColor = Colors.hint
        subtitleLabel.alignment = .center
        subtitleLabel.lineBreakMode = .byWordWrapping
        subtitleLabel.maximumNumberOfLines = 2
        contentContainer.addSubview(subtitleLabel)
        subtitleLabel.snp.makeConstraints { make in
            make.top.equalTo(actionButton.snp.bottom).offset(6)
            make.centerX.equalToSuperview()
            make.leading.greaterThanOrEqualToSuperview()
            make.trailing.lessThanOrEqualToSuperview()
            make.bottom.equalToSuperview()
        }
    }

    private func setupCaptureBar() {
        // 捕获中的悬浮栏（放在边框屏幕区域的顶部）
        captureBarView = NSView()
        captureBarView.wantsLayer = true
        captureBarView.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.7).cgColor
        captureBarView.isHidden = true
        bezelView.screenContentView.addSubview(captureBarView)
        captureBarView.snp.makeConstraints { make in
            make.top.leading.trailing.equalToSuperview()
            make.height.equalTo(28)
        }

        // 状态指示灯
        captureIndicator = NSView()
        captureIndicator.wantsLayer = true
        captureIndicator.layer?.cornerRadius = 3
        captureIndicator.layer?.backgroundColor = NSColor.systemGreen.cgColor
        captureBarView.addSubview(captureIndicator)
        captureIndicator.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(10)
            make.centerY.equalToSuperview()
            make.size.equalTo(6)
        }

        // 捕获状态文本
        captureStatusLabel = NSTextField(labelWithString: L10n.device.capturing)
        captureStatusLabel.font = NSFont.systemFont(ofSize: 10)
        captureStatusLabel.textColor = .white
        captureBarView.addSubview(captureStatusLabel)
        captureStatusLabel.snp.makeConstraints { make in
            make.leading.equalTo(captureIndicator.snp.trailing).offset(5)
            make.centerY.equalToSuperview()
        }

        // 停止按钮
        stopButton = NSButton(title: "", target: self, action: #selector(stopTapped))
        stopButton.image = NSImage(systemSymbolName: "stop.fill", accessibilityDescription: L10n.overlayUI.stop)
        stopButton.bezelStyle = .inline
        stopButton.isBordered = false
        stopButton.contentTintColor = .white
        captureBarView.addSubview(stopButton)
        stopButton.snp.makeConstraints { make in
            make.trailing.equalToSuperview().offset(-10)
            make.centerY.equalToSuperview()
            make.size.equalTo(16)
        }

        // 帧率
        fpsLabel = NSTextField(labelWithString: "")
        fpsLabel.font = NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)
        fpsLabel.textColor = NSColor.white.withAlphaComponent(0.7)
        captureBarView.addSubview(fpsLabel)
        fpsLabel.snp.makeConstraints { make in
            make.trailing.equalTo(stopButton.snp.leading).offset(-10)
            make.centerY.equalToSuperview()
        }

        // 分辨率
        resolutionLabel = NSTextField(labelWithString: "")
        resolutionLabel.font = NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)
        resolutionLabel.textColor = NSColor.white.withAlphaComponent(0.7)
        captureBarView.addSubview(resolutionLabel)
        resolutionLabel.snp.makeConstraints { make in
            make.trailing.equalTo(fpsLabel.snp.leading).offset(-10)
            make.centerY.equalToSuperview()
        }
    }

    // MARK: - 公开方法

    /// 显示断开状态
    func showDisconnected(platform: DevicePlatform, connectionGuide: String) {
        currentState = .disconnected
        currentPlatform = platform

        // 未连接时使用通用边框
        configureBezel(for: platform, deviceName: nil)

        statusContainerView.isHidden = false
        captureBarView.isHidden = true

        iconImageView.image = NSImage(named: platform == .ios ? "IOSIcon" : "AndroidIcon")
        iconImageView.contentTintColor = Colors.icon

        titleLabel.stringValue = platform == .ios ? "iPhone" : "Android"
        titleLabel.textColor = Colors.titleSecondary

        statusIndicator.isHidden = true
        statusLabel.stringValue = ""
        statusStackView.isHidden = true

        actionButton.isHidden = true

        subtitleLabel.stringValue = connectionGuide
        subtitleLabel.textColor = Colors.hint
        subtitleLabel.isHidden = false
    }

    /// 显示已连接状态
    func showConnected(
        deviceName: String,
        platform: DevicePlatform,
        userPrompt: String? = nil,
        onStart: @escaping () -> Void
    ) {
        currentState = .connected
        currentPlatform = platform
        onStartAction = onStart

        // 根据设备名称配置对应的边框
        configureBezel(for: platform, deviceName: deviceName)

        statusContainerView.isHidden = false
        captureBarView.isHidden = true

        iconImageView.image = NSImage(named: platform == .ios ? "IOSIcon" : "AndroidIcon")
        iconImageView.contentTintColor = Colors.iconHighlight

        titleLabel.stringValue = deviceName
        titleLabel.textColor = Colors.title

        statusStackView.isHidden = false
        statusIndicator.isHidden = false

        if let prompt = userPrompt {
            statusIndicator.layer?.backgroundColor = NSColor.systemOrange.cgColor
            statusLabel.stringValue = "⚠️ \(prompt)"
            statusLabel.textColor = .systemOrange
        } else {
            statusIndicator.layer?.backgroundColor = NSColor.systemGreen.cgColor
            statusLabel.stringValue = L10n.overlayUI.deviceDetected
            statusLabel.textColor = Colors.status
        }

        actionButton.title = L10n.overlayUI.startCapture
        actionButton.isEnabled = true
        actionButton.isHidden = false

        subtitleLabel.stringValue = platform == .ios ? L10n.overlayUI.captureIOSHint : L10n.overlayUI.captureAndroidHint
        subtitleLabel.textColor = Colors.hint
        subtitleLabel.isHidden = false
    }

    /// 显示捕获中状态
    func showCapturing(
        deviceName: String,
        platform: DevicePlatform,
        fps: Double,
        resolution: CGSize,
        onStop: @escaping () -> Void
    ) {
        currentState = .capturing
        currentPlatform = platform
        onStopAction = onStop

        // 根据设备名称和实际分辨率配置边框
        configureBezel(for: platform, deviceName: deviceName, aspectRatio: resolution)

        statusContainerView.isHidden = true
        captureBarView.isHidden = false

        captureStatusLabel.stringValue = L10n.device.capturing

        if resolution.width > 0, resolution.height > 0 {
            resolutionLabel.stringValue = "\(Int(resolution.width))×\(Int(resolution.height))"
        } else {
            resolutionLabel.stringValue = ""
        }

        updateFPS(fps)
        addPulseAnimation(to: captureIndicator)
    }

    /// 显示工具链缺失状态
    func showToolchainMissing(toolName: String, onInstall: @escaping () -> Void) {
        currentState = .toolchainMissing
        onInstallAction = onInstall
        onStartAction = onInstall

        // 工具链缺失时使用通用 Android 边框
        configureBezel(for: .android, deviceName: nil)

        statusContainerView.isHidden = false
        captureBarView.isHidden = true

        iconImageView.image = NSImage(systemSymbolName: "exclamationmark.triangle", accessibilityDescription: nil)
        iconImageView.contentTintColor = .systemOrange

        titleLabel.stringValue = L10n.overlayUI.toolNotInstalled(toolName)
        titleLabel.textColor = Colors.title

        statusStackView.isHidden = false
        statusIndicator.isHidden = false
        statusIndicator.layer?.backgroundColor = NSColor.systemOrange.cgColor
        statusLabel.stringValue = L10n.overlayUI.needInstall(toolName)
        statusLabel.textColor = .systemOrange

        actionButton.title = L10n.overlayUI.installTool(toolName)
        actionButton.isEnabled = true
        actionButton.isHidden = false

        subtitleLabel.stringValue = L10n.toolchain.installScrcpyHint
        subtitleLabel.textColor = Colors.hint
        subtitleLabel.isHidden = false
    }

    /// 更新帧率
    func updateFPS(_ fps: Double) {
        guard currentState == .capturing else { return }

        fpsLabel.stringValue = L10n.overlay.fps(Int(fps))

        if fps >= 30 {
            fpsLabel.textColor = NSColor.systemGreen.withAlphaComponent(0.9)
        } else if fps >= 15 {
            fpsLabel.textColor = NSColor.systemOrange.withAlphaComponent(0.9)
        } else {
            fpsLabel.textColor = NSColor.systemRed.withAlphaComponent(0.9)
        }
    }

    /// 获取边框屏幕区域的位置（用于 Metal 渲染）
    var screenFrame: CGRect {
        let bezelScreenFrame = bezelView.screenFrame
        return bezelView.convert(bezelScreenFrame, to: self)
    }

    // MARK: - 私有方法

    private var currentDeviceName: String?

    private func configureBezel(for platform: DevicePlatform, deviceName: String? = nil, aspectRatio: CGSize? = nil) {
        currentDeviceName = deviceName
        if let size = aspectRatio, size.width > 0, size.height > 0 {
            bezelView.configure(deviceName: deviceName, platform: platform, aspectRatio: size.width / size.height)
        } else {
            bezelView.configure(deviceName: deviceName, platform: platform)
        }
    }

    // MARK: - 操作

    @objc private func actionTapped() {
        onStartAction?()
    }

    @objc private func stopTapped() {
        onStopAction?()
    }

    // MARK: - 动画

    private func addPulseAnimation(to view: NSView) {
        view.layer?.removeAnimation(forKey: "pulse")

        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = 1.0
        animation.toValue = 0.4
        animation.duration = 0.8
        animation.autoreverses = true
        animation.repeatCount = .infinity
        view.layer?.add(animation, forKey: "pulse")
    }
}
