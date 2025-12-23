//
//  PreferencesWindowController.swift
//  ScreenPresenter
//
//  Created by Sun on 2025/12/22.
//
//  偏好设置窗口控制器（纯 AppKit）
//

import AppKit

// MARK: - 偏好设置窗口控制器

final class PreferencesWindowController: NSWindowController {
    // MARK: - 单例

    static let shared: PreferencesWindowController = {
        let controller = PreferencesWindowController()
        return controller
    }()

    // MARK: - 初始化

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 380),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = L10n.window.preferences
        window.center()

        self.init(window: window)

        window.contentViewController = PreferencesViewController()
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        window?.center()
        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: - 偏好设置视图控制器

final class PreferencesViewController: NSViewController {
    // MARK: - UI 组件

    private var tabView: NSTabView!

    // MARK: - 生命周期

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 480, height: 320))
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
    }

    // MARK: - UI 设置

    private func setupUI() {
        // 标签页视图
        tabView = NSTabView()
        tabView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tabView)

        // 通用设置标签页
        let generalTab = NSTabViewItem(identifier: "general")
        generalTab.label = L10n.prefs.tab.general
        generalTab.view = createGeneralView()
        tabView.addTabViewItem(generalTab)

        // 工具链标签页
        let toolchainTab = NSTabViewItem(identifier: "toolchain")
        toolchainTab.label = L10n.prefs.tab.toolchain
        toolchainTab.view = createToolchainView()
        tabView.addTabViewItem(toolchainTab)

        // 关于标签页
        let aboutTab = NSTabViewItem(identifier: "about")
        aboutTab.label = L10n.prefs.tab.about
        aboutTab.view = createAboutView()
        tabView.addTabViewItem(aboutTab)

        // 约束
        NSLayoutConstraint.activate([
            tabView.topAnchor.constraint(equalTo: view.topAnchor, constant: 12),
            tabView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            tabView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            tabView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -12),
        ])
    }

    // MARK: - 通用设置

    private func createGeneralView() -> NSView {
        let containerView = NSView()

        // 标题
        let titleLabel = createLabel(
            text: L10n.prefs.general.displaySettings,
            font: .systemFont(ofSize: 13, weight: .semibold)
        )
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(titleLabel)

        // 启动时自动开始捕获
        let autoStartCheckbox = NSButton(
            checkboxWithTitle: L10n.prefs.general.autoStartCapture,
            target: nil,
            action: nil
        )
        autoStartCheckbox.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(autoStartCheckbox)

        // 显示帧率
        let showFPSCheckbox = NSButton(checkboxWithTitle: L10n.prefs.general.showFPS, target: nil, action: nil)
        showFPSCheckbox.state = .on
        showFPSCheckbox.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(showFPSCheckbox)

        // 语言设置标签
        let languageLabel = createLabel(text: L10n.prefs.general.language, font: .systemFont(ofSize: 13))
        languageLabel.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(languageLabel)

        // 语言选择器
        let languagePopup = NSPopUpButton()
        languagePopup.translatesAutoresizingMaskIntoConstraints = false
        for lang in AppLanguage.allCases {
            languagePopup.addItem(withTitle: lang.nativeName)
            languagePopup.lastItem?.representedObject = lang
        }
        // 选中当前语言
        let currentLang = UserPreferences.shared.appLanguage
        if let index = AppLanguage.allCases.firstIndex(of: currentLang) {
            languagePopup.selectItem(at: index)
        }
        languagePopup.target = self
        languagePopup.action = #selector(languageChanged(_:))
        containerView.addSubview(languagePopup)

        // 语言说明
        let languageNote = createLabel(text: L10n.prefs.general.languageNote, font: .systemFont(ofSize: 11))
        languageNote.textColor = .secondaryLabelColor
        languageNote.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(languageNote)

        // 约束
        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 16),
            titleLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 16),

            autoStartCheckbox.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 16),
            autoStartCheckbox.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 16),

            showFPSCheckbox.topAnchor.constraint(equalTo: autoStartCheckbox.bottomAnchor, constant: 8),
            showFPSCheckbox.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 16),

            languageLabel.topAnchor.constraint(equalTo: showFPSCheckbox.bottomAnchor, constant: 24),
            languageLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 16),

            languagePopup.centerYAnchor.constraint(equalTo: languageLabel.centerYAnchor),
            languagePopup.leadingAnchor.constraint(equalTo: languageLabel.trailingAnchor, constant: 12),
            languagePopup.widthAnchor.constraint(equalToConstant: 150),

            languageNote.topAnchor.constraint(equalTo: languageLabel.bottomAnchor, constant: 8),
            languageNote.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 16),
        ])

        return containerView
    }

    @objc private func languageChanged(_ sender: NSPopUpButton) {
        guard let lang = sender.selectedItem?.representedObject as? AppLanguage else { return }
        UserPreferences.shared.appLanguage = lang
    }

    // MARK: - 工具链设置

    private func createToolchainView() -> NSView {
        let containerView = NSView()

        // 标题
        let titleLabel = createLabel(text: L10n.prefs.toolchain.title, font: .systemFont(ofSize: 13, weight: .semibold))
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(titleLabel)

        // adb 状态
        let adbLabel = createLabel(text: L10n.prefs.toolchain.adb(L10n.common.checking), font: .systemFont(ofSize: 12))
        adbLabel.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(adbLabel)

        // scrcpy 状态
        let scrcpyLabel = createLabel(
            text: L10n.prefs.toolchain.scrcpy(L10n.common.checking),
            font: .systemFont(ofSize: 12)
        )
        scrcpyLabel.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(scrcpyLabel)

        // 刷新按钮
        let refreshButton = NSButton(
            title: L10n.prefs.toolchain.refresh,
            target: self,
            action: #selector(refreshToolchain)
        )
        refreshButton.bezelStyle = .rounded
        refreshButton.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(refreshButton)

        // 安装 scrcpy 按钮
        let installButton = NSButton(
            title: L10n.prefs.toolchain.installScrcpy,
            target: self,
            action: #selector(installScrcpy)
        )
        installButton.bezelStyle = .rounded
        installButton.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(installButton)

        // 约束
        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 16),
            titleLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 16),

            adbLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 16),
            adbLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 16),

            scrcpyLabel.topAnchor.constraint(equalTo: adbLabel.bottomAnchor, constant: 8),
            scrcpyLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 16),

            refreshButton.topAnchor.constraint(equalTo: scrcpyLabel.bottomAnchor, constant: 16),
            refreshButton.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 16),

            installButton.topAnchor.constraint(equalTo: refreshButton.bottomAnchor, constant: 8),
            installButton.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 16),
        ])

        // 更新工具链状态
        Task { @MainActor in
            let toolchain = AppState.shared.toolchainManager
            adbLabel.stringValue = L10n.prefs.toolchain.adb(toolchain.adbVersionDescription)
            scrcpyLabel.stringValue = L10n.prefs.toolchain.scrcpy(toolchain.scrcpyVersionDescription)
        }

        return containerView
    }

    // MARK: - 关于

    private func createAboutView() -> NSView {
        let containerView = NSView()

        // 应用图标
        let iconView = NSImageView()
        iconView.image = NSImage(named: NSImage.applicationIconName)
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(iconView)

        // 应用名称
        let nameLabel = createLabel(text: L10n.app.name, font: .systemFont(ofSize: 18, weight: .bold))
        nameLabel.alignment = .center
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(nameLabel)

        // 版本
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let versionLabel = createLabel(text: L10n.prefs.about.version(version), font: .systemFont(ofSize: 12))
        versionLabel.textColor = .secondaryLabelColor
        versionLabel.alignment = .center
        versionLabel.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(versionLabel)

        // 描述
        let descLabel = createLabel(
            text: L10n.app.description,
            font: .systemFont(ofSize: 12)
        )
        descLabel.textColor = .secondaryLabelColor
        descLabel.alignment = .center
        descLabel.maximumNumberOfLines = 2
        descLabel.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(descLabel)

        // 约束
        NSLayoutConstraint.activate([
            iconView.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 24),
            iconView.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 64),
            iconView.heightAnchor.constraint(equalToConstant: 64),

            nameLabel.topAnchor.constraint(equalTo: iconView.bottomAnchor, constant: 12),
            nameLabel.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),

            versionLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 4),
            versionLabel.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),

            descLabel.topAnchor.constraint(equalTo: versionLabel.bottomAnchor, constant: 16),
            descLabel.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
            descLabel.leadingAnchor.constraint(greaterThanOrEqualTo: containerView.leadingAnchor, constant: 24),
            descLabel.trailingAnchor.constraint(lessThanOrEqualTo: containerView.trailingAnchor, constant: -24),
        ])

        return containerView
    }

    // MARK: - 辅助方法

    private func createLabel(text: String, font: NSFont) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = font
        return label
    }

    // MARK: - 操作

    @objc private func refreshToolchain() {
        Task {
            await AppState.shared.toolchainManager.refresh()
        }
    }

    @objc private func installScrcpy() {
        Task {
            await AppState.shared.toolchainManager.installScrcpy()
        }
    }
}
