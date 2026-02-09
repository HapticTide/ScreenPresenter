//
//  NSPopover+Extension.swift
//  MarkdownEditor
//
//  Created by Sun on 2026/2/6.
//

import AppKit

extension NSPopover {
    var sourceView: NSView? {
        value(forKey: "positioningView") as? NSView
    }
}
