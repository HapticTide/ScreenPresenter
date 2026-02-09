//
//  EditorViewController+Encoding.swift
//  MarkdownEditor
//
//  Created by Sun on 2026/2/6.
//

import AppKit
import MarkdownKit

extension EditorViewController {
    @objc func reopenWithEncoding(_ sender: NSMenuItem) {
        guard let encoding = sender.representedObject as? EditorTextEncoding else {
            return Logger.assertFail("Invalid encoding: \(String(describing: sender.representedObject))")
        }

        guard let data = document?.fileData else {
            return Logger.assertFail("Missing fileData from: \(String(describing: document))")
        }

        document?.stringValue = encoding.decode(data: data)
        resetEditor()
    }
}
