//
//  MarkdownPreviewView.swift
//  MarkdownEditor
//
//  Created by Sun on 2026/02/06.
//
//  Markdown 渲染预览视图
//  封装 MarkdownPreview 包，提供完整的预览功能
//

import AppKit
import MarkdownPreview

/// 预览视图代理协议
@MainActor
protocol MarkdownPreviewViewDelegate: AnyObject {
    /// 双击预览区域
    func markdownPreviewViewDidDoubleClick(_ previewView: MarkdownPreviewView)
}

/// Markdown 渲染预览视图
///
/// 内部使用 MarkdownPreview 包实现，支持：
/// - Mermaid 图表
/// - KaTeX 数学公式
/// - 代码语法高亮
final class MarkdownPreviewView: NSView {
    // MARK: - Properties

    weak var delegate: MarkdownPreviewViewDelegate?

    /// 内部预览视图
    private lazy var previewView: MarkdownPreview.MarkdownPreviewView = {
        let view = MarkdownPreview.MarkdownPreviewView(frame: .zero)
        view.delegate = self
        return view
    }()

    // MARK: - Initialization

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupUI()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Layout

    override func layout() {
        super.layout()
        previewView.frame = bounds
    }

    // MARK: - Public Methods

    /// 更新预览内容
    /// - Parameters:
    ///   - markdown: Markdown 文本
    ///   - forceUpdate: 强制更新（即使内容相同）
    func updatePreview(markdown: String, forceUpdate: Bool = false) {
        previewView.updatePreview(markdown: markdown, forceUpdate: forceUpdate)
    }

    /// 设置主题模式
    func setThemeMode(_ mode: MarkdownEditorThemeMode) {
        previewView.setThemeMode(mode.toPreviewThemeMode())
    }

    /// 设置基础路径（用于加载相对路径的本地图片）
    func setBasePath(_ url: URL?) {
        previewView.setBasePath(url)
    }

    /// 当前缩放级别
    var zoomLevel: Double {
        previewView.zoomLevel
    }

    /// 是否可以放大
    func canZoomIn() -> Bool {
        previewView.canZoomIn()
    }

    /// 是否可以缩小
    func canZoomOut() -> Bool {
        previewView.canZoomOut()
    }

    /// 放大
    func zoomIn() {
        previewView.zoomIn()
    }

    /// 缩小
    func zoomOut() {
        previewView.zoomOut()
    }

    /// 重置缩放
    func resetZoom() {
        previewView.resetZoom()
    }

    // MARK: - Private Methods

    private func setupUI() {
        wantsLayer = true
        addSubview(previewView)
    }
}

// MARK: - MarkdownPreviewDelegate

extension MarkdownPreviewView: MarkdownPreviewDelegate {
    func markdownPreviewViewDidFinishLoading(_ view: MarkdownPreview.MarkdownPreviewView) {
        // 预览加载完成，可在此添加额外处理
    }

    func markdownPreviewViewDidDoubleClick(_ view: MarkdownPreview.MarkdownPreviewView) {
        delegate?.markdownPreviewViewDidDoubleClick(self)
    }
}

// MARK: - Theme Mode Conversion

private extension MarkdownEditorThemeMode {
    func toPreviewThemeMode() -> MarkdownPreviewThemeMode {
        switch self {
        case .system: .system
        case .light: .light
        case .dark: .dark
        }
    }
}
