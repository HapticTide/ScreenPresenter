//
//  EditorConfig+Extension.swift
//
//  Created by Sun on 2026/2/6.
//

import Foundation

public extension EditorConfig {
    /// Bundle 用于加载 Editor 资源。由 MarkdownEditor 在初始化时设置为其 Bundle.module
    /// 默认值 nil 表示回退到 Bundle.main
    /// 使用 nonisolated(unsafe) 因为这是在应用启动时设置一次且之后不再修改
    nonisolated(unsafe) static var editorResourcesBundle: Bundle?

    var toHtml: String {
        indexHtml?
            .replacingOccurrences(of: "/chunk-loader/", with: "chunk-loader://")
            .replacingOccurrences(of: "\"{{EDITOR_CONFIG}}\"", with: jsonEncoded) ?? ""
    }
}

extension EditorConfig {
    /// index.html built by CoreEditor.
    private var indexHtml: String? {
        // 优先从设定的 bundle 加载（SPM module bundle）
        if let bundle = Self.editorResourcesBundle,
           let editorFolderURL = bundle.url(forResource: "Editor", withExtension: nil),
           let indexPath = try? editorFolderURL.appending(path: "index.html"),
           FileManager.default.fileExists(atPath: indexPath.path),
           let data = try? Data(contentsOf: indexPath) {
            return data.toString()
        }

        // 回退到 Bundle.main（兼容旧架构）
        if let editorFolderURL = Bundle.main.url(forResource: "Editor", withExtension: nil),
           let indexPath = try? editorFolderURL.appending(path: "index.html"),
           FileManager.default.fileExists(atPath: indexPath.path),
           let data = try? Data(contentsOf: indexPath) {
            return data.toString()
        }

        // 根目录回退
        guard let path = Bundle.main.url(forResource: "index", withExtension: "html") else {
            fatalError("Missing dist/index.html to set up the editor. In the wiki, see Building CoreEditor.")
        }

        return try? Data(contentsOf: path).toString()
    }
}
