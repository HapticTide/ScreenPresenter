//
//  AppDelegate.swift
//  ScreenPresenter
//
//  Created by Sun on 2025/12/22.
//
//  应用程序入口
//  配置主窗口和应用状态
//

import AppKit
import AVFoundation

// MARK: - 应用程序委托

final class AppDelegate: NSObject, NSApplicationDelegate {
    // MARK: - 窗口

    private var mainWindow: NSWindow?
    private var mainViewController: MainViewController?

    // MARK: - 工具栏

    private var windowToolbar: NSToolbar?
    private var refreshToolbarItem: NSToolbarItem?
    private var toggleBezelToolbarItem: NSToolbarItem?
    private var preventSleepToolbarItem: NSToolbarItem?
    private var layoutModeToolbarItem: NSToolbarItem?
    private var layoutModeSegmentedControl: NSSegmentedControl?
    private var isRefreshing: Bool = false

    // MARK: - 菜单项

    private var bezelMenuItem: NSMenuItem?
    private var preventSleepMenuItem: NSMenuItem?

    // MARK: - 应用生命周期

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppLogger.app.info("应用启动")

        // 创建主菜单（纯代码 AppKit 应用必须）
        setupMainMenu()

        // 启用 CoreMediaIO 屏幕捕获设备
        let dalEnabled = IOSScreenMirrorActivator.shared.enableDALDevices()
        AppLogger.app.info("DAL 设备启用结果: \(dalEnabled)")

        // 请求摄像头权限（iOS 设备投屏需要）
        requestCameraPermission()

        // 创建主窗口
        setupMainWindow()

        // 监听语言变更
        setupLanguageObserver()

        // 启动捕获电源协调器（管理防休眠）
        CapturePowerCoordinator.shared.start()

        // 初始化自动更新管理器
        UpdateManager.shared.initialize()

        // 初始化应用状态
        Task {
            AppLogger.app.info("开始异步初始化应用状态...")
            await AppState.shared.initialize()
            AppLogger.app.info("应用状态初始化完成")
        }
    }

    private func setupLanguageObserver() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleLanguageChange),
            name: LocalizationManager.languageDidChangeNotification,
            object: nil
        )

        // 监听 bezel 可见性变化
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleBezelVisibilityChange),
            name: .deviceBezelVisibilityDidChange,
            object: nil
        )

        // 监听防休眠设置变化
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handlePreventSleepSettingChange),
            name: .preventAutoLockSettingDidChange,
            object: nil
        )
    }

    @objc private func handleBezelVisibilityChange() {
        // 更新工具栏按钮图标
        if let item = toggleBezelToolbarItem {
            updateBezelToolbarItemImage(item)
        }
        // 更新菜单项状态
        bezelMenuItem?.state = UserPreferences.shared.showDeviceBezel ? .on : .off
    }

    @objc private func handlePreventSleepSettingChange() {
        // 更新工具栏按钮图标
        if let item = preventSleepToolbarItem {
            updatePreventSleepToolbarItemImage(item)
        }
        // 更新菜单项状态
        preventSleepMenuItem?.state = UserPreferences.shared.preventAutoLockDuringCapture ? .on : .off
    }

    @objc private func handleLanguageChange() {
        // 重建主菜单
        setupMainMenu()

        // 更新主窗口标题
        mainWindow?.title = L10n.window.main

        // 重建工具栏以更新按钮文字
        if let window = mainWindow {
            rebuildWindowToolbar(for: window)
        }

        // 通知主视图控制器更新本地化文本
        mainViewController?.updateLocalizedTexts()
    }

    private func rebuildWindowToolbar(for window: NSWindow) {
        // 移除旧工具栏
        window.toolbar = nil
        refreshToolbarItem = nil
        toggleBezelToolbarItem = nil
        preventSleepToolbarItem = nil
        layoutModeToolbarItem = nil
        layoutModeSegmentedControl = nil

        // 创建新工具栏
        setupWindowToolbar(for: window)
    }

    /// 请求摄像头权限
    private func requestCameraPermission() {
        let status = AVCaptureDevice.authorizationStatus(for: .video)

        switch status {
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { _ in }
        case .denied:
            AppLogger.app.warning("摄像头权限已被拒绝，请在系统设置中开启")
        case .authorized, .restricted:
            break
        @unknown default:
            break
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppLogger.app.info("应用即将退出")

        // 停止捕获电源协调器（释放防休眠 assertion）
        CapturePowerCoordinator.shared.stop()

        // 清理资源
        Task {
            await AppState.shared.cleanup()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }

    // MARK: - 主菜单设置

    private func setupMainMenu() {
        let mainMenu = NSMenu()

        // 应用菜单
        let appMenu = NSMenu()
        let appMenuItem = NSMenuItem()
        appMenuItem.submenu = appMenu

        appMenu.addItem(
            withTitle: L10n.menu.about,
            action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
            keyEquivalent: ""
        )
        appMenu.addItem(NSMenuItem.separator())

        // 检查更新
        let checkUpdatesItem = appMenu.addItem(
            withTitle: L10n.menu.checkForUpdates,
            action: #selector(checkForUpdates(_:)),
            keyEquivalent: ""
        )
        checkUpdatesItem.image = NSImage(systemSymbolName: "arrow.triangle.2.circlepath", accessibilityDescription: nil)

        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(
            withTitle: L10n.menu.preferences,
            action: #selector(showPreferences(_:)),
            keyEquivalent: ","
        )
        appMenu.addItem(NSMenuItem.separator())

        let servicesMenu = NSMenu()
        let servicesItem = appMenu.addItem(
            withTitle: L10n.menu.services,
            action: nil,
            keyEquivalent: ""
        )
        servicesItem.submenu = servicesMenu
        NSApp.servicesMenu = servicesMenu

        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(
            withTitle: L10n.menu.hide,
            action: #selector(NSApplication.hide(_:)),
            keyEquivalent: "h"
        )
        let hideOthersItem = appMenu.addItem(
            withTitle: L10n.menu.hideOthers,
            action: #selector(NSApplication.hideOtherApplications(_:)),
            keyEquivalent: "h"
        )
        hideOthersItem.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(
            withTitle: L10n.menu.showAll,
            action: #selector(NSApplication.unhideAllApplications(_:)),
            keyEquivalent: ""
        )
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(
            withTitle: L10n.menu.quit,
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )

        mainMenu.addItem(appMenuItem)

        // 设备菜单
        let deviceMenu = NSMenu(title: L10n.menu.device)
        let deviceMenuItem = NSMenuItem()
        deviceMenuItem.submenu = deviceMenu

        let refreshItem = deviceMenu.addItem(
            withTitle: L10n.menu.refreshDevices,
            action: #selector(refreshDevices(_:)),
            keyEquivalent: "r"
        )
        refreshItem.image = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: nil)

        deviceMenu.addItem(NSMenuItem.separator())

        // 导出日志
        let exportItem = deviceMenu.addItem(
            withTitle: L10n.menu.exportLogs,
            action: #selector(exportLogs(_:)),
            keyEquivalent: "E"
        )
        exportItem.keyEquivalentModifierMask = [.command, .shift]
        exportItem.image = NSImage(systemSymbolName: "square.and.arrow.up", accessibilityDescription: nil)

        deviceMenu.addItem(NSMenuItem.separator())

        let closeItem = deviceMenu.addItem(
            withTitle: L10n.menu.close,
            action: #selector(NSWindow.performClose(_:)),
            keyEquivalent: "w"
        )
        closeItem.target = nil

        mainMenu.addItem(deviceMenuItem)

        // 显示菜单
        let viewMenu = NSMenu(title: L10n.menu.view)
        let viewMenuItem = NSMenuItem()
        viewMenuItem.submenu = viewMenu

        // 显示/隐藏设备边框
        let bezelItem = viewMenu.addItem(
            withTitle: L10n.menu.toggleDeviceBezel,
            action: #selector(toggleDeviceBezel(_:)),
            keyEquivalent: "B"
        )
        bezelItem.keyEquivalentModifierMask = [.command, .shift]
        bezelItem.image = NSImage(systemSymbolName: "iphone", accessibilityDescription: nil)
        bezelItem.state = UserPreferences.shared.showDeviceBezel ? .on : .off
        bezelMenuItem = bezelItem

        // 禁止息屏
        let sleepItem = viewMenu.addItem(
            withTitle: L10n.menu.togglePreventSleep,
            action: #selector(togglePreventSleep(_:)),
            keyEquivalent: "S"
        )
        sleepItem.keyEquivalentModifierMask = [.command, .shift]
        sleepItem.image = NSImage(systemSymbolName: "lock.display", accessibilityDescription: nil)
        sleepItem.state = UserPreferences.shared.preventAutoLockDuringCapture ? .on : .off
        preventSleepMenuItem = sleepItem

        viewMenu.addItem(NSMenuItem.separator())

        // 颜色补偿
        let colorCompItem = viewMenu.addItem(
            withTitle: L10n.menu.colorCompensation,
            action: #selector(toggleColorCompensationPanel(_:)),
            keyEquivalent: "C"
        )
        colorCompItem.keyEquivalentModifierMask = [.command, .shift]
        colorCompItem.image = NSImage(systemSymbolName: "paintpalette", accessibilityDescription: nil)

        viewMenu.addItem(NSMenuItem.separator())

        mainMenu.addItem(viewMenuItem)

        // 窗口菜单
        let windowMenu = NSMenu(title: L10n.menu.window)
        let windowMenuItem = NSMenuItem()
        windowMenuItem.submenu = windowMenu

        windowMenu.addItem(
            withTitle: L10n.menu.minimize,
            action: #selector(NSWindow.performMiniaturize(_:)),
            keyEquivalent: "m"
        )
        windowMenu.addItem(
            withTitle: L10n.menu.zoom,
            action: #selector(NSWindow.performZoom(_:)),
            keyEquivalent: ""
        )
        windowMenu.addItem(NSMenuItem.separator())
        windowMenu.addItem(
            withTitle: L10n.menu.bringAllToFront,
            action: #selector(NSApplication.arrangeInFront(_:)),
            keyEquivalent: ""
        )

        mainMenu.addItem(windowMenuItem)
        NSApp.windowsMenu = windowMenu

        // 帮助菜单
        let helpMenu = NSMenu(title: L10n.menu.help)
        let helpMenuItem = NSMenuItem()
        helpMenuItem.submenu = helpMenu
        mainMenu.addItem(helpMenuItem)
        NSApp.helpMenu = helpMenu

        NSApp.mainMenu = mainMenu
    }

    // MARK: - 窗口设置

    private func setupMainWindow() {
        // 创建主视图控制器
        mainViewController = MainViewController()

        // 创建窗口
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1200, height: 800),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        window.title = L10n.window.main
        window.titlebarSeparatorStyle = .none
        window.titlebarAppearsTransparent = true
        window.minSize = NSSize(width: 800, height: 600)
        window.contentViewController = mainViewController
        window.center()
        window.setFrameAutosaveName("MainWindow")

        // 设置窗口工具栏
        setupWindowToolbar(for: window)

        // 设置窗口代理
        window.delegate = self

        // 显示窗口
        window.makeKeyAndOrderFront(nil)
        mainWindow = window

        // 激活应用（确保窗口显示在最前面）
        NSApp.activate(ignoringOtherApps: true)

        AppLogger.app.info("主窗口已创建")
    }

    private func setupWindowToolbar(for window: NSWindow) {
        let toolbar = NSToolbar(identifier: "MainToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        toolbar.showsBaselineSeparator = false

        window.toolbar = toolbar
        windowToolbar = toolbar
    }
}

// MARK: - 窗口代理

extension AppDelegate: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        AppLogger.app.info("主窗口即将关闭")
    }

    func windowDidResize(_ notification: Notification) {
        // 通知渲染器更新尺寸
        mainViewController?.handleWindowResize()
    }

    func windowWillEnterFullScreen(_ notification: Notification) {
        // 在全屏动画开始前更新状态，避免动画过程中布局跳动
        mainViewController?.handleFullScreenChange(isFullScreen: true)
    }

    func windowWillExitFullScreen(_ notification: Notification) {
        // 在退出全屏动画开始前更新状态，避免动画过程中布局跳动
        mainViewController?.handleFullScreenChange(isFullScreen: false)
    }

    func windowDidExitFullScreen(_ notification: Notification) {
        // 退出全屏动画完成后，确保 toolbar 正确恢复显示
        mainViewController?.ensureToolbarVisible()
    }
}

// MARK: - 菜单操作

extension AppDelegate {
    @IBAction func showPreferences(_ sender: Any?) {
        PreferencesWindowController.shared.showWindow(nil)
    }

    @IBAction func checkForUpdates(_ sender: Any?) {
        UpdateManager.shared.checkForUpdates()
    }

    @IBAction func toggleColorCompensationPanel(_ sender: Any?) {
        ColorCompensationPanel.shared.togglePanel()
    }

    @IBAction func refreshDevices(_ sender: Any?) {
        guard !isRefreshing else { return }

        startRefreshLoading()

        Task {
            await AppState.shared.refreshDevices()
            await MainActor.run {
                stopRefreshLoading()
                showRefreshToast()
            }
        }
    }

    /// 导出日志
    @IBAction func exportLogs(_ sender: Any?) {
        guard let window = mainWindow else { return }

        let savePanel = NSSavePanel()
        savePanel.nameFieldStringValue = "ScreenPresenter_logs_\(formattedTimestamp()).log"
        savePanel.allowedContentTypes = [.plainText, .log]
        savePanel.canCreateDirectories = true

        savePanel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = savePanel.url else { return }
            self?.collectAndExportLogs(to: url)
        }
    }

    /// 格式化时间戳用于文件名
    private func formattedTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        return formatter.string(from: Date())
    }

    /// 收集并导出日志
    private func collectAndExportLogs(to url: URL) {
        Task {
            do {
                let logs = try await collectSystemLogs()
                try logs.write(to: url, atomically: true, encoding: .utf8)

                await MainActor.run {
                    // 显示成功提示并打开 Finder 选中文件
                    ToastView.success(L10n.toast.exportLogsSuccess, in: mainWindow)
                    NSWorkspace.shared.selectFile(
                        url.path,
                        inFileViewerRootedAtPath: url.deletingLastPathComponent().path
                    )
                }
            } catch {
                await MainActor.run {
                    ToastView.error(L10n.toast.exportLogsFailed(error.localizedDescription), in: mainWindow)
                }
            }
        }
    }

    /// 从系统日志收集应用日志
    private func collectSystemLogs() async throws -> String {
        let bundleId = Bundle.main.bundleIdentifier ?? "com.webull.ScreenPresenter"
        var allLogs = ""

        // 添加头部信息
        let header = """
        ========================================
        ScreenPresenter Log Export
        ========================================
        Export Time: \(ISO8601DateFormatter().string(from: Date()))
        Bundle ID: \(bundleId)
        App Version: \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown")
        Build: \(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown")
        macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)
        ========================================

        """
        allLogs += header

        // 收集应用日志（info 级别以上，使用 --info 标志）
        let appLogs = try await runLogCommand([
            "show",
            "--predicate", "subsystem == '\(bundleId)'",
            "--last", "1h",
            "--style", "compact",
            "--info", // 包含 info 级别日志
        ])
        allLogs += "\n--- Application Logs ---\n"
        allLogs += appLogs.isEmpty ? "(No logs found)\n" : appLogs

        // 添加内存中的日志缓存（如果有）
        let cachedLogs = LogBuffer.shared.getLogs()
        if !cachedLogs.isEmpty {
            allLogs += "\n--- In-Memory Log Buffer ---\n"
            allLogs += cachedLogs.joined(separator: "\n")
            allLogs += "\n"
        }

        return allLogs
    }

    /// 执行 log 命令并返回输出
    private func runLogCommand(_ arguments: [String]) async throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/log")
        process.arguments = arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }

    @IBAction func toggleDeviceBezel(_ sender: Any?) {
        UserPreferences.shared.showDeviceBezel.toggle()
        // 更新工具栏按钮图标
        if let item = toggleBezelToolbarItem {
            updateBezelToolbarItemImage(item)
        }
    }

    @IBAction func togglePreventSleep(_ sender: Any?) {
        UserPreferences.shared.preventAutoLockDuringCapture.toggle()
        // 更新工具栏按钮图标
        if let item = preventSleepToolbarItem {
            updatePreventSleepToolbarItemImage(item)
        }
    }

    @objc private func layoutModeChanged(_ sender: NSSegmentedControl) {
        let selectedIndex = sender.selectedSegment
        guard selectedIndex >= 0, selectedIndex < PreviewLayoutMode.allCases.count else { return }

        let newMode = PreviewLayoutMode.allCases[selectedIndex]
        UserPreferences.shared.layoutMode = newMode
    }

    private func startRefreshLoading() {
        isRefreshing = true
        refreshToolbarItem?.isEnabled = false
    }

    private func stopRefreshLoading() {
        isRefreshing = false
        refreshToolbarItem?.isEnabled = true
    }

    @MainActor
    private func showRefreshToast() {
        ToastView.success(L10n.toolbar.refreshComplete, in: mainWindow)
    }
}

// MARK: - 工具栏代理

extension AppDelegate: NSToolbarDelegate {
    private enum ToolbarItemIdentifier {
        static let layoutMode = NSToolbarItem.Identifier("layoutMode")
        static let refresh = NSToolbarItem.Identifier("refresh")
        static let toggleBezel = NSToolbarItem.Identifier("toggleBezel")
        static let preventSleep = NSToolbarItem.Identifier("preventSleep")
        static let preferences = NSToolbarItem.Identifier("preferences")
        static let flexibleSpace = NSToolbarItem.Identifier.flexibleSpace
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [
            .flexibleSpace,
            ToolbarItemIdentifier.layoutMode,
            .flexibleSpace,
            ToolbarItemIdentifier.refresh,
            .flexibleSpace,
            ToolbarItemIdentifier.preferences,
        ]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [
            ToolbarItemIdentifier.refresh,
            ToolbarItemIdentifier.layoutMode,
            .flexibleSpace,
            .space,
            ToolbarItemIdentifier.preferences,
        ]
    }

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        switch itemIdentifier {
        case ToolbarItemIdentifier.layoutMode:
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.label = L10n.toolbar.layoutMode
            item.paletteLabel = L10n.toolbar.layoutMode
            item.toolTip = L10n.toolbar.layoutModeTooltip

            // 创建分段控件
            let segmentedControl = NSSegmentedControl()
            segmentedControl.segmentStyle = .separated
            segmentedControl.trackingMode = .selectOne
            segmentedControl.segmentCount = 3

            // 设置每个分段的图标
            for (index, mode) in PreviewLayoutMode.allCases.enumerated() {
                segmentedControl.setImage(
                    NSImage(systemSymbolName: mode.iconName, accessibilityDescription: mode.displayName),
                    forSegment: index
                )
                segmentedControl.setToolTip(mode.displayName, forSegment: index)
                segmentedControl.setWidth(32, forSegment: index)
            }

            // 读取当前布局模式
            let currentMode = UserPreferences.shared.layoutMode
            if let index = PreviewLayoutMode.allCases.firstIndex(of: currentMode) {
                segmentedControl.selectedSegment = index
            }

            segmentedControl.target = self
            segmentedControl.action = #selector(layoutModeChanged(_:))

            item.view = segmentedControl
            layoutModeToolbarItem = item
            layoutModeSegmentedControl = segmentedControl
            return item

        case ToolbarItemIdentifier.refresh:
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.label = L10n.toolbar.refresh
            item.paletteLabel = L10n.toolbar.refresh
            item.toolTip = L10n.toolbar.refreshTooltip
            item.image = NSImage(
                systemSymbolName: "arrow.clockwise",
                accessibilityDescription: L10n.toolbar.refresh
            )
            item.target = self
            item.action = #selector(refreshDevices(_:))
            refreshToolbarItem = item
            return item

        case ToolbarItemIdentifier.toggleBezel:
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.label = L10n.toolbar.toggleBezel
            item.paletteLabel = L10n.toolbar.toggleBezel
            item.toolTip = L10n.toolbar.toggleBezelTooltip
            updateBezelToolbarItemImage(item)
            item.target = self
            item.action = #selector(toggleDeviceBezel(_:))
            toggleBezelToolbarItem = item
            return item

        case ToolbarItemIdentifier.preventSleep:
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.label = L10n.toolbar.preventSleep
            item.paletteLabel = L10n.toolbar.preventSleep
            item.toolTip = L10n.toolbar.preventSleepTooltip
            updatePreventSleepToolbarItemImage(item)
            item.target = self
            item.action = #selector(togglePreventSleep(_:))
            preventSleepToolbarItem = item
            return item

        case ToolbarItemIdentifier.preferences:
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.label = L10n.toolbar.preferences
            item.paletteLabel = L10n.toolbar.preferences
            item.toolTip = L10n.toolbar.preferencesTooltip
            item.image = NSImage(systemSymbolName: "gear", accessibilityDescription: L10n.toolbar.preferences)
            item.target = self
            item.action = #selector(showPreferences(_:))
            return item

        default:
            return nil
        }
    }

    private func updateBezelToolbarItemImage(_ item: NSToolbarItem) {
        let showBezel = UserPreferences.shared.showDeviceBezel
        // 使用不同的图标表示当前状态
        let symbolName = showBezel ? "iphone" : "iphone.slash"
        item.image = NSImage(
            systemSymbolName: symbolName,
            accessibilityDescription: showBezel ? L10n.toolbar.hideBezel : L10n.toolbar.showBezel
        )
    }

    private func updatePreventSleepToolbarItemImage(_ item: NSToolbarItem) {
        let enabled = UserPreferences.shared.preventAutoLockDuringCapture
        // moon.zzz.fill = 阻止休眠（启用）；moon.zzz = 允许休眠（禁用）
        let symbolName = enabled ? "moon.zzz.fill" : "moon.zzz"
        item.image = NSImage(
            systemSymbolName: symbolName,
            accessibilityDescription: enabled ? L10n.toolbar.preventSleepOn : L10n.toolbar.preventSleepOff
        )
    }
}
