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
    /// 操作按钮加载指示器
    private var actionLoadingIndicator: NSProgressIndicator!

    /// 刷新按钮
    private var refreshButton: PaddedButton!
    /// 刷新加载指示器
    private var refreshLoadingIndicator: NSProgressIndicator!

    // 捕获中的悬浮栏
    private var captureBarView: NSView!
    private var captureIndicator: NSView!
    private var captureDeviceNameLabel: NSTextField! // 设备名称
    private var captureDeviceInfoLabel: NSTextField! // 型号 · 系统版本
    private var resolutionLabel: NSTextField!
    private var fpsLabel: NSTextField!
    private var stopButton: NSButton!

    /// 当前设备系统版本（用于 captureBar 显示）
    private var currentDeviceSystemVersion: String?

    // MARK: - 回调

    private var onStartAction: (() -> Void)?
    private var onStopAction: (() -> Void)?
    private var onInstallAction: (() -> Void)?
    private var onRefreshAction: ((@escaping () -> Void) -> Void)?

    /// 当前设备状态提示（用于 Toast 显示）
    private var currentUserPrompt: String?

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

    // MARK: - FPS 更新定时器

    private var fpsUpdateTimer: Timer?

    // MARK: - Bezel 可见性

    /// 是否显示设备边框
    private(set) var showBezel: Bool = true

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

    /// 检查鼠标是否在 captureBar 显示区域内（渲染区域上方 1/3）
    private func checkMouseInCaptureZone(with event: NSEvent) {
        let locationInView = convert(event.locationInWindow, from: nil)
        // 使用实际渲染区域来判断
        let renderRect = actualRenderRect

        guard renderRect.width > 0, renderRect.height > 0 else {
            isMouseInside = false
            updateCaptureBarVisibility()
            return
        }

        // 计算上方 1/3 区域
        let topThirdHeight = renderRect.height / 3
        let captureZone = CGRect(
            x: renderRect.minX,
            y: renderRect.maxY - topThirdHeight,
            width: renderRect.width,
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
        // 强制使用 darkAqua 外观，确保在深色背景下菊花图标可见（白色）
        loadingIndicator.appearance = NSAppearance(named: .darkAqua)
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
        statusLabel.font = NSFont.systemFont(ofSize: 16)
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

        // 操作按钮加载指示器（菊花）
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

        // 副标题/提示
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

        // 刷新按钮
        refreshButton = PaddedButton(
            horizontalPadding: 8,
            verticalPadding: 4
        )
        refreshButton.wantsLayer = true
        refreshButton.isBordered = false
        refreshButton.layer?.cornerRadius = 6
        refreshButton.layer?.backgroundColor = Colors.actionSecondary.withAlphaComponent(0.2).cgColor
        refreshButton.focusRingType = .none
        refreshButton.refusesFirstResponder = true
        refreshButton.target = self
        refreshButton.action = #selector(refreshTapped)
        let buttonFont = NSFont.systemFont(ofSize: 12, weight: .regular)
        let attributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: Colors.actionSecondary,
            .font: buttonFont,
        ]
        refreshButton.attributedTitle = NSAttributedString(
            string: L10n.common.refresh,
            attributes: attributes
        )
        contentContainer.addSubview(refreshButton)
        refreshButton.snp.makeConstraints { make in
            make.top.equalTo(subtitleLabel.snp.bottom).offset(12)
            make.centerX.equalToSuperview()
            make.bottom.equalToSuperview()
        }

        // 刷新加载指示器（菊花）
        refreshLoadingIndicator = NSProgressIndicator()
        refreshLoadingIndicator.style = .spinning
        refreshLoadingIndicator.controlSize = .small
        refreshLoadingIndicator.isIndeterminate = true
        refreshLoadingIndicator.isHidden = true
        // 强制使用 darkAqua 外观，确保在深色背景下菊花图标可见（白色）
        refreshLoadingIndicator.appearance = NSAppearance(named: .darkAqua)
        refreshButton.addSubview(refreshLoadingIndicator)
        refreshLoadingIndicator.snp.makeConstraints { make in
            make.center.equalToSuperview()
        }

        // 状态栏点击手势（用于显示 Toast 提示）
        let tapGesture = NSClickGestureRecognizer(target: self, action: #selector(statusTapped))
        statusStackView.addGestureRecognizer(tapGesture)
    }

    private func setupCaptureBar() {
        // 捕获中的悬浮栏（放在 bezelView 上层，不遮挡 screenContentView）
        captureBarView = NSView(frame: CGRect(x: 0, y: 0, width: 300, height: 44)) // 初始 frame，避免约束冲突
        captureBarView.wantsLayer = true
        captureBarView.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.75).cgColor
        captureBarView.layer?.cornerRadius = 8
        // 添加细边框（在深色背景下可见）
        captureBarView.layer?.borderWidth = 0.5
        captureBarView.layer?.borderColor = NSColor.white.withAlphaComponent(0.2).cgColor
        // 添加阴影（在浅色背景下可见）
        captureBarView.shadow = NSShadow()
        captureBarView.layer?.shadowColor = NSColor.black.cgColor
        captureBarView.layer?.shadowOpacity = 0.5
        captureBarView.layer?.shadowOffset = CGSize(width: 0, height: -2)
        captureBarView.layer?.shadowRadius = 8
        captureBarView.isHidden = true
        addSubview(captureBarView)
        // frame 会在 layout() 中根据 screenFrame 动态更新

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

        // 设备名称（第一行）
        captureDeviceNameLabel = NSTextField(labelWithString: "")
        captureDeviceNameLabel.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        captureDeviceNameLabel.textColor = .white
        captureDeviceNameLabel.lineBreakMode = .byTruncatingTail
        captureDeviceNameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        // 设备详细信息（第二行：型号 · 系统版本）
        captureDeviceInfoLabel = NSTextField(labelWithString: "")
        captureDeviceInfoLabel.font = NSFont.systemFont(ofSize: 10)
        captureDeviceInfoLabel.textColor = NSColor.white.withAlphaComponent(0.7)
        captureDeviceInfoLabel.lineBreakMode = .byTruncatingTail
        captureDeviceInfoLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        // 使用 StackView 将两个 label 作为整体垂直居中
        let deviceInfoStack = NSStackView(views: [captureDeviceNameLabel, captureDeviceInfoLabel])
        deviceInfoStack.orientation = .vertical
        deviceInfoStack.alignment = .leading
        deviceInfoStack.spacing = 2
        captureBarView.addSubview(deviceInfoStack)
        deviceInfoStack.snp.makeConstraints { make in
            make.leading.equalTo(captureIndicator.snp.trailing).offset(6)
            make.centerY.equalToSuperview()
            make.trailing.lessThanOrEqualToSuperview().offset(-100).priority(.high) // 留空间给右侧信息
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
        stopFPSUpdateTimer()

        // 未连接时使用通用边框
        configureBezel(for: platform, deviceName: nil)

        // 隐藏渲染视图，显示状态容器
        renderView.isHidden = true
        statusContainerView.isHidden = false
        captureBarView.isHidden = true

        // 隐藏加载指示器
        loadingIndicator.stopAnimation(nil)
        loadingIndicator.isHidden = true

        // 隐藏刷新按钮
        refreshButton.isHidden = true
        currentUserPrompt = nil

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
    /// - Parameters:
    ///   - deviceName: 设备名称
    ///   - platform: 设备平台
    ///   - modelName: 设备型号名称（如 "iPhone 15 Pro"）
    ///   - systemVersion: 系统版本（如 "18.2"）
    ///   - buildVersion: 系统 build 版本（如 "22C5125e"）
    ///   - userPrompt: 用户提示信息（如需要信任、解锁等）
    ///   - deviceState: 设备状态
    ///   - onStart: 开始捕获回调
    ///   - onRefresh: 刷新设备信息回调
    func showConnected(
        device: IOSDevice,
        onStart: @escaping () -> Void,
        onRefresh: ((@escaping () -> Void) -> Void)? = nil
    ) {
        showConnected(
            deviceName: device.displayName,
            platform: .ios,
            modelName: device.displayModelName,
            systemVersion: device.productVersion,
            buildVersion: device.buildVersion,
            userPrompt: device.userPrompt,
            deviceState: device.state,
            iosDevice: device,
            onStart: onStart,
            onRefresh: onRefresh
        )
    }

    /// 显示已连接状态（通用方式）
    /// - Parameters:
    ///   - deviceName: 设备名称
    ///   - platform: 设备平台
    ///   - modelName: 设备型号名称
    ///   - systemVersion: 系统版本
    ///   - buildVersion: build 版本
    ///   - userPrompt: 用户提示信息（如需要信任、解锁等）
    ///   - deviceState: 设备状态
    ///   - iosDevice: iOS 设备实例（用于精确识别设备型号）
    ///   - onStart: 开始捕获回调
    ///   - onRefresh: 刷新设备信息回调
    func showConnected(
        deviceName: String,
        platform: DevicePlatform,
        modelName: String? = nil,
        systemVersion: String? = nil,
        buildVersion: String? = nil,
        userPrompt: String? = nil,
        deviceState: IOSDevice.State? = nil,
        iosDevice: IOSDevice? = nil,
        onStart: @escaping () -> Void,
        onRefresh: ((@escaping () -> Void) -> Void)? = nil
    ) {
        currentState = .connected
        currentPlatform = platform
        onStartAction = onStart
        onRefreshAction = onRefresh
        currentUserPrompt = userPrompt
        stopFPSUpdateTimer()

        // 配置边框：优先使用 IOSDevice 的 productType 精确识别
        if let device = iosDevice {
            configureBezel(for: device)
        } else {
            configureBezel(for: platform, deviceName: deviceName)
        }

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
            // 根据设备状态选择颜色
            let statusColor: NSColor = if let state = deviceState {
                IOSDeviceStateMapper.statusColor(for: state)
            } else {
                .systemOrange
            }

            statusIndicator.layer?.backgroundColor = statusColor.cgColor
            statusLabel.stringValue = "⚠️ \(prompt)"
            statusLabel.textColor = statusColor
        } else {
            statusIndicator.layer?.backgroundColor = NSColor.systemGreen.cgColor
            statusLabel.stringValue = L10n.overlayUI.deviceDetected
            statusLabel.textColor = Colors.status
        }

        setActionButtonTitle(L10n.overlayUI.startCapture)
        actionButton.isEnabled = true
        actionButton.isHidden = false

        // 显示刷新按钮（仅当提供了 onRefresh 回调时）
        refreshButton.isHidden = onRefresh == nil
        // 确保加载状态重置
        stopRefreshLoading()

        // 构建设备详细信息文本
        let detailInfo = buildDeviceDetailInfo(
            platform: platform,
            modelName: modelName,
            systemVersion: systemVersion,
            buildVersion: buildVersion
        )
        subtitleLabel.stringValue = detailInfo
        subtitleLabel.textColor = Colors.hint
        subtitleLabel.isHidden = false
    }

    /// 构建设备详细信息文本
    private func buildDeviceDetailInfo(
        platform: DevicePlatform,
        modelName: String?,
        systemVersion: String?,
        buildVersion: String?
    ) -> String {
        var parts: [String] = []

        // 型号名称（如 iPhone 15 Pro 或 M2007J17C）
        if let model = modelName, !model.isEmpty {
            parts.append(model)
        }

        // 系统版本
        if let version = systemVersion, !version.isEmpty {
            if platform == .ios {
                // iOS 版本格式：iOS 17.0 (21A5248v)
                if let build = buildVersion, !build.isEmpty {
                    parts.append("iOS \(version) (\(build))")
                } else {
                    parts.append("iOS \(version)")
                }
            } else {
                // Android 版本格式：Android 12
                parts.append(version)
            }
        }

        if parts.isEmpty {
            // 如果没有任何信息，返回默认提示
            return platform == .ios
                ? L10n.overlayUI.captureIOSHint
                : L10n.overlayUI.captureAndroidHint
        }

        return parts.joined(separator: " · ")
    }

    /// 显示 iOS 设备捕获中状态（推荐方式，使用 productType 精确识别）
    func showCapturing(
        device: IOSDevice,
        fps: Double,
        resolution: CGSize,
        onStop: @escaping () -> Void
    ) {
        // 停止加载状态
        stopActionLoading()

        currentState = .capturing
        currentPlatform = .ios
        onStopAction = onStop

        // 保存设备信息用于更新状态栏
        currentDeviceDisplayName = device.displayName
        currentDeviceModelName = device.displayModelName
        // iOS 系统版本格式：iOS 17.0
        if let version = device.productVersion {
            currentDeviceSystemVersion = "iOS \(version)"
        } else {
            currentDeviceSystemVersion = nil
        }

        // 使用 IOSDevice 的 productType 精确配置边框
        configureBezel(for: device, aspectRatio: resolution)

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

        // 更新捕获状态文本：显示设备型号和名称
        updateCaptureStatusText()

        if resolution.width > 0, resolution.height > 0 {
            resolutionLabel.stringValue = "\(Int(resolution.width))×\(Int(resolution.height))"
        } else {
            resolutionLabel.stringValue = ""
        }

        updateFPS(fps)
        addPulseAnimation(to: captureIndicator)

        // 启动 FPS 更新定时器
        startFPSUpdateTimer()
    }

    /// 显示捕获中状态（通用方式，通过设备名称识别）
    func showCapturing(
        deviceName: String,
        modelName: String?,
        systemVersion: String? = nil,
        platform: DevicePlatform,
        fps: Double,
        resolution: CGSize,
        onStop: @escaping () -> Void
    ) {
        // 停止加载状态
        stopActionLoading()

        currentState = .capturing
        currentPlatform = platform
        onStopAction = onStop

        // 保存设备信息用于更新状态栏
        currentDeviceDisplayName = deviceName
        currentDeviceModelName = modelName
        currentDeviceSystemVersion = systemVersion

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

        // 更新捕获状态文本：显示设备型号和名称
        updateCaptureStatusText()

        if resolution.width > 0, resolution.height > 0 {
            resolutionLabel.stringValue = "\(Int(resolution.width))×\(Int(resolution.height))"
        } else {
            resolutionLabel.stringValue = ""
        }

        updateFPS(fps)
        addPulseAnimation(to: captureIndicator)

        // 启动 FPS 更新定时器
        startFPSUpdateTimer()
    }

    /// 显示加载状态
    func showLoading(platform: DevicePlatform) {
        currentState = .loading
        currentPlatform = platform
        stopFPSUpdateTimer()

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
        refreshButton.isHidden = true
        currentUserPrompt = nil
    }

    /// 显示工具链缺失状态
    func showToolchainMissing(toolName: String, onInstall: @escaping () -> Void) {
        currentState = .toolchainMissing
        onInstallAction = onInstall
        onStartAction = onInstall
        stopFPSUpdateTimer()

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

        // 隐藏刷新按钮
        refreshButton.isHidden = true
        currentUserPrompt = nil
    }

    // MARK: - 按钮控制

    /// 设置操作按钮的启用状态
    func setActionButtonEnabled(_ enabled: Bool) {
        actionButton.isEnabled = enabled
        actionButton.alphaValue = enabled ? 1.0 : 0.7
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
        if showBezel {
            let bezelScreenFrame = bezelView.screenFrame
            return bezelView.convert(bezelScreenFrame, to: self)
        } else {
            // 隐藏 bezel 时，返回整个面板的边界
            return bounds
        }
    }

    /// 获取设备的宽高比（宽度/高度）
    /// 返回值保证 > 0，避免布局约束问题
    var deviceAspectRatio: CGFloat {
        if showBezel {
            let ratio = bezelView.aspectRatio
            // 确保返回有效的宽高比，避免除零或无效约束
            return ratio > 0.1 ? ratio : 0.46 // 默认使用 iPhone 的宽高比
        } else {
            // 隐藏 bezel 时，使用屏幕内容的宽高比
            let ratio = bezelView.screenAspectRatio
            return ratio > 0.1 ? ratio : 0.46
        }
    }

    /// 获取屏幕圆角半径（用于 Metal 渲染遮罩）
    var screenCornerRadius: CGFloat {
        showBezel ? bezelView.screenCornerRadius : 0
    }

    /// 获取顶部特征（刘海/灵动岛/摄像头开孔）的底部距离
    var topFeatureBottomInset: CGFloat {
        showBezel ? bezelView.topFeatureBottomInset : 0
    }

    /// 设置 bezel 可见性
    /// - Parameter visible: 是否显示 bezel
    func setBezelVisible(_ visible: Bool) {
        guard showBezel != visible else { return }
        showBezel = visible
        updateBezelVisibility()
    }

    /// 更新 bezel 可见性（重新布局视图）
    private func updateBezelVisibility() {
        if showBezel {
            // 显示 bezel：将 renderView 和 statusContainerView 移回 bezelView.screenContentView
            bezelView.isHidden = false

            renderView.removeFromSuperview()
            bezelView.screenContentView.addSubview(renderView)
            renderView.snp.remakeConstraints { make in
                make.edges.equalToSuperview()
            }

            statusContainerView.removeFromSuperview()
            bezelView.screenContentView.addSubview(statusContainerView)
            statusContainerView.snp.remakeConstraints { make in
                make.edges.equalToSuperview()
            }
        } else {
            // 隐藏 bezel：将 renderView 和 statusContainerView 移到 self 中
            bezelView.isHidden = true

            renderView.removeFromSuperview()
            addSubview(renderView)
            renderView.snp.remakeConstraints { make in
                make.edges.equalToSuperview()
            }

            statusContainerView.removeFromSuperview()
            addSubview(statusContainerView)
            statusContainerView.snp.remakeConstraints { make in
                make.edges.equalToSuperview()
            }
        }

        // 确保 captureBarView 在最上层
        captureBarView.removeFromSuperview()
        addSubview(captureBarView)

        // 强制重新布局
        needsLayout = true
        layoutSubtreeIfNeeded()
    }

    // MARK: - 私有方法

    private var currentDeviceName: String?
    private var currentDeviceDisplayName: String?
    private var currentDeviceModelName: String?

    /// 更新捕获状态文本（显示设备名称、型号、系统版本）
    private func updateCaptureStatusText() {
        // 第一行：设备名称
        if let displayName = currentDeviceDisplayName, !displayName.isEmpty {
            captureDeviceNameLabel.stringValue = displayName
        } else {
            captureDeviceNameLabel.stringValue = L10n.device.capturing
        }

        // 第二行：型号 · 系统版本
        var infoParts: [String] = []
        if let modelName = currentDeviceModelName, !modelName.isEmpty, modelName != currentDeviceDisplayName {
            infoParts.append(modelName)
        }
        if let systemVersion = currentDeviceSystemVersion, !systemVersion.isEmpty {
            infoParts.append(systemVersion)
        }
        captureDeviceInfoLabel.stringValue = infoParts.joined(separator: " · ")
        captureDeviceInfoLabel.isHidden = infoParts.isEmpty
    }

    private func configureBezel(for platform: DevicePlatform, deviceName: String? = nil, aspectRatio: CGSize? = nil) {
        currentDeviceName = deviceName
        if let size = aspectRatio, size.width > 0, size.height > 0 {
            bezelView.configure(deviceName: deviceName, platform: platform, aspectRatio: size.width / size.height)
        } else {
            bezelView.configure(deviceName: deviceName, platform: platform)
        }
    }

    /// 配置 iOS 设备的边框（使用 productType 精确识别）
    private func configureBezel(for device: IOSDevice, aspectRatio: CGSize? = nil) {
        currentDeviceName = device.displayName
        if let size = aspectRatio, size.width > 0, size.height > 0 {
            bezelView.configure(device: device, aspectRatio: size.width / size.height)
        } else {
            bezelView.configure(device: device)
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
        // 显示加载状态
        startActionLoading()
        onStartAction?()
    }

    @objc private func stopTapped() {
        onStopAction?()
    }

    @objc private func refreshTapped() {
        // 显示加载状态
        startRefreshLoading()

        // 调用刷新回调，传入完成回调
        onRefreshAction? { [weak self] in
            DispatchQueue.main.async {
                self?.stopRefreshLoading()
            }
        }
    }

    /// 开始刷新加载状态
    private func startRefreshLoading() {
        refreshButton.isEnabled = false
        refreshLoadingIndicator.isHidden = false
        refreshLoadingIndicator.startAnimation(nil)
    }

    /// 停止刷新加载状态
    private func stopRefreshLoading() {
        refreshButton.isEnabled = true
        refreshLoadingIndicator.stopAnimation(nil)
        refreshLoadingIndicator.isHidden = true
    }

    /// 开始操作按钮加载状态
    func startActionLoading() {
        actionButton.isEnabled = false
        actionButton.alphaValue = 0.7
        // 隐藏按钮文字，显示菊花
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
        // 恢复按钮文字
        setActionButtonTitle(L10n.overlayUI.startCapture)
    }

    @objc private func statusTapped() {
        // 如果有提示信息，显示 Toast
        guard let prompt = currentUserPrompt, !prompt.isEmpty else { return }
        ToastView.warning(prompt, in: window)
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

    // MARK: - FPS 更新定时器

    private func startFPSUpdateTimer() {
        stopFPSUpdateTimer()
        fpsUpdateTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self else { return }
            updateFPS(renderView.fps)
        }
    }

    private func stopFPSUpdateTimer() {
        fpsUpdateTimer?.invalidate()
        fpsUpdateTimer = nil
    }

    // MARK: - 布局

    override func layout() {
        super.layout()
        updateCaptureBarPosition()
    }

    /// 更新捕获栏位置（跟随渲染区域，考虑刘海/灵动岛/摄像头开孔）
    private func updateCaptureBarPosition() {
        // 获取实际渲染区域（保持视频宽高比）
        let renderRect = actualRenderRect
        guard renderRect.width > 0, renderRect.height > 0 else { return }

        // 高度：如果有第二行信息则增加高度
        let hasSecondLine = !(captureDeviceInfoLabel.stringValue.isEmpty)
        let barHeight: CGFloat = hasSecondLine ? 44 : 28
        let horizontalInset: CGFloat = 20

        // 计算顶部偏移：存在顶部特征，y 从特征底部 + 12 开始
        // 如果没有顶部特征（topFeatureBottomInset == 0），则从屏幕顶部下移 12pt
        let topOffset: CGFloat = max(topFeatureBottomInset, 0) + 12

        captureBarView.frame = CGRect(
            x: renderRect.minX + horizontalInset,
            y: renderRect.maxY - barHeight - topOffset,
            width: renderRect.width - horizontalInset * 2,
            height: barHeight
        )
    }

    /// 获取实际渲染区域（保持视频宽高比居中显示）
    private var actualRenderRect: CGRect {
        if showBezel {
            // 显示 bezel 时，渲染区域就是 screenFrame
            return screenFrame
        } else {
            // 隐藏 bezel 时，需要计算保持视频宽高比的实际渲染区域
            let containerRect = bounds
            guard containerRect.width > 0, containerRect.height > 0 else { return .zero }

            // 获取视频宽高比（使用 bezelView 的 screenAspectRatio）
            let videoAspect = bezelView.screenAspectRatio
            guard videoAspect > 0 else { return containerRect }

            let containerAspect = containerRect.width / containerRect.height

            var renderWidth: CGFloat
            var renderHeight: CGFloat

            if videoAspect > containerAspect {
                // 视频更宽，以宽度为基准
                renderWidth = containerRect.width
                renderHeight = renderWidth / videoAspect
            } else {
                // 视频更高，以高度为基准
                renderHeight = containerRect.height
                renderWidth = renderHeight * videoAspect
            }

            // 居中
            let x = (containerRect.width - renderWidth) / 2
            let y = (containerRect.height - renderHeight) / 2

            return CGRect(x: x, y: y, width: renderWidth, height: renderHeight)
        }
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
            // 捕获中显示设备信息，不需要本地化更新
            break

        case .toolchainMissing:
            let toolName = "scrcpy"
            titleLabel.stringValue = L10n.overlayUI.toolNotInstalled(toolName)
            statusLabel.stringValue = L10n.overlayUI.needInstall(toolName)
            setActionButtonTitle(L10n.overlayUI.installTool(toolName))
            subtitleLabel.stringValue = L10n.toolchain.installScrcpyHint
        }
    }
}
