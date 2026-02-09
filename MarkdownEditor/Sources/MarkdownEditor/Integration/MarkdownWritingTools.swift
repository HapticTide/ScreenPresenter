//
//  MarkdownWritingTools.swift
//  MarkdownEditor
//
//  Created by Sun on 2026/02/06.
//
//  Swift shim for the ObjC MarkdownWritingTools class.
//  Provides stub implementations for Writing Tools integration.
//

import AppKit

// MARK: - WritingTool Enum

enum WritingTool: Int {
    case panel = 0
    case proofread = 1
    case rewrite = 2
    case makeFriendly = 11
    case makeProfessional = 12
    case makeConcise = 13
    case summarize = 21
    case createKeyPoints = 22
    case makeList = 23
    case makeTable = 24
    case compose = 201
}

// MARK: - MarkdownWritingTools

enum MarkdownWritingTools {
    static var requestedTool: WritingTool {
        .panel
    }

    static var affordanceIcon: NSImage? {
        if #available(macOS 15.1, *) {
            let config = NSImage.SymbolConfiguration(pointSize: 12.5, weight: .medium)
            return NSImage(systemSymbolName: "apple.writing.tools", accessibilityDescription: nil)?
                .withSymbolConfiguration(config)
        }
        return nil
    }

    static func shouldReselect(withItem item: Any?) -> Bool {
        guard let menuItem = item as? NSMenuItem else { return false }
        return shouldReselect(with: WritingTool(rawValue: Int(menuItem.tag)) ?? .panel)
    }

    static func shouldReselect(with tool: WritingTool) -> Bool {
        // Compose mode can start without text selections
        tool != .compose
    }
}
