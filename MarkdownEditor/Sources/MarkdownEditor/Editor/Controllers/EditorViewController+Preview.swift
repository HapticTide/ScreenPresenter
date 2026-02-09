//
//  EditorViewController+Preview.swift
//  MarkdownEditor
//
//  Created by Sun on 2026/2/6.
//

import AppKit
import MarkdownKit
import Previewer

extension EditorViewController {
    func showPreview(code: String, type: PreviewType, rect: CGRect) {
        if removePresentedPopovers(contentClass: Previewer.self) {
            return
        }

        let previewer = Previewer(code: code, type: type)
        presentAsPopover(contentViewController: previewer, rect: rect)
    }
}

// MARK: - Private

private extension EditorViewController {
    func presentAsPopover(contentViewController: Previewer, rect: CGRect) {
        if focusTrackingView.superview == nil {
            webView.addSubview(focusTrackingView)
        }

        // The origin has to be inside the viewport
        focusTrackingView.frame = CGRect(
            x: max(0, rect.minX),
            y: max(0, rect.minY),
            width: rect.width,
            height: rect.height
        )

        present(
            contentViewController,
            asPopoverRelativeTo: focusTrackingView.bounds,
            of: focusTrackingView,
            preferredEdge: .maxX,
            behavior: .transient
        )
    }
}
