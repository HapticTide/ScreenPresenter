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
    private let bezelView = DeviceBezelView()

    /// Metal 渲染视图（显示设备画面，嵌入到 screenContentView 中）
    private(set) var renderView = SingleDeviceRenderView()

    /// 状态视图（显示在边框屏幕区域内）
    private let statusView = DeviceStatusView()

    /// 捕获中的信息视图
    private let captureInfoView = DeviceCaptureInfoView()

    /// 当前设备系统版本（用于 captureInfoView 显示）
    private var currentDeviceSystemVersion: String?

    // MARK: - 回调

    private var onStartAction: (() -> Void)?
    private var onStopAction: (() -> Void)?
    private var onInstallAction: (() -> Void)?
    private var onRefreshAction: ((@escaping () -> Void) -> Void)?

    /// 当前设备状态提示（用于 Toast 显示）
    private var currentUserPrompt: String?

    // MARK: - 状态

    private enum PanelState {
        case loading
        case disconnected
        case connected
        case capturing
        case toolchainMissing
    }

    private var currentState: PanelState = .loading {
        didSet {
            if currentState != .capturing {
                resetCaptureIdle()
            }
        }
    }
    private var currentPlatform: DevicePlatform = .ios {
        didSet {
            if oldValue != currentPlatform {
                // 平台变化时更新渲染视图的色彩滤镜
                renderView.colorFilter = ColorProfileManager.shared.filter(for: currentPlatform)
            }
        }
    }

    // MARK: - 鼠标追踪

    private var trackingArea: NSTrackingArea?
    private var isMouseInside: Bool = false
    private var isMouseInsideCaptureInfo = false

    /// 仅记录投屏画面内的静止时间，不影响侧边浮层上的操作。
    private var captureIdleTimer: Timer?
    private var isCaptureIdle = false
    private let captureIdleDuration: TimeInterval = 1

    /// 独立子窗口允许控制浮层超出主窗口，同时不改变设备画面的尺寸。
    private var captureInfoPanel: NSPanel?
    /// 两侧均无法完整显示时，复用信息视图作为画面内蒙层。
    private var isCaptureInfoEmbedded = false

    /// 隐藏延迟计时器（鼠标移出后延迟隐藏）
    private var hideDelayTimer: Timer?
    /// 隐藏延迟时间（秒）
    private let hideDelayDuration: TimeInterval = 1.5

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
        cancelHideDelayTimer()
        resetCaptureIdle()
        fpsUpdateTimer?.invalidate()
        NotificationCenter.default.removeObserver(self)
        if let panel = captureInfoPanel {
            panel.parent?.removeChildWindow(panel)
        }
        captureInfoPanel?.orderOut(nil)
    }

    // MARK: - UI 设置

    private func setupUI() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        setupBezelView()
        setupStatusContent()
        setupCaptureInfoView()
    }

    private func setupBezelView() {
        addSubview(bezelView)

        // 添加 Metal 渲染视图到 screenContentView（画面会跟随 bezel 动画）
        bezelView.screenContentView.addSubview(renderView)

        // 设置默认的色彩滤镜
        renderView.colorFilter = ColorProfileManager.shared.filter(for: currentPlatform)
    }

    private func setupTrackingArea() {
        let options: NSTrackingArea.Options = [.mouseEnteredAndExited, .mouseMoved, .enabledDuringMouseDrag, .activeInActiveApp, .inVisibleRect]
        trackingArea = NSTrackingArea(rect: .zero, options: options, owner: self, userInfo: nil)
        if let trackingArea {
            addTrackingArea(trackingArea)
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let oldTrackingArea = trackingArea {
            removeTrackingArea(oldTrackingArea)
        }

        let options: NSTrackingArea.Options = [.mouseEnteredAndExited, .mouseMoved, .enabledDuringMouseDrag, .activeInActiveApp, .inVisibleRect]
        trackingArea = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
        if let trackingArea {
            addTrackingArea(trackingArea)
        }
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        checkMouseInCaptureZone(with: event)
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        isMouseInside = false
        resetCaptureIdle()
        updateCaptureInfoVisibility()
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        checkMouseInCaptureZone(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        super.mouseDragged(with: event)
        checkMouseInCaptureZone(with: event)
    }

    /// 整个投屏画面都可触发侧边浮层，隐藏设备边框时使用实际渲染区域。
    private func checkMouseInCaptureZone(with event: NSEvent) {
        let screenView = showBezel ? bezelView.screenContentView : renderView
        let location = screenView.convert(event.locationInWindow, from: nil)
        let wasInside = isMouseInside
        let wasIdle = isCaptureIdle
        isMouseInside = screenView.bounds.contains(location)
        // 每次实际移动都重新计时；静止隐藏后首次移动要重新显示浮层。
        resetCaptureIdle()
        if isMouseInside, currentState == .capturing {
            scheduleCaptureIdleTimer()
        }
        if wasInside != isMouseInside || wasIdle {
            updateCaptureInfoVisibility()
        }
    }

    private func updateCaptureInfoVisibility() {
        guard canShowCaptureInfo else {
            hideCaptureInfo()
            return
        }
        guard currentState == .capturing else {
            captureInfoView.isHidden = true
            cancelHideDelayTimer()
            return
        }

        if isMouseInside || isMouseInsideCaptureInfo {
            // 鼠标进入：立即取消所有隐藏计时器，立即显示
            cancelHideDelayTimer()
            if !isCaptureIdle {
                showCaptureInfo()
                if isMouseInside, !isMouseInsideCaptureInfo, captureIdleTimer == nil {
                    scheduleCaptureIdleTimer()
                }
            }
        } else {
            // 离开后保留短暂操作时间；已隐藏或正在等待隐藏时无需重复调度。
            if !captureInfoView.isHidden, hideDelayTimer == nil {
                scheduleHideDelayTimer()
            }
        }
    }

    /// 静止一秒后同时收起控制浮层和光标；布局刷新不能重新显示它们。
    private func scheduleCaptureIdleTimer() {
        captureIdleTimer?.invalidate()
        let timer = Timer(timeInterval: captureIdleDuration, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.captureIdleTimer = nil
            guard self.currentState == .capturing, self.isMouseInside,
                  self.canShowCaptureInfo,
                  !self.isMouseInsideCaptureInfo, !self.isHiddenOrHasHiddenAncestor else { return }
            self.cancelHideDelayTimer()
            self.isCaptureIdle = true
            self.captureInfoView.isHidden = true
            // 由 AppKit 在下一次真实鼠标移动时自动恢复，避免隐藏计数影响其他窗口。
            NSCursor.setHiddenUntilMouseMoves(true)
        }
        captureIdleTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    /// 离开画面、停止投屏或应用失活时，取消计时并恢复本次隐藏的光标。
    private func resetCaptureIdle() {
        captureIdleTimer?.invalidate()
        captureIdleTimer = nil
        if isCaptureIdle {
            isCaptureIdle = false
            NSCursor.setHiddenUntilMouseMoves(false)
        }
    }

    /// 启动延迟隐藏计时器
    private func scheduleHideDelayTimer() {
        cancelHideDelayTimer()
        hideDelayTimer = Timer.scheduledTimer(withTimeInterval: hideDelayDuration, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.hideDelayTimer = nil
            // 鼠标可以跨过画面与浮层之间的间隙，进入浮层后继续操作。
            if !self.isMouseInside, !self.isMouseInsideCaptureInfo {
                self.captureInfoView.hideAnimated()
            }
        }
    }

    /// 取消延迟隐藏计时器
    private func cancelHideDelayTimer() {
        hideDelayTimer?.invalidate()
        hideDelayTimer = nil
    }

    private func setupStatusContent() {
        bezelView.screenContentView.addSubview(statusView)

        // 设置回调
        statusView.onActionTapped = { [weak self] in
            self?.startActionLoading()
            self?.onStartAction?()
        }

        statusView.onRefreshTapped = { [weak self] completion in
            self?.onRefreshAction?(completion)
        }

        statusView.onStatusTapped = { [weak self] in
            guard let self, let prompt = currentUserPrompt, !prompt.isEmpty else { return }
            ToastView.warning(prompt, in: window)
        }
    }

    private func setupCaptureInfoView() {
        captureInfoView.isHidden = true
        captureInfoView.onHoverChanged = { [weak self] isInside in
            guard let self, !self.isCaptureInfoEmbedded else { return }
            self.isMouseInsideCaptureInfo = isInside
            if isInside {
                self.resetCaptureIdle()
            }
            self.updateCaptureInfoVisibility()
        }
        captureInfoView.onHidden = { [weak self] in
            self?.captureInfoPanel?.orderOut(nil)
            self?.isMouseInsideCaptureInfo = false
        }

        captureInfoView.onStopTapped = { [weak self] in
            self?.onStopAction?()
        }

        // 音频控制回调
        captureInfoView.onAudioToggle = { [weak self] enabled in
            guard let self else { return }
            // 根据当前平台更新对应设备源的音频状态
            if self.currentPlatform == .ios {
                AppState.shared.iosDeviceSource?.isAudioEnabled = enabled
            } else if self.currentPlatform == .android {
                // audioEnabled 属性会自动更新 UserPreferences 和 audioPlayer 的静音状态
                AppState.shared.androidDeviceSource?.audioEnabled = enabled
            }
        }

        captureInfoView.onVolumeChange = { [weak self] volume in
            guard let self else { return }
            // 根据当前平台更新对应设备源的音量
            if self.currentPlatform == .ios {
                AppState.shared.iosDeviceSource?.audioVolume = volume
            } else if self.currentPlatform == .android {
                // audioVolume 属性会自动更新 UserPreferences 和 audioPlayer 的音量
                AppState.shared.androidDeviceSource?.audioVolume = volume
            }
        }
    }

    // MARK: - 侧边控制浮层

    /// 非激活浮层仍会改变父子窗口组的层级，只允许当前正在操作的投屏窗口显示它。
    /// 浮层自身成为键窗口时也保留操作，避免点击音量等控件后立即收起。
    private var canShowCaptureInfo: Bool {
        guard let window else { return false }
        return window.isKeyWindow || captureInfoPanel?.isKeyWindow == true
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        NotificationCenter.default.removeObserver(self)
        resetCaptureIdle()
        captureInfoView.isHidden = true
        if let panel = captureInfoPanel {
            panel.parent?.removeChildWindow(panel)
        }
        super.viewWillMove(toWindow: newWindow)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else { return }
        // 偏好设置等窗口获得焦点后立即收起浮层并取消静止计时。
        NotificationCenter.default.addObserver(
            self, selector: #selector(captureWindowFocusChanged),
            name: NSWindow.didBecomeKeyNotification, object: nil
        )
        for name in [NSWindow.didMoveNotification, NSWindow.didResizeNotification] {
            NotificationCenter.default.addObserver(
                self, selector: #selector(captureWindowGeometryChanged), name: name, object: window
            )
        }
        // 应用退到后台或主窗口最小化时，清除悬停状态，避免恢复后残留浮层。
        for (name, object) in [
            (NSApplication.didResignActiveNotification, NSApp as AnyObject),
            (NSWindow.willMiniaturizeNotification, window as AnyObject),
            (NSWindow.willCloseNotification, window as AnyObject),
        ] {
            NotificationCenter.default.addObserver(
                self, selector: #selector(hideCaptureInfo), name: name, object: object
            )
        }
    }

    override func viewDidHide() {
        super.viewDidHide()
        hideCaptureInfo()
    }

    @objc private func hideCaptureInfo() {
        isMouseInside = false
        isMouseInsideCaptureInfo = false
        resetCaptureIdle()
        cancelHideDelayTimer()
        captureInfoView.isHidden = true
    }

    @objc private func captureWindowGeometryChanged() {
        updateCaptureInfoPanelFrame()
        refreshCaptureHover()
    }

    @objc private func captureWindowFocusChanged() {
        if !canShowCaptureInfo {
            hideCaptureInfo()
        }
    }

    private func refreshCaptureHover() {
        // 几何变化也会触发本方法；后台布局不能被当成新的鼠标悬停。
        guard NSApp.isActive else {
            hideCaptureInfo()
            return
        }
        guard let window, !isHiddenOrHasHiddenAncestor else { return }
        let screenView = showBezel ? bezelView.screenContentView : renderView
        let location = screenView.convert(window.mouseLocationOutsideOfEventStream, from: nil)
        isMouseInside = screenView.bounds.contains(location)
        isMouseInsideCaptureInfo = !isCaptureInfoEmbedded && !captureInfoView.isHidden
            && (captureInfoPanel?.frame.contains(NSEvent.mouseLocation) ?? false)
        if !isMouseInside || isMouseInsideCaptureInfo {
            resetCaptureIdle()
        }
        updateCaptureInfoVisibility()
    }

    private func showCaptureInfo() {
        guard canShowCaptureInfo, let window, !isHiddenOrHasHiddenAncestor, !window.isMiniaturized else { return }
        if captureInfoPanel == nil {
            let panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 240, height: 420),
                styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true
            )
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = true
            panel.hidesOnDeactivate = true
            panel.isReleasedWhenClosed = false
            panel.collectionBehavior = [.fullScreenAuxiliary]
            panel.contentView = captureInfoView
            captureInfoPanel = panel
        }
        guard let panel = captureInfoPanel else { return }
        updateCaptureInfoPanelFrame()
        if !isCaptureInfoEmbedded {
            if panel.parent !== window {
                window.addChildWindow(panel, ordered: .above)
            }
            panel.orderFront(nil)
        }
        captureInfoView.showAnimated()
    }

    /// 优先利用画面两侧空白；双设备布局中避开另一台设备，必要时超出主窗口。
    private func updateCaptureInfoPanelFrame() {
        // 几何更新先于悬停刷新，必须在这里阻止后台窗口再次 orderFront。
        guard canShowCaptureInfo else {
            hideCaptureInfo()
            return
        }
        guard let window, let panel = captureInfoPanel else { return }
        let deviceFrame = window.convertToScreen(convert(bounds, to: nil))
        let size = NSSize(width: 240, height: 420)
        let gap: CGFloat = 12
        let rightX = deviceFrame.maxX + gap
        let leftX = deviceFrame.minX - gap - size.width
        let siblingFrames = superview?.subviews.compactMap { view -> NSRect? in
            guard let device = view as? DevicePanelView, device !== self,
                  !device.isHiddenOrHasHiddenAncestor else { return nil }
            return window.convertToScreen(device.convert(device.bounds, to: nil))
        } ?? []
        let visibleFrame = window.screen?.visibleFrame ?? deviceFrame
        let y = max(visibleFrame.minY, min(deviceFrame.midY - size.height / 2, visibleFrame.maxY - size.height))
        let candidates = [rightX, leftX].map { NSRect(x: $0, y: y, width: size.width, height: size.height) }
        let frame = candidates.first { candidate in
            visibleFrame.contains(candidate) && !siblingFrames.contains { $0.intersects(candidate) }
        }
        let screenView: NSView = showBezel ? bezelView.screenContentView : self
        isCaptureInfoEmbedded = frame == nil
        captureInfoView.setEmbeddedInScreen(isCaptureInfoEmbedded)
        if let frame {
            // 从画面内恢复到侧边时，始终保留固定大小，不继承蒙层的屏幕尺寸。
            if panel.contentView !== captureInfoView {
                captureInfoView.removeFromSuperview()
                panel.contentView = captureInfoView
            }
            panel.setFrame(frame, display: true)
            if !captureInfoView.isHidden {
                if panel.parent !== window {
                    window.addChildWindow(panel, ordered: .above)
                }
                panel.orderFront(nil)
            }
        } else {
            // 两侧都放不下时恢复旧的画面内蒙层，不再把控制按钮放到显示器外。
            panel.orderOut(nil)
            if captureInfoView.superview !== screenView {
                panel.contentView = nil
                captureInfoView.removeFromSuperview()
                screenView.addSubview(captureInfoView)
            }
            captureInfoView.frame = screenView.bounds
            // 内嵌蒙层属于投屏画面，不能被当作侧边控件而阻止一秒静止隐藏。
            isMouseInsideCaptureInfo = false
        }
    }

    // MARK: - 公开方法

    /// 显示断开状态
    func showDisconnected(platform: DevicePlatform, connectionGuide: String) {
        currentState = .disconnected
        currentPlatform = platform
        currentCaptureResolution = .zero
        stopFPSUpdateTimer()
        currentUserPrompt = nil

        // 未连接时使用通用边框
        configureBezel(for: platform, deviceName: nil)

        // 隐藏渲染视图，显示状态容器
        renderView.isHidden = true
        statusView.isHidden = false
        captureInfoView.isHidden = true

        // 更新状态视图
        let title = platform == .ios ? L10n.overlayUI.waitingForIPhone : L10n.overlayUI.waitingForAndroid
        statusView.showDisconnected(title: title, subtitle: connectionGuide)
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
    ///   - buildVersion: iOS build 版本（如 "22C5125e"）
    ///   - sdkVersion: Android SDK 版本（如 "31"）
    ///   - userPrompt: 用户提示信息（如需要信任、解锁等）
    ///   - deviceState: 设备状态
    ///   - iosDevice: iOS 设备实例（用于精确识别设备型号）
    ///   - androidDevice: Android 设备实例（用于精确识别设备型号）
    ///   - onStart: 开始捕获回调
    ///   - onRefresh: 刷新设备信息回调
    func showConnected(
        deviceName: String,
        platform: DevicePlatform,
        modelName: String? = nil,
        systemVersion: String? = nil,
        buildVersion: String? = nil,
        sdkVersion: String? = nil,
        userPrompt: String? = nil,
        deviceState: IOSDevice.State? = nil,
        iosDevice: IOSDevice? = nil,
        androidDevice: AndroidDevice? = nil,
        onStart: @escaping () -> Void,
        onRefresh: ((@escaping () -> Void) -> Void)? = nil
    ) {
        // 记录之前是否在捕获状态（用于决定是否重新配置 bezel）
        let wasCapturing = currentState == .capturing

        currentState = .connected
        currentPlatform = platform
        // 注意：不重置 currentCaptureResolution，以便保留最后的 aspectRatio
        onStartAction = onStart
        onRefreshAction = onRefresh
        currentUserPrompt = userPrompt
        stopFPSUpdateTimer()

        // 配置边框：
        // - 如果之前在捕获状态（停止投屏），保留当前的 aspectRatio，避免位置跳动
        // - 如果之前不在捕获状态（新连接设备），使用设备默认值配置
        if !wasCapturing {
            if let device = iosDevice {
                configureBezel(for: device)
            } else if let device = androidDevice {
                configureBezel(for: device)
            } else {
                configureBezel(for: platform, deviceName: deviceName)
            }
        }
        // 如果是从捕获状态切换过来，保留当前 bezel 的 aspectRatio，不重新配置

        // 隐藏渲染视图，显示状态容器
        renderView.isHidden = true
        statusView.isHidden = false
        captureInfoView.isHidden = true

        // 计算状态颜色和是否有警告
        let statusColor: NSColor
        let hasWarning: Bool
        if userPrompt != nil {
            statusColor = if let state = deviceState {
                IOSDeviceStateMapper.statusColor(for: state)
            } else {
                .systemOrange
            }
            hasWarning = true
        } else {
            statusColor = .systemGreen
            hasWarning = false
        }

        // 构建设备详细信息文本
        let detailInfo = buildDeviceDetailInfo(
            platform: platform,
            modelName: modelName,
            systemVersion: systemVersion,
            buildVersion: buildVersion,
            sdkVersion: sdkVersion
        )

        // 更新状态视图
        statusView.showConnected(
            deviceName: deviceName,
            statusText: userPrompt ?? L10n.overlayUI.deviceDetected,
            statusColor: statusColor,
            hasWarning: hasWarning,
            subtitle: detailInfo,
            showRefresh: onRefresh != nil
        )
    }

    /// 构建设备详细信息文本
    /// - Parameters:
    ///   - platform: 设备平台
    ///   - modelName: 型号名称
    ///   - systemVersion: 系统版本
    ///   - buildVersion: iOS build 版本
    ///   - sdkVersion: Android SDK 版本
    private func buildDeviceDetailInfo(
        platform: DevicePlatform,
        modelName: String?,
        systemVersion: String?,
        buildVersion: String?,
        sdkVersion: String? = nil
    ) -> String {
        var parts: [String] = []

        // 型号名称（如 iPhone 15 Pro 或 OnePlus PKX110）
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
                // Android 版本：直接使用已格式化的 displaySystemVersion
                // 格式如: ColorOS 15(Android 15 · SDK 35) 或 Android 15(SDK 35)
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
        let wasCapturing = currentState == .capturing && currentPlatform == .ios

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
            if let build = device.buildVersion, !build.isEmpty {
                currentDeviceSystemVersion = "iOS \(version) (\(build))"
            } else {
                currentDeviceSystemVersion = "iOS \(version)"
            }
        } else {
            currentDeviceSystemVersion = nil
        }

        // 更新 bezel：
        // - resolution 有效时（收到第一帧后）：使用实际分辨率的 aspectRatio
        // - resolution 无效时（未收到帧）：保留当前 bezel 配置，避免位置跳动
        let resolutionValid = resolution.width > 0 && resolution.height > 0
        let resolutionChanged = abs(resolution.width - currentCaptureResolution.width) > 1 ||
            abs(resolution.height - currentCaptureResolution.height) > 1

        // 只有在收到有效分辨率且分辨率变化时才更新 bezel
        if resolutionValid, !wasCapturing || resolutionChanged {
            // 收到第一帧后，使用实际视频分辨率更新 bezel
            bezelView.updateAspectRatio(resolution.width / resolution.height)
            currentCaptureResolution = resolution
        }
        // 注意：如果还没收到帧，保留当前 bezel 的 aspectRatio，不重新配置

        // 如果已经在捕获状态，只更新分辨率相关的 UI，跳过其他配置
        if wasCapturing {
            if resolutionValid {
                captureInfoView.updateResolution(resolution)
            }
            return
        }

        // 显示渲染视图，隐藏状态容器
        renderView.isHidden = false
        statusView.isHidden = true

        // 更新捕获状态文本：显示设备型号和名称
        updateCaptureStatusText()

        // 设置平台以控制音频控件显示
        captureInfoView.setPlatform(.ios)

        // 更新分辨率和 FPS
        captureInfoView.updateResolution(resolutionValid ? resolution : .zero)
        updateFPS(fps)

        // 仅在光标位于画面上时显示控制浮层，开始投屏不主动打断演示。
        refreshCaptureHover()

        // 启动 FPS 更新定时器
        startFPSUpdateTimer()
    }

    /// 显示捕获中状态（通用方式，通过设备名称识别）
    /// - Parameters:
    ///   - deviceName: 设备名称
    ///   - modelName: 型号名称
    ///   - systemVersion: 系统版本
    ///   - sdkVersion: Android SDK 版本（如 "31"）
    ///   - platform: 设备平台
    ///   - fps: 帧率
    ///   - resolution: 分辨率
    ///   - androidDevice: Android 设备实例（用于精确识别设备型号）
    ///   - onStop: 停止捕获回调
    func showCapturing(
        deviceName: String,
        modelName: String?,
        systemVersion: String? = nil,
        sdkVersion: String? = nil,
        platform: DevicePlatform,
        fps: Double,
        resolution: CGSize,
        androidDevice: AndroidDevice? = nil,
        onStop: @escaping () -> Void
    ) {
        let wasCapturing = currentState == .capturing && currentPlatform == platform

        // 停止加载状态
        stopActionLoading()

        currentState = .capturing
        currentPlatform = platform
        onStopAction = onStop

        // 保存设备信息用于更新状态栏
        currentDeviceDisplayName = deviceName
        currentDeviceModelName = modelName
        // Android 的 systemVersion 已经是完整格式（如 ColorOS 15(Android 15 · SDK 35)）
        // iOS 不需要额外处理
        currentDeviceSystemVersion = systemVersion

        // 更新 bezel：
        // - resolution 有效时（收到第一帧后）：使用实际分辨率的 aspectRatio
        // - resolution 无效时（未收到帧）：保留当前 bezel 配置，避免位置跳动
        let resolutionValid = resolution.width > 0 && resolution.height > 0
        let resolutionChanged = abs(resolution.width - currentCaptureResolution.width) > 1 ||
            abs(resolution.height - currentCaptureResolution.height) > 1

        // 只有在收到有效分辨率且分辨率变化时才更新 bezel
        if resolutionValid, !wasCapturing || resolutionChanged {
            // 收到第一帧后，使用实际视频分辨率更新 bezel
            bezelView.updateAspectRatio(resolution.width / resolution.height)
            currentCaptureResolution = resolution
        }
        // 注意：如果还没收到帧，保留当前 bezel 的 aspectRatio，不重新配置

        // 如果已经在捕获状态，只更新分辨率相关的 UI，跳过其他配置
        if wasCapturing {
            if resolutionValid {
                captureInfoView.updateResolution(resolution)
            }
            return
        }

        // 显示渲染视图，隐藏状态容器
        renderView.isHidden = false
        statusView.isHidden = true

        // 更新捕获状态文本：显示设备型号和名称
        updateCaptureStatusText()

        // 设置平台以控制音频控件显示
        captureInfoView.setPlatform(platform)

        // 更新分辨率和 FPS
        captureInfoView.updateResolution(resolutionValid ? resolution : .zero)
        updateFPS(fps)

        // 仅在光标位于画面上时显示控制浮层，开始投屏不主动打断演示。
        refreshCaptureHover()

        // 启动 FPS 更新定时器
        startFPSUpdateTimer()
    }

    /// 显示加载状态
    func showLoading(platform: DevicePlatform) {
        currentState = .loading
        currentPlatform = platform
        currentCaptureResolution = .zero
        stopFPSUpdateTimer()
        currentUserPrompt = nil

        // 配置边框外观
        configureBezel(for: platform, deviceName: nil)

        // 隐藏渲染视图，显示状态容器
        renderView.isHidden = true
        statusView.isHidden = false
        captureInfoView.isHidden = true

        // 更新状态视图
        statusView.showLoading(title: L10n.common.loading)
    }

    /// 显示工具链缺失状态
    func showToolchainMissing(toolName: String, onInstall: @escaping () -> Void) {
        currentState = .toolchainMissing
        currentCaptureResolution = .zero
        onInstallAction = onInstall
        onStartAction = onInstall
        stopFPSUpdateTimer()
        currentUserPrompt = nil

        // 工具链缺失时使用通用 Android 边框
        configureBezel(for: .android, deviceName: nil)

        // 隐藏渲染视图，显示状态容器
        renderView.isHidden = true
        statusView.isHidden = false
        captureInfoView.isHidden = true

        // 更新状态视图
        statusView.showToolchainMissing(
            toolName: toolName,
            hint: L10n.toolchain.installScrcpyHint
        )
    }

    // MARK: - 按钮控制

    /// 设置操作按钮的启用状态
    func setActionButtonEnabled(_ enabled: Bool) {
        statusView.setActionButtonEnabled(enabled)
    }

    /// 更新帧率
    func updateFPS(_ fps: Double) {
        guard currentState == .capturing else { return }
        captureInfoView.updateFPS(fps)
    }

    /// 更新捕获分辨率（在捕获过程中分辨率变化时调用）
    /// 只更新 bezel 的 aspectRatio 和分辨率标签，避免重新配置整个 UI
    func updateCaptureResolution(_ resolution: CGSize) {
        guard currentState == .capturing else { return }

        // 检查分辨率是否真的变化了
        let resolutionChanged = abs(resolution.width - currentCaptureResolution.width) > 1 ||
            abs(resolution.height - currentCaptureResolution.height) > 1
        guard resolutionChanged else { return }

        currentCaptureResolution = resolution

        // 更新 bezel 的 aspectRatio
        if resolution.width > 0, resolution.height > 0 {
            bezelView.updateAspectRatio(resolution.width / resolution.height)
            captureInfoView.updateResolution(resolution)
        }

        // 重新布局以更新 captureInfoView 位置
        needsLayout = true
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
            // 显示 bezel：将画面和状态视图移回屏幕区域，控制浮层始终留在独立窗口中。
            bezelView.isHidden = false

            renderView.removeFromSuperview()
            bezelView.screenContentView.addSubview(renderView)

            statusView.removeFromSuperview()
            bezelView.screenContentView.addSubview(statusView)
        } else {
            // 隐藏 bezel：将画面和状态视图移到 self 中。
            bezelView.isHidden = true

            renderView.removeFromSuperview()
            addSubview(renderView)

            statusView.removeFromSuperview()
            addSubview(statusView)
        }

        // 强制重新布局
        needsLayout = true
        layoutSubtreeIfNeeded()
    }

    private func updateContentFrames() {
        let containerView: NSView = showBezel ? bezelView.screenContentView : self
        let targetFrame = containerView.bounds
        renderView.frame = targetFrame
        statusView.frame = targetFrame
        updateCaptureInfoPanelFrame()
    }

    override func layout() {
        super.layout()
        // 禁用隐式动画，避免 frame 变化时子视图产生动画
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        bezelView.frame = bounds
        bezelView.layoutSubtreeIfNeeded()
        updateContentFrames()
        CATransaction.commit()
        // 布局变化后以实际光标位置更新状态，兼容设备交换和边框开关。
        refreshCaptureHover()
    }

    // MARK: - 私有方法

    private var currentDeviceName: String?
    private var currentDeviceDisplayName: String?
    private var currentDeviceModelName: String?
    /// 当前捕获分辨率（用于检测变化，避免重复配置）
    private var currentCaptureResolution: CGSize = .zero

    /// 更新捕获状态文本（显示设备名称、型号、系统版本）
    private func updateCaptureStatusText() {
        // 第一行：设备名称
        let deviceName = currentDeviceDisplayName ?? L10n.device.capturing

        // 第二行：型号 · 系统版本
        var infoParts: [String] = []
        if let modelName = currentDeviceModelName, !modelName.isEmpty, modelName != currentDeviceDisplayName {
            infoParts.append(modelName)
        }
        if let systemVersion = currentDeviceSystemVersion, !systemVersion.isEmpty {
            infoParts.append(systemVersion)
        }
        let deviceInfo = infoParts.joined(separator: " · ")

        captureInfoView.updateDeviceInfo(deviceName: deviceName, deviceInfo: deviceInfo)
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

    /// 配置 Android 设备的边框（使用 brand 精确识别）
    private func configureBezel(for device: AndroidDevice, aspectRatio: CGSize? = nil) {
        currentDeviceName = device.displayName
        if let size = aspectRatio, size.width > 0, size.height > 0 {
            bezelView.configure(device: device, aspectRatio: size.width / size.height)
        } else {
            bezelView.configure(device: device)
        }
    }

    // MARK: - 操作按钮状态控制

    /// 开始操作按钮加载状态
    func startActionLoading() {
        statusView.startActionLoading()
    }

    /// 停止操作按钮加载状态
    func stopActionLoading() {
        statusView.stopActionLoading()
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
        // 更新状态视图的本地化文本
        statusView.updateLocalizedTexts()

        // 根据当前状态重新显示对应的界面
        // 这样可以确保所有本地化文本都被更新
        switch currentState {
        case .loading:
            statusView.showLoading(title: L10n.common.loading)

        case .disconnected:
            let title = currentPlatform == .ios
                ? L10n.overlayUI.waitingForIPhone
                : L10n.overlayUI.waitingForAndroid
            let subtitle = currentPlatform == .ios
                ? L10n.overlayUI.connectIOS
                : L10n.overlayUI.connectAndroid
            statusView.showDisconnected(title: title, subtitle: subtitle)

        case .connected:
            // 设备已连接状态需要保持当前的设备信息，只更新可本地化的文本
            // 这里不做完整的重新显示，因为设备信息是动态的
            break

        case .capturing:
            // 捕获中显示设备信息，不需要本地化更新
            break

        case .toolchainMissing:
            statusView.showToolchainMissing(
                toolName: "scrcpy",
                hint: L10n.toolchain.installScrcpyHint
            )
        }
    }
}
