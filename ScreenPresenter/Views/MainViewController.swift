//
//  MainViewController.swift
//  ScreenPresenter
//
//  Created by Sun on 2025/12/22.
//
//  主视图控制器
//  包含工具栏和预览区域
//

import AppKit
import Combine
import SnapKit

// MARK: - 主视图控制器

final class MainViewController: NSViewController {
    // MARK: - UI 组件

    private var toolbarView: ToolbarView!
    private var previewContainerView: NSView!
    private var renderView: MetalRenderView!

    // MARK: - 设备面板

    /// Android 面板（默认在左侧/上方）
    private var androidPanelView: DevicePanelView!
    /// iOS 面板（默认在右侧/下方）
    private var iosPanelView: DevicePanelView!
    private var dividerView: NSBox!

    // MARK: - 状态

    private var cancellables = Set<AnyCancellable>()
    private var currentLayout: LayoutMode = .sideBySide
    private var isSwapped: Bool = false

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

        // 延迟初始化渲染区域（等待初始布局完成）
        DispatchQueue.main.async { [weak self] in
            self?.updateRenderScreenFrames()
        }
    }

    override func viewWillDisappear() {
        super.viewWillDisappear()
        renderView.stopRendering()
    }

    // MARK: - UI 设置

    private func setupUI() {
        setupToolbar()
        setupPreviewContainer()
        setupDevicePanels()
        updatePanelLayout()
    }

    private func setupToolbar() {
        toolbarView = ToolbarView()
        toolbarView.delegate = self
        view.addSubview(toolbarView)
        toolbarView.snp.makeConstraints { make in
            make.top.leading.trailing.equalToSuperview()
            make.height.equalTo(44)
        }
    }

    private func setupPreviewContainer() {
        previewContainerView = NSView()
        previewContainerView.wantsLayer = true
        previewContainerView.layer?.backgroundColor = UserPreferences.shared.backgroundColor.cgColor
        view.addSubview(previewContainerView)
        previewContainerView.snp.makeConstraints { make in
            make.top.equalTo(toolbarView.snp.bottom)
            make.leading.trailing.bottom.equalToSuperview()
        }

        renderView = MetalRenderView()
        previewContainerView.addSubview(renderView)
        renderView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
    }

    private func setupDevicePanels() {
        androidPanelView = DevicePanelView()
        previewContainerView.addSubview(androidPanelView)

        iosPanelView = DevicePanelView()
        previewContainerView.addSubview(iosPanelView)

        dividerView = NSBox()
        dividerView.boxType = .custom
        dividerView.fillColor = NSColor.separatorColor
        dividerView.borderWidth = 0
        dividerView.contentViewMargins = .zero
        previewContainerView.addSubview(dividerView)
    }

    private func updatePanelLayout() {
        // 更新面板内容
        updateAndroidPanel(androidPanelView)
        updateIOSPanel(iosPanelView)

        // 重置约束
        androidPanelView.snp.removeConstraints()
        iosPanelView.snp.removeConstraints()
        dividerView.snp.removeConstraints()

        // 根据 isSwapped 决定哪个面板在主位置（左/上）
        let primaryPanel = isSwapped ? iosPanelView! : androidPanelView!
        let secondaryPanel = isSwapped ? androidPanelView! : iosPanelView!

        switch currentLayout {
        case .sideBySide:
            primaryPanel.snp.makeConstraints { make in
                make.top.leading.bottom.equalToSuperview()
                make.width.equalToSuperview().multipliedBy(0.5).offset(-0.5)
            }

            dividerView.snp.makeConstraints { make in
                make.centerX.top.bottom.equalToSuperview()
                make.width.equalTo(1)
            }

            secondaryPanel.snp.makeConstraints { make in
                make.top.trailing.bottom.equalToSuperview()
                make.width.equalToSuperview().multipliedBy(0.5).offset(-0.5)
            }

            secondaryPanel.isHidden = false
            dividerView.isHidden = false

        case .topBottom:
            primaryPanel.snp.makeConstraints { make in
                make.top.leading.trailing.equalToSuperview()
                make.height.equalToSuperview().multipliedBy(0.5).offset(-0.5)
            }

            dividerView.snp.makeConstraints { make in
                make.centerY.leading.trailing.equalToSuperview()
                make.height.equalTo(1)
            }

            secondaryPanel.snp.makeConstraints { make in
                make.bottom.leading.trailing.equalToSuperview()
                make.height.equalToSuperview().multipliedBy(0.5).offset(-0.5)
            }

            secondaryPanel.isHidden = false
            dividerView.isHidden = false

        case .single:
            primaryPanel.snp.makeConstraints { make in
                make.edges.equalToSuperview()
            }

            secondaryPanel.isHidden = true
            dividerView.isHidden = true
        }

        // 动画
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            context.allowsImplicitAnimation = true
            previewContainerView.layoutSubtreeIfNeeded()
        } completionHandler: { [weak self] in
            // 布局完成后更新渲染区域
            self?.updateRenderScreenFrames()
        }
    }

    /// 更新渲染器的屏幕区域
    private func updateRenderScreenFrames() {
        let primaryPanel = isSwapped ? iosPanelView! : androidPanelView!
        let secondaryPanel = isSwapped ? androidPanelView! : iosPanelView!

        // 获取面板的屏幕区域并转换为 renderView 的坐标系
        let primaryFrame = primaryPanel.convert(primaryPanel.screenFrame, to: renderView)
        renderView.setPrimaryScreenFrame(primaryFrame)

        if currentLayout != .single {
            let secondaryFrame = secondaryPanel.convert(secondaryPanel.screenFrame, to: renderView)
            renderView.setSecondaryScreenFrame(secondaryFrame)
        } else {
            renderView.setSecondaryScreenFrame(.zero)
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

        renderView.onRenderFrame = { [weak self] in
            self?.updateTextures()
        }

        // 监听背景色变化
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleBackgroundColorChange),
            name: .backgroundColorDidChange,
            object: nil
        )
    }

    @objc private func handleBackgroundColorChange() {
        previewContainerView.layer?.backgroundColor = UserPreferences.shared.backgroundColor.cgColor
    }

    // MARK: - 渲染

    private func startRendering() {
        renderView.startRendering()
    }

    private func updateTextures() {
        if let pixelBuffer = AppState.shared.iosDeviceSource?.latestPixelBuffer {
            if isSwapped {
                renderView.updateLeftTexture(from: pixelBuffer)
            } else {
                renderView.updateRightTexture(from: pixelBuffer)
            }
        }

        if let pixelBuffer = AppState.shared.androidDeviceSource?.latestPixelBuffer {
            if isSwapped {
                renderView.updateRightTexture(from: pixelBuffer)
            } else {
                renderView.updateLeftTexture(from: pixelBuffer)
            }
        }
    }

    // MARK: - UI 更新

    private func updateUI() {
        updateAndroidPanel(androidPanelView)
        updateIOSPanel(iosPanelView)
    }

    private func updateAndroidPanel(_ panel: DevicePanelView) {
        let appState = AppState.shared
        let scrcpyReady = appState.toolchainManager.scrcpyStatus.isReady
        // Android texture 位置: !isSwapped -> left, isSwapped -> right
        let androidFPS = isSwapped ? renderView.rightFPS : renderView.leftFPS

        if !scrcpyReady {
            panel.showToolchainMissing(toolName: "scrcpy") { [weak self] in
                self?.installScrcpy()
            }
        } else if appState.androidCapturing {
            panel.showCapturing(
                deviceName: appState.androidDeviceName ?? "Android",
                platform: .android,
                fps: androidFPS,
                resolution: appState.androidDeviceSource?.captureSize ?? .zero,
                onStop: { [weak self] in
                    self?.stopAndroidCapture()
                }
            )
        } else if appState.androidConnected {
            panel.showConnected(
                deviceName: appState.androidDeviceName ?? "Android",
                platform: .android,
                onStart: { [weak self] in
                    self?.startAndroidCapture()
                }
            )
        } else {
            panel.showDisconnected(platform: .android, connectionGuide: L10n.overlayUI.connectAndroid)
        }
    }

    private func updateIOSPanel(_ panel: DevicePanelView) {
        let appState = AppState.shared
        // iOS texture 位置: !isSwapped -> right, isSwapped -> left
        let iosFPS = isSwapped ? renderView.leftFPS : renderView.rightFPS

        if appState.iosCapturing {
            panel.showCapturing(
                deviceName: appState.iosDeviceName ?? "iPhone",
                platform: .ios,
                fps: iosFPS,
                resolution: appState.iosDeviceSource?.captureSize ?? .zero,
                onStop: { [weak self] in
                    self?.stopIOSCapture()
                }
            )
        } else if appState.iosConnected {
            panel.showConnected(
                deviceName: appState.iosDeviceName ?? "iPhone",
                platform: .ios,
                userPrompt: appState.iosDeviceUserPrompt,
                onStart: { [weak self] in
                    self?.startIOSCapture()
                }
            )
        } else {
            panel.showDisconnected(platform: .ios, connectionGuide: L10n.overlayUI.connectIOS)
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
        renderView.needsDisplay = true
        // 延迟更新屏幕区域，等待布局完成
        DispatchQueue.main.async { [weak self] in
            self?.updateRenderScreenFrames()
        }
    }
}

// MARK: - 工具栏代理

extension MainViewController: ToolbarViewDelegate {
    func toolbarDidRequestRefresh() {
        Task {
            await AppState.shared.refreshDevices()
            toolbarView.setRefreshing(false)
        }
    }

    func toolbarDidChangeLayout(_ layout: LayoutMode) {
        currentLayout = layout
        renderView.setLayoutMode(layout)
        updatePanelLayout()
    }

    func toolbarDidToggleSwap(_ swapped: Bool) {
        isSwapped = swapped
        renderView.setSwapped(swapped)
        updatePanelLayout()
    }

    func toolbarDidRequestPreferences() {
        PreferencesWindowController.shared.showWindow(nil)
    }
}
