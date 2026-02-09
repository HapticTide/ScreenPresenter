//
//  EditorViewController+HyperLink.swift
//  MarkdownEditor
//
//  Created by Sun on 2026/2/6.
//

import AppKit
import MarkdownKit

extension EditorViewController {
    func insertHyperLink(prefix: String?) {
        Task {
            guard let text = try? await bridge.selection.getText() else {
                return
            }

            let prefersURL = text == NSDataDetector.extractURL(from: text)
            let defaultTitle = Localized.Editor.defaultLinkTitle
            let title = (text.isEmpty || text.components(separatedBy: .newlines).count > 1) ? defaultTitle : text

            // Try our best to guess from selection and clipboard
            await bridge.format.insertHyperLink(
                title: prefersURL ? defaultTitle : title,
                url: prefersURL ? text : (NSPasteboard.general.url() ?? "https://"),
                prefix: prefix
            )
        }
    }
}
