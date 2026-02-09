//
//  EditorMenuItem.swift
//  MarkdownEditor
//
//  Created by Sun on 2026/2/6.
//

import Foundation
import MarkdownKit

/**
 User defined menu that will be added to the main menu bar.
 */
struct EditorMenuItem: Equatable {
    static let uniquePrefix = "userDefinedMenuItem"
    static let specialDivider = "extensionsMenuDivider"

    let id: String
    let item: WebMenuItem

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id
    }
}
