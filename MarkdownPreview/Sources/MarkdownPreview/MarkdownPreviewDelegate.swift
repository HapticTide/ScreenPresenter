//
//  MarkdownPreviewDelegate.swift
//  MarkdownPreview
//
//  Created by Sun on 2026/02/09.
//
//  Markdown 预览视图代理协议
//

import AppKit

/// Markdown 预览视图代理协议
@MainActor
public protocol MarkdownPreviewDelegate: AnyObject {
    /// 预览视图加载完成
    func markdownPreviewViewDidFinishLoading(_ previewView: MarkdownPreviewView)
    
    /// 双击预览区域（用于退出预览模式）
    func markdownPreviewViewDidDoubleClick(_ previewView: MarkdownPreviewView)
}

// MARK: - 默认实现

public extension MarkdownPreviewDelegate {
    func markdownPreviewViewDidFinishLoading(_ previewView: MarkdownPreviewView) {}
    func markdownPreviewViewDidDoubleClick(_ previewView: MarkdownPreviewView) {}
}
