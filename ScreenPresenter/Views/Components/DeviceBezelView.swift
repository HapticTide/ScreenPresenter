//
//  DeviceBezelView.swift
//  ScreenPresenter
//
//  Created by Sun on 2025/12/23.
//
//  设备边框视图
//  根据连接的真实设备绘制对应的设备外观
//

import AppKit
import SnapKit

// MARK: - 设备边框视图

final class DeviceBezelView: NSView {
    // MARK: - 属性

    private(set) var deviceModel: DeviceModel = .unknown

    /// 屏幕内容区域的宽高比（不是设备整体的宽高比）
    /// 这个值应该与视频的宽高比一致，以避免渲染时产生黑边
    private(set) var screenAspectRatio: CGFloat = 9.0 / 19.5

    /// 设备整体的宽高比（包含边框，用于外部布局参考）
    private(set) var aspectRatio: CGFloat = 9.0 / 19.0

    /// 顶部特征（刘海/灵动岛/摄像头开孔）的底部 Y 坐标
    /// 相对于 screenContentView 的顶部（向下为正），用于 captureBar 定位
    private(set) var topFeatureBottomInset: CGFloat = 0

    // MARK: - UI 组件（使用嵌套 CALayer 实现连续曲率圆角）

    /// 金属外壳边框图层（最外层，使用 continuous 圆角）
    private var metalFrameLayer: CALayer!
    /// 屏幕黑色边框图层（中间层，使用 continuous 圆角）
    private var screenBezelLayer: CALayer!
    /// 顶部特征层（刘海/灵动岛/摄像头开孔）
    private var featureLayer: CAShapeLayer?
    /// Home 按钮层
    private var homeButtonLayer: CAShapeLayer?
    /// 侧边按钮层
    private var sideButtonLayers: [CALayer] = []

    private(set) var screenContentView: NSView!

    /// 顶部特征覆盖视图（在 screenContentView 之上，用于显示刘海/灵动岛等）
    private var featureOverlayView: NSView!

    // MARK: - 初始化

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupUI()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
    }

    // MARK: - 配置方法

    /// 配置 iOS 设备外观（推荐方式）
    /// 基于 IOSDevice 的 productType 精确识别设备型号
    /// - Parameters:
    ///   - device: iOS 设备信息
    ///   - aspectRatio: 屏幕内容区域的宽高比（如视频的宽高比），nil 时使用设备默认值
    func configure(device: IOSDevice, aspectRatio: CGFloat? = nil) {
        deviceModel = device.deviceModel
        screenAspectRatio = aspectRatio ?? deviceModel.defaultScreenAspectRatio
        updateLayers()
    }

    /// 配置 Android 设备外观（推荐方式）
    /// 基于 AndroidDevice 的 brand 精确识别设备型号
    /// - Parameters:
    ///   - device: Android 设备信息
    ///   - aspectRatio: 屏幕内容区域的宽高比（如视频的宽高比），nil 时使用设备默认值
    func configure(device: AndroidDevice, aspectRatio: CGFloat? = nil) {
        deviceModel = device.deviceModel
        screenAspectRatio = aspectRatio ?? deviceModel.defaultScreenAspectRatio
        updateLayers()
    }

    /// 配置设备外观（fallback 方式）
    /// - Parameters:
    ///   - deviceName: 设备名称（用于识别设备型号）
    ///   - platform: 设备平台
    ///   - aspectRatio: 屏幕内容区域的宽高比（如视频的宽高比），nil 时使用设备默认值
    func configure(deviceName: String?, platform: DevicePlatform, aspectRatio: CGFloat? = nil) {
        deviceModel = DeviceModel.identify(from: deviceName, platform: platform)
        screenAspectRatio = aspectRatio ?? deviceModel.defaultScreenAspectRatio
        updateLayers()
    }

    /// 配置设备外观
    /// - Parameters:
    ///   - model: 设备型号
    ///   - aspectRatio: 屏幕内容区域的宽高比，nil 时使用设备默认值
    func configure(model: DeviceModel, aspectRatio: CGFloat? = nil) {
        deviceModel = model
        screenAspectRatio = aspectRatio ?? model.defaultScreenAspectRatio
        updateLayers()
    }

    /// 更新屏幕内容区域的宽高比
    func updateAspectRatio(_ ratio: CGFloat) {
        guard ratio > 0, ratio != screenAspectRatio else { return }
        screenAspectRatio = ratio
        updateLayers()
    }

    // MARK: - UI 设置

    private func setupUI() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        // 使用嵌套的 CALayer 结构实现边框，所有圆角都使用 .continuous
        // 结构：metalFrameLayer > screenBezelLayer > screenContentView

        // 1. 金属外壳边框（最外层）
        metalFrameLayer = CALayer()
        metalFrameLayer.masksToBounds = true
        metalFrameLayer.cornerCurve = .continuous
        layer?.addSublayer(metalFrameLayer)

        // 2. 屏幕黑色边框（中间层，嵌套在金属边框内）
        screenBezelLayer = CALayer()
        screenBezelLayer.masksToBounds = true
        screenBezelLayer.cornerCurve = .continuous
        metalFrameLayer.addSublayer(screenBezelLayer)

        // 3. 屏幕内容区域（最内层）
        screenContentView = NSView()
        screenContentView.wantsLayer = true
        screenContentView.layer?.backgroundColor = NSColor.clear.cgColor
        screenContentView.layer?.masksToBounds = true
        screenContentView.layer?.cornerCurve = .continuous
        addSubview(screenContentView)

        // 4. 顶部特征覆盖视图（在 screenContentView 之上）
        // 使用独立的 view 确保顶部特征始终在屏幕内容之上
        featureOverlayView = FeatureOverlayView()
        featureOverlayView.wantsLayer = true
        featureOverlayView.layer?.backgroundColor = NSColor.clear.cgColor
        addSubview(featureOverlayView)

        updateLayers()
    }

    // MARK: - 布局

    override func layout() {
        super.layout()
        updateLayers()
    }

    private func updateLayers() {
        guard bounds.width > 0, bounds.height > 0 else { return }

        // 禁用 CALayer 隐式动画，避免窗口 resize 时 layer 动画与 NSView 动画不同步导致错位
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        // 核心思路：以屏幕内容区域的宽高比 (screenAspectRatio) 为基准，反推设备整体尺寸
        // 这样确保 screenRect 的宽高比与视频一致，避免渲染时产生黑边
        //
        // 数学推导：
        // 设 r = screenAspectRatio, b = bezelRatio, e = extraBezelRatio
        // 由于 bezelWidth = deviceWidth * b，边框是按设备宽度计算的：
        //   screenWidth = deviceWidth * (1 - 2*b)
        //   screenHeight = deviceHeight - 2*bezelWidth - 2*extraBezel
        //                = deviceHeight - 2*deviceWidth*(b + e)
        // 设 da = deviceWidth/deviceHeight，则：
        //   r = screenWidth/screenHeight
        //     = [da * (1 - 2*b)] / [1 - 2*da*(b + e)]
        // 解出 da：
        //   da = r / [(1 - 2*b) + 2*r*(b + e)]

        let containerAspect = bounds.width / bounds.height

        // 边框相关比例（金属边框 + 屏幕黑边框）
        let metalFrameRatio = deviceModel.metalFrameWidthRatio
        let screenBezelRatio = deviceModel.screenBezelWidthRatio
        let totalBezelRatio = metalFrameRatio + screenBezelRatio

        let hasHomeButton = if case .homeButton = deviceModel.topFeature {
            true
        } else {
            false
        }
        let extraBezelRatio: CGFloat = hasHomeButton ? 0.10 : 0

        // 计算设备整体的宽高比（根据屏幕宽高比和边框推算）
        let r = screenAspectRatio
        let b = totalBezelRatio
        let e = extraBezelRatio
        let deviceAspect = r / ((1 - 2 * b) + 2 * r * (b + e))

        let deviceWidth: CGFloat
        let deviceHeight: CGFloat

        // 设备尽可能填满容器，保持设备整体宽高比
        if deviceAspect < containerAspect {
            // 容器更宽，以高度为基准
            deviceHeight = bounds.height
            deviceWidth = deviceHeight * deviceAspect
        } else {
            // 容器更高，以宽度为基准
            deviceWidth = bounds.width
            deviceHeight = deviceWidth / deviceAspect
        }

        let deviceRect = CGRect(
            x: (bounds.width - deviceWidth) / 2,
            y: (bounds.height - deviceHeight) / 2,
            width: deviceWidth,
            height: deviceHeight
        )

        // 更新设备整体宽高比（供外部布局使用）
        aspectRatio = deviceAspect

        // 两层边框的宽度（各自独立计算）
        let metalFrameWidth = deviceWidth * metalFrameRatio
        let screenBezelWidth = deviceWidth * screenBezelRatio
        let totalBezelWidth = metalFrameWidth + screenBezelWidth

        // 计算屏幕宽度（用于屏幕圆角计算）
        let screenWidth = deviceWidth - 2 * totalBezelWidth

        // 圆角计算（从内向外，每层圆角递增）：
        // 1. 屏幕圆角（最内层）- 相对于屏幕宽度
        let screenCornerRadius = screenWidth * deviceModel.screenCornerRadiusRatio

        // 2. 屏幕黑边框外圆角 = 屏幕圆角 + 黑边框宽度（物理正确的同心圆角关系）
        let screenBezelOuterCornerRadius = screenCornerRadius + screenBezelWidth

        // 3. 金属边框内圆角 = 屏幕黑边框外圆角（两层紧密贴合）
        let metalInnerCornerRadius = screenBezelOuterCornerRadius

        // 4. 金属边框外圆角 = 金属内圆角 + 金属边框宽度
        let metalOuterCornerRadius = metalInnerCornerRadius + metalFrameWidth

        // 计算各层区域
        // 金属边框内边界（也是屏幕黑色边框外边界）
        var metalInnerRect = deviceRect.insetBy(dx: metalFrameWidth, dy: metalFrameWidth)

        // 屏幕区域（最内层）
        var screenRect = metalInnerRect.insetBy(dx: screenBezelWidth, dy: screenBezelWidth)

        // iPhone SE / Legacy 需要更大的顶部和底部边框
        if case .homeButton = deviceModel.topFeature {
            let extraBezel = deviceWidth * extraBezelRatio
            metalInnerRect = CGRect(
                x: metalInnerRect.minX,
                y: metalInnerRect.minY + extraBezel * 0.4,
                width: metalInnerRect.width,
                height: metalInnerRect.height - extraBezel * 0.8
            )
            screenRect = CGRect(
                x: screenRect.minX,
                y: screenRect.minY + extraBezel,
                width: screenRect.width,
                height: screenRect.height - extraBezel * 2
            )
        }

        // 像素对齐：确保 screenRect 对齐到整像素
        let scale = window?.backingScaleFactor ?? 2.0
        screenRect = CGRect(
            x: round(screenRect.minX * scale) / scale,
            y: round(screenRect.minY * scale) / scale,
            width: round(screenRect.width * scale) / scale,
            height: round(screenRect.height * scale) / scale
        )

        // 使用嵌套 CALayer 实现边框（所有圆角都使用 .continuous）

        // 1. 金属外壳边框（最外层）
        metalFrameLayer.frame = deviceRect
        metalFrameLayer.cornerRadius = metalOuterCornerRadius
        if deviceModel.isIOS {
            metalFrameLayer.backgroundColor = NSColor(red: 0.72, green: 0.72, blue: 0.74, alpha: 1.0).cgColor
        } else {
            metalFrameLayer.backgroundColor = NSColor(red: 0.24, green: 0.86, blue: 0.52, alpha: 1.0).cgColor
        }

        // 2. 屏幕黑色边框（中间层）- 相对于 metalFrameLayer 的坐标
        let screenBezelFrame = CGRect(
            x: metalFrameWidth,
            y: metalFrameWidth + (hasHomeButton ? deviceWidth * extraBezelRatio * 0.4 : 0),
            width: metalInnerRect.width,
            height: metalInnerRect.height
        )
        screenBezelLayer.frame = screenBezelFrame
        screenBezelLayer.cornerRadius = screenBezelOuterCornerRadius
        screenBezelLayer.backgroundColor = NSColor(red: 0.02, green: 0.02, blue: 0.02, alpha: 1.0).cgColor

        // 3. 屏幕内容区域（最内层）- 使用绝对坐标
        screenContentView.frame = screenRect
        screenContentView.layer?.cornerRadius = screenCornerRadius

        // 4. 顶部特征覆盖视图 - 覆盖整个视图区域（与 self 相同坐标系）
        featureOverlayView.frame = bounds

        updateTopFeature(screenRect: screenRect, deviceWidth: deviceWidth)
        updateSideButtons(deviceRect: deviceRect, deviceWidth: deviceWidth, deviceHeight: deviceHeight)
    }

    /// 添加顶部特征 layer（添加到 featureOverlayView 确保在 screenContentView 之上）
    /// featureOverlayView 是在 screenContentView 之后添加的子视图，
    /// AppKit 会确保它始终在 screenContentView 之上
    private func addFeatureLayer(_ layer: CALayer) {
        featureOverlayView.layer?.addSublayer(layer)
    }

    private func updateTopFeature(screenRect: CGRect, deviceWidth: CGFloat) {
        featureLayer?.removeFromSuperlayer()
        featureLayer = nil
        homeButtonLayer?.removeFromSuperlayer()
        homeButtonLayer = nil

        // 重置顶部特征的底部位置
        topFeatureBottomInset = 0

        switch deviceModel.topFeature {
        case .none:
            break

        case let .dynamicIsland(widthRatio, heightRatio):
            let islandWidth = screenRect.width * widthRatio
            let islandHeight = screenRect.width * heightRatio
            let islandCornerRadius = islandHeight / 2
            let islandTopMargin = screenRect.width * 0.028

            let islandRect = CGRect(
                x: screenRect.midX - islandWidth / 2,
                y: screenRect.maxY - islandHeight - islandTopMargin,
                width: islandWidth,
                height: islandHeight
            )

            // 计算顶部特征底部距离屏幕顶部的偏移
            topFeatureBottomInset = islandTopMargin + islandHeight

            let layer = CAShapeLayer()
            layer.fillColor = NSColor.black.cgColor
            layer.shadowColor = NSColor.white.cgColor
            layer.shadowOffset = CGSize(width: 0, height: -0.5)
            layer.shadowRadius = 0.5
            layer.shadowOpacity = 0.1
            layer.path = NSBezierPath(
                roundedRect: islandRect,
                xRadius: islandCornerRadius,
                yRadius: islandCornerRadius
            ).cgPath
            addFeatureLayer(layer)
            featureLayer = layer

        case let .notch(widthRatio, heightRatio):
            let notchWidth = screenRect.width * widthRatio
            let notchHeight = screenRect.width * heightRatio
            let notchCornerRadius = notchHeight * 0.45

            // 刘海从屏幕顶部开始向下延伸
            topFeatureBottomInset = notchHeight

            let notchPath = createNotchPath(
                centerX: screenRect.midX,
                topY: screenRect.maxY,
                width: notchWidth,
                height: notchHeight,
                cornerRadius: notchCornerRadius
            )

            let layer = CAShapeLayer()
            layer.fillColor = NSColor.black.cgColor
            layer.path = notchPath
            addFeatureLayer(layer)
            featureLayer = layer

        case let .punchHole(position, sizeRatio):
            let holeSize = screenRect.width * sizeRatio
            let margin = screenRect.width * 0.045

            // 计算顶部特征底部距离屏幕顶部的偏移
            topFeatureBottomInset = margin + holeSize

            let holeX: CGFloat = switch position {
            case .center:
                screenRect.midX - holeSize / 2
            case .topLeft:
                screenRect.minX + margin
            case .topRight:
                screenRect.maxX - margin - holeSize
            }

            let holeRect = CGRect(
                x: holeX,
                y: screenRect.maxY - margin - holeSize,
                width: holeSize,
                height: holeSize
            )

            let layer = CAShapeLayer()
            layer.fillColor = NSColor.black.cgColor
            layer.strokeColor = NSColor(white: 0.15, alpha: 1.0).cgColor
            layer.lineWidth = 0.5
            layer.path = NSBezierPath(ovalIn: holeRect).cgPath
            addFeatureLayer(layer)
            featureLayer = layer

        case .homeButton:
            let buttonSize = deviceWidth * 0.14
            let buttonY = screenContentView.frame.minY - (deviceWidth * 0.10 + buttonSize) / 2 - buttonSize * 0.15

            let buttonRect = CGRect(
                x: screenContentView.frame.midX - buttonSize / 2,
                y: buttonY,
                width: buttonSize,
                height: buttonSize
            )

            let outerLayer = CAShapeLayer()
            outerLayer.fillColor = NSColor(white: 0.06, alpha: 1.0).cgColor
            outerLayer.strokeColor = NSColor(white: 0.22, alpha: 1.0).cgColor
            outerLayer.lineWidth = 1.0
            outerLayer.path = NSBezierPath(ovalIn: buttonRect).cgPath

            let innerSize = buttonSize * 0.35
            let innerRect = CGRect(
                x: buttonRect.midX - innerSize / 2,
                y: buttonRect.midY - innerSize / 2,
                width: innerSize,
                height: innerSize
            )
            let innerLayer = CAShapeLayer()
            innerLayer.fillColor = nil
            innerLayer.strokeColor = NSColor(white: 0.25, alpha: 1.0).cgColor
            innerLayer.lineWidth = 1.0
            innerLayer.path = NSBezierPath(
                roundedRect: innerRect,
                xRadius: innerSize * 0.2,
                yRadius: innerSize * 0.2
            ).cgPath

            layer?.addSublayer(outerLayer)
            layer?.addSublayer(innerLayer)
            homeButtonLayer = outerLayer
        }
    }

    private func createNotchPath(
        centerX: CGFloat,
        topY: CGFloat,
        width: CGFloat,
        height: CGFloat,
        cornerRadius: CGFloat
    ) -> CGPath {
        let path = CGMutablePath()

        let leftX = centerX - width / 2
        let rightX = centerX + width / 2
        let bottomY = topY - height

        path.move(to: CGPoint(x: leftX - cornerRadius, y: topY))

        path.addQuadCurve(
            to: CGPoint(x: leftX, y: topY - cornerRadius * 0.5),
            control: CGPoint(x: leftX, y: topY)
        )

        path.addLine(to: CGPoint(x: leftX, y: bottomY + cornerRadius))

        path.addQuadCurve(
            to: CGPoint(x: leftX + cornerRadius, y: bottomY),
            control: CGPoint(x: leftX, y: bottomY)
        )

        path.addLine(to: CGPoint(x: rightX - cornerRadius, y: bottomY))

        path.addQuadCurve(
            to: CGPoint(x: rightX, y: bottomY + cornerRadius),
            control: CGPoint(x: rightX, y: bottomY)
        )

        path.addLine(to: CGPoint(x: rightX, y: topY - cornerRadius * 0.5))

        path.addQuadCurve(
            to: CGPoint(x: rightX + cornerRadius, y: topY),
            control: CGPoint(x: rightX, y: topY)
        )

        path.closeSubpath()

        return path
    }

    private func updateSideButtons(deviceRect: CGRect, deviceWidth _: CGFloat, deviceHeight: CGFloat) {
        sideButtonLayers.forEach { $0.removeFromSuperlayer() }
        sideButtonLayers.removeAll()

        let buttons = deviceModel.sideButtons

        for spec in buttons.left {
            let buttonLayer = createButtonLayer(
                spec: spec,
                deviceRect: deviceRect,
                deviceHeight: deviceHeight,
                isLeft: true
            )
            layer?.addSublayer(buttonLayer)
            sideButtonLayers.append(buttonLayer)
        }

        for spec in buttons.right {
            let buttonLayer = createButtonLayer(
                spec: spec,
                deviceRect: deviceRect,
                deviceHeight: deviceHeight,
                isLeft: false
            )
            layer?.addSublayer(buttonLayer)
            sideButtonLayers.append(buttonLayer)
        }
    }

    private func createButtonLayer(
        spec: DeviceModel.SideButtons.ButtonSpec,
        deviceRect: CGRect,
        deviceHeight: CGFloat,
        isLeft: Bool
    ) -> CALayer {
        let buttonHeight = deviceHeight * spec.heightRatio
        let buttonY = deviceRect.maxY - deviceHeight * spec.topRatio - buttonHeight

        let buttonRect = if isLeft {
            CGRect(
                x: deviceRect.minX - spec.width,
                y: buttonY,
                width: spec.width,
                height: buttonHeight
            )
        } else {
            CGRect(
                x: deviceRect.maxX,
                y: buttonY,
                width: spec.width,
                height: buttonHeight
            )
        }

        let layer = CAShapeLayer()

        // 圆角半径：
        // - silentSwitch: 药丸形状（小开关）
        // - actionButton / volumeUp / volumeDown / power: 统一使用小圆角矩形样式
        let cornerRadius: CGFloat = switch spec.type {
        case .silentSwitch:
            buttonHeight / 2 // 静音开关是药丸形状
        default:
            1.5 // 所有其他按钮（包括 actionButton）使用小圆角
        }

        let path = NSBezierPath(roundedRect: buttonRect, xRadius: cornerRadius, yRadius: cornerRadius)
        layer.path = path.cgPath

        // 按钮使用与金属边框一致的颜色
        let buttonColor: NSColor
        let highlightColor: NSColor

        if deviceModel.isIOS {
            // iOS 设备：Apple 银色
            buttonColor = NSColor(red: 0.68, green: 0.68, blue: 0.70, alpha: 1.0)
            highlightColor = NSColor(white: 0.85, alpha: 0.4)
        } else {
            // Android 设备：Android 绿色
            buttonColor = NSColor(red: 0.20, green: 0.75, blue: 0.45, alpha: 1.0)
            highlightColor = NSColor(red: 0.35, green: 0.90, blue: 0.60, alpha: 0.4)
        }

        layer.fillColor = buttonColor.cgColor
        layer.strokeColor = highlightColor.cgColor
        layer.lineWidth = 0.5

        return layer
    }

    // MARK: - 屏幕区域

    var screenFrame: CGRect {
        screenContentView.frame
    }

    /// 屏幕圆角半径（用于 Metal 渲染遮罩）
    var screenCornerRadius: CGFloat {
        screenContentView.layer?.cornerRadius ?? 0
    }
}

// MARK: - 顶部特征覆盖视图

/// 透明的覆盖视图，用于显示顶部特征（刘海/灵动岛/打孔摄像头）
/// 重写 hitTest 方法使鼠标事件穿透到下层视图
private final class FeatureOverlayView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        // 返回 nil 使鼠标事件穿透到下层视图
        nil
    }
}

// MARK: - NSBezierPath CGPath 扩展

extension NSBezierPath {
    var cgPath: CGPath {
        let path = CGMutablePath()
        var points = [CGPoint](repeating: .zero, count: 3)

        for i in 0..<elementCount {
            let type = element(at: i, associatedPoints: &points)
            switch type {
            case .moveTo:
                path.move(to: points[0])
            case .lineTo:
                path.addLine(to: points[0])
            case .curveTo:
                path.addCurve(to: points[2], control1: points[0], control2: points[1])
            case .closePath:
                path.closeSubpath()
            case .cubicCurveTo:
                path.addCurve(to: points[2], control1: points[0], control2: points[1])
            case .quadraticCurveTo:
                path.addQuadCurve(to: points[1], control: points[0])
            @unknown default:
                break
            }
        }

        return path
    }
}
