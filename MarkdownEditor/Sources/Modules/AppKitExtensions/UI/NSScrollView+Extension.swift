//
//  NSScrollView+Extension.swift
//
//  Created by Sun on 2026/2/6.
//

import AppKit

public extension NSScrollView {
    var textView: NSTextView? {
        documentView as? NSTextView
    }

    func scrollTextViewDown() {
        textView?.scrollPageDown(nil)
    }

    func scrollTextViewUp() {
        textView?.scrollPageUp(nil)
    }

    func setContentOffset(_ offset: CGPoint) {
        contentView.scroll(to: offset)
    }

    func setAttributedText(_ text: NSAttributedString) {
        textView?.textStorage?.setAttributedString(text)
    }
}
