//
//  main.swift
//  ScreenPresenter
//
//  应用程序入口点
//  显式启动 NSApplication
//

import AppKit

// 创建应用实例
let app = NSApplication.shared

// 创建并设置 AppDelegate
let delegate = AppDelegate()
app.delegate = delegate

// 运行应用
_ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
