//
//  DevicePanelView.swift
//  ScreenPresenter
//
//  Created by Sun on 2025/12/23.
//
//  设备面板视图
//  包含设备边框和状态信息的完整设备展示
//  设备类型通过边框外观区分，不显示设备图标
//

import AppKit
import SnapKit

// MARK: - 带内边距的按钮

/// 支持内边距的自定义按钮
final class PaddedButton: NSButton {
    private let horizontalPadding: CGFloat
    private let verticalPadding: CGFloat

    init(horizontalPadding: CGFloat = 12, verticalPadding: CGFloat = 6) {
        self.horizontalPadding = horizontalPadding
        self.verticalPadding = verticalPadding
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize {
        let baseSize = super.intrinsicContentSize
        return NSSize(
            width: baseSize.width + horizontalPadding * 2,
            height: baseSize.height + verticalPadding * 2
        )
    }
}

// MARK: - 设备面板视图

final class DevicePanelView: NSView {
    // MARK: - UI 组件

    /// 设备边框视图
    private var bezelView: DeviceBezelView!

    /// Metal 渲染视图（显示设备画面，嵌入到 screenContentView 中）
    private(set) var renderView: SingleDeviceRenderView!

    /// 状态内容容器（显示在边框屏幕区域内）
    private var statusContainerView: NSView!

    // 状态 UI 组件（不再使用图标）
    private var loadingIndicator: NSProgressIndicator!
    private var titleLabel: NSTextField!
    private var statusStackView: NSStackView!
    private var statusIndicator: NSView!
    private var statusLabel: NSTextField!
    private var actionButton: PaddedButton!
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
    }

    // MARK: - 状态

    private enum PanelState {
        case loading
        case disconnected
        case connected
        case capturing
        case toolchainMissing
    }

    private var currentState: PanelState = .loading
    private var currentPlatform: DevicePlatform = .ios

    // MARK: - 鼠标追踪

    private var trackingArea: NSTrackingArea?
    private var isMouseInside: Bool = false

    // MARK: - 初始化

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupUI()
        setupTrackingArea()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
        setupTrackingArea()
    }

    deinit {
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
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
            // 填满父视图，bezelView 内部会根据 aspectRatio 自动调整设备尺寸
            make.edges.equalToSuperview()
        }

        // 添加 Metal 渲染视图到 screenContentView（画面会跟随 bezel 动画）
        renderView = SingleDeviceRenderView()
        bezelView.screenContentView.addSubview(renderView)
        renderView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
    }

    private func setupTrackingArea() {
        let options: NSTrackingArea.Options = [.mouseEnteredAndExited, .mouseMoved, .activeInActiveApp, .inVisibleRect]
        trackingArea = NSTrackingArea(rect: .zero, options: options, owner: self, userInfo: nil)
        addTrackingArea(trackingArea!)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let oldTrackingArea = trackingArea {
            removeTrackingArea(oldTrackingArea)
        }

        let options: NSTrackingArea.Options = [.mouseEnteredAndExited, .mouseMoved, .activeInActiveApp, .inVisibleRect]
        trackingArea = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
        addTrackingArea(trackingArea!)
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        checkMouseInCaptureZone(with: event)
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        isMouseInside = false
        updateCaptureBarVisibility()
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        checkMouseInCaptureZone(with: event)
    }

    /// 检查鼠标是否在 captureBar 显示区域内（screenContentView 上方 1/3）
    private func checkMouseInCaptureZone(with event: NSEvent) {
        let locationInView = convert(event.locationInWindow, from: nil)
        let screen = screenFrame

        guard screen.width > 0, screen.height > 0 else {
            isMouseInside = false
            updateCaptureBarVisibility()
            return
        }

        // 计算上方 1/3 区域
        let topThirdHeight = screen.height / 3
        let captureZone = CGRect(
            x: screen.minX,
            y: screen.maxY - topThirdHeight,
            width: screen.width,
            height: topThirdHeight
        )

        let wasInside = isMouseInside
        isMouseInside = captureZone.contains(locationInView)

        // 只在状态改变时更新
        if wasInside != isMouseInside {
            updateCaptureBarVisibility()
        }
    }

    private func updateCaptureBarVisibility() {
        guard currentState == .capturing else {
            captureBarView.isHidden = true
            return
        }

        if isMouseInside {
            // 显示前先更新位置
            updateCaptureBarPosition()
            captureBarView.isHidden = false
            captureBarView.alphaValue = 0

            // 淡入动画
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                captureBarView.animator().alphaValue = 1.0
            }
        } else {
            // 淡出动画
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                captureBarView.animator().alphaValue = 0.0
            } completionHandler: { [weak self] in
                guard let self, !self.isMouseInside else { return }
                captureBarView.isHidden = true
            }
        }
    }

    private func setupStatusContent() {
        // 状态内容容器（覆盖整个屏幕区域，带有暗色背景）
        statusContainerView = NSView()
        statusContainerView.wantsLayer = true
        statusContainerView.layer?.backgroundColor = NSColor(white: 0.05, alpha: 1.0).cgColor
        bezelView.screenContentView.addSubview(statusContainerView)
        statusContainerView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }

        // 内容居中容器
        let contentContainer = NSView()
        statusContainerView.addSubview(contentContainer)
        contentContainer.snp.makeConstraints { make in
            // 降低所有约束优先级，避免父视图宽度为 0 时产生冲突
            make.center.equalToSuperview().priority(.high)
            make.leading.greaterThanOrEqualToSuperview().offset(16).priority(.high)
            make.trailing.lessThanOrEqualToSuperview().offset(-16).priority(.high)
        }

        // 加载指示器（菊花）
        loadingIndicator = NSProgressIndicator()
        loadingIndicator.style = .spinning
        loadingIndicator.controlSize = .regular
        loadingIndicator.isIndeterminate = true
        loadingIndicator.isHidden = true
        contentContainer.addSubview(loadingIndicator)
        loadingIndicator.snp.makeConstraints { make in
            make.top.equalToSuperview()
            make.centerX.equalToSuperview()
            make.size.equalTo(32)
        }

        // 标题（设备名称或提示文案）
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

        // 状态栏
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
        statusLabel.font = NSFont.systemFont(ofSize: 18)
        statusLabel.textColor = Colors.status
        statusStackView.addArrangedSubview(statusLabel)

        // 操作按钮（使用自定义视图实现内边距）
        actionButton = PaddedButton(
            horizontalPadding: 20,
            verticalPadding: 12
        )
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

        // 副标题/提示
        subtitleLabel = NSTextField(labelWithString: "")
        subtitleLabel.font = NSFont.systemFont(ofSize: 16)
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
            make.bottom.equalToSuperview()
        }
    }

    private func setupCaptureBar() {
        // 捕获中的悬浮栏（放在 bezelView 上层，不遮挡 screenContentView）
        captureBarView = NSView()
        captureBarView.wantsLayer = true
        captureBarView.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.7).cgColor
        captureBarView.layer?.cornerRadius = 8
        captureBarView.isHidden = true
        addSubview(captureBarView)
        // 约束会在 layout() 中根据 screenFrame 动态更新

        // 状态指示灯
        captureIndicator = NSView()
        captureIndicator.wantsLayer = true
        captureIndicator.layer?.cornerRadius = 4
        captureIndicator.layer?.backgroundColor = NSColor.systemGreen.cgColor
        captureBarView.addSubview(captureIndicator)
        captureIndicator.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(10)
            make.centerY.equalToSuperview()
            make.size.equalTo(8)
        }

        // 捕获状态文本
        captureStatusLabel = NSTextField(labelWithString: L10n.device.capturing)
        captureStatusLabel.font = NSFont.systemFont(ofSize: 10)
        captureStatusLabel.textColor = .white
        captureBarView.addSubview(captureStatusLabel)
        captureStatusLabel.snp.makeConstraints { make in
            make.leading.equalTo(captureIndicator.snp.trailing).offset(6)
            make.centerY.equalToSuperview()
        }

        // 停止按钮
        stopButton = NSButton(title: "", target: self, action: #selector(stopTapped))
        stopButton.image = NSImage(systemSymbolName: "stop.fill", accessibilityDescription: L10n.overlayUI.stop)
        stopButton.bezelStyle = .inline
        stopButton.isBordered = false
        stopButton.contentTintColor = .appDanger
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

        // 隐藏渲染视图，显示状态容器
        renderView.isHidden = true
        statusContainerView.isHidden = false
        captureBarView.isHidden = true

        // 隐藏加载指示器
        loadingIndicator.stopAnimation(nil)
        loadingIndicator.isHidden = true

        // 通过文案区分设备类型（边框已经展示了设备外观）
        titleLabel.stringValue = platform == .ios ? L10n.overlayUI.waitingForIPhone : L10n.overlayUI.waitingForAndroid
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

        // 隐藏渲染视图，显示状态容器
        renderView.isHidden = true
        statusContainerView.isHidden = false
        captureBarView.isHidden = true

        // 隐藏加载指示器
        loadingIndicator.stopAnimation(nil)
        loadingIndicator.isHidden = true

        // 显示设备名称
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

        setActionButtonTitle(L10n.overlayUI.startCapture)
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

        // 显示渲染视图，隐藏状态容器
        renderView.isHidden = false
        statusContainerView.isHidden = true

        // 停止加载指示器（虽然 statusContainerView 已隐藏）
        loadingIndicator.stopAnimation(nil)

        // 初始隐藏 captureBarView，只有鼠标悬停时才显示
        captureBarView.isHidden = !isMouseInside
        captureBarView.alphaValue = isMouseInside ? 1.0 : 0.0

        // 更新捕获栏位置
        needsLayout = true
        layoutSubtreeIfNeeded()
        updateCaptureBarPosition()

        captureStatusLabel.stringValue = L10n.device.capturing

        if resolution.width > 0, resolution.height > 0 {
            resolutionLabel.stringValue = "\(Int(resolution.width))×\(Int(resolution.height))"
        } else {
            resolutionLabel.stringValue = ""
        }

        updateFPS(fps)
        addPulseAnimation(to: captureIndicator)
    }

    /// 显示加载状态
    func showLoading(platform: DevicePlatform) {
        currentState = .loading
        currentPlatform = platform

        // 配置边框外观
        configureBezel(for: platform, deviceName: nil)

        // 隐藏渲染视图，显示状态容器
        renderView.isHidden = true
        statusContainerView.isHidden = false
        captureBarView.isHidden = true

        // 显示加载指示器
        loadingIndicator.isHidden = false
        loadingIndicator.startAnimation(nil)

        // 显示加载提示
        titleLabel.stringValue = L10n.common.loading
        titleLabel.textColor = Colors.titleSecondary

        // 隐藏状态栏和按钮
        statusStackView.isHidden = true
        actionButton.isHidden = true
        subtitleLabel.isHidden = true
    }

    /// 显示工具链缺失状态
    func showToolchainMissing(toolName: String, onInstall: @escaping () -> Void) {
        currentState = .toolchainMissing
        onInstallAction = onInstall
        onStartAction = onInstall

        // 工具链缺失时使用通用 Android 边框
        configureBezel(for: .android, deviceName: nil)

        // 隐藏渲染视图，显示状态容器
        renderView.isHidden = true
        statusContainerView.isHidden = false
        captureBarView.isHidden = true

        // 隐藏加载指示器
        loadingIndicator.stopAnimation(nil)
        loadingIndicator.isHidden = true

        // 通过文案说明工具链缺失（不使用图标）
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

        subtitleLabel.stringValue = L10n.toolchain.installScrcpyHint
        subtitleLabel.textColor = Colors.hint
        subtitleLabel.isHidden = false
    }

    // MARK: - 会话中断状态

    /// 显示会话中断提示（设备锁屏等）
    func showSessionInterrupted(reason: String) {
        // 在捕获栏上显示中断提示
        captureStatusLabel.stringValue = "⚠️ \(reason)"
        captureStatusLabel.textColor = .systemOrange

        // 显示捕获栏
        captureBarView.isHidden = false
        captureBarView.alphaValue = 1.0

        // 停止脉冲动画
        captureIndicator.layer?.removeAllAnimations()
        captureIndicator.layer?.backgroundColor = NSColor.systemOrange.cgColor

        AppLogger.capture.warning("会话中断显示: \(reason)")
    }

    /// 隐藏会话中断提示
    func hideSessionInterrupted() {
        // 恢复正常状态
        captureStatusLabel.stringValue = L10n.device.capturing
        captureStatusLabel.textColor = .white

        // 恢复捕获指示器
        captureIndicator.layer?.backgroundColor = NSColor.systemGreen.cgColor
        addPulseAnimation(to: captureIndicator)

        // 恢复捕获栏的悬停行为
        if !isMouseInside {
            captureBarView.isHidden = true
            captureBarView.alphaValue = 0.0
        }

        AppLogger.capture.info("会话中断恢复")
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

    /// 获取设备的宽高比（宽度/高度）
    /// 返回值保证 > 0，避免布局约束问题
    var deviceAspectRatio: CGFloat {
        let ratio = bezelView.aspectRatio
        // 确保返回有效的宽高比，避免除零或无效约束
        return ratio > 0.1 ? ratio : 0.46 // 默认使用 iPhone 的宽高比
    }

    /// 获取屏幕圆角半径（用于 Metal 渲染遮罩）
    var screenCornerRadius: CGFloat {
        bezelView.screenCornerRadius
    }

    /// 获取顶部特征（刘海/灵动岛/摄像头开孔）的底部距离
    var topFeatureBottomInset: CGFloat {
        bezelView.topFeatureBottomInset
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

    /// 设置按钮白色文本标题
    private func setActionButtonTitle(_ title: String) {
        let buttonFont = NSFont.systemFont(ofSize: 16, weight: .medium)
        let attributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor.white,
            .font: buttonFont,
        ]
        actionButton.attributedTitle = NSAttributedString(string: title, attributes: attributes)
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

    // MARK: - 布局

    override func layout() {
        super.layout()
        updateCaptureBarPosition()
    }

    /// 更新捕获栏位置（跟随屏幕区域，考虑刘海/灵动岛/摄像头开孔）
    private func updateCaptureBarPosition() {
        let screen = screenFrame
        guard screen.width > 0, screen.height > 0 else { return }

        let barHeight: CGFloat = 28
        let horizontalInset: CGFloat = 20

        // 计算顶部偏移：存在顶部特征， y 从顶部底部开始
        // 如果没有顶部特征（topFeatureBottomInset < 1），则从屏幕顶部下移 12pt
        let topOffset: CGFloat = if topFeatureBottomInset < 1 {
            12
        } else {
            topFeatureBottomInset
        }

        captureBarView.frame = CGRect(
            x: screen.minX + horizontalInset,
            y: screen.maxY - barHeight - topOffset,
            width: screen.width - horizontalInset * 2,
            height: barHeight
        )
    }

    // MARK: - 语言变更

    /// 更新本地化文本（语言切换时调用）
    func updateLocalizedTexts() {
        // 更新停止按钮的 accessibilityDescription
        stopButton.image = NSImage(systemSymbolName: "stop.fill", accessibilityDescription: L10n.overlayUI.stop)

        // 根据当前状态更新文本
        switch currentState {
        case .loading:
            titleLabel.stringValue = L10n.common.loading

        case .disconnected:
            titleLabel.stringValue = currentPlatform == .ios
                ? L10n.overlayUI.waitingForIPhone
                : L10n.overlayUI.waitingForAndroid
            subtitleLabel.stringValue = currentPlatform == .ios
                ? L10n.overlayUI.connectIOS
                : L10n.overlayUI.connectAndroid

        case .connected:
            // 设备名称不需要本地化，只更新状态和按钮文本
            if statusLabel.stringValue.hasPrefix("⚠️") == false {
                statusLabel.stringValue = L10n.overlayUI.deviceDetected
            }
            setActionButtonTitle(L10n.overlayUI.startCapture)
            subtitleLabel.stringValue = currentPlatform == .ios
                ? L10n.overlayUI.captureIOSHint
                : L10n.overlayUI.captureAndroidHint

        case .capturing:
            if captureStatusLabel.stringValue.hasPrefix("⚠️") == false {
                captureStatusLabel.stringValue = L10n.device.capturing
            }

        case .toolchainMissing:
            let toolName = "scrcpy"
            titleLabel.stringValue = L10n.overlayUI.toolNotInstalled(toolName)
            statusLabel.stringValue = L10n.overlayUI.needInstall(toolName)
            setActionButtonTitle(L10n.overlayUI.installTool(toolName))
            subtitleLabel.stringValue = L10n.toolchain.installScrcpyHint
        }
    }
}
