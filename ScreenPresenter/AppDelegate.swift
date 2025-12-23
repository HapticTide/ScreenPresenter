//
//  AppDelegate.swift
//  ScreenPresenter
//
//  Created by Sun on 2025/12/22.
//
//  应用程序入口（纯 AppKit）
//  配置主窗口和应用状态
//

import AppKit

// MARK: - 应用程序委托

final class AppDelegate: NSObject, NSApplicationDelegate {
    // MARK: - 窗口

    private var mainWindow: NSWindow?
    private var mainViewController: MainViewController?

    // MARK: - 应用生命周期

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppLogger.app.info("应用启动")

        // 创建主菜单（纯代码 AppKit 应用必须）
        setupMainMenu()

        // 启用 CoreMediaIO 屏幕捕获设备
        IOSScreenMirrorActivator.shared.enableDALDevices()

        // 创建主窗口
        setupMainWindow()

        // 初始化应用状态
        Task {
            await AppState.shared.initialize()
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
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )

        window.title = "ScreenPresenter"
        window.titlebarSeparatorStyle = .none
        window.minSize = NSSize(width: 800, height: 600)
        window.contentViewController = mainViewController
        window.center()
        window.setFrameAutosaveName("MainWindow")

        // 设置窗口代理
        window.delegate = self

        // 显示窗口
        window.makeKeyAndOrderFront(nil)
        mainWindow = window

        // 激活应用（确保窗口显示在最前面）
        NSApp.activate(ignoringOtherApps: true)

        AppLogger.app.info("主窗口已创建")
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
}

// MARK: - 菜单操作

extension AppDelegate {
    @IBAction func showPreferences(_ sender: Any?) {
        PreferencesWindowController.shared.showWindow(nil)
    }

    @IBAction func refreshDevices(_ sender: Any?) {
        Task {
            await AppState.shared.refreshDevices()
        }
    }
}
