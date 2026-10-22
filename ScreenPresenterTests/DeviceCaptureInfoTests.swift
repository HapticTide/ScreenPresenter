//
//  DeviceCaptureInfoTests.swift
//  ScreenPresenterTests
//
//  Created by Sun on 2026/10/15.
//
//  验证侧边浮层不遮挡画面，以及跨窗口操作时的显示生命周期。
//

import AppKit
import XCTest
@testable import ScreenPresenter

final class DeviceCaptureInfoTests: XCTestCase {
    private var window: CaptureInfoTestWindow!
    private var device: DevicePanelView!

    override func setUp() {
        super.setUp()
        let visibleFrame = NSScreen.main!.visibleFrame
        window = CaptureInfoTestWindow(
            contentRect: NSRect(x: visibleFrame.midX - 170, y: visibleFrame.midY - 300, width: 340, height: 600),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        device = DevicePanelView(frame: NSRect(x: 20, y: 20, width: 300, height: 560))
        window.contentView!.addSubview(device)
        window.makeKeyAndOrderFront(nil)
        device.layoutSubtreeIfNeeded()
    }

    override func tearDown() {
        window.close()
        device = nil
        window = nil
        super.tearDown()
    }

    func testHoverShowsOutsideNarrowWindowWithoutResizingDevice() throws {
        let originalFrame = device.frame
        let panel = try startCaptureAndHover()
        let deviceFrame = window.convertToScreen(device.convert(device.bounds, to: nil))
        XCTAssertFalse(panel.frame.intersects(deviceFrame))
        XCTAssertFalse(window.frame.contains(panel.frame))
        XCTAssertEqual(device.frame, originalFrame)
        XCTAssertTrue(panel.parent === window)
        XCTAssertFalse(device.renderView.subviews.contains { $0 is DeviceCaptureInfoView })

        // 主窗口移动时子窗口跟随，同时仍保持在投屏画面之外。
        window.setFrameOrigin(NSPoint(x: window.frame.minX + 30, y: window.frame.minY + 20))
        let movedDeviceFrame = window.convertToScreen(device.convert(device.bounds, to: nil))
        XCTAssertFalse(panel.frame.intersects(movedDeviceFrame))
    }

    func testSidePanelAvoidsOtherDevice() throws {
        window.setContentSize(NSSize(width: 700, height: 600))
        device.frame = NSRect(x: 20, y: 20, width: 300, height: 560)
        let other = DevicePanelView(frame: NSRect(x: 340, y: 20, width: 300, height: 560))
        window.contentView!.addSubview(other)
        let panel = try startCaptureAndHover()
        let otherFrame = window.convertToScreen(other.convert(other.bounds, to: nil))
        let deviceFrame = window.convertToScreen(device.convert(device.bounds, to: nil))
        XCTAssertFalse(panel.frame.intersects(otherFrame))
        XCTAssertLessThanOrEqual(panel.frame.maxX, deviceFrame.minX)
    }

    func testMovingIntoPanelKeepsControlsVisibleAndLeavingStartsFadeOut() throws {
        let panel = try startCaptureAndHover()
        let info = try XCTUnwrap(panel.contentView as? DeviceCaptureInfoView)
        device.mouseExited(with: NSEvent())
        // 模拟信息视图自己的追踪区域回调，验证跨子窗口后取消父视图的隐藏计时器。
        info.onHoverChanged?(true)
        RunLoop.main.run(until: Date().addingTimeInterval(1.9))
        XCTAssertTrue(panel.isVisible)
        XCTAssertFalse(info.isHidden)
        info.onHoverChanged?(false)
        RunLoop.main.run(until: Date().addingTimeInterval(1.9))
        // 测试宿主可能嵌套在应用初始化的 RunLoop 中；验证淡出目标，
        // 窗口收起的回调由下一项状态切换测试独立覆盖。
        XCTAssertEqual(info.alphaValue, 0, accuracy: 0.01)
    }

    func testStoppingCaptureAndHidingDeviceDismissPanel() throws {
        let panel = try startCaptureAndHover()
        device.showDisconnected(platform: .ios, connectionGuide: "")
        XCTAssertFalse(panel.isVisible)
        _ = try startCaptureAndHover()
        device.isHidden = true
        XCTAssertFalse(panel.isVisible)
    }

    func testReenterDuringFadeOutDoesNotHideNewlyShownPanel() {
        let info = DeviceCaptureInfoView(frame: NSRect(x: 0, y: 0, width: 240, height: 380))
        info.isHidden = true
        info.showAnimated()
        info.hideAnimated()
        info.showAnimated()
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))
        XCTAssertFalse(info.isHidden)
        XCTAssertEqual(info.alphaValue, 1, accuracy: 0.01)
    }

    func testStationaryCursorHidesPanelAndMovementRestoresIt() throws {
        let panel = try startCaptureAndHover()
        let info = try XCTUnwrap(panel.contentView as? DeviceCaptureInfoView)
        RunLoop.main.run(until: Date().addingTimeInterval(1.1))
        XCTAssertTrue(info.isHidden)
        XCTAssertFalse(panel.isVisible)

        // 再发一次画面内移动事件，验证同一区域内也能恢复并重新开始计时。
        _ = try startCaptureAndHover()
        XCTAssertFalse(info.isHidden)
        device.showDisconnected(platform: .ios, connectionGuide: "")
        RunLoop.main.run(until: Date().addingTimeInterval(1.1))
        XCTAssertFalse(panel.isVisible)
    }

    func testMovementRestartsOneSecondIdleDeadline() throws {
        let panel = try startCaptureAndHover()
        let info = try XCTUnwrap(panel.contentView as? DeviceCaptureInfoView)
        RunLoop.main.run(until: Date().addingTimeInterval(0.6))
        _ = try startCaptureAndHover()
        RunLoop.main.run(until: Date().addingTimeInterval(0.6))
        XCTAssertFalse(info.isHidden)
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        XCTAssertTrue(info.isHidden)
    }

    func testInsufficientSideSpaceUsesScreenOverlayAndStillHidesWhenIdle() throws {
        let visibleFrame = NSScreen.main!.visibleFrame
        window.setFrame(visibleFrame, display: true)
        device.setBezelVisible(false)
        device.frame = window.contentView!.bounds
        let originalFrame = device.frame
        try hoverCapture()
        let info = try XCTUnwrap(device.subviews.first { $0 is DeviceCaptureInfoView } as? DeviceCaptureInfoView)
        XCTAssertEqual(info.frame, device.bounds)
        XCTAssertEqual(device.frame, originalFrame)
        XCTAssertFalse(info.isHidden)
        XCTAssertFalse(window.childWindows?.contains { $0.isVisible } ?? false)

        // 内嵌蒙层上的悬停不能阻止画面静止一秒后的自动隐藏。
        info.onHoverChanged?(true)
        RunLoop.main.run(until: Date().addingTimeInterval(1.1))
        XCTAssertTrue(info.isHidden)
    }

    func testOverlayReturnsToSidePanelWhenSpaceBecomesAvailable() throws {
        let visibleFrame = NSScreen.main!.visibleFrame
        window.setFrame(visibleFrame, display: true)
        device.setBezelVisible(false)
        device.frame = window.contentView!.bounds
        try hoverCapture()
        let info = try XCTUnwrap(device.subviews.first { $0 is DeviceCaptureInfoView } as? DeviceCaptureInfoView)

        // 模拟退出全屏或缩小设备后重新有足够的侧边空间。
        device.frame = NSRect(x: visibleFrame.width / 2 - 150, y: 20, width: 300, height: 560)
        let panel = try startCaptureAndHover()
        XCTAssertTrue(panel.contentView === info)
        XCTAssertEqual(panel.frame.size, NSSize(width: 240, height: 420))
        XCTAssertFalse(device.subviews.contains { $0 === info })
    }

    private func startCaptureAndHover() throws -> NSWindow {
        try hoverCapture()
        let panel = try XCTUnwrap(window.childWindows?.first { $0.contentView is DeviceCaptureInfoView })
        XCTAssertTrue(panel.isVisible)
        return panel
    }

    func testPreferencesWindowPreventsBackgroundHoverAndLayoutFromShowingPanel() throws {
        let preferences = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 520, height: 480),
            styleMask: [.titled, .closable], backing: .buffered, defer: false
        )
        preferences.isReleasedWhenClosed = false
        defer { preferences.close() }
        preferences.makeKeyAndOrderFront(nil)
        window.hasTestFocus = false
        NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: preferences)

        // 设置窗口在前台时，后台投屏仍可能收到悬停与布局回调。
        try hoverCapture()
        device.layoutSubtreeIfNeeded()
        XCTAssertFalse(window.childWindows?.contains { $0.isVisible } ?? false)
        XCTAssertLessThan(preferences.orderedIndex, window.orderedIndex)

        // 点击回投屏窗口后，正常的悬停浮层应恢复。
        window.makeKeyAndOrderFront(nil)
        window.hasTestFocus = true
        _ = try startCaptureAndHover()
    }

    func testOpeningPreferencesDismissesExistingPanelAndCancelsIdle() throws {
        let panel = try startCaptureAndHover()
        let preferences = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 520, height: 480),
            styleMask: [.titled, .closable], backing: .buffered, defer: false
        )
        preferences.isReleasedWhenClosed = false
        defer { preferences.close() }
        preferences.makeKeyAndOrderFront(nil)
        window.hasTestFocus = false
        NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: preferences)
        XCTAssertFalse(panel.isVisible)

        // 几何刷新不能把已经退到后台的窗口组再次抬到设置窗口前面。
        window.setFrameOrigin(NSPoint(x: window.frame.minX + 10, y: window.frame.minY))
        RunLoop.main.run(until: Date().addingTimeInterval(1.1))
        XCTAssertFalse(panel.isVisible)
        XCTAssertLessThan(preferences.orderedIndex, window.orderedIndex)
    }

    private func hoverCapture() throws {
        device.showCapturing(
            deviceName: "Test iPhone", modelName: nil, platform: .ios,
            fps: 60, resolution: CGSize(width: 1170, height: 2532), onStop: {}
        )
        device.layoutSubtreeIfNeeded()
        let point = device.convert(NSPoint(x: device.bounds.midX, y: device.bounds.midY), to: nil)
        let event = try XCTUnwrap(NSEvent.mouseEvent(
            with: .mouseMoved, location: point, modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 0, pressure: 0
        ))
        device.mouseMoved(with: event)
    }
}

/// 测试宿主不一定获得系统焦点，显式模拟焦点以稳定验证窗口切换后的悬停策略。
private final class CaptureInfoTestWindow: NSWindow {
    var hasTestFocus = true
    override var isKeyWindow: Bool { hasTestFocus }
}
