//
//  EditorViewController+GotoLine.swift
//  MarkdownEditor
//
//  Created by Sun on 2026/2/6.
//

import AppKit
import AppKitControls
import MarkdownKit

extension EditorViewController {
    func showGotoLineWindow(_ sender: Any?) {
        guard let parentRect = view.window?.frame else {
            Logger.assertFail("Failed to retrieve window.frame to proceed")
            return
        }

        if completionContext.isPanelVisible {
            cancelCompletion()
        }

        let window = GotoLineWindow(
            effectViewType: AppDesign.modernEffectView,
            relativeTo: parentRect,
            placeholder: Localized.Document.gotoLineLabel,
            accessibilityHelp: Localized.Document.gotoLineHelp,
            iconName: Icons.arrowUturnBackwardCircle,
            defaultLineNumber: States.selectedLineNumber
        ) { [weak self] lineNumber in
            States.selectedLineNumber = lineNumber
            self?.startTextEditing()
            self?.bridge.selection.gotoLine(lineNumber: lineNumber)
        }

        window.appearance = view.effectiveAppearance
        window.makeKeyAndOrderFront(sender)
    }
}

// MARK: - Private

private extension EditorViewController {
    enum States {
        @MainActor static var selectedLineNumber: Int?
    }
}
