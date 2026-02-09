//
//  MarkdownEditorView.swift
//  MarkdownEditor
//
//  Created by Sun on 2026/02/06.
//
//  ScreenPresenter 的 Markdown 编辑器视图
//  封装完整的 Markdown 编辑器（EditorViewController + WKWebView），
//  提供简洁的公开 API 供 ScreenPresenter 调用。
//

import AppKit
import MarkdownCore
import MarkdownKit

/// Markdown 编辑器主题模式
public enum MarkdownEditorThemeMode: String, CaseIterable {
    case system
    case light
    case dark
}

private final class DocumentCloseContext: NSObject {
    private let completion: (Bool) -> Void

    init(completion: @escaping (Bool) -> Void) {
        self.completion = completion
    }

    @objc
    func document(_ document: NSDocument, shouldClose: Bool, contextInfo: UnsafeMutableRawPointer?) {
        completion(shouldClose)
    }
}

/// ScreenPresenter 的 Markdown 编辑器视图控制器
///
/// 内部封装完整的 Markdown 编辑器（EditorViewController + WKWebView）。
/// 使用方式：
/// ```swift
/// let editor = MarkdownEditorView()
/// parentVC.addChild(editor)
/// parentView.addSubview(editor.view)
/// ```
@MainActor
public final class MarkdownEditorView: NSViewController {
    // MARK: - 公开属性

    /// 回调代理
    public weak var delegate: MarkdownEditorDelegate?

    /// 底层桥接，高级用户可直接访问 MarkdownKit 的全部 Web Bridge 能力
    /// 注意：WebModuleBridge 由 MarkdownKit 定义，使用时需 `import MarkdownKit`
    var bridge: WebModuleBridge {
        editorVC.bridge
    }

    /// 编辑器是否已完成加载
    public var hasFinishedLoading: Bool {
        editorVC.hasFinishedLoading
    }

    /// 是否处于预览模式
    public var isPreviewMode: Bool {
        editorVC.isPreviewMode
    }

    /// 是否处于全屏模式（控制顶部间距）
    public var isFullScreen: Bool {
        get { editorVC.isHostFullScreen }
        set { editorVC.isHostFullScreen = newValue }
    }

    /// 建议的标题（来自文档第一个标题），未保存的文档会根据内容自动更新
    /// 对于已保存的文档（有 fileURL），始终返回 nil
    public var suggestedTitle: String? {
        guard document?.fileURL == nil else { return nil }
        return document?.displayName
    }

    /// 当建议标题（来自文档第一个标题）变化时调用
    public var onSuggestedTitleChange: ((String?) -> Void)?

    /// 当预览模式状态变化时调用（参数为当前是否处于预览模式）
    public var onPreviewModeChange: ((Bool) -> Void)?

    /// 当前关联的 EditorDocument（如有）
    /// 注意：EditorDocument 是 MarkdownEditor 内部类型
    var document: EditorDocument? {
        editorVC.document
    }

    /// 当前文件 URL（未保存文档为 nil）
    public var fileURL: URL? {
        document?.fileURL
    }

    /// 底层 EditorViewController（仅在需要直接访问时使用）
    /// 注意：EditorViewController 是 MarkdownEditor 内部类型
    var editorViewController: EditorViewController {
        editorVC
    }

    // MARK: - 私有属性

    private lazy var editorVC: EditorViewController = .init()

    private var contentChangeObserver: NSObjectProtocol?
    private var suggestedTitleObserver: NSObjectProtocol?
    private var previewModeObserver: NSObjectProtocol?
    private var appearanceObservation: NSKeyValueObservation?
    private var closeContext: DocumentCloseContext?
    private var themeMode: MarkdownEditorThemeMode = .system

    /// 确保配置文件只创建一次的标记
    private static var hasInitializedCustomization = false

    // MARK: - 初始化

    public init() {
        // 配置 EditorConfig 使用 MarkdownEditor 的 Bundle.module 加载资源
        EditorConfig.editorResourcesBundle = Bundle.module
        // 确保 Markdown 所需的配置文件存在（仅在首次初始化时执行）
        Self.ensureCustomizationFilesExist()
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - 生命周期

    override public func loadView() {
        view = NSView(frame: CGRect(x: 0, y: 0, width: 720, height: 480))
    }

    override public func viewDidLoad() {
        super.viewDidLoad()
        embedEditorViewController()
        _ = ensureDocumentIfNeeded()
        setupNotificationObservers()
        setupAppearanceObserver()
        applyTheme(mode: themeMode, animated: false)
    }

    deinit {
        if let observer = contentChangeObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = suggestedTitleObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = previewModeObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        appearanceObservation?.invalidate()
    }

    // MARK: - 文档管理

    /// 打开 Markdown 文件
    public func open(url: URL) throws {
        let document = try EditorDocument(contentsOf: url, ofType: "net.daringfireball.markdown")
        // 为嵌入模式设置 hostViewController，确保异步读取后能正确更新
        document.setHostViewController(editorVC)
        editorVC.representedObject = document
    }

    /// 设置编辑器内容（不关联文件）
    public func setContent(_ markdown: String) {
        let document = ensureDocumentIfNeeded()
        document.stringValue = markdown

        if hasFinishedLoading {
            editorVC.resetEditor()
        } else {
            editorVC.prepareInitialContent(markdown)
        }

        document.markContentDirty(!markdown.isEmpty)
    }

    /// 异步获取当前编辑器内容
    public func getContent() async -> String? {
        await editorVC.editorText
    }

    /// 保存当前文档
    public func save() throws {
        let doc = ensureDocumentIfNeeded()
        doc.save(self)
    }

    /// 另存为
    public func saveAs() {
        ensureDocumentIfNeeded().runModalSavePanel(for: .saveAsOperation, delegate: nil, didSave: nil, contextInfo: nil)
    }

    /// 保存到指定路径
    public func save(to url: URL, completion: ((Bool) -> Void)? = nil) {
        let document = ensureDocumentIfNeeded()
        let fileType = document.fileType ?? "net.daringfireball.markdown"
        document.save(to: url, ofType: fileType, for: .saveAsOperation) { error in
            completion?(error == nil)
        }
    }

    /// 当前是否有未保存内容
    public var hasUnsavedChanges: Bool {
        document?.isDocumentEdited ?? false
    }

    /// 关闭前确认（有未保存内容时会弹出保存确认）
    public func requestCloseIfNeeded(completion: @escaping (Bool) -> Void) {
        guard let document else {
            completion(true)
            return
        }

        let context = DocumentCloseContext { [weak self] shouldClose in
            self?.closeContext = nil
            completion(shouldClose)
        }
        closeContext = context
        document.canClose(
            withDelegate: context,
            shouldClose: #selector(DocumentCloseContext.document(_:shouldClose:contextInfo:)),
            contextInfo: nil
        )
    }

    // MARK: - 编辑控制

    public func undo() {
        editorVC.bridge.history.undo()
    }

    public func redo() {
        editorVC.bridge.history.redo()
    }

    // MARK: - 格式化

    public func toggleBold() {
        editorVC.toggleBold(nil)
    }

    public func toggleItalic() {
        editorVC.toggleItalic(nil)
    }

    public func toggleStrikethrough() {
        editorVC.toggleStrikethrough(nil)
    }

    public func toggleInlineCode() {
        editorVC.toggleInlineCode(nil)
    }

    public func toggleInlineMath() {
        editorVC.toggleInlineMath(nil)
    }

    public func toggleHeading(level: Int) {
        editorVC.bridge.format.toggleHeading(level: level)
    }

    public func toggleBullet() {
        editorVC.toggleBullet(nil)
    }

    public func toggleNumbering() {
        editorVC.toggleNumbering(nil)
    }

    public func toggleBlockquote() {
        editorVC.toggleBlockquote(nil)
    }

    public func insertCodeBlock() {
        editorVC.insertCodeBlock(nil)
    }

    public func insertLink() {
        editorVC.insertLink(nil)
    }

    public func insertImage() {
        editorVC.insertImage(nil)
    }

    public func insertTable() {
        editorVC.insertTable(nil)
    }

    public func insertHorizontalRule() {
        editorVC.insertHorizontalRule(nil)
    }

    // MARK: - 搜索

    public func performFind() {
        editorVC.updateTextFinderMode(.find)
    }

    public func performFindAndReplace() {
        editorVC.updateTextFinderMode(.replace)
    }

    public func performTextFinderAction(_ action: NSTextFinder.Action) {
        switch action {
        case .showFindInterface:
            editorVC.updateTextFinderMode(.find)
        case .nextMatch:
            editorVC.findNextInTextFinder()
        case .previousMatch:
            editorVC.findPreviousInTextFinder()
        case .setSearchString:
            editorVC.findSelectionInTextFinder()
        default:
            break
        }
    }

    // MARK: - 预览模式

    /// 切换预览模式（编辑 ↔ 预览）
    public func togglePreview() {
        editorVC.togglePreviewPanel()
    }

    // MARK: - 外观

    /// 设置编辑器主题（内部使用）
    func setTheme(_ theme: AppTheme, animated: Bool = true) {
        editorVC.setTheme(theme, animated: animated)
    }

    public func setFontSize(_ size: Double) {
        editorVC.setFontSize(size)
    }

    public func setThemeMode(_ mode: MarkdownEditorThemeMode, animated: Bool = true) {
        themeMode = mode
        applyTheme(mode: mode, animated: animated)
    }

    public func zoomIn() {
        editorVC.zoomIn()
    }

    public func zoomOut() {
        editorVC.zoomOut()
    }

    // MARK: - 焦点

    /// 让编辑器 WKWebView 成为第一响应者
    public func focusEditor() {
        view.window?.makeFirstResponder(editorVC.webView)
    }
}

// MARK: - 私有方法

private extension MarkdownEditorView {
    func embedEditorViewController() {
        // 嵌入模式：编辑器主题不应影响宿主窗口的外观和背景色
        editorVC.appliesThemeToWindow = false

        addChild(editorVC)
        let editorView = editorVC.view
        editorView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(editorView)

        NSLayoutConstraint.activate([
            editorView.topAnchor.constraint(equalTo: view.topAnchor),
            editorView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            editorView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            editorView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
    }

    func setupNotificationObservers() {
        // 监听文档建议标题（来自第一个标题）变化，通知外部更新标签页标题
        suggestedTitleObserver = NotificationCenter.default.addObserver(
            forName: EditorDocument.suggestedFilenameDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self,
                  let changedDocument = notification.object as? EditorDocument,
                  changedDocument === self.document else { return }
            self.onSuggestedTitleChange?(self.suggestedTitle)
        }

        // 监听预览模式变化，通知外部更新按钮状态
        previewModeObserver = NotificationCenter.default.addObserver(
            forName: EditorViewController.previewModeDidChangeNotification,
            object: editorVC,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.onPreviewModeChange?(self.isPreviewMode)
        }
    }

    func setupAppearanceObserver() {
        // 监听系统外观变化，自动更新编辑器主题
        appearanceObservation = NSApp.observe(\.effectiveAppearance) { [weak self] _, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                applyTheme(mode: themeMode, animated: true)
            }
        }
    }

    func applyTheme(mode: MarkdownEditorThemeMode, animated: Bool) {
        let theme: AppTheme = switch mode {
        case .system:
            AppTheme.current
        case .light:
            AppTheme.withName(AppPreferences.Editor.lightTheme)
        case .dark:
            AppTheme.withName(AppPreferences.Editor.darkTheme)
        }
        setTheme(theme, animated: animated)
        editorVC.setPreviewThemeMode(mode)
    }

    @discardableResult
    func ensureDocumentIfNeeded() -> EditorDocument {
        if let document {
            return document
        }

        let newDocument = EditorDocument()
        newDocument.setHostViewController(editorVC)
        editorVC.representedObject = newDocument
        newDocument.markContentDirty(false)
        return newDocument
    }

    /// 确保 Markdown 配置文件存在（settings.json 等）
    static func ensureCustomizationFilesExist() {
        guard !hasInitializedCustomization else { return }
        hasInitializedCustomization = true
        AppCustomization.createFiles()
    }
}
