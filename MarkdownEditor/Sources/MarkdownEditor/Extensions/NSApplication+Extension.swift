//
//  NSApplication+Extension.swift
//  MarkdownEditor
//
//  Created by Sun on 2026/2/6.
//

import AppKit
import MarkdownKit

extension NSApplication {
    var appDelegate: AppDelegate? {
        guard let delegate = delegate as? AppDelegate else {
            Logger.assert(delegate != nil, "Expected to get AppDelegate")
            return nil
        }

        return delegate
    }
}
