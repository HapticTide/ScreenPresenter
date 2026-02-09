//
//  MarkdownEditorDelegate.swift
//  MarkdownEditor
//
//  Created by Sun on 2026/02/06.
//
//  MarkdownEditorView 的回调协议
//

import AppKit

/// MarkdownEditorView 的回调协议
@MainActor
public protocol MarkdownEditorDelegate: AnyObject {
    /// 编辑器完成加载
    func markdownEditorDidFinishLoading(_ editor: MarkdownEditorView)

    /// 内容发生变化
    func markdownEditor(_ editor: MarkdownEditorView, contentDidChange isDirty: Bool)

    /// 链接被点击
    func markdownEditor(_ editor: MarkdownEditorView, didClickLink url: URL)

    /// 背景色变化（用于同步 host 背景色）
    func markdownEditor(_ editor: MarkdownEditorView, backgroundColorDidChange color: NSColor)
}

/// 所有方法可选
public extension MarkdownEditorDelegate {
    func markdownEditorDidFinishLoading(_ editor: MarkdownEditorView) {}
    func markdownEditor(_ editor: MarkdownEditorView, contentDidChange isDirty: Bool) {}
    func markdownEditor(_ editor: MarkdownEditorView, didClickLink url: URL) {}
    func markdownEditor(_ editor: MarkdownEditorView, backgroundColorDidChange color: NSColor) {}
}
