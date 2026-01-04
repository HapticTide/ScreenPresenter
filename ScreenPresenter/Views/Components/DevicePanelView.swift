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

    private var currentState: PanelState = .loading
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
        let options: NSTrackingArea.Options = [.mouseEnteredAndExited, .mouseMoved, .activeInActiveApp, .inVisibleRect]
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

        let options: NSTrackingArea.Options = [.mouseEnteredAndExited, .mouseMoved, .activeInActiveApp, .inVisibleRect]
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
        updateCaptureInfoVisibility()
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        checkMouseInCaptureZone(with: event)
    }

    /// 检查鼠标是否在 captureInfo 显示区域内（屏幕中心区域）
    private func checkMouseInCaptureZone(with event: NSEvent) {
        // 将鼠标位置转换到 bezelView.screenContentView 的坐标系
        let locationInView = convert(event.locationInWindow, from: nil)
        let locationInScreen = bezelView.screenContentView.convert(locationInView, from: self)

        let screenBounds = bezelView.screenContentView.bounds
        guard screenBounds.width > 0, screenBounds.height > 0 else {
            isMouseInside = false
            updateCaptureInfoVisibility()
            return
        }

        // 计算中心区域（中间 50% 区域）
        let centerRatio: CGFloat = 0.5
        let marginX = screenBounds.width * (1 - centerRatio) / 2
        let marginY = screenBounds.height * (1 - centerRatio) / 2
        let centerZone = CGRect(
            x: marginX,
            y: marginY,
            width: screenBounds.width * centerRatio,
            height: screenBounds.height * centerRatio
        )

        let wasInside = isMouseInside
        isMouseInside = centerZone.contains(locationInScreen)

        // 只在状态改变时更新
        if wasInside != isMouseInside {
            updateCaptureInfoVisibility()
        }
    }

    private func updateCaptureInfoVisibility() {
        guard currentState == .capturing else {
            captureInfoView.isHidden = true
            return
        }

        if isMouseInside {
            captureInfoView.showAnimated(autoHide: false)
        } else {
            captureInfoView.hideAnimated()
        }
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
        // 捕获状态覆盖视图（覆盖整个 screenContentView 区域）
        captureInfoView.isHidden = true
        bezelView.screenContentView.addSubview(captureInfoView)

        captureInfoView.onStopTapped = { [weak self] in
            self?.onStopAction?()
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
        currentState = .connected
        currentPlatform = platform
        currentCaptureResolution = .zero
        onStartAction = onStart
        onRefreshAction = onRefresh
        currentUserPrompt = userPrompt
        stopFPSUpdateTimer()

        // 配置边框：优先使用设备实例精确识别
        if let device = iosDevice {
            configureBezel(for: device)
        } else if let device = androidDevice {
            configureBezel(for: device)
        } else {
            configureBezel(for: platform, deviceName: deviceName)
        }

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
        // - resolution 无效时（未收到帧）：使用设备默认的 aspectRatio
        let resolutionValid = resolution.width > 0 && resolution.height > 0
        let resolutionChanged = abs(resolution.width - currentCaptureResolution.width) > 1 ||
            abs(resolution.height - currentCaptureResolution.height) > 1

        // 只有在分辨率变化时才更新 bezel（避免重复配置）
        if !wasCapturing || resolutionChanged {
            if resolutionValid {
                // 收到第一帧后，使用实际视频分辨率更新 bezel
                bezelView.updateAspectRatio(resolution.width / resolution.height)
            } else if !wasCapturing {
                // 首次进入捕获状态但还没收到帧，使用设备默认值配置 bezel
                configureBezel(for: device, aspectRatio: nil)
            }
            currentCaptureResolution = resolution
        }

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

        // 更新分辨率和 FPS
        captureInfoView.updateResolution(resolutionValid ? resolution : .zero)
        updateFPS(fps)

        // 开始投屏后显示一次，然后延时自动隐藏
        captureInfoView.showAnimated(autoHide: true)

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
        // - resolution 无效时（未收到帧）：使用设备默认的 aspectRatio
        let resolutionValid = resolution.width > 0 && resolution.height > 0
        let resolutionChanged = abs(resolution.width - currentCaptureResolution.width) > 1 ||
            abs(resolution.height - currentCaptureResolution.height) > 1

        // 只有在分辨率变化时才更新 bezel（避免重复配置）
        if !wasCapturing || resolutionChanged {
            if resolutionValid {
                // 收到第一帧后，使用实际视频分辨率更新 bezel
                bezelView.updateAspectRatio(resolution.width / resolution.height)
            } else if !wasCapturing {
                // 首次进入捕获状态但还没收到帧，使用设备默认值配置 bezel
                if let device = androidDevice {
                    configureBezel(for: device, aspectRatio: nil)
                } else {
                    configureBezel(for: platform, deviceName: deviceName, aspectRatio: nil)
                }
            }
            currentCaptureResolution = resolution
        }

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

        // 更新分辨率和 FPS
        captureInfoView.updateResolution(resolutionValid ? resolution : .zero)
        updateFPS(fps)

        // 开始投屏后显示一次，然后延时自动隐藏
        captureInfoView.showAnimated(autoHide: true)

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
            // 显示 bezel：将 renderView、statusView、captureInfoView 移回 bezelView.screenContentView
            bezelView.isHidden = false

            renderView.removeFromSuperview()
            bezelView.screenContentView.addSubview(renderView)

            statusView.removeFromSuperview()
            bezelView.screenContentView.addSubview(statusView)

            captureInfoView.removeFromSuperview()
            bezelView.screenContentView.addSubview(captureInfoView)
        } else {
            // 隐藏 bezel：将 renderView、statusView、captureInfoView 移到 self 中
            bezelView.isHidden = true

            renderView.removeFromSuperview()
            addSubview(renderView)

            statusView.removeFromSuperview()
            addSubview(statusView)

            captureInfoView.removeFromSuperview()
            addSubview(captureInfoView)
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
        captureInfoView.frame = targetFrame
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
