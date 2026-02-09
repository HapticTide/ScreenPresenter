//
//  MarkdownPreviewThemeMode.swift
//  MarkdownPreview
//
//  Created by Sun on 2026/02/09.
//
//  预览主题模式定义
//

import Foundation

/// 预览主题模式
public enum MarkdownPreviewThemeMode: String, CaseIterable, Sendable {
    /// 跟随系统
    case system
    /// 浅色模式
    case light
    /// 深色模式
    case dark
    
    /// 对应的 JavaScript 值
    var jsValue: String {
        switch self {
        case .system: "auto"
        case .light: "light"
        case .dark: "dark"
        }
    }
}
