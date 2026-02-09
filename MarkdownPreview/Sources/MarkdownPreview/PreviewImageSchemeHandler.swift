//
//  PreviewImageSchemeHandler.swift
//  MarkdownPreview
//
//  Created by Sun on 2026/02/09.
//
//  image-loader:// URL Scheme 处理器
//  用于加载本地图片资源
//

import WebKit
import UniformTypeIdentifiers

/// 本地图片 URL Scheme 处理器
final class PreviewImageSchemeHandler: NSObject, WKURLSchemeHandler, @unchecked Sendable {
    // MARK: - Constants
    
    static let scheme = "image-loader"
    
    // MARK: - Properties
    
    /// 基础路径（文档所在目录）
    var basePath: URL?
    
    // MARK: - WKURLSchemeHandler
    
    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url else {
            urlSchemeTask.didFailWithError(URLError(.badURL))
            return
        }
        
        // 从 URL 中提取相对路径
        // image-loader://path/to/image.png → path/to/image.png
        let relativePath = url.absoluteString
            .replacingOccurrences(of: "\(Self.scheme)://", with: "")
            .removingPercentEncoding ?? ""
        
        // 构建完整路径
        let fullPath: URL
        if let basePath {
            fullPath = basePath.appendingPathComponent(relativePath)
        } else {
            // 如果没有基础路径，尝试作为绝对路径处理
            fullPath = URL(fileURLWithPath: relativePath)
        }
        
        // 读取文件数据
        do {
            let data = try Data(contentsOf: fullPath)
            let mimeType = mimeType(for: fullPath)
            
            let response = URLResponse(
                url: url,
                mimeType: mimeType,
                expectedContentLength: data.count,
                textEncodingName: nil
            )
            
            urlSchemeTask.didReceive(response)
            urlSchemeTask.didReceive(data)
            urlSchemeTask.didFinish()
        } catch {
            urlSchemeTask.didFailWithError(error)
        }
    }
    
    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {
        // 图片加载是同步的，不需要取消
    }
    
    // MARK: - Private
    
    private func mimeType(for url: URL) -> String {
        let pathExtension = url.pathExtension.lowercased()
        
        if let utType = UTType(filenameExtension: pathExtension) {
            return utType.preferredMIMEType ?? "application/octet-stream"
        }
        
        // 回退到常见图片类型
        switch pathExtension {
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "gif": return "image/gif"
        case "webp": return "image/webp"
        case "svg": return "image/svg+xml"
        case "bmp": return "image/bmp"
        default: return "application/octet-stream"
        }
    }
}
