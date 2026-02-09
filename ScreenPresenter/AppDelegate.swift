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
import MarkdownEditor

// MARK: - 应用程序委托

final class AppDelegate: NSObject, NSApplicationDelegate, FormatMenuProvider {
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
    private var markdownToggleToolbarItem: NSToolbarItem?
    private var isRefreshing: Bool = false

    // MARK: - 菜单项

    private var bezelMenuItem: NSMenuItem?
    private var preventSleepMenuItem: NSMenuItem?
    private var markdownMenu: NSMenu?
    private var markdownToggleMenuItem: NSMenuItem?
    private var recentFilesMenu: NSMenu?
    private var markdownThemeMenu: NSMenu?
    
    /// FormatMenuProvider 协议 - 格式标题子菜单
    private(set) var formatHeadersMenu: NSMenu?

    // MARK: - 关闭状态

    private var isClosingWindowAfterMarkdownConfirmation = false
    private var isTerminationCloseApproved = false

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

        // 监听布局模式变化（含偏好设置窗口触发）
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleLayoutModePreferenceChange),
            name: .layoutModeDidChange,
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

    @objc private func handleLayoutModePreferenceChange() {
        updateLayoutModeToolbarState()
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
        markdownToggleToolbarItem = nil

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

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let mainViewController else {
            return .terminateNow
        }

        // 第一步：处理未保存的文档
        mainViewController.requestCloseMarkdownIfNeeded { [weak self] shouldProceed in
            guard let self, shouldProceed else {
                // 用户取消了保存操作
                NSApp.reply(toApplicationShouldTerminate: false)
                return
            }

            // 第二步：显示退出确认对话框
            self.showQuitConfirmation { confirmed in
                self.isTerminationCloseApproved = confirmed
                NSApp.reply(toApplicationShouldTerminate: confirmed)
            }
        }
        return .terminateLater
    }

    /// 显示退出确认对话框
    private func showQuitConfirmation(completion: @escaping (Bool) -> Void) {
        let alert = NSAlert()
        alert.messageText = L10n.alert.quitConfirmTitle
        alert.informativeText = L10n.alert.quitConfirmMessage
        alert.alertStyle = .warning
        alert.addButton(withTitle: L10n.alert.quit)
        alert.addButton(withTitle: L10n.alert.cancel)

        let response = alert.runModal()
        completion(response == .alertFirstButtonReturn)
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

        // 编辑菜单（标准操作：撤销、剪切、复制、粘贴等）
        let editMenu = NSMenu(title: L10n.menu.edit)
        let editMenuItem = NSMenuItem()
        editMenuItem.submenu = editMenu

        editMenu.addItem(
            withTitle: L10n.menu.undo,
            action: #selector(UndoManager.undo),
            keyEquivalent: "z"
        )
        editMenu.addItem(
            withTitle: L10n.menu.redo,
            action: #selector(UndoManager.redo),
            keyEquivalent: "Z"
        )
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(
            withTitle: L10n.menu.cut,
            action: #selector(NSText.cut(_:)),
            keyEquivalent: "x"
        )
        editMenu.addItem(
            withTitle: L10n.menu.copy,
            action: #selector(NSText.copy(_:)),
            keyEquivalent: "c"
        )
        editMenu.addItem(
            withTitle: L10n.menu.paste,
            action: #selector(NSText.paste(_:)),
            keyEquivalent: "v"
        )
        editMenu.addItem(
            withTitle: L10n.menu.selectAll,
            action: #selector(NSText.selectAll(_:)),
            keyEquivalent: "a"
        )

        editMenu.addItem(NSMenuItem.separator())

        // 查找子菜单
        let findMenu = NSMenu(title: L10n.menu.find)
        let findMenuItem = editMenu.addItem(
            withTitle: L10n.menu.find,
            action: nil,
            keyEquivalent: ""
        )
        findMenuItem.submenu = findMenu

        findMenu.addItem(
            withTitle: L10n.menu.findAndReplace,
            action: #selector(performFindPanelAction(_:)),
            keyEquivalent: "f"
        ).tag = Int(NSTextFinder.Action.showFindInterface.rawValue)

        findMenu.addItem(
            withTitle: L10n.menu.findNext,
            action: #selector(performFindPanelAction(_:)),
            keyEquivalent: "g"
        ).tag = Int(NSTextFinder.Action.nextMatch.rawValue)

        let findPrevItem = findMenu.addItem(
            withTitle: L10n.menu.findPrevious,
            action: #selector(performFindPanelAction(_:)),
            keyEquivalent: "G"
        )
        findPrevItem.tag = Int(NSTextFinder.Action.previousMatch.rawValue)

        findMenu.addItem(NSMenuItem.separator())

        let useSelItem = findMenu.addItem(
            withTitle: L10n.menu.useSelectionForFind,
            action: #selector(performFindPanelAction(_:)),
            keyEquivalent: "e"
        )
        useSelItem.tag = Int(NSTextFinder.Action.setSearchString.rawValue)

        mainMenu.addItem(editMenuItem)

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

        // Markdown 菜单
        let mdMenu = NSMenu(title: L10n.markdown.menu)
        let mdMenuItem = NSMenuItem()
        mdMenuItem.submenu = mdMenu
        markdownMenu = mdMenu

        // 新建
        let newItem = mdMenu.addItem(
            withTitle: L10n.markdown.new,
            action: #selector(newMarkdownFile(_:)),
            keyEquivalent: "n"
        )
        newItem.keyEquivalentModifierMask = [.command, .shift]
        newItem.image = symbolImage("doc.badge.plus")

        // 从剪切板新建
        let newFromClipboardItem = mdMenu.addItem(
            withTitle: L10n.markdown.newFromClipboard,
            action: #selector(newMarkdownFromClipboard(_:)),
            keyEquivalent: "n"
        )
        newFromClipboardItem.keyEquivalentModifierMask = [.command, .shift, .option]
        newFromClipboardItem.image = symbolImage("clipboard")

        // 新建标签页
        let newTabItem = mdMenu.addItem(
            withTitle: L10n.markdown.newTab,
            action: #selector(newMarkdownTab(_:)),
            keyEquivalent: "t"
        )
        newTabItem.keyEquivalentModifierMask = [.command]
        newTabItem.image = symbolImage("plus.rectangle.on.rectangle")

        // 打开
        let openItem = mdMenu.addItem(
            withTitle: L10n.markdown.open,
            action: #selector(openMarkdownFile(_:)),
            keyEquivalent: "o"
        )
        openItem.keyEquivalentModifierMask = [.command, .shift]
        openItem.image = symbolImage("folder")

        // 打开最近使用 - 子菜单
        let recentMenu = NSMenu(title: L10n.markdown.openRecent)
        let recentMenuItem = mdMenu.addItem(
            withTitle: L10n.markdown.openRecent,
            action: nil,
            keyEquivalent: ""
        )
        recentMenuItem.submenu = recentMenu
        recentMenuItem.image = symbolImage("clock.arrow.circlepath")
        recentFilesMenu = recentMenu
        recentMenu.delegate = self
        updateRecentFilesMenu()

        mdMenu.addItem(NSMenuItem.separator())

        // 保存
        let saveItem = mdMenu.addItem(
            withTitle: L10n.markdown.save,
            action: #selector(saveMarkdownFile(_:)),
            keyEquivalent: "s"
        )
        saveItem.keyEquivalentModifierMask = [.command]
        saveItem.image = symbolImage("square.and.arrow.down")

        // 另存为
        let saveAsItem = mdMenu.addItem(
            withTitle: L10n.markdown.saveAs,
            action: #selector(saveMarkdownFileAs(_:)),
            keyEquivalent: "s"
        )
        saveAsItem.keyEquivalentModifierMask = [.command, .shift]
        saveAsItem.image = symbolImage("square.and.arrow.down.on.square")

        mdMenu.addItem(NSMenuItem.separator())

        // 缩放
        let zoomInItem = mdMenu.addItem(
            withTitle: L10n.markdown.zoomIn,
            action: #selector(zoomInMarkdownEditor(_:)),
            keyEquivalent: "+"
        )
        zoomInItem.keyEquivalentModifierMask = [.command]
        zoomInItem.image = symbolImage("plus.magnifyingglass")

        let zoomOutItem = mdMenu.addItem(
            withTitle: L10n.markdown.zoomOut,
            action: #selector(zoomOutMarkdownEditor(_:)),
            keyEquivalent: "-"
        )
        zoomOutItem.keyEquivalentModifierMask = [.command]
        zoomOutItem.image = symbolImage("minus.magnifyingglass")

        mdMenu.addItem(NSMenuItem.separator())

        // 格式子菜单
        setupFormatSubmenu(in: mdMenu)

        mdMenu.addItem(NSMenuItem.separator())

        // 编辑器位置子菜单
        let positionMenu = NSMenu(title: L10n.markdown.position)
        for position in MarkdownEditorPosition.allCases {
            let title: String
            switch position {
            case .center: title = L10n.markdown.positionCenter
            case .left: title = L10n.markdown.positionLeft
            case .right: title = L10n.markdown.positionRight
            }
            let item = positionMenu.addItem(
                withTitle: title,
                action: #selector(setMarkdownEditorPosition(_:)),
                keyEquivalent: ""
            )
            item.tag = MarkdownEditorPosition.allCases.firstIndex(of: position) ?? 0
            item.state = (UserPreferences.shared.markdownEditorPosition == position) ? .on : .off
            switch position {
            case .center:
                item.image = symbolImage("rectangle.split.3x1")
            case .left:
                item.image = symbolImage("sidebar.left")
            case .right:
                item.image = symbolImage("sidebar.right")
            }
        }
        let positionMenuItem = mdMenu.addItem(
            withTitle: L10n.markdown.position,
            action: nil,
            keyEquivalent: ""
        )
        positionMenuItem.submenu = positionMenu
        positionMenuItem.image = symbolImage("rectangle.split.3x1")

        // 主题子菜单
        let themeMenu = NSMenu(title: L10n.markdown.theme)
        markdownThemeMenu = themeMenu
        let themeModes: [MarkdownEditorThemeMode] = [.system, .light, .dark]
        for mode in themeModes {
            let title: String
            switch mode {
            case .system:
                title = L10n.markdown.themeSystem
            case .light:
                title = L10n.markdown.themeLight
            case .dark:
                title = L10n.markdown.themeDark
            }

            let item = themeMenu.addItem(
                withTitle: title,
                action: #selector(setMarkdownThemeMode(_:)),
                keyEquivalent: ""
            )
            item.tag = themeModes.firstIndex(of: mode) ?? 0
            item.state = (UserPreferences.shared.markdownThemeMode == mode) ? .on : .off
            switch mode {
            case .system:
                item.image = symbolImage("circle.lefthalf.striped.horizontal")
            case .light:
                item.image = symbolImage("sun.max")
            case .dark:
                item.image = symbolImage("moon")
            }
        }
        let themeMenuItem = mdMenu.addItem(
            withTitle: L10n.markdown.theme,
            action: nil,
            keyEquivalent: ""
        )
        themeMenuItem.submenu = themeMenu
        themeMenuItem.image = symbolImage("paintbrush")

        mdMenu.addItem(NSMenuItem.separator())

        // 显示/隐藏编辑器
        let toggleItem = mdMenu.addItem(
            withTitle: L10n.markdown.toggle,
            action: #selector(toggleMarkdownEditor(_:)),
            keyEquivalent: "e"
        )
        toggleItem.keyEquivalentModifierMask = [.command]
        toggleItem.image = symbolImage("sidebar.right")
        markdownToggleMenuItem = toggleItem

        // 关闭当前标签页
        let closeTabItem = mdMenu.addItem(
            withTitle: L10n.markdown.closeTab,
            action: #selector(closeCurrentMarkdownTab(_:)),
            keyEquivalent: "w"
        )
        closeTabItem.keyEquivalentModifierMask = [.command, .option]
        closeTabItem.image = symbolImage("xmark.rectangle")

        mainMenu.addItem(mdMenuItem)

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

    /// 设置格式子菜单（在 Markdown 菜单内）
    private func setupFormatSubmenu(in parentMenu: NSMenu) {
        let formatMenu = NSMenu(title: L10n.menu.format)
        let formatMenuItem = parentMenu.addItem(
            withTitle: L10n.menu.format,
            action: nil,
            keyEquivalent: ""
        )
        formatMenuItem.submenu = formatMenu
        formatMenuItem.image = symbolImage("textformat")

        let boldItem = formatMenu.addItem(
            withTitle: L10n.menu.bold,
            action: #selector(toggleBold(_:)),
            keyEquivalent: "b"
        )
        boldItem.image = symbolImage("bold")

        let italicItem = formatMenu.addItem(
            withTitle: L10n.menu.italic,
            action: #selector(toggleItalic(_:)),
            keyEquivalent: "i"
        )
        italicItem.image = symbolImage("italic")

        let strikeItem = formatMenu.addItem(
            withTitle: L10n.menu.strikethrough,
            action: #selector(toggleStrikethrough(_:)),
            keyEquivalent: "u"
        )
        strikeItem.keyEquivalentModifierMask = [.command, .shift]
        strikeItem.image = symbolImage("strikethrough")

        let inlineCodeItem = formatMenu.addItem(
            withTitle: L10n.menu.inlineCode,
            action: #selector(toggleInlineCode(_:)),
            keyEquivalent: "`"
        )
        inlineCodeItem.image = symbolImage("chevron.left.forwardslash.chevron.right")

        formatMenu.addItem(NSMenuItem.separator())

        // 标题子菜单
        let headingMenu = NSMenu(title: L10n.menu.heading)
        let headingMenuItem = formatMenu.addItem(
            withTitle: L10n.menu.heading,
            action: nil,
            keyEquivalent: ""
        )
        headingMenuItem.submenu = headingMenu
        headingMenuItem.image = symbolImage("textformat.size")
        formatHeadersMenu = headingMenu

        let heading1Item = headingMenu.addItem(
            withTitle: L10n.menu.heading1,
            action: #selector(toggleHeading(_:)),
            keyEquivalent: "1"
        )
        heading1Item.keyEquivalentModifierMask = [.command]
        heading1Item.image = symbolImage("1.circle")

        let heading2Item = headingMenu.addItem(
            withTitle: L10n.menu.heading2,
            action: #selector(toggleHeading(_:)),
            keyEquivalent: "2"
        )
        heading2Item.keyEquivalentModifierMask = [.command]
        heading2Item.image = symbolImage("2.circle")

        let heading3Item = headingMenu.addItem(
            withTitle: L10n.menu.heading3,
            action: #selector(toggleHeading(_:)),
            keyEquivalent: "3"
        )
        heading3Item.keyEquivalentModifierMask = [.command]
        heading3Item.image = symbolImage("3.circle")

        let heading4Item = headingMenu.addItem(
            withTitle: L10n.menu.heading4,
            action: #selector(toggleHeading(_:)),
            keyEquivalent: "4"
        )
        heading4Item.keyEquivalentModifierMask = [.command]
        heading4Item.image = symbolImage("4.circle")

        let heading5Item = headingMenu.addItem(
            withTitle: L10n.menu.heading5,
            action: #selector(toggleHeading(_:)),
            keyEquivalent: "5"
        )
        heading5Item.keyEquivalentModifierMask = [.command]
        heading5Item.image = symbolImage("5.circle")

        let heading6Item = headingMenu.addItem(
            withTitle: L10n.menu.heading6,
            action: #selector(toggleHeading(_:)),
            keyEquivalent: "6"
        )
        heading6Item.keyEquivalentModifierMask = [.command]
        heading6Item.image = symbolImage("6.circle")

        // 为每个标题菜单项设置 tag（表示 heading level）
        for (index, item) in headingMenu.items.enumerated() {
            item.tag = index + 1
        }

        formatMenu.addItem(NSMenuItem.separator())

        let bulletItem = formatMenu.addItem(
            withTitle: L10n.menu.bulletList,
            action: #selector(toggleBullet(_:)),
            keyEquivalent: "l"
        )
        bulletItem.keyEquivalentModifierMask = [.command, .shift]
        bulletItem.image = symbolImage("list.bullet")

        let numberedItem = formatMenu.addItem(
            withTitle: L10n.menu.numberedList,
            action: #selector(toggleNumbering(_:)),
            keyEquivalent: "l"
        )
        numberedItem.keyEquivalentModifierMask = [.command, .option]
        numberedItem.image = symbolImage("list.number")

        let blockquoteItem = formatMenu.addItem(
            withTitle: L10n.menu.blockquote,
            action: #selector(toggleBlockquote(_:)),
            keyEquivalent: "'"
        )
        blockquoteItem.keyEquivalentModifierMask = [.command, .shift]
        blockquoteItem.image = symbolImage("text.quote")

        let codeBlockItem = formatMenu.addItem(
            withTitle: L10n.menu.codeBlock,
            action: #selector(insertCodeBlock(_:)),
            keyEquivalent: "k"
        )
        codeBlockItem.keyEquivalentModifierMask = [.command, .shift]
        codeBlockItem.image = symbolImage("chevron.left.forwardslash.chevron.right")

        formatMenu.addItem(NSMenuItem.separator())

        let linkItem = formatMenu.addItem(
            withTitle: L10n.menu.insertLink,
            action: #selector(insertLink(_:)),
            keyEquivalent: "k"
        )
        linkItem.image = symbolImage("link")

        let imageItem = formatMenu.addItem(
            withTitle: L10n.menu.insertImage,
            action: #selector(insertImage(_:)),
            keyEquivalent: "i"
        )
        imageItem.keyEquivalentModifierMask = [.command, .shift]
        imageItem.image = symbolImage("photo")

        let tableItem = formatMenu.addItem(
            withTitle: L10n.menu.insertTable,
            action: #selector(insertTable(_:)),
            keyEquivalent: "t"
        )
        tableItem.keyEquivalentModifierMask = [.command, .option]
        tableItem.image = symbolImage("tablecells")

        let horizontalRuleItem = formatMenu.addItem(
            withTitle: L10n.menu.insertHorizontalRule,
            action: #selector(insertHorizontalRule(_:)),
            keyEquivalent: "-"
        )
        horizontalRuleItem.keyEquivalentModifierMask = [.command, .shift]
        horizontalRuleItem.image = symbolImage("minus")
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
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard sender == mainWindow else {
            return true
        }

        if isTerminationCloseApproved {
            return true
        }

        if isClosingWindowAfterMarkdownConfirmation {
            isClosingWindowAfterMarkdownConfirmation = false
            return true
        }

        guard let mainViewController else {
            return true
        }

        mainViewController.requestCloseMarkdownIfNeeded { [weak self, weak sender] shouldClose in
            guard let self, let sender else { return }
            guard shouldClose else { return }
            self.isClosingWindowAfterMarkdownConfirmation = true
            sender.performClose(nil)
        }
        return false
    }

    func windowWillClose(_ notification: Notification) {
        AppLogger.app.info("主窗口即将关闭")
        isTerminationCloseApproved = false
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
        let bundleId = Bundle.main.bundleIdentifier ?? "com.haptictide.ScreenPresenter"
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

    @objc private func selectDualLayoutMode(_ sender: Any?) {
        setLayoutMode(.dual)
    }

    @objc private func selectLeftOnlyLayoutMode(_ sender: Any?) {
        setLayoutMode(.leftOnly)
    }

    @objc private func selectRightOnlyLayoutMode(_ sender: Any?) {
        setLayoutMode(.rightOnly)
    }

    @objc private func layoutModeSegmentChanged(_ sender: NSSegmentedControl) {
        switch sender.selectedSegment {
        case 0:  // 双设备
            setLayoutMode(.dual)
        case 1:  // 交换面板
            swapPanels(sender)
            // 交换后恢复到之前选中的布局模式
            updateLayoutModeToolbarState()
        case 2:  // 左侧设备
            setLayoutMode(.leftOnly)
        case 3:  // 右侧设备
            setLayoutMode(.rightOnly)
        default:
            break
        }
    }

    private func setLayoutMode(_ newMode: PreviewLayoutMode) {
        UserPreferences.shared.layoutMode = newMode
        updateLayoutModeToolbarState()
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

    // MARK: - 面板交换操作

    @IBAction func swapPanels(_ sender: Any?) {
        mainViewController?.swapPanels()
    }

    // MARK: - Markdown 编辑器操作

    @IBAction func newMarkdownFile(_ sender: Any?) {
        mainViewController?.newMarkdownFile()
    }

    @IBAction func newMarkdownTab(_ sender: Any?) {
        mainViewController?.newMarkdownTab()
    }

    @IBAction func newMarkdownFromClipboard(_ sender: Any?) {
        mainViewController?.newMarkdownFromClipboard()
    }

    @IBAction func toggleMarkdownEditor(_ sender: Any?) {
        mainViewController?.toggleMarkdownEditor()
        updateMarkdownToolbarAndMenu()
    }

    @IBAction func openMarkdownFile(_ sender: Any?) {
        mainViewController?.openMarkdownFile()
    }

    @IBAction func openRecentFile(_ sender: NSMenuItem) {
        guard let path = sender.representedObject as? String else { return }
        let url = URL(fileURLWithPath: path)
        mainViewController?.openMarkdownFile(url: url)
    }

    @IBAction func closeCurrentMarkdownTab(_ sender: Any?) {
        mainViewController?.closeCurrentMarkdownTab()
    }

    @IBAction func clearRecentFiles(_ sender: Any?) {
        UserPreferences.shared.recentMarkdownFiles = []
        updateRecentFilesMenu()
    }

    @IBAction func saveMarkdownFile(_ sender: Any?) {
        mainViewController?.saveMarkdownFile()
    }

    @IBAction func saveMarkdownFileAs(_ sender: Any?) {
        mainViewController?.saveMarkdownFileAs()
    }

    @IBAction func zoomInMarkdownEditor(_ sender: Any?) {
        mainViewController?.zoomInMarkdownEditor()
    }

    @IBAction func zoomOutMarkdownEditor(_ sender: Any?) {
        mainViewController?.zoomOutMarkdownEditor()
    }

    @objc private func setMarkdownEditorPosition(_ sender: NSMenuItem) {
        guard sender.tag < MarkdownEditorPosition.allCases.count else { return }
        let position = MarkdownEditorPosition.allCases[sender.tag]
        UserPreferences.shared.markdownEditorPosition = position
        mainViewController?.setMarkdownEditorPosition(position)

        // 更新菜单状态
        if let positionMenu = sender.menu {
            for item in positionMenu.items {
                item.state = item.tag == sender.tag ? .on : .off
            }
        }
    }

    @objc private func setMarkdownThemeMode(_ sender: NSMenuItem) {
        let modes: [MarkdownEditorThemeMode] = [.system, .light, .dark]
        guard sender.tag >= 0, sender.tag < modes.count else { return }
        let mode = modes[sender.tag]
        UserPreferences.shared.markdownThemeMode = mode
        mainViewController?.setMarkdownThemeMode(mode)

        if let themeMenu = markdownThemeMenu {
            for item in themeMenu.items {
                item.state = item.tag == sender.tag ? .on : .off
            }
        }
    }

    private func updateRecentFilesMenu() {
        guard let menu = recentFilesMenu else { return }

        menu.removeAllItems()

        let recentFiles = UserPreferences.shared.recentMarkdownFiles
        if recentFiles.isEmpty {
            let emptyItem = menu.addItem(
                withTitle: L10n.markdown.noRecentFiles,
                action: nil,
                keyEquivalent: ""
            )
            emptyItem.isEnabled = false
            emptyItem.image = symbolImage("tray")
        } else {
            for path in recentFiles {
                let url = URL(fileURLWithPath: path)
                let item = menu.addItem(
                    withTitle: url.lastPathComponent,
                    action: #selector(openRecentFile(_:)),
                    keyEquivalent: ""
                )
                item.representedObject = path
                item.toolTip = path
                item.image = symbolImage("doc.text")
            }

            menu.addItem(NSMenuItem.separator())

            let clearItem = menu.addItem(
                withTitle: L10n.markdown.clearRecent,
                action: #selector(clearRecentFiles(_:)),
                keyEquivalent: ""
            )
            clearItem.image = symbolImage("trash")
        }
    }

    private func updateMarkdownToolbarAndMenu() {
        let isVisible = UserPreferences.shared.markdownEditorVisible
        // 更新工具栏按钮图标
        if let item = markdownToggleToolbarItem {
            updateMarkdownToggleToolbarItemImage(item)
        }
        // 更新菜单项标题
        markdownToggleMenuItem?.title = isVisible ? L10n.markdown.toggle : L10n.markdown.toggle
    }

    private func updateMarkdownToggleToolbarItemImage(_ item: NSToolbarItem) {
        let isVisible = UserPreferences.shared.markdownEditorVisible
        let symbolName = isVisible ? "doc.richtext.fill" : "doc.richtext"
        let image = NSImage(
            systemSymbolName: symbolName,
            accessibilityDescription: L10n.toolbar.markdownEditorTooltip
        )
        item.image = image
    }

    private func updateLayoutModeToolbarState() {
        guard let segmentedControl = layoutModeSegmentedControl else { return }
        let currentMode = UserPreferences.shared.layoutMode
        // 段索引: 0=dual, 1=swap, 2=leftOnly, 3=rightOnly
        switch currentMode {
        case .dual:
            segmentedControl.selectedSegment = 0
        case .leftOnly:
            segmentedControl.selectedSegment = 2
        case .rightOnly:
            segmentedControl.selectedSegment = 3
        }
        // 交换按钮仅在双设备模式下可用
        let shouldEnableSwap = currentMode == .dual
        segmentedControl.setEnabled(shouldEnableSwap, forSegment: 1)
    }

    private func symbolImage(_ name: String) -> NSImage? {
        NSImage(systemSymbolName: name, accessibilityDescription: nil)
    }
}

// MARK: - 菜单代理

extension AppDelegate: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu === recentFilesMenu else { return }
        updateRecentFilesMenu()
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
        static let markdownToggle = NSToolbarItem.Identifier("markdownToggle")
        static let flexibleSpace = NSToolbarItem.Identifier.flexibleSpace
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [
            ToolbarItemIdentifier.markdownToggle,
            .space,
            ToolbarItemIdentifier.layoutMode,
            .space,
            ToolbarItemIdentifier.refresh,
            .space,
            ToolbarItemIdentifier.preferences,
        ]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [
            ToolbarItemIdentifier.refresh,
            ToolbarItemIdentifier.markdownToggle,
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

            // 使用 NSSegmentedControl 实现标准工具栏按钮组
            let segmentedControl = NSSegmentedControl()
            segmentedControl.segmentCount = 4
            segmentedControl.trackingMode = .selectOne
            segmentedControl.segmentStyle = .separated
            segmentedControl.target = self
            segmentedControl.action = #selector(layoutModeSegmentChanged(_:))

            // 段 0: 双设备
            segmentedControl.setImage(
                NSImage(systemSymbolName: PreviewLayoutMode.dual.iconName, accessibilityDescription: PreviewLayoutMode.dual.displayName),
                forSegment: 0
            )
            segmentedControl.setToolTip(PreviewLayoutMode.dual.displayName, forSegment: 0)

            // 段 1: 交换面板
            segmentedControl.setImage(
                NSImage(systemSymbolName: "arrow.left.arrow.right", accessibilityDescription: L10n.toolbar.swapPanels),
                forSegment: 1
            )
            segmentedControl.setToolTip(L10n.toolbar.swapPanelsTooltip, forSegment: 1)

            // 段 2: 左侧设备
            segmentedControl.setImage(
                NSImage(systemSymbolName: PreviewLayoutMode.leftOnly.iconName, accessibilityDescription: PreviewLayoutMode.leftOnly.displayName),
                forSegment: 2
            )
            segmentedControl.setToolTip(PreviewLayoutMode.leftOnly.displayName, forSegment: 2)

            // 段 3: 右侧设备
            segmentedControl.setImage(
                NSImage(systemSymbolName: PreviewLayoutMode.rightOnly.iconName, accessibilityDescription: PreviewLayoutMode.rightOnly.displayName),
                forSegment: 3
            )
            segmentedControl.setToolTip(PreviewLayoutMode.rightOnly.displayName, forSegment: 3)

            item.view = segmentedControl
            layoutModeToolbarItem = item
            layoutModeSegmentedControl = segmentedControl
            updateLayoutModeToolbarState()
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

        case ToolbarItemIdentifier.markdownToggle:
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.label = L10n.toolbar.markdownEditor
            item.paletteLabel = L10n.toolbar.markdownEditor
            item.toolTip = L10n.toolbar.markdownEditorTooltip
            item.target = self
            item.action = #selector(toggleMarkdownEditor(_:))
            markdownToggleToolbarItem = item
            updateMarkdownToggleToolbarItemImage(item)
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
            item.image = NSImage(
                systemSymbolName: "gear",
                accessibilityDescription: L10n.toolbar.preferences
            )
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

    // MARK: - 查找操作

    @objc
    private func performFindPanelAction(_ sender: NSMenuItem) {
        guard let action = NSTextFinder.Action(rawValue: sender.tag) else { return }
        mainViewController?.performTextFinderAction(action)
    }

    // MARK: - 格式操作

    @objc
    private func toggleBold(_ sender: Any?) {
        mainViewController?.toggleBold()
    }

    @objc
    private func toggleItalic(_ sender: Any?) {
        mainViewController?.toggleItalic()
    }

    @objc
    private func toggleStrikethrough(_ sender: Any?) {
        mainViewController?.toggleStrikethrough()
    }

    @objc
    private func toggleInlineCode(_ sender: Any?) {
        mainViewController?.toggleInlineCode()
    }

    @objc
    private func toggleHeading(_ sender: NSMenuItem) {
        mainViewController?.toggleHeading(level: sender.tag)
    }

    @objc
    private func toggleBullet(_ sender: Any?) {
        mainViewController?.toggleBullet()
    }

    @objc
    private func toggleNumbering(_ sender: Any?) {
        mainViewController?.toggleNumbering()
    }

    @objc
    private func toggleBlockquote(_ sender: Any?) {
        mainViewController?.toggleBlockquote()
    }

    @objc
    private func insertCodeBlock(_ sender: Any?) {
        mainViewController?.insertCodeBlock()
    }

    @objc
    private func insertLink(_ sender: Any?) {
        mainViewController?.insertLink()
    }

    @objc
    private func insertImage(_ sender: Any?) {
        mainViewController?.insertImage()
    }

    @objc
    private func insertTable(_ sender: Any?) {
        mainViewController?.insertTable()
    }

    @objc
    private func insertHorizontalRule(_ sender: Any?) {
        mainViewController?.insertHorizontalRule()
    }
}

// MARK: - NSMenuItemValidation

extension AppDelegate: NSMenuItemValidation {
    /// 格式化操作 - 预览模式下应禁用
    private static let formatActions: Set<Selector> = [
        #selector(toggleBold(_:)),
        #selector(toggleItalic(_:)),
        #selector(toggleStrikethrough(_:)),
        #selector(toggleInlineCode(_:)),
        #selector(toggleHeading(_:)),
        #selector(toggleBullet(_:)),
        #selector(toggleNumbering(_:)),
        #selector(toggleBlockquote(_:)),
        #selector(insertCodeBlock(_:)),
        #selector(insertLink(_:)),
        #selector(insertImage(_:)),
        #selector(insertTable(_:)),
        #selector(insertHorizontalRule(_:)),
    ]

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        guard let action = menuItem.action else { return true }

        // 检查是否为格式化操作且当前处于预览模式
        if Self.formatActions.contains(action) {
            // 获取当前活跃的编辑器的预览模式状态
            if let editorView = mainViewController?.markdownEditorView {
                return !editorView.isPreviewMode
            }
            return true
        }

        return true
    }
}
