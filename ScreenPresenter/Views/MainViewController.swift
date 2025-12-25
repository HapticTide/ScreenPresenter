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

    private var previewContainerView: PreviewContainerView!

    // MARK: - 设备面板快捷访问

    /// iOS 面板（默认在左侧）
    private var iosPanelView: DevicePanelView { previewContainerView.iosPanelView }
    /// Android 面板（默认在右侧）
    private var androidPanelView: DevicePanelView { previewContainerView.androidPanelView }

    // MARK: - 鼠标追踪

    private var swapButtonTrackingArea: NSTrackingArea?
    private var isMouseInSwapArea: Bool = false

    // MARK: - 状态

    private var cancellables = Set<AnyCancellable>()
    private var isFullScreen: Bool = false

    // MARK: - 生命周期

    override func loadView() {
        view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        setupUI()
        setupBindings()
        startRendering()

        // 从偏好设置读取默认设备位置
        if !UserPreferences.shared.iosOnLeft {
            previewContainerView.swapPanels(animated: false)
        }

        // 应用初始 bezel 可见性设置
        previewContainerView.updateBezelVisibility()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        // 视图已添加到窗口，可以正确获取 titlebar 高度
        updatePreviewContainerTopConstraint()
    }

    override func viewWillDisappear() {
        super.viewWillDisappear()
        stopRendering()
    }

    // MARK: - UI 设置

    private func setupUI() {
        setupPreviewContainer()
        setupSwapButtonTracking()
        updatePanelLayout()
    }

    private func setupPreviewContainer() {
        previewContainerView = PreviewContainerView()
        // 非全屏时使用默认背景色，全屏时使用用户偏好的黑色+透明度
        previewContainerView.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        view.addSubview(previewContainerView)
        previewContainerView.snp.makeConstraints { make in
            // 顶部留出 titlebar 区域
            // 初始使用 0，在 viewDidAppear 中会更新为正确的 titlebar 高度
            make.top.equalToSuperview()
            make.leading.trailing.bottom.equalToSuperview()
        }
    }

    /// 动态获取 titlebar 高度
    private var titlebarHeight: CGFloat {
        guard let window = view.window else {
            // 默认值：macOS 标准 titlebar 高度
            return 28
        }
        // contentLayoutRect 是内容区域的矩形，不包含 titlebar
        // titlebar 高度 = 窗口高度 - 内容区域高度
        let contentHeight = window.contentLayoutRect.height
        let windowHeight = window.frame.height
        return windowHeight - contentHeight
    }

    /// 交换按钮（委托给 previewContainerView）
    private var swapButton: NSButton { previewContainerView.swapButton }

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

    /// 确保 toolbar 可见（退出全屏后调用）
    func ensureToolbarVisible() {
        guard !isFullScreen, let window = view.window else { return }
        window.toolbar?.isVisible = true
    }

    private func updatePreviewContainerTopConstraint() {
        // 全屏时内容区域延伸到顶部，非全屏时留出 titlebar 区域
        let topOffset: CGFloat = isFullScreen ? 0 : titlebarHeight

        previewContainerView.snp.remakeConstraints { make in
            make.top.equalToSuperview().offset(topOffset)
            make.leading.trailing.bottom.equalToSuperview()
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

    private func updatePanelLayout(animated: Bool = true) {
        // 更新面板内容
        updateAndroidPanel(androidPanelView)
        updateIOSPanel(iosPanelView)

        // 委托给 previewContainerView 处理布局
        previewContainerView.updateLayout(animated: animated)
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

        // 监听 bezel 可见性变化
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleBezelVisibilityChange),
            name: .deviceBezelVisibilityDidChange,
            object: nil
        )
    }

    @objc private func handleBezelVisibilityChange() {
        previewContainerView.updateBezelVisibility()
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
            // 设置帧回调，每个新帧到来时更新纹理
            appState.androidDeviceSource?.onFrame = { [weak panel] pixelBuffer in
                panel?.renderView.updateTexture(from: pixelBuffer)
            }

            panel.showCapturing(
                deviceName: appState.androidDeviceName ?? "Android",
                modelName: appState.androidDeviceModelName,
                systemVersion: appState.androidDeviceSystemVersion,
                sdkVersion: appState.androidDeviceSdkVersion,
                platform: .android,
                fps: panel.renderView.fps,
                resolution: appState.androidDeviceSource?.captureSize ?? .zero,
                androidDevice: appState.currentAndroidDevice,
                onStop: { [weak self] in
                    self?.stopAndroidCapture()
                }
            )
        } else if appState.androidConnected {
            // 清除帧回调
            appState.androidDeviceSource?.onFrame = nil
            // 检查设备是否已授权（state == .device）
            let isDeviceReady = appState.androidDeviceReady
            let userPrompt = appState.androidDeviceUserPrompt

            panel.showConnected(
                deviceName: appState.androidDeviceName ?? "Android",
                platform: .android,
                modelName: appState.androidDeviceModelName,
                systemVersion: appState.androidDeviceSystemVersion,
                sdkVersion: appState.androidDeviceSdkVersion,
                userPrompt: userPrompt,
                androidDevice: appState.currentAndroidDevice,
                onStart: { [weak self] in
                    // 只有设备已授权才允许捕获
                    if isDeviceReady {
                        self?.startAndroidCapture()
                    }
                },
                onRefresh: { [weak self] completion in
                    self?.refreshAndroidDeviceInfo(completion: completion)
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

        if appState.iosCapturing, let device = appState.currentIOSDevice {
            // 设置帧回调，每个新帧到来时更新纹理
            appState.iosDeviceSource?.onFrame = { [weak panel] pixelBuffer in
                panel?.renderView.updateTexture(from: pixelBuffer)
            }

            // 使用 IOSDevice 的 productType 精确识别设备型号
            panel.showCapturing(
                device: device,
                fps: panel.renderView.fps,
                resolution: appState.iosDeviceSource?.captureSize ?? .zero,
                onStop: { [weak self] in
                    self?.stopIOSCapture()
                }
            )
        } else if let device = appState.currentIOSDevice {
            // 清除帧回调
            appState.iosDeviceSource?.onFrame = nil

            // 获取设备详细信息
            // 使用 IOSDevice 的 productType 精确识别设备型号
            panel.showConnected(
                device: device,
                onStart: { [weak self] in
                    self?.startIOSCapture()
                },
                onRefresh: { [weak self] completion in
                    self?.refreshIOSDeviceInfo(completion: completion)
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
                await MainActor.run {
                    iosPanelView.stopActionLoading()
                }
                showError(L10n.error.startCaptureFailed(L10n.platform.ios, error.localizedDescription))
            }
        }
    }

    private func stopIOSCapture() {
        Task {
            await AppState.shared.stopIOSCapture()
            await MainActor.run {
                ToastView.info(L10n.overlayUI.captureStopped(L10n.platform.ios), in: iosPanelView)
            }
        }
    }

    private func refreshIOSDeviceInfo(completion: @escaping () -> Void) {
        // 只刷新当前设备的信息（不刷新设备列表）
        let appState = AppState.shared
        guard let currentDevice = appState.iosDeviceProvider.devices.first else {
            completion()
            return
        }

        // 异步刷新设备信息
        Task {
            // 使用 DeviceInsightService 刷新当前设备的信息
            let insight = DeviceInsightService.shared.refresh(udid: currentDevice.avUniqueID)

            await MainActor.run {
                // 更新 IOSDeviceProvider 中的当前设备信息
                appState.iosDeviceProvider.updateDevice(currentDevice.enriched(with: insight))

                // 触发 UI 更新
                updateUI()

                // 显示刷新成功提示（在 iOS 面板上弹出）
                ToastView.success(L10n.toolbar.deviceInfoRefreshed, in: iosPanelView)

                // 完成回调
                completion()
            }
        }
    }

    private func refreshAndroidDeviceInfo(completion: @escaping () -> Void) {
        // 刷新 Android 设备列表
        let appState = AppState.shared

        Task {
            await appState.androidDeviceProvider.refreshDevices()

            await MainActor.run {
                // 触发 UI 更新
                updateUI()

                // 显示刷新成功提示
                ToastView.success(L10n.toolbar.deviceInfoRefreshed, in: androidPanelView)

                // 完成回调
                completion()
            }
        }
    }

    private func startAndroidCapture() {
        Task {
            do {
                try await AppState.shared.startAndroidCapture()
            } catch {
                await MainActor.run {
                    androidPanelView.stopActionLoading()
                }
                showError(L10n.error.startCaptureFailed(L10n.platform.android, error.localizedDescription))
            }
        }
    }

    private func stopAndroidCapture() {
        Task {
            await AppState.shared.stopAndroidCapture()
            await MainActor.run {
                ToastView.info(L10n.overlayUI.captureStopped(L10n.platform.android), in: androidPanelView)
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
        // 窗口大小变化时重新计算面板布局（基于新的容器尺寸和 aspectRatio）
        updatePanelLayout(animated: false)
    }

    func handleFullScreenChange(isFullScreen: Bool) {
        self.isFullScreen = isFullScreen
        previewContainerView.isFullScreen = isFullScreen

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

        // 更新面板布局（禁用动画，让系统全屏动画统一控制）
        updatePanelLayout(animated: false)

        // 根据鼠标实际位置更新状态，然后更新按钮可见性
        updateMouseInSwapAreaState()
        updateSwapButtonVisibility()
    }

    // MARK: - 语言变更

    /// 更新本地化文本（语言切换时调用）
    func updateLocalizedTexts() {
        previewContainerView.updateLocalizedTexts()
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
