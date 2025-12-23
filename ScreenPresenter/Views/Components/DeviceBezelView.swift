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

// MARK: - 设备型号定义

/// 设备型号，包含具体设备的外观参数
enum DeviceModel: Equatable {
    // MARK: - iPhone 系列

    /// iPhone 14 Pro / 14 Pro Max / 15 Pro / 15 Pro Max / 16 Pro / 16 Pro Max (动态岛)
    case iPhoneDynamicIsland
    /// iPhone 14 / 14 Plus / 15 / 15 Plus / 16 / 16 Plus (刘海屏)
    case iPhoneNotch
    /// iPhone SE (Home 键)
    case iPhoneSE
    /// iPhone 通用（未识别具体型号时使用）
    case iPhoneGeneric

    // MARK: - Android 系列

    /// 三星 Galaxy S 系列 (打孔屏，居中)
    case samsungGalaxyS
    /// 三星 Galaxy Z Fold (折叠屏展开)
    case samsungGalaxyFold
    /// Google Pixel 系列 (打孔屏，左上角)
    case googlePixel
    /// 小米系列 (打孔屏，居中或左上角)
    case xiaomi
    /// 一加系列
    case oneplus
    /// OPPO / Vivo 系列
    case oppoVivo
    /// Android 通用（未识别具体型号时使用）
    case androidGeneric

    // MARK: - 通用

    /// 完全未知设备
    case unknown

    // MARK: - 属性

    /// 屏幕圆角半径比例（相对于屏幕宽度）
    var screenCornerRadiusRatio: CGFloat {
        switch self {
        case .iPhoneDynamicIsland, .iPhoneNotch:
            0.12
        case .iPhoneSE:
            0.0
        case .iPhoneGeneric:
            0.10
        case .samsungGalaxyS, .googlePixel, .xiaomi, .oneplus, .oppoVivo:
            0.06
        case .samsungGalaxyFold:
            0.04
        case .androidGeneric:
            0.05
        case .unknown:
            0.06
        }
    }

    /// 边框宽度比例（相对于设备宽度）
    var bezelWidthRatio: CGFloat {
        switch self {
        case .iPhoneDynamicIsland, .iPhoneNotch:
            0.025
        case .iPhoneSE:
            0.08
        case .iPhoneGeneric:
            0.03
        case .samsungGalaxyS, .googlePixel, .xiaomi, .oneplus, .oppoVivo:
            0.015
        case .samsungGalaxyFold:
            0.01
        case .androidGeneric:
            0.02
        case .unknown:
            0.02
        }
    }

    /// 边框圆角半径比例（相对于设备宽度）
    var bezelCornerRadiusRatio: CGFloat {
        switch self {
        case .iPhoneDynamicIsland, .iPhoneNotch:
            0.14
        case .iPhoneSE:
            0.08
        case .iPhoneGeneric:
            0.12
        case .samsungGalaxyS, .googlePixel, .xiaomi, .oneplus, .oppoVivo:
            0.08
        case .samsungGalaxyFold:
            0.05
        case .androidGeneric:
            0.06
        case .unknown:
            0.06
        }
    }

    /// 默认宽高比
    var defaultAspectRatio: CGFloat {
        switch self {
        case .iPhoneDynamicIsland:
            9.0 / 19.5
        case .iPhoneNotch:
            9.0 / 19.5
        case .iPhoneSE:
            9.0 / 16.0
        case .iPhoneGeneric:
            9.0 / 19.5
        case .samsungGalaxyS:
            9.0 / 20.0
        case .samsungGalaxyFold:
            22.5 / 18.5 // 展开状态接近方形
        case .googlePixel:
            9.0 / 20.0
        case .xiaomi, .oneplus, .oppoVivo:
            9.0 / 20.0
        case .androidGeneric:
            9.0 / 20.0
        case .unknown:
            9.0 / 19.0
        }
    }

    /// 顶部特征类型
    enum TopFeature {
        case none
        case dynamicIsland(widthRatio: CGFloat, heightRatio: CGFloat)
        case notch(widthRatio: CGFloat, heightRatio: CGFloat)
        case punchHole(position: PunchHolePosition, sizeRatio: CGFloat)
        case homeButton
    }

    enum PunchHolePosition {
        case center
        case topLeft
        case topRight
    }

    var topFeature: TopFeature {
        switch self {
        case .iPhoneDynamicIsland:
            .dynamicIsland(widthRatio: 0.35, heightRatio: 0.035)
        case .iPhoneNotch:
            .notch(widthRatio: 0.35, heightRatio: 0.035)
        case .iPhoneSE:
            .homeButton
        case .iPhoneGeneric:
            .dynamicIsland(widthRatio: 0.30, heightRatio: 0.03)
        case .samsungGalaxyS, .xiaomi, .oppoVivo:
            .punchHole(position: .center, sizeRatio: 0.025)
        case .googlePixel:
            .punchHole(position: .topLeft, sizeRatio: 0.025)
        case .oneplus:
            .punchHole(position: .topLeft, sizeRatio: 0.02)
        case .samsungGalaxyFold:
            .punchHole(position: .topRight, sizeRatio: 0.02)
        case .androidGeneric:
            .punchHole(position: .center, sizeRatio: 0.02)
        case .unknown:
            .none
        }
    }

    /// 边框颜色
    var bezelColor: NSColor {
        switch self {
        case .iPhoneDynamicIsland, .iPhoneNotch, .iPhoneSE, .iPhoneGeneric:
            NSColor(white: 0.12, alpha: 1.0) // 深空黑
        case .samsungGalaxyS, .samsungGalaxyFold:
            NSColor(white: 0.10, alpha: 1.0)
        case .googlePixel:
            NSColor(white: 0.15, alpha: 1.0)
        case .xiaomi, .oneplus, .oppoVivo:
            NSColor(white: 0.13, alpha: 1.0)
        case .androidGeneric:
            NSColor(white: 0.14, alpha: 1.0)
        case .unknown:
            NSColor(white: 0.18, alpha: 1.0)
        }
    }

    /// 边框高光颜色
    var bezelHighlightColor: NSColor {
        switch self {
        case .iPhoneDynamicIsland, .iPhoneNotch, .iPhoneSE, .iPhoneGeneric:
            NSColor(white: 0.22, alpha: 1.0)
        case .samsungGalaxyS, .samsungGalaxyFold:
            NSColor(white: 0.20, alpha: 1.0)
        default:
            NSColor(white: 0.24, alpha: 1.0)
        }
    }

    /// 是否为 iOS 设备
    var isIOS: Bool {
        switch self {
        case .iPhoneDynamicIsland, .iPhoneNotch, .iPhoneSE, .iPhoneGeneric:
            true
        default:
            false
        }
    }

    // MARK: - 设备识别

    /// 根据设备名称识别设备型号
    static func identify(from deviceName: String?, platform: DevicePlatform) -> DeviceModel {
        guard let name = deviceName?.lowercased() else {
            return platform == .ios ? .iPhoneGeneric : .androidGeneric
        }

        if platform == .ios {
            return identifyiPhone(from: name)
        } else {
            return identifyAndroid(from: name)
        }
    }

    private static func identifyiPhone(from name: String) -> DeviceModel {
        // iPhone 16/15/14 Pro 系列 - 动态岛
        if
            name.contains("iphone 16") || name.contains("iphone16") ||
            name.contains("iphone 15") || name.contains("iphone15") ||
            name.contains("iphone 14 pro") || name.contains("iphone14 pro") {
            if name.contains("pro") || name.contains("16") || name.contains("15") {
                return .iPhoneDynamicIsland
            }
        }

        // iPhone 14/13/12/11/X 系列 - 刘海屏
        if
            name.contains("iphone 14") || name.contains("iphone14") ||
            name.contains("iphone 13") || name.contains("iphone13") ||
            name.contains("iphone 12") || name.contains("iphone12") ||
            name.contains("iphone 11") || name.contains("iphone11") ||
            name.contains("iphone x") {
            return .iPhoneNotch
        }

        // iPhone SE
        if name.contains("iphone se") {
            return .iPhoneSE
        }

        return .iPhoneGeneric
    }

    private static func identifyAndroid(from name: String) -> DeviceModel {
        // Samsung
        if name.contains("samsung") || name.contains("galaxy") || name.contains("sm-") {
            if name.contains("fold") || name.contains("z fold") {
                return .samsungGalaxyFold
            }
            return .samsungGalaxyS
        }

        // Google Pixel
        if name.contains("pixel") || name.contains("google") {
            return .googlePixel
        }

        // Xiaomi
        if name.contains("xiaomi") || name.contains("redmi") || name.contains("poco") || name.contains("mi ") {
            return .xiaomi
        }

        // OnePlus
        if name.contains("oneplus") || name.contains("one plus") {
            return .oneplus
        }

        // OPPO/Vivo/Realme
        if name.contains("oppo") || name.contains("vivo") || name.contains("realme") || name.contains("iqoo") {
            return .oppoVivo
        }

        return .androidGeneric
    }
}

// MARK: - 设备边框视图

final class DeviceBezelView: NSView {
    // MARK: - 属性

    private(set) var deviceModel: DeviceModel = .unknown
    private(set) var aspectRatio: CGFloat = 9.0 / 19.0

    // MARK: - UI 组件

    private var bezelLayer: CAShapeLayer!
    private var screenLayer: CAShapeLayer!
    private var featureLayer: CAShapeLayer?
    private var homeButtonLayer: CAShapeLayer?

    /// 屏幕内容视图（用于放置状态信息或视频）
    private(set) var screenContentView: NSView!

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

    /// 根据设备名称和平台配置边框
    func configure(deviceName: String?, platform: DevicePlatform, aspectRatio: CGFloat? = nil) {
        deviceModel = DeviceModel.identify(from: deviceName, platform: platform)
        self.aspectRatio = aspectRatio ?? deviceModel.defaultAspectRatio
        updateLayers()
    }

    /// 直接设置设备型号
    func configure(model: DeviceModel, aspectRatio: CGFloat? = nil) {
        deviceModel = model
        self.aspectRatio = aspectRatio ?? model.defaultAspectRatio
        updateLayers()
    }

    /// 更新宽高比（基于实际视频尺寸）
    func updateAspectRatio(_ ratio: CGFloat) {
        guard ratio > 0, ratio != aspectRatio else { return }
        aspectRatio = ratio
        updateLayers()
    }

    // MARK: - UI 设置

    private func setupUI() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        // 边框层
        bezelLayer = CAShapeLayer()
        bezelLayer.lineWidth = 0.5
        layer?.addSublayer(bezelLayer)

        // 屏幕层（透明，让视频显示）
        screenLayer = CAShapeLayer()
        screenLayer.fillColor = NSColor.clear.cgColor
        layer?.addSublayer(screenLayer)

        // 屏幕内容视图
        screenContentView = NSView()
        screenContentView.wantsLayer = true
        screenContentView.layer?.backgroundColor = NSColor.clear.cgColor
        screenContentView.layer?.masksToBounds = true
        addSubview(screenContentView)

        updateLayers()
    }

    // MARK: - 布局

    override func layout() {
        super.layout()
        updateLayers()
    }

    private func updateLayers() {
        guard bounds.width > 0, bounds.height > 0 else { return }

        // 计算设备尺寸（保持宽高比，适应容器）
        let containerAspect = bounds.width / bounds.height
        let deviceWidth: CGFloat
        let deviceHeight: CGFloat

        if aspectRatio < containerAspect {
            // 容器更宽，以高度为准
            deviceHeight = bounds.height * 0.92
            deviceWidth = deviceHeight * aspectRatio
        } else {
            // 容器更高，以宽度为准
            deviceWidth = bounds.width * 0.92
            deviceHeight = deviceWidth / aspectRatio
        }

        let deviceRect = CGRect(
            x: (bounds.width - deviceWidth) / 2,
            y: (bounds.height - deviceHeight) / 2,
            width: deviceWidth,
            height: deviceHeight
        )

        // 边框参数
        let bezelWidth = deviceWidth * deviceModel.bezelWidthRatio
        let bezelCornerRadius = deviceWidth * deviceModel.bezelCornerRadiusRatio
        let screenCornerRadius = deviceWidth * deviceModel.screenCornerRadiusRatio

        // 绘制边框
        bezelLayer.fillColor = deviceModel.bezelColor.cgColor
        bezelLayer.strokeColor = deviceModel.bezelHighlightColor.cgColor
        let bezelPath = NSBezierPath(roundedRect: deviceRect, xRadius: bezelCornerRadius, yRadius: bezelCornerRadius)
        bezelLayer.path = bezelPath.cgPath

        // 计算屏幕区域
        var screenRect = deviceRect.insetBy(dx: bezelWidth, dy: bezelWidth)

        // iPhone SE 需要更大的顶部和底部边框
        if case .homeButton = deviceModel.topFeature {
            let extraBezel = deviceWidth * 0.12
            screenRect = CGRect(
                x: screenRect.minX,
                y: screenRect.minY + extraBezel,
                width: screenRect.width,
                height: screenRect.height - extraBezel * 2
            )
        }

        let screenPath = NSBezierPath(roundedRect: screenRect, xRadius: screenCornerRadius, yRadius: screenCornerRadius)
        screenLayer.path = screenPath.cgPath

        // 更新屏幕内容视图
        screenContentView.frame = screenRect
        screenContentView.layer?.cornerRadius = screenCornerRadius

        // 更新顶部特征
        updateTopFeature(screenRect: screenRect, deviceWidth: deviceWidth)
    }

    private func updateTopFeature(screenRect: CGRect, deviceWidth: CGFloat) {
        // 清除旧的特征层
        featureLayer?.removeFromSuperlayer()
        featureLayer = nil
        homeButtonLayer?.removeFromSuperlayer()
        homeButtonLayer = nil

        switch deviceModel.topFeature {
        case .none:
            break

        case let .dynamicIsland(widthRatio, heightRatio):
            let islandWidth = screenRect.width * widthRatio
            let islandHeight = screenRect.width * heightRatio
            let islandCornerRadius = islandHeight / 2

            let islandRect = CGRect(
                x: screenRect.midX - islandWidth / 2,
                y: screenRect.maxY - islandHeight - screenRect.width * 0.025,
                width: islandWidth,
                height: islandHeight
            )

            let layer = CAShapeLayer()
            layer.fillColor = NSColor.black.cgColor
            layer.path = NSBezierPath(roundedRect: islandRect, xRadius: islandCornerRadius, yRadius: islandCornerRadius)
                .cgPath
            self.layer?.addSublayer(layer)
            featureLayer = layer

        case let .notch(widthRatio, heightRatio):
            let notchWidth = screenRect.width * widthRatio
            let notchHeight = screenRect.width * heightRatio
            let notchCornerRadius = notchHeight * 0.4

            let notchRect = CGRect(
                x: screenRect.midX - notchWidth / 2,
                y: screenRect.maxY - notchHeight,
                width: notchWidth,
                height: notchHeight + 2
            )

            let layer = CAShapeLayer()
            layer.fillColor = NSColor.black.cgColor
            layer.path = NSBezierPath(roundedRect: notchRect, xRadius: notchCornerRadius, yRadius: notchCornerRadius)
                .cgPath
            self.layer?.addSublayer(layer)
            featureLayer = layer

        case let .punchHole(position, sizeRatio):
            let holeSize = screenRect.width * sizeRatio
            let margin = screenRect.width * 0.04

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
            layer.path = NSBezierPath(ovalIn: holeRect).cgPath
            self.layer?.addSublayer(layer)
            featureLayer = layer

        case .homeButton:
            // Home 键在底部边框中
            let buttonSize = deviceWidth * 0.15
            let buttonY = screenRect.minY - (deviceWidth * 0.12 + buttonSize) / 2 - buttonSize * 0.3

            let buttonRect = CGRect(
                x: screenRect.midX - buttonSize / 2,
                y: buttonY,
                width: buttonSize,
                height: buttonSize
            )

            let layer = CAShapeLayer()
            layer.fillColor = NSColor(white: 0.08, alpha: 1.0).cgColor
            layer.strokeColor = NSColor(white: 0.25, alpha: 1.0).cgColor
            layer.lineWidth = 1.5
            layer.path = NSBezierPath(ovalIn: buttonRect).cgPath
            self.layer?.addSublayer(layer)
            homeButtonLayer = layer
        }
    }

    // MARK: - 屏幕区域

    /// 获取屏幕区域在父视图坐标系中的位置
    var screenFrame: CGRect {
        screenContentView.frame
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
