//
//  Application.swift
//  MarkdownEditor
//
//  Created by Sun on 2026/2/6.
//  Adapted for ScreenPresenter — removed @main entry point.
//

import AppKit
import MarkdownKit

/// NSApplication 扩展，提供 MarkdownEditor 的实用方法。
/// 当宿主 App 使用自定义 NSApplication 子类时可直接使用；
/// 否则通过 `NSApp.currentMarkdownEditor` 便捷访问。
extension NSApplication {
    /// 获取当前 key window 的 EditorViewController（如有）
    var currentMarkdownEditor: EditorViewController? {
        keyWindow?.contentViewController as? EditorViewController
    }
}
