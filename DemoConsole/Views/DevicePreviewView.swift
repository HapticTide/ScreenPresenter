//
//  DevicePreviewView.swift
//  DemoConsole
//
//  Created by Sun on 2025/12/22.
//
//  设备预览视图
//  显示捕获的设备画面帧
//

import AppKit
import CoreImage
import SwiftUI

// MARK: - 设备预览视图

/// 显示设备捕获画面的视图
struct DevicePreviewView: View {
    /// 设备源
    @ObservedObject var deviceSource: BaseDeviceSource

    /// 当前颜色主题
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // 背景
                Color.black

                // 根据状态显示不同内容
                switch deviceSource.state {
                case .idle, .disconnected:
                    disconnectedView

                case .connecting:
                    connectingView

                case .connected:
                    connectedView

                case .capturing:
                    capturingView(size: geometry.size)

                case .paused:
                    pausedView(size: geometry.size)

                case let .error(error):
                    errorView(error: error)
                }

                // 顶部状态栏
                VStack {
                    statusBar
                    Spacer()
                }
            }
        }
    }

    // MARK: - 状态视图

    /// 未连接状态
    private var disconnectedView: some View {
        VStack(spacing: 16) {
            Image(systemName: "cable.connector")
                .font(.system(size: 48))
                .foregroundStyle(.white.opacity(0.3))

            Text("设备未连接")
                .font(.headline)
                .foregroundStyle(.white.opacity(0.5))
        }
    }

    /// 连接中状态
    private var connectingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)
                .tint(.white)

            Text("正在连接...")
                .font(.headline)
                .foregroundStyle(.white.opacity(0.7))
        }
    }

    /// 已连接状态（等待捕获）
    private var connectedView: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 48))
                .foregroundStyle(.green.opacity(0.7))

            Text("设备已连接")
                .font(.headline)
                .foregroundStyle(.white.opacity(0.7))

            Text("正在准备捕获...")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.5))
        }
    }

    /// 捕获中状态 - 显示画面
    private func capturingView(size: CGSize) -> some View {
        Group {
            if
                let frame = deviceSource.latestFrame,
                let cgImage = createCGImage(from: frame) {
                Image(nsImage: NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height)))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: size.width, maxHeight: size.height)
            } else {
                // 没有帧数据时显示占位符
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.2)
                        .tint(.white)

                    Text("等待画面...")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
        }
    }

    /// 暂停状态
    private func pausedView(size: CGSize) -> some View {
        ZStack {
            // 显示最后一帧（如果有）
            if
                let frame = deviceSource.latestFrame,
                let cgImage = createCGImage(from: frame) {
                Image(nsImage: NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height)))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: size.width, maxHeight: size.height)
                    .opacity(0.5)
            }

            // 暂停图标
            VStack(spacing: 12) {
                Image(systemName: "pause.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.white.opacity(0.8))

                Text("已暂停")
                    .font(.headline)
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
    }

    /// 错误状态
    private func errorView(error: DeviceSourceError) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.orange)

            Text("连接错误")
                .font(.headline)
                .foregroundStyle(.white.opacity(0.8))

            Text(error.localizedDescription)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.5))
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Button("重试") {
                Task {
                    try? await deviceSource.reconnect()
                }
            }
            .buttonStyle(.bordered)
            .tint(.white)
        }
    }

    // MARK: - 状态栏

    private var statusBar: some View {
        HStack {
            // 连接状态指示器
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)

            // 设备名称
            Text(deviceSource.displayName)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.8))

            Spacer()

            // 捕获信息
            if deviceSource.state == .capturing {
                let size = deviceSource.captureSize
                if size != .zero {
                    Text("\(Int(size.width))×\(Int(size.height))")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.black.opacity(0.5))
    }

    private var statusColor: Color {
        switch deviceSource.state {
        case .idle, .disconnected:
            .gray
        case .connecting:
            .yellow
        case .connected, .capturing:
            .green
        case .paused:
            .orange
        case .error:
            .red
        }
    }

    // MARK: - 帧转换

    /// 将 CapturedFrame 转换为 CGImage
    private func createCGImage(from frame: CapturedFrame) -> CGImage? {
        guard let pixelBuffer = frame.pixelBuffer else { return nil }

        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext(options: [.useSoftwareRenderer: false])

        return context.createCGImage(ciImage, from: ciImage.extent)
    }
}

// MARK: - 简化版预览视图（不依赖 DeviceSource）

/// 简化版预览视图，直接接收帧数据
struct SimplePreviewView: View {
    let frame: CapturedFrame?
    let deviceName: String
    let isConnected: Bool

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black

                if let frame, let cgImage = createCGImage(from: frame) {
                    Image(nsImage: NSImage(
                        cgImage: cgImage,
                        size: NSSize(width: cgImage.width, height: cgImage.height)
                    ))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: geometry.size.width, maxHeight: geometry.size.height)
                } else if isConnected {
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.2)
                            .tint(.white)
                        Text("等待画面...")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.5))
                    }
                } else {
                    VStack(spacing: 16) {
                        Image(systemName: "cable.connector")
                            .font(.system(size: 48))
                            .foregroundStyle(.white.opacity(0.3))
                        Text("设备未连接")
                            .font(.headline)
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }

                // 状态栏
                VStack {
                    HStack {
                        Circle()
                            .fill(isConnected ? Color.green : Color.gray)
                            .frame(width: 8, height: 8)
                        Text(deviceName)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.8))
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.black.opacity(0.5))

                    Spacer()
                }
            }
        }
    }

    private func createCGImage(from frame: CapturedFrame) -> CGImage? {
        guard let pixelBuffer = frame.pixelBuffer else { return nil }
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext(options: [.useSoftwareRenderer: false])
        return context.createCGImage(ciImage, from: ciImage.extent)
    }
}

// MARK: - Preview

#Preview("Device Preview - Disconnected") {
    // 需要模拟 DeviceSource，这里用占位符
    Text("Preview not available")
        .frame(width: 400, height: 300)
}
