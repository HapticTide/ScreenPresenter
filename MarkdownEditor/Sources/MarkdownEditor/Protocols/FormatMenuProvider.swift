//
//  FormatMenuProvider.swift
//  MarkdownEditor
//
//  Created by Sun on 2026/02/06.
//
//  允许宿主 App 提供格式菜单的协议

import AppKit

/// 格式菜单提供者协议
/// 宿主应用程序的 AppDelegate 可以实现此协议以提供格式相关的菜单
public protocol FormatMenuProvider: AnyObject {
    /// 格式 > 标题子菜单（H1~H6）
    var formatHeadersMenu: NSMenu? { get }
}
