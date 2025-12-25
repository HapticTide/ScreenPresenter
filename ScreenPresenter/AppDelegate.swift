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
    private var isRefreshing: Bool = false

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
    }

    @objc private func handleBezelVisibilityChange() {
        // 更新工具栏按钮图标
        if let item = toggleBezelToolbarItem {
            updateBezelToolbarItemImage(item)
        }
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

        // 创建新工具栏
        setupWindowToolbar(for: window)
    }

    /// 请求摄像头权限
    private func requestCameraPermission() {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        AppLogger.app.info("摄像头权限状态: \(status.rawValue) (0=未确定, 1=受限, 2=拒绝, 3=已授权)")

        if status == .notDetermined {
            AppLogger.app.info("请求摄像头权限...")
            AVCaptureDevice.requestAccess(for: .video) { granted in
                AppLogger.app.info("摄像头权限请求结果: \(granted ? "已授权" : "已拒绝")")
            }
        } else if status == .denied {
            AppLogger.app.warning("摄像头权限已被拒绝，请在系统设置中开启")
        } else if status == .authorized {
            AppLogger.app.info("摄像头权限已授权")
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppLogger.app.info("应用即将退出")

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

        // 文件菜单
        let fileMenu = NSMenu(title: L10n.menu.file)
        let fileMenuItem = NSMenuItem()
        fileMenuItem.submenu = fileMenu

        fileMenu.addItem(
            withTitle: L10n.menu.refreshDevices,
            action: #selector(refreshDevices(_:)),
            keyEquivalent: "r"
        )
        fileMenu.addItem(NSMenuItem.separator())
        let closeItem = fileMenu.addItem(
            withTitle: L10n.menu.close,
            action: #selector(NSWindow.performClose(_:)),
            keyEquivalent: "w"
        )
        closeItem.target = nil

        mainMenu.addItem(fileMenuItem)

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

    @IBAction func toggleDeviceBezel(_ sender: Any?) {
        UserPreferences.shared.showDeviceBezel.toggle()
        // 更新工具栏按钮图标
        if let item = toggleBezelToolbarItem {
            updateBezelToolbarItemImage(item)
        }
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
        static let refresh = NSToolbarItem.Identifier("refresh")
        static let toggleBezel = NSToolbarItem.Identifier("toggleBezel")
        static let preferences = NSToolbarItem.Identifier("preferences")
        static let flexibleSpace = NSToolbarItem.Identifier.flexibleSpace
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [
            .flexibleSpace,
            ToolbarItemIdentifier.refresh,
            ToolbarItemIdentifier.toggleBezel,
            ToolbarItemIdentifier.preferences,
        ]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [
            .flexibleSpace,
            ToolbarItemIdentifier.refresh,
            ToolbarItemIdentifier.toggleBezel,
            ToolbarItemIdentifier.preferences,
        ]
    }

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        switch itemIdentifier {
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
}
