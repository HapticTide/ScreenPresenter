//
//  EditorViewController+FileVersion.swift
//  MarkdownEditor
//
//  Created by Sun on 2026/2/6.
//

import AppKit
import MarkdownKit

extension EditorViewController {
    func deleteFileVersions(_ versions: [NSFileVersion]) async {
        let alert = NSAlert()
        alert.alertStyle = .warning

        guard !versions.isEmpty else {
            alert.messageText = Localized.FileVersion.noVersionsTitle
            await presentSheetModal(alert)
            return
        }

        alert.messageText = String(format: Localized.FileVersion.foundVersionsFormat, versions.count)
        alert.informativeText = Localized.FileVersion.cannotBeUndone

        alert.addButton(withTitle: Localized.General.delete)
        alert.addButton(withTitle: Localized.General.cancel)

        guard await presentSheetModal(alert) == .alertFirstButtonReturn else {
            return
        }

        DispatchQueue.global(qos: .default).async {
            do {
                try versions.forEach { try $0.remove() }
            } catch {
                Logger.log(.error, error.localizedDescription)
            }
        }
    }
}
