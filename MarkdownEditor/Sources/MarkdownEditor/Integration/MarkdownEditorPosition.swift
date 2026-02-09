//
//  MarkdownEditorPosition.swift
//  MarkdownEditor
//
//  Created by Sun on 2026/02/06.
//
//  编辑器在主窗口中的布局位置
//

import Foundation

/// 编辑器在主窗口中的位置
public enum MarkdownEditorPosition: String, CaseIterable, Sendable {
    /// 两个投屏之间（默认）
    case center
    /// 最左侧
    case left
    /// 最右侧
    case right

    /// 显示名称（需要在宿主 app 中本地化）
    public var displayName: String {
        switch self {
        case .center: "Center"
        case .left: "Left"
        case .right: "Right"
        }
    }
}
