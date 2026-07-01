//
//  RecordingFrameSnapshot.swift
//  ScreenPresenter
//
//  Created by Sun on 2026/06/30.
//
//  录制截图快照
//  描述当前可保存截图的一台投屏设备
//

import CoreVideo
import Foundation

// MARK: - 录制截图快照

struct RecordingFrameSnapshot {
    let platform: DevicePlatform
    let deviceName: String
    let pixelBuffer: CVPixelBuffer
}
