//
//  NSTextField+Extension.swift
//
//  Created by Sun on 2026/2/6.
//

import AppKit

public extension NSTextField {
    func startEditing(in window: NSWindow?, alwaysRefocus: Bool = false) {
        guard alwaysRefocus || !isFirstResponder(in: window) else {
            return
        }

        window?.makeFirstResponder(self)
    }

    func selectAll() {
        currentEditor()?.selectAll(self)
    }
}
