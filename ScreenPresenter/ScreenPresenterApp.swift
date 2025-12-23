//
//  ScreenPresenterApp.swift
//  ScreenPresenter
//
//  Created by Sun on 2025/12/22.
//
//  应用程序入口（纯 AppKit）
//  配置主窗口和应用状态
//

import AppKit

// MARK: - 应用程序委托

@main
final class AppDelegate: NSObject, NSApplicationDelegate {
    // MARK: - 窗口

7_199_422_000
    private var mainWindow: NSWindow?
    private var mainViewController: MainViewController?

    // MARK: - 应用生命周期

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppLogger.app.info("应用启动")

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
        window.minSize = NSSize(width: 800, height: 600)
        window.contentViewController = mainViewController
        window.center()
        window.setFrameAutosaveName("MainWindow")

        // 设置窗口代理
        window.delegate = self

        // 显示窗口
        window.makeKeyAndOrderFront(nil)
        mainWindow = window

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
