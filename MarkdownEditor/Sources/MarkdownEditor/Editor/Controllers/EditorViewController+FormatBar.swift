//
//  EditorViewController+FormatBar.swift
//  MarkdownEditor
//
//  Created by Sun on 2026/02/06.
//
//  EditorViewController 的格式工具栏代理实现
//

import AppKit
import MarkdownKit

// MARK: - EditorFormatBarDelegate

extension EditorViewController: EditorFormatBarDelegate {
    func formatBarDidToggleBold() {
        toggleBold(nil)
    }

    func formatBarDidToggleItalic() {
        toggleItalic(nil)
    }

    func formatBarDidToggleStrikethrough() {
        toggleStrikethrough(nil)
    }

    func formatBarDidRequestHeaders() {
        // 通过 FormatMenuProvider 协议获取标题菜单
        // 支持 MarkdownEditor 自身的 AppDelegate 或宿主 App 实现的协议
        let menu: NSMenu? = if let provider = NSApp.delegate as? FormatMenuProvider {
            provider.formatHeadersMenu
        } else if let appDelegate = NSApp.appDelegate {
            appDelegate.formatHeadersMenu
        } else {
            nil
        }

        guard let headingMenu = menu else {
            return
        }

        // 在 formatBar 的按钮附近显示菜单
        if let formatBar {
            let location = NSPoint(x: 100, y: formatBar.frame.minY)
            headingMenu.popUp(positioning: nil, at: location, in: view)
        }
    }

    func formatBarDidInsertLink() {
        insertLink(nil)
    }

    func formatBarDidInsertImage() {
        insertImage(nil)
    }

    func formatBarDidInsertHorizontalRule() {
        insertHorizontalRule(nil)
    }

    func formatBarDidToggleBullet() {
        toggleBullet(nil)
    }

    func formatBarDidToggleNumbering() {
        toggleNumbering(nil)
    }

    func formatBarDidToggleBlockquote() {
        toggleBlockquote(nil)
    }

    func formatBarDidInsertCode() {
        insertCodeBlock(nil)
    }

    func formatBarDidInsertTable() {
        insertTable(nil)
    }

    func formatBarDidTogglePreview() {
        togglePreviewPanel()
    }

    func formatBarDidShowTableOfContents() {
        // 由于嵌入模式下没有 toolbar 的目录按钮，
        // 需要显示一个弹出菜单来替代
        guard let bar = formatBar else { return }

        Task { @MainActor in
            // 获取目录数据
            guard let items = try? await bridge.toc.getTableOfContents(), !items.isEmpty else {
                return
            }

            // 创建目录菜单
            let menu = NSMenu()
            menu.autoenablesItems = false

            for item in items {
                let menuItem = NSMenuItem(
                    title: item.title,
                    action: #selector(handleTableOfContentsSelection(_:)),
                    keyEquivalent: ""
                )
                menuItem.target = self
                menuItem.representedObject = item
                menuItem.indentationLevel = item.level - 1
                menu.addItem(menuItem)
            }

            // 在格式栏下方显示菜单
            let location = NSPoint(x: bar.frame.maxX - 32, y: bar.frame.minY)
            menu.popUp(positioning: nil, at: location, in: view)
        }
    }

    @objc private func handleTableOfContentsSelection(_ sender: NSMenuItem) {
        guard let item = sender.representedObject as? HeadingInfo else { return }
        bridge.toc.gotoHeader(headingInfo: item)
    }
}

// MARK: - Preview Mode

extension EditorViewController {
    /// 是否处于预览模式
    var isPreviewMode: Bool {
        previewView != nil && previewView?.isHidden == false
    }

    /// 切换预览模式（编辑 ↔ 预览）
    func togglePreviewPanel() {
        if isPreviewMode {
            exitPreviewMode()
        } else {
            enterPreviewMode()
        }
    }

    /// 进入预览模式：隐藏编辑器，显示 HTML 渲染预览
    func enterPreviewMode() {
        // 如果已经在预览模式，不重复执行
        guard !isPreviewMode else { return }

        // 创建预览视图（如果还没有）
        let isNewPreview = previewView == nil
        if isNewPreview {
            let preview = MarkdownPreviewView()
            preview.delegate = self
            view.addSubview(preview)
            previewView = preview
        }

        // 更新格式栏按钮状态（禁用格式按钮）
        formatBar?.setPreviewMode(true)

        // 获取当前内容并更新预览
        Task { @MainActor in
            let text = await editorText ?? ""
            previewView?.setThemeMode(previewThemeMode)
            // 强制更新：新创建时总是加载内容（即使为空）
            previewView?.updatePreview(markdown: text, forceUpdate: isNewPreview)

            // 隐藏编辑器，显示预览（全屏覆盖）
            webView.isHidden = true
            previewView?.isHidden = false
            layoutPreviewView()
            NotificationCenter.default.post(name: Self.previewModeDidChangeNotification, object: self)
        }
    }

    /// 退出预览模式：显示编辑器，隐藏预览
    func exitPreviewMode() {
        guard isPreviewMode else { return }
        previewView?.isHidden = true
        webView.isHidden = false

        // 更新格式栏按钮状态（启用格式按钮）
        formatBar?.setPreviewMode(false)
        NotificationCenter.default.post(name: Self.previewModeDidChangeNotification, object: self)
    }

    /// 布局预览视图（全屏覆盖编辑区域）
    func layoutPreviewView() {
        guard let preview = previewView, !preview.isHidden else { return }

        // 预览视图覆盖整个 webView 区域
        preview.frame = CGRect(
            x: 0,
            y: webView.frame.minY,
            width: view.bounds.width,
            height: webView.frame.height
        )
    }
}

// MARK: - MarkdownPreviewViewDelegate

extension EditorViewController: MarkdownPreviewViewDelegate {
    func markdownPreviewViewDidDoubleClick(_ previewView: MarkdownPreviewView) {
        // 双击预览区域，退出预览模式进入编辑
        exitPreviewMode()
        // 将焦点设置到编辑器
        Task { @MainActor in
            _ = webView.becomeFirstResponder()
        }
    }
}
