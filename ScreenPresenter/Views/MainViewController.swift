//
//  MainViewController.swift
//  ScreenPresenter
//
//  Created by Sun on 2025/12/22.
//
//  主视图控制器（纯 AppKit）
//  包含工具栏、预览区域和状态栏
//

import AppKit
import Combine

// MARK: - 主视图控制器

final class MainViewController: NSViewController {
    // MARK: - UI 组件

    private var toolbarView: ToolbarView!
    private var renderView: MetalRenderView!
    private var statusBar: StatusBarView!

    // MARK: - 叠加层

    private var leftOverlayView: DeviceOverlayView!
    private var rightOverlayView: DeviceOverlayView!

    // MARK: - 状态

    private var cancellables = Set<AnyCancellable>()

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
    }

    override func viewWillDisappear() {
        super.viewWillDisappear()
        renderView.stopRendering()
    }

    // MARK: - UI 设置

    private func setupUI() {
        // 工具栏
        toolbarView = ToolbarView()
        toolbarView.translatesAutoresizingMaskIntoConstraints = false
        toolbarView.delegate = self
        view.addSubview(toolbarView)

        // Metal 渲染视图
        renderView = MetalRenderView()
        renderView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(renderView)

        // 设备叠加层
        leftOverlayView = DeviceOverlayView()
        leftOverlayView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(leftOverlayView)

        rightOverlayView = DeviceOverlayView()
        rightOverlayView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(rightOverlayView)

        // 状态栏
        statusBar = StatusBarView()
        statusBar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(statusBar)

        // 约束
        NSLayoutConstraint.activate([
            // 工具栏
            toolbarView.topAnchor.constraint(equalTo: view.topAnchor),
            toolbarView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            toolbarView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            toolbarView.heightAnchor.constraint(equalToConstant: 44),

            // 渲染视图
            renderView.topAnchor.constraint(equalTo: toolbarView.bottomAnchor),
            renderView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            renderView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            renderView.bottomAnchor.constraint(equalTo: statusBar.topAnchor),

            // 左侧叠加层
            leftOverlayView.topAnchor.constraint(equalTo: renderView.topAnchor, constant: 8),
            leftOverlayView.leadingAnchor.constraint(equalTo: renderView.leadingAnchor, constant: 8),
            leftOverlayView.widthAnchor.constraint(equalTo: renderView.widthAnchor, multiplier: 0.5, constant: -12),

            // 右侧叠加层
            rightOverlayView.topAnchor.constraint(equalTo: renderView.topAnchor, constant: 8),
            rightOverlayView.trailingAnchor.constraint(equalTo: renderView.trailingAnchor, constant: -8),
            rightOverlayView.widthAnchor.constraint(equalTo: renderView.widthAnchor, multiplier: 0.5, constant: -12),

            // 状态栏
            statusBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            statusBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            statusBar.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            statusBar.heightAnchor.constraint(equalToConstant: 24),
        ])

        // 初始状态
        updateOverlays()
    }

    // MARK: - 绑定

    private func setupBindings() {
        // 监听应用状态变化
        AppState.shared.stateChangedPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                self?.updateUI()
            }
            .store(in: &cancellables)

        // 渲染帧回调
        renderView.onRenderFrame = { [weak self] in
            self?.updateTextures()
        }
    }

    // MARK: - 渲染

    private func startRendering() {
        renderView.startRendering()
    }

    /// 更新纹理
    private func updateTextures() {
        // 更新 iOS 纹理（左侧）
        if let pixelBuffer = AppState.shared.iosDeviceSource?.latestPixelBuffer {
            renderView.updateLeftTexture(from: pixelBuffer)
        }

        // 更新 Android 纹理（右侧）
        if let pixelBuffer = AppState.shared.androidDeviceSource?.latestPixelBuffer {
            renderView.updateRightTexture(from: pixelBuffer)
        }
    }

    // MARK: - UI 更新

    private func updateUI() {
        updateOverlays()
        updateStatusBar()
    }

    private func updateOverlays() {
        let appState = AppState.shared

        // 左侧：iOS 设备
        if appState.iosCapturing {
            leftOverlayView.showCapturing(
                deviceName: appState.iosDeviceName ?? "iOS",
                fps: renderView.leftFPS
            )
        } else if appState.iosConnected {
            leftOverlayView.showConnected(
                deviceName: appState.iosDeviceName ?? "iOS",
                platform: .ios,
                onStart: { [weak self] in
                    self?.startIOSCapture()
                }
            )
        } else {
            leftOverlayView.showDisconnected(platform: .ios)
        }

        // 右侧：Android 设备
        if appState.androidCapturing {
            rightOverlayView.showCapturing(
                deviceName: appState.androidDeviceName ?? "Android",
                fps: renderView.rightFPS
            )
        } else if appState.androidConnected {
            rightOverlayView.showConnected(
                deviceName: appState.androidDeviceName ?? "Android",
                platform: .android,
                onStart: { [weak self] in
                    self?.startAndroidCapture()
                }
            )
        } else {
            rightOverlayView.showDisconnected(platform: .android)
        }
    }

    private func updateStatusBar() {
        let appState = AppState.shared

        var statusParts: [String] = []

        if appState.iosConnected {
            let status = appState.iosCapturing ? "捕获中" : "已连接"
            statusParts.append("iOS: \(status)")
        }

        if appState.androidConnected {
            let status = appState.androidCapturing ? "捕获中" : "已连接"
            statusParts.append("Android: \(status)")
        }

        if statusParts.isEmpty {
            statusBar.setStatus("等待设备连接...")
        } else {
            statusBar.setStatus(statusParts.joined(separator: " | "))
        }

        // 显示帧率
        if appState.iosCapturing || appState.androidCapturing {
            let leftFPS = Int(renderView.leftFPS)
            let rightFPS = Int(renderView.rightFPS)
            statusBar.setFPS(left: leftFPS, right: rightFPS)
        } else {
            statusBar.setFPS(left: 0, right: 0)
        }
    }

    // MARK: - 操作

    private func startIOSCapture() {
        Task {
            do {
                try await AppState.shared.startIOSCapture()
            } catch {
                showError("启动 iOS 捕获失败: \(error.localizedDescription)")
            }
        }
    }

    private func startAndroidCapture() {
        Task {
            do {
                try await AppState.shared.startAndroidCapture()
            } catch {
                showError("启动 Android 捕获失败: \(error.localizedDescription)")
            }
        }
    }

    private func showError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "错误"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "确定")
        alert.runModal()
    }

    // MARK: - 窗口事件

    func handleWindowResize() {
        // 更新渲染视图
        renderView.needsDisplay = true
    }
}

// MARK: - 工具栏代理

extension MainViewController: ToolbarViewDelegate {
    func toolbarDidRequestRefresh() {
        Task {
            await AppState.shared.refreshDevices()
        }
    }

    func toolbarDidChangeLayout(_ layout: LayoutMode) {
        renderView.setLayoutMode(layout)
    }

    func toolbarDidToggleSwap(_ swapped: Bool) {
        renderView.setSwapped(swapped)

        // 交换叠加层
        let temp = leftOverlayView.frame
        leftOverlayView.frame = rightOverlayView.frame
        rightOverlayView.frame = temp
    }

    func toolbarDidRequestPreferences() {
        PreferencesWindowController.shared.showWindow(nil)
    }
}
