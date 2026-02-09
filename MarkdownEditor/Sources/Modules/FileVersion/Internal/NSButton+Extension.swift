//
//  NSButton+Extension.swift
//
//  Created by Sun on 2026/2/6.
//

import AppKit

extension NSButton {
    func setTitle(_ title: String, font: NSFont = .systemFont(ofSize: 12)) {
        attributedTitle = NSAttributedString(
            string: title,
            attributes: [.font: font]
        )
    }
}
