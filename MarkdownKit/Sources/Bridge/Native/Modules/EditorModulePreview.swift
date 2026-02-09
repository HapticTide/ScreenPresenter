//
//  EditorModulePreview.swift
//
//  Created by Sun on 2026/2/6.
//

import Foundation
import MarkdownCore

@MainActor
public protocol EditorModulePreviewDelegate: AnyObject {
    func editorPreview(_ sender: EditorModulePreview, show code: String, type: PreviewType, rect: CGRect)
}

public final class EditorModulePreview: NativeModulePreview {
    private weak var delegate: EditorModulePreviewDelegate?

    public init(delegate: EditorModulePreviewDelegate) {
        self.delegate = delegate
    }

    public func show(code: String, type: PreviewType, rect: WebRect) {
        delegate?.editorPreview(self, show: code, type: type, rect: rect.cgRect)
    }
}
