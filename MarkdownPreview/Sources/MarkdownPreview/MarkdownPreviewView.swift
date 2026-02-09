//
//  MarkdownPreviewView.swift
//  MarkdownPreview
//
//  Created by Sun on 2026/02/09.
//
//  Markdown 渲染预览视图
//  使用 WKWebView + markdown-it 将 Markdown 渲染为富文本预览
//  支持 mermaid 图表、KaTeX 公式、代码高亮
//

import AppKit
import WebKit

/// Markdown 渲染预览视图
///
/// 提供完整的 Markdown 预览功能，包括：
/// - 标准 Markdown 语法渲染
/// - Mermaid 图表支持
/// - KaTeX 数学公式
/// - 代码语法高亮
/// - 深色模式自动切换
/// - 页面缩放控制
public final class MarkdownPreviewView: NSView {
    // MARK: - Public Properties
    
    /// 代理
    public weak var delegate: MarkdownPreviewDelegate?
    
    /// 当前缩放级别
    public var zoomLevel: Double {
        webView.magnification
    }
    
    /// 是否已完成加载
    public private(set) var hasFinishedLoading: Bool = false
    
    // MARK: - Private Properties
    
    private lazy var webView: WKWebView = createWebView()
    private var messageHandler: PreviewMessageHandler?  // 保持对消息处理器的强引用
    private let imageSchemeHandler = PreviewImageSchemeHandler()
    
    private var currentMarkdown: String = ""
    private var themeMode: MarkdownPreviewThemeMode = .system
    private var pendingMarkdown: String?
    
    // MARK: - Constants
    
    private enum Zoom {
        static let minimum: Double = 0.5
        static let maximum: Double = 3.0
        static let step: Double = 0.1
    }
    
    private enum Constants {
        static let bridgeName = "bridge"
    }
    
    // MARK: - Initialization
    
    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupUI()
    }
    
    @available(*, unavailable)
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Layout
    
    public override func layout() {
        super.layout()
        webView.frame = bounds
    }
    
    // MARK: - Public Methods
    
    /// 更新预览内容
    /// - Parameters:
    ///   - markdown: Markdown 文本
    ///   - forceUpdate: 强制更新（即使内容相同）
    public func updatePreview(markdown: String, forceUpdate: Bool = false) {
        guard forceUpdate || markdown != currentMarkdown else { return }
        currentMarkdown = markdown
        
        if hasFinishedLoading {
            evaluateSetContent(markdown)
        } else {
            pendingMarkdown = markdown
        }
    }
    
    /// 设置主题模式
    public func setThemeMode(_ mode: MarkdownPreviewThemeMode) {
        guard themeMode != mode else { return }
        themeMode = mode
        
        if hasFinishedLoading {
            evaluateSetTheme(mode)
        }
    }
    
    /// 设置基础路径（用于加载相对路径的本地图片）
    public func setBasePath(_ url: URL?) {
        imageSchemeHandler.basePath = url
    }
    
    /// 是否可以放大
    public func canZoomIn() -> Bool {
        webView.magnification < Zoom.maximum
    }
    
    /// 是否可以缩小
    public func canZoomOut() -> Bool {
        webView.magnification > Zoom.minimum
    }
    
    /// 放大
    public func zoomIn() {
        webView.magnification = min(Zoom.maximum, webView.magnification + Zoom.step)
    }
    
    /// 缩小
    public func zoomOut() {
        webView.magnification = max(Zoom.minimum, webView.magnification - Zoom.step)
    }
    
    /// 重置缩放
    public func resetZoom() {
        webView.magnification = 1.0
    }
    
    /// 设置背景色
    /// - Parameter color: 背景色，传 nil 使用窗口背景色
    public func setBackgroundColor(_ color: NSColor?) {
        guard hasFinishedLoading else { return }
        let resolvedColor = color ?? (window?.backgroundColor ?? NSColor.windowBackgroundColor)
        evaluateSetBackgroundColor(resolvedColor)
    }
    
    // MARK: - View Lifecycle
    
    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if hasFinishedLoading {
            updateBackgroundColorFromWindow()
        }
    }
    
    public override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        if hasFinishedLoading {
            updateBackgroundColorFromWindow()
        }
    }
    
    // MARK: - Private Methods
    
    private func setupUI() {
        wantsLayer = true
        addSubview(webView)
        loadPreviewHTML()
    }
    
    private func createWebView() -> WKWebView {
        let controller = WKUserContentController()
        
        // 设置消息处理器
        let handler = PreviewMessageHandler(delegate: self)
        self.messageHandler = handler  // 保持强引用，防止被释放
        controller.add(handler, name: Constants.bridgeName)
        
        let config = WKWebViewConfiguration()
        config.userContentController = controller
        config.setURLSchemeHandler(imageSchemeHandler, forURLScheme: PreviewImageSchemeHandler.scheme)
        
        // 允许本地文件访问
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
        
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.allowsMagnification = true
        
        // 透明背景
        webView.setValue(false, forKey: "drawsBackground")
        
        return webView
    }
    
    private func loadPreviewHTML() {
        guard let htmlURL = Bundle.module.url(forResource: "index", withExtension: "html", subdirectory: "Preview") else {
            assertionFailure("Missing Preview/index.html in bundle")
            return
        }
        
        webView.loadFileURL(htmlURL, allowingReadAccessTo: htmlURL.deletingLastPathComponent())
    }
    
    private func evaluateSetContent(_ markdown: String) {
        let escapedMarkdown = escapeForJavaScript(markdown)
        let js = "window.setPreviewContent?.('\(escapedMarkdown)');"
        webView.evaluateJavaScript(js) { _, error in
            if let error {
                print("[MarkdownPreview] setContent error: \(error)")
            }
        }
    }
    
    private func evaluateSetTheme(_ mode: MarkdownPreviewThemeMode) {
        let js = "window.setThemeMode?.('\(mode.jsValue)');"
        webView.evaluateJavaScript(js) { _, error in
            if let error {
                print("[MarkdownPreview] setTheme error: \(error)")
            }
        }
    }
    
    private func evaluateSetBackgroundColor(_ color: NSColor) {
        let cssColor = cssColorString(from: color)
        let js = "window.setBackgroundColor?.('\(cssColor)');"
        webView.evaluateJavaScript(js) { _, error in
            if let error {
                print("[MarkdownPreview] setBackgroundColor error: \(error)")
            }
        }
    }
    
    private func updateBackgroundColorFromWindow() {
        let color = window?.backgroundColor ?? NSColor.windowBackgroundColor
        evaluateSetBackgroundColor(color)
    }
    
    private func cssColorString(from color: NSColor) -> String {
        // 转换到 sRGB 色彩空间
        guard let rgb = color.usingColorSpace(.sRGB) else {
            // 回退：尝试 deviceRGB
            guard let deviceRGB = color.usingColorSpace(.deviceRGB) else {
                return "#FFFFFF"
            }
            return formatColorComponents(deviceRGB)
        }
        return formatColorComponents(rgb)
    }
    
    private func formatColorComponents(_ color: NSColor) -> String {
        let red = Int(round(color.redComponent * 255))
        let green = Int(round(color.greenComponent * 255))
        let blue = Int(round(color.blueComponent * 255))
        let alpha = max(0, min(1, color.alphaComponent))
        
        if alpha < 1 {
            return String(format: "rgba(%d, %d, %d, %.3f)", red, green, blue, alpha)
        }
        return String(format: "#%02X%02X%02X", red, green, blue)
    }
    
    private func escapeForJavaScript(_ string: String) -> String {
        string
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")
    }
}

// MARK: - PreviewMessageHandlerDelegate

extension MarkdownPreviewView: PreviewMessageHandlerDelegate {
    func previewDidFinishLoading() {
        hasFinishedLoading = true
        
        // 设置主题
        evaluateSetTheme(themeMode)
        
        // 设置背景色
        updateBackgroundColorFromWindow()
        
        // 处理待渲染的内容
        if let pending = pendingMarkdown {
            pendingMarkdown = nil
            evaluateSetContent(pending)
        }
        
        delegate?.markdownPreviewViewDidFinishLoading(self)
    }
    
    func previewDidReceiveDoubleClick() {
        delegate?.markdownPreviewViewDidDoubleClick(self)
    }
    
    func previewDidReceiveError(_ message: String) {
        print("[MarkdownPreview] JS Error: \(message)")
    }
}
