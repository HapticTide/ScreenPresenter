//
//  EditorToolbarItems.swift
//  MarkdownEditor
//
//  Created by Sun on 2026/2/6.
//

import AppKit
import MarkdownKit

extension NSToolbarItem {
    static func with(identifier: NSToolbarItem.Identifier, menu: NSMenu?) -> NSMenuToolbarItem {
        let item = NSMenuToolbarItem(itemIdentifier: identifier)
        item.label = identifier.itemLabel
        item.image = NSImage(systemSymbolName: identifier.itemIcon, accessibilityDescription: item.label)

        // Special icon for Writing Tools
        if #available(macOS 15.1, *), identifier == .writingTools {
            item.image = MarkdownWritingTools.affordanceIcon ?? item.image
        }

        if let menu {
            menu.needsHack = true
            item.menu = menu
        } else {
            Logger.log(.error, "Missing menu for NSMenuToolbarItem")
        }

        return item
    }

    static func with(
        identifier: NSToolbarItem.Identifier,
        iconSize: Double? = nil,
        action: @escaping () -> Void
    ) -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.label = identifier.itemLabel

        if let iconSize {
            item.image = .with(
                symbolName: identifier.itemIcon,
                pointSize: iconSize,
                accessibilityLabel: item.label
            )
        } else {
            item.image = NSImage(systemSymbolName: identifier.itemIcon, accessibilityDescription: item.label)
        }

        item.addAction(action)
        return item
    }

    static func with(identifier: NSToolbarItem.Identifier, customItem: CustomToolbarItem) -> NSToolbarItem {
        let type = customItem.menuName == nil ? NSToolbarItem.self : NSMenuToolbarItem.self
        let item = type.init(itemIdentifier: identifier)

        item.label = customItem.title
        item.image = NSImage(systemSymbolName: customItem.icon, accessibilityDescription: item.label)

        if let actionName = customItem.actionName {
            item.addAction {
                if let menuItem = NSApp.mainMenu?.firstActionNamed(actionName) {
                    menuItem.performAction()
                } else {
                    Logger.log(.error, "Missing action named: \(actionName)")
                }
            }
        }

        return item
    }

    /// Used in toolTip as a hint, values should match mainMenu.
    var shortcutHint: String? {
        switch itemIdentifier {
        case .tableOfContents: "⇧ ⌘ O"
        case .toggleBold: "⌘ B"
        case .toggleItalic: "⌘ I"
        case .toggleStrikethrough: "⌃ ⌘ S"
        case .insertLink: "⌘ K"
        case .insertImage: "⌃ ⌘ K"
        case .statistics: "⇧ ⌘ I"
        default: nil
        }
    }
}

extension NSToolbarItem.Identifier {
    static let tableOfContents = newItem("tableOfContents")
    static let formatHeaders = newItem("formatHeaders")
    static let toggleBold = newItem("toggleBold")
    static let toggleItalic = newItem("toggleItalic")
    static let toggleStrikethrough = newItem("toggleStrikethrough")
    static let insertLink = newItem("insertLink")
    static let insertImage = newItem("insertImage")
    static let toggleList = newItem("toggleList")
    static let toggleBlockquote = newItem("toggleBlockquote")
    static let horizontalRule = newItem("horizontalRule")
    static let insertTable = newItem("insertTable")
    static let insertCode = newItem("insertCode")
    static let textFormat = newItem("textFormat")
    static let statistics = newItem("statistics")
    static let shareDocument = newItem("shareDocument")
    static let copyPandocCommand = newItem("copyPandocCommand")
    static let writingTools = newItem("writingTools")

    static var defaultItems: [NSToolbarItem.Identifier] {
        [
            .tableOfContents,
            .formatHeaders,
            .toggleBold,
            .toggleItalic,
            .toggleList,
        ]
    }

    static var allItems: [NSToolbarItem.Identifier] {
        [
            .tableOfContents,
            .formatHeaders,
            .toggleBold,
            .toggleItalic,
            .toggleStrikethrough,
            .insertLink,
            .insertImage,
            .toggleList,
            .toggleBlockquote,
            .horizontalRule,
            .insertTable,
            .insertCode,
            .textFormat,
            .statistics,
            .shareDocument,
            .copyPandocCommand,
        ]
            + {
                if #available(macOS 15.1, *) {
                    return [.writingTools]
                }

                return []
            }()
            + [
                .space,
                .flexibleSpace,
            ]
    }
}

// MARK: - Private

private extension NSToolbarItem.Identifier {
    static func newItem(_ identifier: String) -> Self {
        Self("com.haptictide.screenpresenter.editor.\(identifier)")
    }

    var itemLabel: String {
        switch self {
        case .tableOfContents: Localized.Toolbar.tableOfContents
        case .formatHeaders: Localized.Toolbar.formatHeaders
        case .toggleBold: Localized.Toolbar.toggleBold
        case .toggleItalic: Localized.Toolbar.toggleItalic
        case .toggleStrikethrough: Localized.Toolbar.toggleStrikethrough
        case .insertLink: Localized.Toolbar.insertLink
        case .insertImage: Localized.Toolbar.insertImage
        case .toggleList: Localized.Toolbar.toggleList
        case .toggleBlockquote: Localized.Toolbar.toggleBlockquote
        case .horizontalRule: Localized.Toolbar.horizontalRule
        case .insertTable: Localized.Toolbar.insertTable
        case .insertCode: Localized.Toolbar.insertCode
        case .textFormat: Localized.Toolbar.textFormat
        case .statistics: Localized.Toolbar.statistics
        case .shareDocument: Localized.Toolbar.shareDocument
        case .copyPandocCommand: Localized.Toolbar.copyPandocCommand
        case .writingTools: Localized.WritingTools.title
        default: fatalError("Unexpected toolbar item identifier: \(self)")
        }
    }

    var itemIcon: String {
        switch self {
        case .tableOfContents: Icons.listBulletRectangle
        case .formatHeaders: Icons.number
        case .toggleBold: Icons.bold
        case .toggleItalic: Icons.italic
        case .toggleStrikethrough: Icons.strikethrough
        case .insertLink: Icons.link
        case .insertImage: Icons.photo
        case .toggleList: Icons.listBullet
        case .toggleBlockquote: Icons.textQuote
        case .horizontalRule: Icons.squareSplit1x2
        case .insertTable: Icons.tablecells
        case .insertCode: Icons.curlybracesSquare
        case .textFormat: Icons.textformat
        case .statistics: Icons.chartPie
        case .shareDocument: Icons.squareAndArrowUp
        case .copyPandocCommand: Icons.terminal
        case .writingTools: Icons.wandAndSparkles
        default: fatalError("Unexpected toolbar item identifier: \(self)")
        }
    }
}
