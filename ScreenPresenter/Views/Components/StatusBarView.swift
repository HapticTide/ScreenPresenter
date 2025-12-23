//
//  StatusBarView.swift
//  ScreenPresenter
//
//  Created by Sun on 2025/12/22.
//
//  状态栏视图（纯 AppKit）
//  显示连接状态和帧率信息
//

import AppKit

// MARK: - 状态栏视图

final class StatusBarView: NSView {
    // MARK: - UI 组件

    private var statusLabel: NSTextField!
    private var leftFPSLabel: NSTextField!
    private var rightFPSLabel: NSTextField!
    private var separator1: NSBox!
    private var separator2: NSBox!

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
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor

        // 顶部分隔线
        let topSeparator = NSBox()
        topSeparator.boxType = .separator
        topSeparator.translatesAutoresizingMaskIntoConstraints = false
        addSubview(topSeparator)

        // 状态标签
        statusLabel = createLabel(text: "等待设备连接...")
        statusLabel.alignment = .left
        addSubview(statusLabel)

        // 分隔线 1
        separator1 = NSBox()
        separator1.boxType = .separator
        separator1.translatesAutoresizingMaskIntoConstraints = false
        addSubview(separator1)

        // 左侧帧率
        leftFPSLabel = createLabel(text: "iOS: -- fps")
        leftFPSLabel.alignment = .center
        addSubview(leftFPSLabel)

        // 分隔线 2
        separator2 = NSBox()
        separator2.boxType = .separator
        separator2.translatesAutoresizingMaskIntoConstraints = false
        addSubview(separator2)

        // 右侧帧率
        rightFPSLabel = createLabel(text: "Android: -- fps")
        rightFPSLabel.alignment = .center
        addSubview(rightFPSLabel)

        // 约束
        NSLayoutConstraint.activate([
            // 顶部分隔线
            topSeparator.topAnchor.constraint(equalTo: topAnchor),
            topSeparator.leadingAnchor.constraint(equalTo: leadingAnchor),
            topSeparator.trailingAnchor.constraint(equalTo: trailingAnchor),
            topSeparator.heightAnchor.constraint(equalToConstant: 1),

            // 状态标签
            statusLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            statusLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            // 分隔线 1
            separator1.leadingAnchor.constraint(equalTo: statusLabel.trailingAnchor, constant: 12),
            separator1.centerYAnchor.constraint(equalTo: centerYAnchor),
            separator1.widthAnchor.constraint(equalToConstant: 1),
            separator1.heightAnchor.constraint(equalToConstant: 14),

            // 左侧帧率
            leftFPSLabel.leadingAnchor.constraint(equalTo: separator1.trailingAnchor, constant: 12),
            leftFPSLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            leftFPSLabel.widthAnchor.constraint(equalToConstant: 80),

            // 分隔线 2
            separator2.leadingAnchor.constraint(equalTo: leftFPSLabel.trailingAnchor, constant: 12),
            separator2.centerYAnchor.constraint(equalTo: centerYAnchor),
            separator2.widthAnchor.constraint(equalToConstant: 1),
            separator2.heightAnchor.constraint(equalToConstant: 14),

            // 右侧帧率
            rightFPSLabel.leadingAnchor.constraint(equalTo: separator2.trailingAnchor, constant: 12),
            rightFPSLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            rightFPSLabel.widthAnchor.constraint(equalToConstant: 100),
        ])
    }

    private func createLabel(text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        label.textColor = .secondaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }

    // MARK: - 公开方法

    /// 设置状态文本
    func setStatus(_ text: String) {
        statusLabel.stringValue = text
    }

    /// 设置帧率
    func setFPS(left: Int, right: Int) {
        if left > 0 {
            leftFPSLabel.stringValue = "iOS: \(left) fps"
            leftFPSLabel.textColor = left >= 30 ? .systemGreen : .systemOrange
        } else {
            leftFPSLabel.stringValue = "iOS: -- fps"
            leftFPSLabel.textColor = .secondaryLabelColor
        }

        if right > 0 {
            rightFPSLabel.stringValue = "Android: \(right) fps"
            rightFPSLabel.textColor = right >= 30 ? .systemGreen : .systemOrange
        } else {
            rightFPSLabel.stringValue = "Android: -- fps"
            rightFPSLabel.textColor = .secondaryLabelColor
        }
    }
}
