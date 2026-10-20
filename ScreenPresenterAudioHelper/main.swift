//
//  main.swift
//  ScreenPresenterAudioHelper
//
//  Created by Tank on 2026/07/18.
//

import AppKit
import Foundation

private func argumentValue(for flag: String) -> String? {
    guard let index = CommandLine.arguments.firstIndex(of: flag) else { return nil }
    let valueIndex = CommandLine.arguments.index(after: index)
    guard valueIndex < CommandLine.arguments.endIndex else { return nil }
    return CommandLine.arguments[valueIndex]
}

guard
    let outputPath = argumentValue(for: "--output"),
    let controlDirectoryPath = argumentValue(for: "--control-directory"),
    let ownerPIDValue = argumentValue(for: "--owner-pid"),
    let ownerPID = Int32(ownerPIDValue)
else {
    exit(EXIT_FAILURE)
}

let application = NSApplication.shared
application.setActivationPolicy(.accessory)

// Helper 通过 LaunchServices 作为独立 App 启动，必须完成 AppKit 启动生命周期。
// 之前直接进入 dispatchMain，LaunchServices 会等待约 30 秒后才回调主 App；
// 此时麦克风其实已经开始录制，但主界面仍停留在 starting / 00:00。
application.finishLaunching()

AudioHelperController(
    outputURL: URL(fileURLWithPath: outputPath),
    controlDirectoryURL: URL(fileURLWithPath: controlDirectoryPath, isDirectory: true),
    ownerPID: ownerPID
).run()
