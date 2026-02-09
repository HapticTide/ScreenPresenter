//
//  AppDelegate.swift
//  MarkdownEditor
//
//  Created by Sun on 2026/2/6.

import AppKit
import AppKitExtensions
import MarkdownKit
import SettingsUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    @IBOutlet var mainFileMenu: NSMenu?
    @IBOutlet var mainEditMenu: NSMenu?
    @IBOutlet var mainExtensionsMenu: NSMenu?
    @IBOutlet var mainWindowMenu: NSMenu?

    @IBOutlet var copyPandocCommandMenu: NSMenu?
    @IBOutlet var openFileInMenu: NSMenu?
    @IBOutlet var reopenFileMenu: NSMenu?
    @IBOutlet var lineEndingsMenu: NSMenu?
    @IBOutlet var editCommandsMenu: NSMenu?
    @IBOutlet var editTableOfContentsMenu: NSMenu?
    @IBOutlet var editFontMenu: NSMenu?
    @IBOutlet var editFindMenu: NSMenu?
    @IBOutlet var textFormatMenu: NSMenu?
    @IBOutlet var formatHeadersMenu: NSMenu?

    @IBOutlet var lineEndingsLFItem: NSMenuItem?
    @IBOutlet var lineEndingsCRLFItem: NSMenuItem?
    @IBOutlet var lineEndingsCRItem: NSMenuItem?
    @IBOutlet var fileFromClipboardItem: NSMenuItem?
    @IBOutlet var editUndoItem: NSMenuItem?
    @IBOutlet var editRedoItem: NSMenuItem?
    @IBOutlet var editPasteItem: NSMenuItem?
    @IBOutlet var editGotoLineItem: NSMenuItem?
    @IBOutlet var editReadOnlyItem: NSMenuItem?
    @IBOutlet var editStatisticsItem: NSMenuItem?
    @IBOutlet var editTypewriterItem: NSMenuItem?
    @IBOutlet var formatBulletItem: NSMenuItem?
    @IBOutlet var formatNumberingItem: NSMenuItem?
    @IBOutlet var formatTodoItem: NSMenuItem?
    @IBOutlet var formatCodeItem: NSMenuItem?
    @IBOutlet var formatCodeBlockItem: NSMenuItem?
    @IBOutlet var formatMathItem: NSMenuItem?
    @IBOutlet var formatMathBlockItem: NSMenuItem?
    @IBOutlet var windowFloatingItem: NSMenuItem?

    @IBOutlet var mainUpdateItem: NSMenuItem?
    @IBOutlet var presentUpdateItem: NSMenuItem?
    @IBOutlet var postponeUpdateItem: NSMenuItem?
    @IBOutlet var ignoreUpdateItem: NSMenuItem?

    private var appearanceObservation: NSKeyValueObservation?
    private var settingsWindowController: NSWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.appearance = AppPreferences.General.appearance.resolved()
        appearanceObservation = NSApp.observe(\.effectiveAppearance) { _, _ in
            Task { @MainActor in
                AppTheme.current.updateAppearance()
            }
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidResignKey(_:)),
            name: NSWindow.didResignKeyNotification,
            object: nil
        )

        // App level setting for "Ask to keep changes when closing documents"
        if let closeAlwaysConfirmsChanges = AppRuntimeConfig.closeAlwaysConfirmsChanges {
            UserDefaults.standard.set(closeAlwaysConfirmsChanges, forKey: NSCloseAlwaysConfirmsChanges)
        } else {
            UserDefaults.standard.removeObject(forKey: NSCloseAlwaysConfirmsChanges)
        }

        // Register global hot key to activate the document window, if provided
        if let hotKey = AppRuntimeConfig.mainWindowHotKey {
            AppHotKeys.register(keyEquivalent: hotKey.key, modifiers: hotKey.modifiers) {
                self.toggleDocumentWindowVisibility()
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            EditorReusePool.shared.warmUp()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            self.presentUpdateItem?.title = Localized.Updater.viewReleasePage
            self.postponeUpdateItem?.title = Localized.Updater.remindMeLater
            self.ignoreUpdateItem?.title = Localized.Updater.skipThisVersion

            DispatchQueue.global(qos: .utility).async {
                let defaults = UserDefaults.standard.dictionaryRepresentation()
                let plist = defaults.merging(AppRuntimeConfig.jsonObject) { _, rhs in rhs }
                let fileData = try? PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
                try? fileData?.write(to: AppCustomization.debugDirectory.fileURL.appending(path: "user-settings.xml"))
            }
        }

        // Install uncaught exception handler
        AppExceptionCatcher.install()
    }

    func applicationShouldTerminate(_ application: NSApplication) -> NSApplication.TerminateReply {
        if AppRuntimeConfig.autoSaveWhenIdle, NSDocumentController.shared.hasOutdatedDocuments {
            // Terminate after all outdated documents are saved
            Task {
                await NSDocumentController.shared.saveOutdatedDocuments()
                application.reply(toApplicationShouldTerminate: true)
            }

            return .terminateLater
        }

        return .terminateNow
    }

    func shouldOpenOrCreateDocument() -> Bool {
        if let settingsWindow = settingsWindowController?.window {
            // We don't open or create documents when the settings pane is the key and visible
            return !(settingsWindow.isKeyWindow && settingsWindow.isVisible)
        }

        return true
    }
}

// MARK: - URL Handling

extension AppDelegate {
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            switch components?.host {
            case "new-file":
                // screenpresenter://new-file?filename=Untitled&initial-content=Hello
                createNewFile(queryDict: components?.queryDict)
            case "open":
                // screenpresenter://open or screenpresenter://open?path=Untitled.md
                openFile(queryDict: components?.queryDict)
            default:
                break
            }
        }
    }
}

// MARK: - Private

private extension AppDelegate {
    @objc func windowDidResignKey(_ notification: Notification) {
        // To reduce the glitches between switching windows,
        // close openPanel once we don't have any key windows.
        //
        // Delay because there's no keyWindow during window transitions.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if NSApp.windows.allSatisfy({ !$0.isKeyWindow }) {
                NSApp.closeOpenPanels()
            }
        }
    }

    @IBAction func showPreferences(_ sender: Any?) {
        if settingsWindowController == nil {
            settingsWindowController = SettingsRootViewController.withTabs([
                .editor,
                .assistant,
                .general,
                .window,
            ])

            // The window size relies on the SwiftUI content view size, it takes time
            DispatchQueue.main.async {
                self.settingsWindowController?.showWindow(self)
            }
        } else {
            settingsWindowController?.showWindow(self)
        }
    }
}
