//
//  FramePipeline.swift
//  ScreenPresenter
//
//  Created by Sun on 2025/12/22.
//
//  帧数据结构
//  定义捕获帧的通用格式
//

import CoreImage
import CoreMedia
import CoreVideo
import Foundation
import QuartzCore

// MARK: - 帧数据

struct CapturedFrame: Identifiable {
    let id: UUID
    let sourceID: UUID
    let timestamp: CMTime
    let size: CGSize

    /// 视频帧的像素缓冲区（内部使用）
    private let _pixelBuffer: CVPixelBuffer?

    /// 可选的原始采样缓冲区（内部使用）
    private let _sampleBuffer: CMSampleBuffer?

    /// 获取像素缓冲区（公开只读）
    var pixelBuffer: CVPixelBuffer? { _pixelBuffer }

    /// 获取采样缓冲区（公开只读）
    var sampleBuffer: CMSampleBuffer? { _sampleBuffer }

    /// 从 CMSampleBuffer 初始化
    init(sourceID: UUID, sampleBuffer: CMSampleBuffer) {
        id = UUID()
        self.sourceID = sourceID
        _sampleBuffer = sampleBuffer
        _pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)
        timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)

        if let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer) {
            let dimensions = CMVideoFormatDescriptionGetDimensions(formatDescription)
            size = CGSize(width: Int(dimensions.width), height: Int(dimensions.height))
        } else {
            size = .zero
        }
    }

    /// 从 CVPixelBuffer 初始化
    init(pixelBuffer: CVPixelBuffer, presentationTime: CMTime, size: CGSize) {
        id = UUID()
        sourceID = UUID()
        _pixelBuffer = pixelBuffer
        _sampleBuffer = nil
        timestamp = presentationTime
        self.size = size
    }

    /// 转换为 CIImage
    func toCIImage() -> CIImage? {
        if let pixelBuffer = _pixelBuffer {
            return CIImage(cvImageBuffer: pixelBuffer)
        }
        if let imageBuffer = _sampleBuffer.flatMap({ CMSampleBufferGetImageBuffer($0) }) {
            return CIImage(cvImageBuffer: imageBuffer)
        }
        return nil
    }

    /// 转换为 CGImage
    func toCGImage() -> CGImage? {
        guard let ciImage = toCIImage() else { return nil }

        let context = CIContext(options: [.useSoftwareRenderer: false])
        return context.createCGImage(ciImage, from: ciImage.extent)
    }
}

// MARK: - 分屏布局

/// 分屏布局枚举（用于 UI 选择器）
enum SplitLayout: String, CaseIterable, Identifiable {
    case sideBySide
    case topBottom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .sideBySide: "左右"
        case .topBottom: "上下"
        }
    }

    var icon: String {
        switch self {
        case .sideBySide: "rectangle.split.2x1"
        case .topBottom: "rectangle.split.1x2"
        }
    }

    /// 转换为 LayoutMode
    var layoutMode: LayoutMode {
        switch self {
        case .sideBySide: .sideBySide
        case .topBottom: .topBottom
        }
    }
}
