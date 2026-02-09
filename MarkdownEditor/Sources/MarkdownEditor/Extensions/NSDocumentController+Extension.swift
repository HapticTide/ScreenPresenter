//
//  NSDocumentController+Extension.swift
//  MarkdownEditor
//
//  Created by Sun on 2026/2/6.
//

import AppKit
import MarkdownKit

extension NSDocumentController {
    var hasOutdatedDocuments: Bool {
        !outdatedDocuments.isEmpty
    }

    func saveOutdatedDocuments(userInitiated: Bool = false) async {
        await withTaskGroup(of: Void.self) { group in
            for document in outdatedDocuments {
                group.addTask {
                    await document.waitUntilSaveCompleted(userInitiated: userInitiated)
                }
            }
        }
    }

    /**
     Force the override of the last root directory for NSOpenPanel and NSSavePanel.
     */
    func setOpenPanelDirectory(_ directory: String) {
        UserDefaults.standard.set(directory, forKey: NSNavLastRootDirectory)
    }
}

// MARK: - Private

private extension NSDocumentController {
    var outdatedDocuments: [EditorDocument] {
        NSDocumentController.shared.documents.compactMap {
            guard let document = $0 as? EditorDocument, document.isOutdated else {
                return nil
            }

            return document
        }
    }
}
