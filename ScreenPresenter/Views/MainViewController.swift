//
//  MainViewController.swift
//  ScreenPresenter
//
//  Created by Sun on 2025/12/22.
//
//  主视图控制器
//  包含预览区域和交换按钮
//

import AppKit
import Combine
import SnapKit

// MARK: - 主视图控制器

final class MainViewController: NSViewController {
    // MARK: - UI 组件

    private var previewContainerView: NSView!

    // MARK: - 设备面板

    /// iOS 面板（默认在左侧）
    private var iosPanelView: DevicePanelView!
    /// Android 面板（默认在右侧）
    private var androidPanelView: DevicePanelView!
    private var swapButton: NSButton!
    private var swapButtonIconLayer: CALayer!
    private var swapButtonTrackingArea: NSTrackingArea?

    // MARK: - 状态

    private var cancellables = Set<AnyCancellable>()
    private var isSwapped: Bool = false
    private var isFullScreen: Bool = false
    private var isInitialLayout: Bool = true
    private var isMouseInSwapArea: Bool = false

    // MARK: - 生命周期

    override func loadView() {
        view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        // 从偏好设置读取默认设备位置
        isSwapped = !UserPreferences.shared.iosOnLeft

        setupUI()
        setupBindings()
        startRendering()
    }

    override func viewWillDisappear() {
        super.viewWillDisappear()
        stopRendering()
    }

    // MARK: - UI 设置

    private func setupUI() {
        setupPreviewContainer()
        setupDevicePanels()
        setupSwapButton()
        setupSwapButtonTracking()
        updatePanelLayout()
    }

    private func setupPreviewContainer() {
        previewContainerView = NSView()
        previewContainerView.wantsLayer = true
        // 非全屏时使用默认背景色，全屏时使用用户偏好的黑色+透明度
        previewContainerView.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        view.addSubview(previewContainerView)
        previewContainerView.snp.makeConstraints { make in
            // 顶部留出 titlebar 区域（约 28pt）
            make.top.equalToSuperview().offset(28)
            make.leading.trailing.bottom.equalToSuperview()
        }
    }

    private func setupDevicePanels() {
        androidPanelView = DevicePanelView()
        previewContainerView.addSubview(androidPanelView)

        iosPanelView = DevicePanelView()
        previewContainerView.addSubview(iosPanelView)
    }

    private func setupSwapButton() {
        swapButton = NSButton(title: "", target: self, action: #selector(swapTapped))
        swapButton.bezelStyle = .circular
        swapButton.isBordered = false
        swapButton.wantsLayer = true
        swapButton.layer?.cornerRadius = 16
        swapButton.layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.8).cgColor
        swapButton.toolTip = L10n.toolbar.swapTooltip
        swapButton.focusRingType = .none
        swapButton.refusesFirstResponder = true
        swapButton.alphaValue = 1.0
        previewContainerView.addSubview(swapButton)

        // 使用 CALayer 显示图标，便于精确控制动画锚点
        let iconSize: CGFloat = 16
        let buttonSize: CGFloat = 32

        swapButtonIconLayer = CALayer()
        swapButtonIconLayer.bounds = CGRect(x: 0, y: 0, width: iconSize, height: iconSize)
        swapButtonIconLayer.position = CGPoint(x: buttonSize / 2, y: buttonSize / 2)
        swapButtonIconLayer.anchorPoint = CGPoint(x: 0.5, y: 0.5)

        // 使用 SF Symbol 创建图标
        if let iconImage = NSImage(systemSymbolName: "arrow.left.arrow.right", accessibilityDescription: nil) {
            let config = NSImage.SymbolConfiguration(pointSize: iconSize, weight: .regular)
            let configuredImage = iconImage.withSymbolConfiguration(config)
            swapButtonIconLayer.contents = configuredImage?.tinted(with: .labelColor)
            swapButtonIconLayer.contentsGravity = .resizeAspect
        }

        swapButton.layer?.addSublayer(swapButtonIconLayer)
    }

    @objc private func swapTapped() {
        isSwapped.toggle()
        updatePanelLayout()
    }

    private func setupSwapButtonTracking() {
        // 移除旧的追踪区域
        if let oldArea = swapButtonTrackingArea {
            previewContainerView.removeTrackingArea(oldArea)
        }

        // 创建中间区域的追踪范围（基于 previewContainerView，比按钮大一些方便触发）
        // swapButton 在 previewContainerView 的中心，所以基于 previewContainerView.bounds 计算
        let centerRect = CGRect(
            x: previewContainerView.bounds.midX - 60,
            y: previewContainerView.bounds.midY - 60,
            width: 120,
            height: 120
        )

        let trackingArea = NSTrackingArea(
            rect: centerRect,
            options: [.mouseEnteredAndExited, .activeInKeyWindow],
            owner: self,
            userInfo: nil
        )
        previewContainerView.addTrackingArea(trackingArea)
        swapButtonTrackingArea = trackingArea

        // 重建 tracking area 后，主动检查鼠标当前位置
        // 避免依赖系统的 mouseEntered/mouseExited 事件（它们的时序可能不确定）
        updateMouseInSwapAreaState()
    }

    /// 根据鼠标当前位置更新 isMouseInSwapArea 状态
    private func updateMouseInSwapAreaState() {
        guard let window = view.window else {
            isMouseInSwapArea = false
            return
        }

        // 获取鼠标在窗口中的位置
        let mouseLocationInWindow = window.mouseLocationOutsideOfEventStream
        // 转换到 previewContainerView 的坐标系
        let mouseLocationInContainer = previewContainerView.convert(mouseLocationInWindow, from: nil)

        // 计算 tracking 区域
        let centerRect = CGRect(
            x: previewContainerView.bounds.midX - 60,
            y: previewContainerView.bounds.midY - 60,
            width: 120,
            height: 120
        )

        isMouseInSwapArea = centerRect.contains(mouseLocationInContainer)
    }

    private func updateSwapButtonVisibility() {
        // 非全屏时始终显示，全屏时仅当鼠标在区域内时显示
        let shouldShow = !isFullScreen || isMouseInSwapArea
        swapButton.isHidden = !shouldShow
        swapButton.alphaValue = shouldShow ? 1.0 : 0.0
    }

    private func updateTitlebarVisibility(animated: Bool = true) {
        guard let window = view.window else { return }

        // 全屏时隐藏 toolbar，非全屏时显示
        let shouldShow = !isFullScreen

        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                context.allowsImplicitAnimation = true
                window.toolbar?.isVisible = shouldShow
            }
        } else {
            window.toolbar?.isVisible = shouldShow
        }

        // 更新 previewContainerView 的顶部约束
        updatePreviewContainerTopConstraint()
    }

    private func updatePreviewContainerTopConstraint() {
        // 全屏时内容区域延伸到顶部，非全屏时留出 titlebar 区域
        let topOffset: CGFloat = isFullScreen ? 0 : 28

        previewContainerView.snp.updateConstraints { make in
            make.top.equalToSuperview().offset(topOffset)
        }
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        isMouseInSwapArea = true
        updateSwapButtonVisibility()
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        isMouseInSwapArea = false
        updateSwapButtonVisibility()
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        // 当视图大小改变时更新追踪区域
        setupSwapButtonTracking()
        // 更新按钮可见性
        updateSwapButtonVisibility()
    }

    private func updatePanelLayout() {
        // 更新面板内容
        updateAndroidPanel(androidPanelView)
        updateIOSPanel(iosPanelView)

        // 重置约束
        androidPanelView.snp.removeConstraints()
        iosPanelView.snp.removeConstraints()
        swapButton.snp.removeConstraints()

        // 根据 isSwapped 决定哪个面板在左侧
        // 默认 (isSwapped=false): iOS 在左侧，Android 在右侧
        // 交换后 (isSwapped=true): Android 在左侧，iOS 在右侧
        let leftPanel = isSwapped ? androidPanelView! : iosPanelView!
        let rightPanel = isSwapped ? iosPanelView! : androidPanelView!

        let panelGap: CGFloat = 8
        // 非全屏时添加上下缩进以平衡视觉效果，全屏时无缩进
        let verticalPadding: CGFloat = isFullScreen ? 0 : 24

        // 左右并排布局
        leftPanel.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(verticalPadding)
            make.bottom.equalToSuperview().offset(-verticalPadding)
            make.leading.equalToSuperview()
            make.width.equalToSuperview().multipliedBy(0.5).offset(-panelGap / 2)
        }

        rightPanel.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(verticalPadding)
            make.bottom.equalToSuperview().offset(-verticalPadding)
            make.leading.equalTo(leftPanel.snp.trailing).offset(panelGap)
            make.trailing.equalToSuperview()
        }

        // swap 按钮在两个面板中间
        swapButton.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.centerY.equalToSuperview()
            make.width.height.equalTo(32)
        }

        // 首次布局时不执行动画，避免启动时的视觉跳动
        if isInitialLayout {
            isInitialLayout = false
            previewContainerView.layoutSubtreeIfNeeded()
        } else {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.3
                context.allowsImplicitAnimation = true
                previewContainerView.layoutSubtreeIfNeeded()
            }
        }
    }

    // MARK: - 绑定

    private func setupBindings() {
        AppState.shared.stateChangedPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                self?.updateUI()
            }
            .store(in: &cancellables)

        // 注意：纹理更新由数据源的帧回调驱动，而不是渲染请求
        // 这在 updateIOSPanel/updateAndroidPanel 中设置

        // 监听背景色变化
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleBackgroundColorChange),
            name: .backgroundColorDidChange,
            object: nil
        )
    }

    @objc private func handleBackgroundColorChange() {
        // 只有全屏时才应用用户偏好的背景色（黑色+透明度）
        if isFullScreen {
            let bgColor = UserPreferences.shared.backgroundColor.cgColor
            view.layer?.backgroundColor = bgColor // titlebar 透明，会显示 view 的背景色
            previewContainerView.layer?.backgroundColor = bgColor
        }
    }

    // MARK: - 渲染

    private func startRendering() {
        iosPanelView.renderView.startRendering()
        androidPanelView.renderView.startRendering()
    }

    private func stopRendering() {
        iosPanelView.renderView.stopRendering()
        androidPanelView.renderView.stopRendering()
    }

    // MARK: - UI 更新

    /// 记录上次的 aspectRatio，用于检测变化
    private var lastIOSAspectRatio: CGFloat = 0
    private var lastAndroidAspectRatio: CGFloat = 0

    private func updateUI() {
        // 先记录旧的 aspectRatio
        let oldIOSRatio = iosPanelView.deviceAspectRatio
        let oldAndroidRatio = androidPanelView.deviceAspectRatio

        // 更新面板内容
        updateAndroidPanel(androidPanelView)
        updateIOSPanel(iosPanelView)

        // 检查 aspectRatio 是否变化，如果变化则重新布局
        let newIOSRatio = iosPanelView.deviceAspectRatio
        let newAndroidRatio = androidPanelView.deviceAspectRatio

        if abs(newIOSRatio - oldIOSRatio) > 0.01 || abs(newAndroidRatio - oldAndroidRatio) > 0.01 {
            updatePanelLayout()
        }
    }

    private func updateAndroidPanel(_ panel: DevicePanelView) {
        let appState = AppState.shared

        // 应用初始化期间显示加载状态，避免显示"未安装"的闪烁
        if appState.isInitializing {
            panel.showLoading(platform: .android)
            return
        }

        let scrcpyReady = appState.toolchainManager.scrcpyStatus.isReady

        if !scrcpyReady {
            panel.showToolchainMissing(toolName: "scrcpy") { [weak self] in
                self?.installScrcpy()
            }
            panel.renderView.clearTexture()
        } else if appState.androidCapturing {
            panel.showCapturing(
                deviceName: appState.androidDeviceName ?? "Android",
                platform: .android,
                fps: panel.renderView.fps,
                resolution: appState.androidDeviceSource?.captureSize ?? .zero,
                onStop: { [weak self] in
                    self?.stopAndroidCapture()
                }
            )
        } else if appState.androidConnected {
            // 检查设备是否已授权（state == .device）
            let isDeviceReady = appState.androidDeviceReady
            let userPrompt = appState.androidDeviceUserPrompt

            panel.showConnected(
                deviceName: appState.androidDeviceName ?? "Android",
                platform: .android,
                userPrompt: userPrompt,
                onStart: { [weak self] in
                    // 只有设备已授权才允许捕获
                    if isDeviceReady {
                        self?.startAndroidCapture()
                    }
                }
            )

            // 如果设备未授权，禁用开始按钮
            if !isDeviceReady {
                panel.setActionButtonEnabled(false)
            }

            panel.renderView.clearTexture()
        } else {
            panel.showDisconnected(platform: .android, connectionGuide: L10n.overlayUI.connectAndroid)
            panel.renderView.clearTexture()
        }
    }

    private func updateIOSPanel(_ panel: DevicePanelView) {
        let appState = AppState.shared

        // 应用初始化期间显示加载状态
        if appState.isInitializing {
            panel.showLoading(platform: .ios)
            return
        }

        if appState.iosCapturing {
            // 设置帧回调，每个新帧到来时更新纹理
            appState.iosDeviceSource?.onFrame = { [weak panel] pixelBuffer in
                panel?.renderView.updateTexture(from: pixelBuffer)
            }

            // 设置会话中断回调（设备锁屏等）
            appState.iosDeviceSource?.onSessionInterrupted = { [weak panel] reason in
                DispatchQueue.main.async {
                    panel?.showSessionInterrupted(reason: reason)
                }
            }

            // 设置会话恢复回调（设备解锁等）
            appState.iosDeviceSource?.onSessionResumed = { [weak panel] in
                DispatchQueue.main.async {
                    panel?.hideSessionInterrupted()
                }
            }

            panel.showCapturing(
                deviceName: appState.iosDeviceName ?? "iPhone",
                platform: .ios,
                fps: panel.renderView.fps,
                resolution: appState.iosDeviceSource?.captureSize ?? .zero,
                onStop: { [weak self] in
                    self?.stopIOSCapture()
                }
            )
        } else if appState.iosConnected {
            // 清除帧回调
            appState.iosDeviceSource?.onFrame = nil
            appState.iosDeviceSource?.onSessionInterrupted = nil
            appState.iosDeviceSource?.onSessionResumed = nil

            panel.showConnected(
                deviceName: appState.iosDeviceName ?? "iPhone",
                platform: .ios,
                userPrompt: appState.iosDeviceUserPrompt,
                onStart: { [weak self] in
                    self?.startIOSCapture()
                }
            )
            panel.renderView.clearTexture()
        } else {
            panel.showDisconnected(platform: .ios, connectionGuide: L10n.overlayUI.connectIOS)
            panel.renderView.clearTexture()
        }
    }

    // MARK: - 操作

    private func startIOSCapture() {
        Task {
            do {
                try await AppState.shared.startIOSCapture()
            } catch {
                showError(L10n.error.startCaptureFailed(L10n.platform.ios, error.localizedDescription))
            }
        }
    }

    private func stopIOSCapture() {
        Task {
            await AppState.shared.stopIOSCapture()
            await MainActor.run {
                ToastView.info(L10n.overlayUI.captureStopped(L10n.platform.ios), in: view.window)
            }
        }
    }

    private func startAndroidCapture() {
        Task {
            do {
                try await AppState.shared.startAndroidCapture()
            } catch {
                showError(L10n.error.startCaptureFailed(L10n.platform.android, error.localizedDescription))
            }
        }
    }

    private func stopAndroidCapture() {
        Task {
            await AppState.shared.stopAndroidCapture()
            await MainActor.run {
                ToastView.info(L10n.overlayUI.captureStopped(L10n.platform.android), in: view.window)
            }
        }
    }

    private func installScrcpy() {
        Task {
            await AppState.shared.toolchainManager.installScrcpy()
            updateUI()
        }
    }

    private func showError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = L10n.common.error
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: L10n.common.ok)
        alert.runModal()
    }

    // MARK: - 窗口事件

    func handleWindowResize() {
        iosPanelView.needsLayout = true
        androidPanelView.needsLayout = true
    }

    func handleFullScreenChange(isFullScreen: Bool) {
        self.isFullScreen = isFullScreen

        // 更新背景色
        if isFullScreen {
            // 全屏时使用用户偏好的黑色+透明度
            let bgColor = UserPreferences.shared.backgroundColor.cgColor
            view.layer?.backgroundColor = bgColor
            previewContainerView.layer?.backgroundColor = bgColor
        } else {
            // 非全屏时使用默认背景色
            view.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
            previewContainerView.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        }

        // 更新 titlebar 显示状态（全屏时隐藏 toolbar）
        updateTitlebarVisibility(animated: false)

        // 更新面板布局（包含上下缩进）
        updatePanelLayout()

        // 根据鼠标实际位置更新状态，然后更新按钮可见性
        updateMouseInSwapAreaState()
        updateSwapButtonVisibility()
    }

    // MARK: - 语言变更

    /// 更新本地化文本（语言切换时调用）
    func updateLocalizedTexts() {
        // 更新交换按钮的 tooltip
        swapButton.toolTip = L10n.toolbar.swapTooltip

        // 更新设备面板的本地化文本
        iosPanelView.updateLocalizedTexts()
        androidPanelView.updateLocalizedTexts()
    }
}

// MARK: - NSImage 扩展

private extension NSImage {
    /// 将图像着色为指定颜色
    func tinted(with color: NSColor) -> NSImage {
        let image = copy() as! NSImage
        image.lockFocus()
        color.set()
        let imageRect = NSRect(origin: .zero, size: image.size)
        imageRect.fill(using: .sourceAtop)
        image.unlockFocus()
        return image
    }
}
