//
//  DeviceCaptureInfoView.swift
//  ScreenPresenter
//
//  Created by Sun on 2025/12/25.
//
//  捕获信息视图
//  覆盖整个屏幕区域，显示设备名称、型号、分辨率、FPS 等信息
//

import AppKit
import SnapKit

// MARK: - 捕获信息视图

final class DeviceCaptureInfoView: NSView {
    // MARK: - UI 组件

    /// 内容容器（居中显示所有元素）
    private var contentContainer: NSView!
    /// 设备名称
    private var deviceNameLabel: NSTextField!
    /// 设备详细信息（型号 · 系统版本）
    private var deviceInfoLabel: NSTextField!
    /// 分辨率
    private var resolutionLabel: NSTextField!
    /// FPS
    private var fpsLabel: NSTextField!
    /// 停止按钮容器
    private var stopButtonContainer: NSView!
    /// 停止按钮图标
    private var stopButtonIcon: NSImageView!
    /// 顶部状态栏（captureIndicator + fpsLabel）
    private var topStatusBar: NSView!

    // MARK: - 字体配置

    /// 设备名称标签的基准字体大小
    private let deviceNameBaseFontSize: CGFloat = 22
    /// 设备名称标签的最小字体大小
    private let deviceNameMinFontSize: CGFloat = 16
    /// 设备名称标签的基准字体大小
    private let deviceInfoBaseFontSize: CGFloat = 16
    /// 设备名称标签的最小字体大小
    private let deviceInfoMinFontSize: CGFloat = 12
    
    // MARK: - 回调

    var onStopTapped: (() -> Void)?

    // MARK: - 自动隐藏

    private var autoHideTimer: Timer?
    /// 自动隐藏延时（秒）
    private let autoHideDelay: TimeInterval = 3.0

    // MARK: - 初始化

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupUI()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
    }

    deinit {
        cancelAutoHide()
    }

    // MARK: - UI 设置

    private func setupUI() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.65).cgColor

        setupContentContainer()
        setupTopStatusBar()
        setupDeviceLabels()
        setupStopButton()
    }

    private func setupContentContainer() {
        contentContainer = NSView()
        addSubview(contentContainer)
        contentContainer.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.leading.greaterThanOrEqualToSuperview().offset(20)
            make.trailing.lessThanOrEqualToSuperview().offset(-20)
        }
    }

    private func setupTopStatusBar() {
        // 顶部状态栏：fpsLabel
        topStatusBar = NSView()
        contentContainer.addSubview(topStatusBar)
        topStatusBar.snp.makeConstraints { make in
            make.top.equalToSuperview()
            make.centerX.equalToSuperview()
            make.width.greaterThanOrEqualTo(200)
        }

        // FPS（中间）
        fpsLabel = NSTextField(labelWithString: "")
        fpsLabel.font = NSFont.monospacedSystemFont(ofSize: 14, weight: .medium)
        fpsLabel.textColor = .white
        fpsLabel.alignment = .center
        topStatusBar.addSubview(fpsLabel)
        fpsLabel.snp.makeConstraints { make in
            make.top.bottom.equalToSuperview()
            make.centerX.equalToSuperview()
        }
    }

    private func setupDeviceLabels() {
        // 分辨率（第二行，居中）
        resolutionLabel = NSTextField(labelWithString: "")
        resolutionLabel.font = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        resolutionLabel.textColor = NSColor.white.withAlphaComponent(0.8)
        resolutionLabel.alignment = .center
        contentContainer.addSubview(resolutionLabel)
        resolutionLabel.snp.makeConstraints { make in
            make.top.equalTo(topStatusBar.snp.bottom).offset(20)
            make.centerX.equalToSuperview()
            make.leading.greaterThanOrEqualToSuperview()
            make.trailing.lessThanOrEqualToSuperview()
        }

        // 设备名称（第三行，居中）
        deviceNameLabel = NSTextField(labelWithString: "")
        deviceNameLabel.font = NSFont.systemFont(ofSize: 22, weight: .semibold)
        deviceNameLabel.textColor = .white
        deviceNameLabel.alignment = .center
        deviceNameLabel.lineBreakMode = .byTruncatingTail
        deviceNameLabel.maximumNumberOfLines = 1
        contentContainer.addSubview(deviceNameLabel)
        deviceNameLabel.snp.makeConstraints { make in
            make.top.equalTo(resolutionLabel.snp.bottom).offset(16)
            make.centerX.equalToSuperview()
            make.leading.greaterThanOrEqualToSuperview()
            make.trailing.lessThanOrEqualToSuperview()
        }

        // 设备详细信息（第四行，居中）
        deviceInfoLabel = NSTextField(labelWithString: "")
        deviceInfoLabel.font = NSFont.systemFont(ofSize: 16, weight: .regular)
        deviceInfoLabel.textColor = NSColor.white.withAlphaComponent(0.7)
        deviceInfoLabel.alignment = .center
        deviceInfoLabel.lineBreakMode = .byTruncatingTail
        deviceInfoLabel.maximumNumberOfLines = 1
        contentContainer.addSubview(deviceInfoLabel)
        deviceInfoLabel.snp.makeConstraints { make in
            make.top.equalTo(deviceNameLabel.snp.bottom).offset(16)
            make.centerX.equalToSuperview()
            make.leading.greaterThanOrEqualToSuperview()
            make.trailing.lessThanOrEqualToSuperview()
        }
    }

    private func setupStopButton() {
        // 停止按钮容器（圆形背景）
        stopButtonContainer = NSView()
        stopButtonContainer.wantsLayer = true
        stopButtonContainer.layer?.cornerRadius = 24
        stopButtonContainer.layer?.backgroundColor = NSColor.appDanger.cgColor

        // 添加点击手势
        let clickGesture = NSClickGestureRecognizer(target: self, action: #selector(stopTapped))
        stopButtonContainer.addGestureRecognizer(clickGesture)

        // 添加鼠标悬停效果
        let trackingArea = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
            owner: self,
            userInfo: ["view": "stopButton"]
        )
        stopButtonContainer.addTrackingArea(trackingArea)

        contentContainer.addSubview(stopButtonContainer)
        stopButtonContainer.snp.makeConstraints { make in
            make.top.equalTo(deviceInfoLabel.snp.bottom).offset(24)
            make.centerX.equalToSuperview()
            make.width.height.equalTo(48)
            make.bottom.equalToSuperview()
        }

        // 停止图标
        let config = NSImage.SymbolConfiguration(pointSize: 18, weight: .bold)
        let stopImage = NSImage(
            systemSymbolName: "stop.fill",
            accessibilityDescription: L10n.overlayUI.stop
        )?.withSymbolConfiguration(config)

        stopButtonIcon = NSImageView(image: stopImage ?? NSImage())
        stopButtonIcon.contentTintColor = .white
        stopButtonContainer.addSubview(stopButtonIcon)
        stopButtonIcon.snp.makeConstraints { make in
            make.center.equalToSuperview()
        }
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        if
            let userInfo = event.trackingArea?.userInfo as? [String: String],
            userInfo["view"] == "stopButton" {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.15
                stopButtonContainer.animator().alphaValue = 0.8
            }
        }
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        if
            let userInfo = event.trackingArea?.userInfo as? [String: String],
            userInfo["view"] == "stopButton" {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.15
                stopButtonContainer.animator().alphaValue = 1.0
            }
        }
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
        let titleFont = deviceNameLabel.stringValue.calculateFittingFont(
            baseSize: deviceNameBaseFontSize,
            minSize: deviceNameMinFontSize,
            weight: .semibold,
            availableWidth: availableWidth
        )
        deviceNameLabel.font = titleFont

        // 更新副标题标签字体
        let subtitleFont = deviceInfoLabel.stringValue.calculateFittingFont(
            baseSize: deviceInfoBaseFontSize,
            minSize: deviceInfoMinFontSize,
            weight: .regular,
            availableWidth: availableWidth
        )
        deviceInfoLabel.font = subtitleFont
    }
    
    // MARK: - 公开方法

    /// 更新设备信息
    /// - Parameters:
    ///   - deviceName: 设备名称
    ///   - deviceInfo: 设备详情（型号 · 系统版本）
    func updateDeviceInfo(deviceName: String, deviceInfo: String) {
        deviceNameLabel.stringValue = deviceName
        deviceInfoLabel.stringValue = deviceInfo
        deviceInfoLabel.isHidden = deviceInfo.isEmpty
        
        needsLayout = true
    }

    /// 更新分辨率
    func updateResolution(_ resolution: CGSize) {
        if resolution.width > 0, resolution.height > 0 {
            resolutionLabel.stringValue = "\(Int(resolution.width))×\(Int(resolution.height))"
        } else {
            resolutionLabel.stringValue = ""
        }
    }

    /// 更新 FPS
    func updateFPS(_ fps: Double) {
        if fps > 0 {
            fpsLabel.stringValue = String(format: "%.0f FPS", fps)

            // 根据帧率调整颜色
            if fps >= 30 {
                fpsLabel.textColor = NSColor.systemGreen
            } else if fps >= 15 {
                fpsLabel.textColor = NSColor.systemOrange
            } else {
                fpsLabel.textColor = NSColor.systemRed
            }
        } else {
            fpsLabel.stringValue = ""
        }
    }

    // MARK: - 显示/隐藏控制

    /// 显示视图（带淡入动画）
    func showAnimated(autoHide: Bool = false) {
        cancelAutoHide()

        isHidden = false
        alphaValue = 0

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            self.animator().alphaValue = 1.0
        } completionHandler: { [weak self] in
            if autoHide {
                self?.scheduleAutoHide()
            }
        }
    }

    /// 隐藏视图（带淡出动画）
    func hideAnimated() {
        cancelAutoHide()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            self.animator().alphaValue = 0.0
        } completionHandler: { [weak self] in
            self?.isHidden = true
        }
    }

    /// 计划自动隐藏
    func scheduleAutoHide() {
        cancelAutoHide()
        autoHideTimer = Timer.scheduledTimer(withTimeInterval: autoHideDelay, repeats: false) { [weak self] _ in
            self?.hideAnimated()
        }
    }

    /// 取消自动隐藏
    func cancelAutoHide() {
        autoHideTimer?.invalidate()
        autoHideTimer = nil
    }

    // MARK: - 操作

    @objc private func stopTapped() {
        onStopTapped?()
    }
}
