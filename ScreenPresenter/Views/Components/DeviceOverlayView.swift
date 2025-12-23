//
//  DeviceOverlayView.swift
//  ScreenPresenter
//
//  Created by Sun on 2025/12/22.
//
//  设备叠加层视图（纯 AppKit）
//  显示设备状态和操作按钮
//

import AppKit

// MARK: - 设备叠加层视图

final class DeviceOverlayView: NSView {
    // MARK: - UI 组件

    private var containerView: NSView!
    private var iconImageView: NSImageView!
    private var titleLabel: NSTextField!
    private var subtitleLabel: NSTextField!
    private var actionButton: NSButton!
    private var stopButton: NSButton!
    private var fpsLabel: NSTextField!
    private var statusIndicator: NSView!

    // MARK: - 回调

    private var onStartAction: (() -> Void)?
    private var onStopAction: (() -> Void)?

    // MARK: - 状态

    private enum OverlayState {
        case disconnected
        case connected
        case capturing
    }

    private var currentState: OverlayState = .disconnected

    // MARK: - 初始化

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupUI()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
    }

    // MARK: - UI 设置

    private func setupUI() {
        wantsLayer = true

        // 容器
        containerView = NSView()
        containerView.wantsLayer = true
        containerView.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.7).cgColor
        containerView.layer?.cornerRadius = 12
        containerView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(containerView)

        // 状态指示灯
        statusIndicator = NSView()
        statusIndicator.wantsLayer = true
        statusIndicator.layer?.cornerRadius = 4
        statusIndicator.layer?.backgroundColor = NSColor.systemGray.cgColor
        statusIndicator.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(statusIndicator)

        // 图标
        iconImageView = NSImageView()
        iconImageView.imageScaling = .scaleProportionallyUpOrDown
        iconImageView.contentTintColor = .white
        iconImageView.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(iconImageView)

        // 标题
        titleLabel = NSTextField(labelWithString: "")
        titleLabel.font = NSFont.systemFont(ofSize: 14, weight: .semibold)
        titleLabel.textColor = .white
        titleLabel.alignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(titleLabel)

        // 副标题
        subtitleLabel = NSTextField(labelWithString: "")
        subtitleLabel.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        subtitleLabel.textColor = NSColor.white.withAlphaComponent(0.7)
        subtitleLabel.alignment = .center
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(subtitleLabel)

        // 操作按钮
        actionButton = NSButton(title: "开始捕获", target: self, action: #selector(actionTapped))
        actionButton.bezelStyle = .rounded
        actionButton.controlSize = .regular
        actionButton.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(actionButton)

        // 停止按钮
        stopButton = NSButton(
            title: "",
            image: NSImage(systemSymbolName: "stop.fill", accessibilityDescription: "停止")!,
            target: self,
            action: #selector(stopTapped)
        )
        stopButton.bezelStyle = .rounded
        stopButton.translatesAutoresizingMaskIntoConstraints = false
        stopButton.isHidden = true
        containerView.addSubview(stopButton)

        // 帧率标签
        fpsLabel = NSTextField(labelWithString: "")
        fpsLabel.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        fpsLabel.textColor = NSColor.white.withAlphaComponent(0.6)
        fpsLabel.alignment = .center
        fpsLabel.translatesAutoresizingMaskIntoConstraints = false
        fpsLabel.isHidden = true
        containerView.addSubview(fpsLabel)

        // 约束
        NSLayoutConstraint.activate([
            // 容器
            containerView.centerXAnchor.constraint(equalTo: centerXAnchor),
            containerView.topAnchor.constraint(equalTo: topAnchor),
            containerView.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, constant: -16),
            containerView.widthAnchor.constraint(greaterThanOrEqualToConstant: 180),

            // 状态指示灯
            statusIndicator.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 12),
            statusIndicator.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -12),
            statusIndicator.widthAnchor.constraint(equalToConstant: 8),
            statusIndicator.heightAnchor.constraint(equalToConstant: 8),

            // 图标
            iconImageView.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 16),
            iconImageView.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
            iconImageView.widthAnchor.constraint(equalToConstant: 32),
            iconImageView.heightAnchor.constraint(equalToConstant: 32),

            // 标题
            titleLabel.topAnchor.constraint(equalTo: iconImageView.bottomAnchor, constant: 8),
            titleLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 16),
            titleLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -16),

            // 副标题
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            subtitleLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 16),
            subtitleLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -16),

            // 操作按钮
            actionButton.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 12),
            actionButton.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
            actionButton.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -16),

            // 停止按钮
            stopButton.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 12),
            stopButton.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),

            // 帧率标签
            fpsLabel.topAnchor.constraint(equalTo: stopButton.bottomAnchor, constant: 8),
            fpsLabel.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
        ])
    }

    // MARK: - 公开方法

    /// 显示断开状态
    func showDisconnected(platform: DevicePlatform) {
        currentState = .disconnected

        let iconName = platform == .ios ? "iphone" : "candybarphone"
        iconImageView.image = NSImage(systemSymbolName: iconName, accessibilityDescription: nil)

        titleLabel.stringValue = platform == .ios ? "iPhone" : "Android"
        subtitleLabel.stringValue = "使用 USB 数据线连接设备"

        actionButton.title = "等待连接..."
        actionButton.isEnabled = false
        actionButton.isHidden = false

        stopButton.isHidden = true
        fpsLabel.isHidden = true

        statusIndicator.layer?.backgroundColor = NSColor.systemGray.cgColor

        onStartAction = nil
    }

    /// 显示已连接状态
    func showConnected(deviceName: String, platform: DevicePlatform, onStart: @escaping () -> Void) {
        currentState = .connected

        let iconName = platform == .ios ? "iphone" : "candybarphone"
        iconImageView.image = NSImage(systemSymbolName: iconName, accessibilityDescription: nil)

        titleLabel.stringValue = deviceName
        subtitleLabel.stringValue = "设备已就绪"

        actionButton.title = "开始捕获"
        actionButton.isEnabled = true
        actionButton.isHidden = false

        stopButton.isHidden = true
        fpsLabel.isHidden = true

        statusIndicator.layer?.backgroundColor = NSColor.systemGreen.cgColor

        onStartAction = onStart
    }

    /// 显示捕获中状态
    func showCapturing(deviceName: String, fps: Double) {
        currentState = .capturing

        titleLabel.stringValue = deviceName
        subtitleLabel.stringValue = "捕获中"

        actionButton.isHidden = true

        stopButton.isHidden = false
        fpsLabel.isHidden = false
        fpsLabel.stringValue = "\(Int(fps)) fps"

        // 更新帧率颜色
        if fps >= 30 {
            fpsLabel.textColor = NSColor.systemGreen.withAlphaComponent(0.8)
        } else if fps >= 15 {
            fpsLabel.textColor = NSColor.systemOrange.withAlphaComponent(0.8)
        } else {
            fpsLabel.textColor = NSColor.systemRed.withAlphaComponent(0.8)
        }

        statusIndicator.layer?.backgroundColor = NSColor.systemGreen.cgColor

        // 添加脉冲动画
        addPulseAnimation()
    }

    /// 更新帧率
    func updateFPS(_ fps: Double) {
        guard currentState == .capturing else { return }

        fpsLabel.stringValue = "\(Int(fps)) fps"

        if fps >= 30 {
            fpsLabel.textColor = NSColor.systemGreen.withAlphaComponent(0.8)
        } else if fps >= 15 {
            fpsLabel.textColor = NSColor.systemOrange.withAlphaComponent(0.8)
        } else {
            fpsLabel.textColor = NSColor.systemRed.withAlphaComponent(0.8)
        }
    }

    // MARK: - 操作

    @objc private func actionTapped() {
        onStartAction?()
    }

    @objc private func stopTapped() {
        onStopAction?()
    }

    // MARK: - 动画

    private func addPulseAnimation() {
        statusIndicator.layer?.removeAnimation(forKey: "pulse")

        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = 1.0
        animation.toValue = 0.4
        animation.duration = 0.8
        animation.autoreverses = true
        animation.repeatCount = .infinity
        statusIndicator.layer?.add(animation, forKey: "pulse")
    }
}
