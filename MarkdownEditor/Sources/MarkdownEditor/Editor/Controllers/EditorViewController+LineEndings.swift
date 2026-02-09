//
//  EditorViewController+LineEndings.swift
//  MarkdownEditor
//
//  Created by Sun on 2026/2/6.
//

import AppKit
import MarkdownKit

extension EditorViewController {
    @IBAction func setLineEndings(_ sender: Any?) {
        guard let item = sender as? NSMenuItem else {
            return Logger.assertFail("Invalid sender")
        }

        guard let lineEndings = LineEndings(rawValue: item.tag) else {
            return Logger.assertFail("Invalid lineEndings: \(item.tag)")
        }

        document?.save(sender)
        bridge.lineEndings.setLineEndings(lineEndings: lineEndings)
    }
}
