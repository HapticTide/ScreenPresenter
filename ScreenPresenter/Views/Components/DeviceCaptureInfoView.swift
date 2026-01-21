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

// MARK: - 捕获信息视图

final class DeviceCaptureInfoView: NSView {
    // MARK: - UI 组件

    /// 内容容器（居中显示所有元素）
    private let contentContainer = NSView()
    /// 设备名称
    private let deviceNameLabel = NSTextField(labelWithString: "")
    /// 设备详细信息（型号 · 系统版本）
    private let deviceInfoLabel = NSTextField(labelWithString: "")
    /// 分辨率
    private let resolutionLabel = NSTextField(labelWithString: "")
    /// FPS
    private let fpsLabel = NSTextField(labelWithString: "")
    /// 停止按钮容器
    private let stopButtonContainer = NSView()
    /// 停止按钮图标
    private let stopButtonIcon = NSImageView()
    /// 顶部状态栏（captureIndicator + fpsLabel）
    private let topStatusBar = NSView()

    // MARK: - 音频控制 UI

    /// 音频控制容器
    private let audioControlContainer = NSView()
    /// 音频开关按钮
    private let audioToggleButton = NSButton()
    /// 音量滑块
    private let volumeSlider = NSSlider()
    /// 音量标签
    private let volumeLabel = NSTextField(labelWithString: "")

    // MARK: - 字体配置

    /// 设备名称标签的基准字体大小
    private let deviceNameBaseFontSize: CGFloat = 24
    /// 设备名称标签的最小字体大小
    private let deviceNameMinFontSize: CGFloat = 16
    /// 设备名称标签的基准字体大小
    private let deviceInfoBaseFontSize: CGFloat = 14
    /// 设备名称标签的最小字体大小
    private let deviceInfoMinFontSize: CGFloat = 10

    // MARK: - 平台

    /// 当前设备平台
    private var currentPlatform: DevicePlatform = .ios

    // MARK: - 回调

    var onStopTapped: (() -> Void)?
    var onAudioToggle: ((Bool) -> Void)?
    var onVolumeChange: ((Float) -> Void)?

    // MARK: - 自动隐藏

    private var autoHideTimer: Timer?
    /// 自动隐藏延时（秒）
    private let autoHideDelay: TimeInterval = 1.5

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
        setupAudioControls()
        setupStopButton()
    }

    private func setupContentContainer() {
        addSubview(contentContainer)
    }

    private func setupTopStatusBar() {
        // 顶部状态栏：fpsLabel
        contentContainer.addSubview(topStatusBar)

        // FPS（中间）
        fpsLabel.font = NSFont.monospacedSystemFont(ofSize: 14, weight: .medium)
        fpsLabel.textColor = .white
        fpsLabel.alignment = .center
        topStatusBar.addSubview(fpsLabel)
    }

    private func setupDeviceLabels() {
        // 分辨率（第二行，居中）
        resolutionLabel.font = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        resolutionLabel.textColor = NSColor.white.withAlphaComponent(0.8)
        resolutionLabel.alignment = .center
        contentContainer.addSubview(resolutionLabel)

        // 设备名称（第三行，居中）
        deviceNameLabel.font = NSFont.systemFont(ofSize: 22, weight: .semibold)
        deviceNameLabel.textColor = .white
        deviceNameLabel.alignment = .center
        deviceNameLabel.lineBreakMode = .byWordWrapping
        deviceNameLabel.maximumNumberOfLines = 2
        deviceNameLabel.cell?.truncatesLastVisibleLine = true
        contentContainer.addSubview(deviceNameLabel)

        // 设备详细信息（第四行，居中）
        deviceInfoLabel.font = NSFont.systemFont(ofSize: 16, weight: .regular)
        deviceInfoLabel.textColor = NSColor.white.withAlphaComponent(0.7)
        deviceInfoLabel.alignment = .center
        deviceInfoLabel.lineBreakMode = .byWordWrapping
        deviceInfoLabel.maximumNumberOfLines = 2
        deviceInfoLabel.cell?.truncatesLastVisibleLine = true
        contentContainer.addSubview(deviceInfoLabel)
    }

    private func setupAudioControls() {
        // 音频控制容器（只包含音量调节，不包含开关）
        audioControlContainer.wantsLayer = true
        audioControlContainer.layer?.cornerRadius = 8
        audioControlContainer.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.1).cgColor
        contentContainer.addSubview(audioControlContainer)

        // 音量图标（静态显示，不可点击）
        audioToggleButton.bezelStyle = .inline
        audioToggleButton.isBordered = false
        audioToggleButton.image = NSImage(systemSymbolName: "speaker.wave.2.fill", accessibilityDescription: "音量")
        audioToggleButton.contentTintColor = .white
        audioToggleButton.isEnabled = false  // 禁用点击，只作为图标显示
        audioControlContainer.addSubview(audioToggleButton)

        // 音量滑块
        volumeSlider.minValue = 0
        volumeSlider.maxValue = 1
        volumeSlider.doubleValue = 1
        volumeSlider.target = self
        volumeSlider.action = #selector(volumeSliderChanged)
        volumeSlider.controlSize = .small
        audioControlContainer.addSubview(volumeSlider)

        // 音量标签
        volumeLabel.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .medium)
        volumeLabel.textColor = NSColor.white.withAlphaComponent(0.8)
        volumeLabel.alignment = .right
        volumeLabel.stringValue = "100%"
        audioControlContainer.addSubview(volumeLabel)

        // 默认隐藏音频控制（等待设置平台后显示）
        audioControlContainer.isHidden = true
    }

    private func setupStopButton() {
        // 停止按钮容器（圆形背景）
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

        // 停止图标
        let config = NSImage.SymbolConfiguration(pointSize: 18, weight: .bold)
        let stopImage = NSImage(
            systemSymbolName: "stop.fill",
            accessibilityDescription: L10n.overlayUI.stop
        )?.withSymbolConfiguration(config)

        stopButtonIcon.image = stopImage ?? NSImage()
        stopButtonIcon.contentTintColor = .white
        stopButtonContainer.addSubview(stopButtonIcon)
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
        layoutContent()
    }

    // MARK: - 字体自适应

    /// 根据可用宽度更新字体大小
    /// 注意：由于启用了多行换行，这里使用固定字体大小
    private func updateFontsForWidth(_: CGFloat) {
        // 使用固定字体大小，依赖多行换行来显示完整内容
        deviceNameLabel.font = NSFont.systemFont(ofSize: deviceNameBaseFontSize, weight: .semibold)
        deviceInfoLabel.font = NSFont.systemFont(ofSize: deviceInfoBaseFontSize, weight: .regular)
    }

    private func layoutContent() {
        let availableWidth = max(0, bounds.width - 16)
        updateFontsForWidth(availableWidth)

        // 使用固定高度确保空标签也能正确显示
        let fpsSize = fpsLabel.intrinsicContentSize
        let topStatusHeight = max(fpsSize.height, 20) // 最小高度 20
        let fpsWidth = max(fpsSize.width, 80) // 最小宽度 80
        let topStatusWidth = min(availableWidth, max(200, fpsWidth))

        let resolutionSize = resolutionLabel.intrinsicContentSize
        let resolutionHeight = max(resolutionSize.height, 20) // 最小高度 20
        let resolutionWidth = max(min(availableWidth, resolutionSize.width), 120) // 最小宽度 120

        // 计算多行文本的实际尺寸
        // 设置 preferredMaxLayoutWidth 以启用多行换行计算
        deviceNameLabel.preferredMaxLayoutWidth = availableWidth
        deviceInfoLabel.preferredMaxLayoutWidth = availableWidth

        let deviceNameSize = deviceNameLabel.intrinsicContentSize
        let deviceInfoSize = deviceInfoLabel.intrinsicContentSize

        let deviceNameWidth = availableWidth
        let deviceInfoWidth = availableWidth

        // 音频控件尺寸
        let audioControlHeight: CGFloat = audioControlContainer.isHidden ? 0 : 32
        let audioControlWidth: CGFloat = min(availableWidth, 200)

        let contentWidth = max(topStatusWidth, resolutionWidth, deviceNameWidth, deviceInfoWidth, audioControlWidth, 48)
        let audioSpacing: CGFloat = audioControlContainer.isHidden ? 0 : 16
        let totalHeight = topStatusHeight + 20
            + resolutionHeight + 16
            + deviceNameSize.height + 16
            + deviceInfoSize.height + audioSpacing
            + audioControlHeight + 24
            + 48

        contentContainer.frame = CGRect(
            x: (bounds.width - contentWidth) / 2,
            y: (bounds.height - totalHeight) / 2,
            width: contentWidth,
            height: totalHeight
        )

        // 从顶部开始向下布局（macOS 默认坐标系原点在左下角）
        // y 从 totalHeight 开始递减，先放置的元素在视觉顶部
        var y: CGFloat = totalHeight

        // FPS（顶部）
        y -= topStatusHeight
        topStatusBar.frame = CGRect(
            x: (contentWidth - topStatusWidth) / 2,
            y: y,
            width: topStatusWidth,
            height: topStatusHeight
        )
        fpsLabel.frame = CGRect(
            x: (topStatusWidth - fpsWidth) / 2,
            y: 0,
            width: fpsWidth,
            height: topStatusHeight
        )
        y -= 20

        // 分辨率
        y -= resolutionHeight
        resolutionLabel.frame = CGRect(
            x: (contentWidth - resolutionWidth) / 2,
            y: y,
            width: resolutionWidth,
            height: resolutionHeight
        )
        y -= 16

        // 设备名称（使用可用宽度，允许多行换行）
        y -= deviceNameSize.height
        deviceNameLabel.frame = CGRect(
            x: (contentWidth - deviceNameWidth) / 2,
            y: y,
            width: deviceNameWidth,
            height: deviceNameSize.height
        )
        y -= 16

        // 设备详情
        y -= deviceInfoSize.height
        deviceInfoLabel.frame = CGRect(
            x: (contentWidth - deviceInfoWidth) / 2,
            y: y,
            width: deviceInfoWidth,
            height: deviceInfoSize.height
        )

        // 音频控件
        if !audioControlContainer.isHidden {
            y -= audioSpacing
            y -= audioControlHeight
            audioControlContainer.frame = CGRect(
                x: (contentWidth - audioControlWidth) / 2,
                y: y,
                width: audioControlWidth,
                height: audioControlHeight
            )

            // 布局音频控件内部元素
            let buttonSize: CGFloat = 24
            let sliderWidth: CGFloat = audioControlWidth - buttonSize - 50 - 16 // 按钮 + 标签 + 间距
            let labelWidth: CGFloat = 40

            audioToggleButton.frame = CGRect(
                x: 8,
                y: (audioControlHeight - buttonSize) / 2,
                width: buttonSize,
                height: buttonSize
            )

            volumeSlider.frame = CGRect(
                x: 8 + buttonSize + 8,
                y: (audioControlHeight - 20) / 2,
                width: sliderWidth,
                height: 20
            )

            volumeLabel.frame = CGRect(
                x: audioControlWidth - labelWidth - 8,
                y: (audioControlHeight - 16) / 2,
                width: labelWidth,
                height: 16
            )
        }

        y -= 24

        // 停止按钮（底部）
        y -= 48
        stopButtonContainer.frame = CGRect(
            x: (contentWidth - 48) / 2,
            y: y,
            width: 48,
            height: 48
        )

        let iconSize: CGFloat = 18
        // SF Symbol 可能有内部 baseline 偏移，视觉上微调 Y 坐标使其看起来居中
        let iconY = (48 - iconSize) / 2 + 1 // 向上偏移 1 点
        stopButtonIcon.frame = CGRect(
            x: (48 - iconSize) / 2,
            y: iconY,
            width: iconSize,
            height: iconSize
        )
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

    /// 检查自动隐藏定时器是否正在运行
    var isAutoHideScheduled: Bool {
        autoHideTimer != nil
    }

    // MARK: - 音频控制

    /// 设置当前设备平台，决定是否显示音频控件
    /// - Parameter platform: 设备平台类型
    func setPlatform(_ platform: DevicePlatform) {
        currentPlatform = platform

        // 根据平台和偏好设置决定是否显示音量调节控件
        // 只有当偏好设置中启用了音频捕获时，才显示音量调节
        let showVolumeControl: Bool
        let volume: Float
        if platform == .ios {
            showVolumeControl = UserPreferences.shared.iosAudioEnabled
            volume = UserPreferences.shared.iosAudioVolume
        } else if platform == .android {
            showVolumeControl = UserPreferences.shared.androidAudioEnabled
            volume = UserPreferences.shared.androidAudioVolume
        } else {
            showVolumeControl = false
            volume = 1.0
        }
        audioControlContainer.isHidden = !showVolumeControl

        if showVolumeControl {
            // 初始化音量滑块状态
            volumeSlider.floatValue = volume
            let volumePercent = Int(volume * 100)
            volumeLabel.stringValue = "\(volumePercent)%"
        }

        needsLayout = true
    }

    /// 更新音频控件状态（只更新音量显示）
    /// - Parameters:
    ///   - enabled: 音频是否启用（不再使用，保留参数兼容性）
    ///   - volume: 音量 (0.0 - 1.0)
    func updateAudioState(enabled _: Bool, volume: Float) {
        volumeSlider.floatValue = volume
        let volumePercent = Int(volume * 100)
        volumeLabel.stringValue = "\(volumePercent)%"
    }

    // MARK: - 操作

    @objc private func volumeSliderChanged() {
        guard currentPlatform == .ios || currentPlatform == .android else { return }

        let volume = volumeSlider.floatValue

        if currentPlatform == .ios {
            UserPreferences.shared.iosAudioVolume = volume
        } else {
            UserPreferences.shared.androidAudioVolume = volume
        }

        let volumePercent = Int(volume * 100)
        volumeLabel.stringValue = "\(volumePercent)%"

        onVolumeChange?(volume)
    }

    @objc private func stopTapped() {
        onStopTapped?()
    }
}
