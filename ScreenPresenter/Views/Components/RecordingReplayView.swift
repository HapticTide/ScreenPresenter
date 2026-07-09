//
//  RecordingReplayView.swift
//  ScreenPresenter
//
//  Created by Tank on 2026/07/02.
//
//  录制回看视图
//  同步音频播放进度与设备截图轨道
//

import AVFoundation
import AppKit
import QuartzCore

// MARK: - 录制回看视图

final class RecordingReplayView: NSView {
    // MARK: - 回调

    var onBack: (() -> Void)?

    // MARK: - UI 组件

    let headerContainer = NSView()
    let backButton = NSButton()
    let titleLabel = NSTextField(labelWithString: "")
    let deviceCountLabel = NSTextField(labelWithString: "")

    let contentContainer = NSView()
    let emptyLabel = NSTextField(labelWithString: "")
    let deviceStackView = NSStackView()

    let controlsContainer = NSView()
    let currentTimeLabel = NSTextField(labelWithString: "00:00")
    let rewindButton = NSButton()
    let playPauseButton = NSButton()
    let forwardButton = NSButton()
    let speedButton = NSButton()
    let progressSlider = NSSlider(value: 0, minValue: 0, maxValue: 1, target: nil, action: nil)
    let totalTimeLabel = NSTextField(labelWithString: "00:00")

    // MARK: - 播放状态

    var session: RecordingSession?
    var clock: ReplayClock?
    var playbackTimer: Timer?
    private var keyboardMonitor: Any?
    var devicePanes: [DevicePane] = []
    /// 回放截图缓存。用 NSCache 限制条目数与总字节，避免长录制回放时内存无上限增长，
    /// 内存吃紧时系统会自动回收。
    let imageCache: NSCache<NSURL, NSImage> = {
        let cache = NSCache<NSURL, NSImage>()
        cache.countLimit = 60
        cache.totalCostLimit = 256 * 1024 * 1024
        return cache
    }()
    var playbackRate: Float = 1.0

    // MARK: - 初始化

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupUI()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
    }

    deinit {
        stopPlayback()
        stopKeyboardMonitor()
    }

    override func layout() {
        super.layout()
        layoutReplayView()
    }

    override func viewWillMove(toSuperview newSuperview: NSView?) {
        super.viewWillMove(toSuperview: newSuperview)

        if newSuperview == nil {
            stopPlayback()
            stopKeyboardMonitor()
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()

        if window == nil {
            stopKeyboardMonitor()
        } else {
            startKeyboardMonitor()
        }
    }

    // MARK: - 公开方法

    func configure(session: RecordingSession) {
        stopPlayback()

        self.session = session
        imageCache.removeAllObjects()
        playbackRate = 1.0

        titleLabel.stringValue = L10n.recording.replayTitle(session.directory.lastPathComponent)
        deviceCountLabel.stringValue = L10n.recording.replayDeviceCount(session.deviceTracks.count)
        currentTimeLabel.stringValue = "\(Self.formatTime(0)) / \(Self.formatTime(session.duration))"
        totalTimeLabel.stringValue = ""
        progressSlider.minValue = 0
        progressSlider.maxValue = max(session.duration, 1)
        progressSlider.doubleValue = 0
        updateSpeedButtonTitle()
        updatePlaybackControls(isEnabled: false)
        rebuildDevicePanes(for: session.deviceTracks)

        if let audioURL = session.audioURL, let player = try? AVAudioPlayer(contentsOf: audioURL) {
            player.enableRate = true
            player.rate = playbackRate
            player.prepareToPlay()
            clock = AudioReplayClock(player: player)
            setErrorMessage(nil)
            updatePlaybackControls(isEnabled: true)
            refreshPlaybackState(at: 0)
            startAutoPlayback()
        } else if session.duration > 0 {
            // 纯截图录制或音频加载失败：用虚拟时钟按截图时间轴回放。
            clock = VirtualReplayClock(duration: session.duration)
            setErrorMessage(nil)
            updatePlaybackControls(isEnabled: true)
            refreshPlaybackState(at: 0)
            startAutoPlayback()
        } else {
            clock = nil
            setErrorMessage(L10n.recording.replayLoadFailed)
        }
    }

    func stopPlayback() {
        playbackTimer?.invalidate()
        playbackTimer = nil

        clock?.pause()
        clock = nil

        updatePlayPauseButton(isPlaying: false)
        updatePlaybackControls(isEnabled: false)
    }

    private func startKeyboardMonitor() {
        guard keyboardMonitor == nil else { return }
        keyboardMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            guard self.window != nil, event.window === self.window else { return event }

            return self.handleReplayKeyDown(event)
        }
    }

    private func stopKeyboardMonitor() {
        guard let keyboardMonitor else { return }
        NSEvent.removeMonitor(keyboardMonitor)
        self.keyboardMonitor = nil
    }

    private func handleReplayKeyDown(_ event: NSEvent) -> NSEvent? {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let ignoredModifiers: NSEvent.ModifierFlags = [.capsLock, .numericPad, .function]
        guard modifiers.subtracting(ignoredModifiers).isEmpty else {
            return event
        }

        switch event.keyCode {
        case 49:
            playPauseTapped()
            return nil
        case 123:
            rewindTapped()
            return nil
        case 124:
            forwardTapped()
            return nil
        default:
            if event.charactersIgnoringModifiers == " " {
                playPauseTapped()
                return nil
            }
            return event
        }
    }

    static func formatTime(_ time: TimeInterval) -> String {
        let totalSeconds = max(0, Int(floor(time)))
        return String(format: "%02d:%02d", totalSeconds / 60, totalSeconds % 60)
    }

    // MARK: - UI 设置

    func setupUI() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        setupHeader()
        setupContent()
        setupControls()
    }

    func setupHeader() {
        addSubview(headerContainer)

        backButton.title = ""
        backButton.image = NSImage(
            systemSymbolName: "chevron.left",
            accessibilityDescription: L10n.recording.back
        )
        backButton.imagePosition = .imageOnly
        backButton.imageScaling = .scaleProportionallyDown
        backButton.bezelStyle = .rounded
        backButton.toolTip = L10n.recording.back
        backButton.target = self
        backButton.action = #selector(backTapped)
        headerContainer.addSubview(backButton)

        titleLabel.font = NSFont.systemFont(ofSize: 17, weight: .semibold)
        titleLabel.lineBreakMode = .byTruncatingTail
        headerContainer.addSubview(titleLabel)

        deviceCountLabel.font = NSFont.systemFont(ofSize: 12)
        deviceCountLabel.textColor = .secondaryLabelColor
        headerContainer.addSubview(deviceCountLabel)
    }

    func setupContent() {
        contentContainer.wantsLayer = true
        contentContainer.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.9).cgColor
        addSubview(contentContainer)

        emptyLabel.stringValue = L10n.recording.noSnapshots
        emptyLabel.font = NSFont.systemFont(ofSize: 15)
        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.alignment = .center
        emptyLabel.isHidden = true
        contentContainer.addSubview(emptyLabel)

        deviceStackView.orientation = .horizontal
        deviceStackView.alignment = .top
        deviceStackView.distribution = .fillEqually
        deviceStackView.spacing = 12
        contentContainer.addSubview(deviceStackView)
    }

    func setupControls() {
        addSubview(controlsContainer)

        currentTimeLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        currentTimeLabel.alignment = .left
        controlsContainer.addSubview(currentTimeLabel)

        configureIconButton(
            rewindButton,
            systemSymbolName: "gobackward.5",
            tooltip: L10n.recording.rewindFiveSeconds,
            action: #selector(rewindTapped)
        )
        configureIconButton(
            playPauseButton,
            systemSymbolName: "play.fill",
            tooltip: L10n.recording.play,
            action: #selector(playPauseTapped)
        )
        configureIconButton(
            forwardButton,
            systemSymbolName: "goforward.5",
            tooltip: L10n.recording.forwardFiveSeconds,
            action: #selector(forwardTapped)
        )
        configureButton(speedButton, title: "1.0x", action: #selector(speedTapped))

        progressSlider.target = self
        progressSlider.action = #selector(progressChanged)
        controlsContainer.addSubview(progressSlider)

        totalTimeLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        totalTimeLabel.textColor = .secondaryLabelColor
        controlsContainer.addSubview(totalTimeLabel)

        updatePlayPauseButton(isPlaying: false)
    }

    func configureButton(_ button: NSButton, title: String, action: Selector) {
        button.title = title
        button.bezelStyle = .rounded
        button.target = self
        button.action = action
        button.focusRingType = .none
        controlsContainer.addSubview(button)
    }

    func configureIconButton(
        _ button: NSButton,
        systemSymbolName: String,
        tooltip: String,
        action: Selector
    ) {
        button.title = ""
        button.image = NSImage(systemSymbolName: systemSymbolName, accessibilityDescription: tooltip)
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        button.bezelStyle = .rounded
        button.toolTip = tooltip
        button.target = self
        button.action = action
        button.focusRingType = .none
        controlsContainer.addSubview(button)
    }
}

extension NSImage {
    /// 估算位图占用字节数(像素数 × 4)，作为 NSCache 的 cost。取最大的位图表示，
    /// 无位图表示时回退到点尺寸估算。
    var estimatedByteCost: Int {
        let pixelCost = representations
            .map { $0.pixelsWide * $0.pixelsHigh }
            .max() ?? 0
        if pixelCost > 0 {
            return pixelCost * 4
        }
        return Int(size.width * size.height) * 4
    }
}

// MARK: - 回放时钟

/// 回放时间轴抽象。有音频时由 AVAudioPlayer 驱动，无音频时由虚拟时钟驱动，
/// 使回放控制逻辑无需区分是否存在音频轨道。
protocol ReplayClock: AnyObject {
    var currentTime: TimeInterval { get set }
    var duration: TimeInterval { get }
    var rate: Float { get set }
    var isPlaying: Bool { get }
    @discardableResult func play() -> Bool
    func pause()
}

/// 音频驱动时钟，直接转发到 AVAudioPlayer。
final class AudioReplayClock: ReplayClock {
    private let player: AVAudioPlayer

    init(player: AVAudioPlayer) {
        self.player = player
    }

    var currentTime: TimeInterval {
        get { player.currentTime }
        set { player.currentTime = newValue }
    }

    var duration: TimeInterval { player.duration }

    var rate: Float {
        get { player.rate }
        set { player.rate = newValue }
    }

    var isPlaying: Bool { player.isPlaying }

    @discardableResult
    func play() -> Bool { player.play() }
    func pause() { player.pause() }
}

/// 虚拟时钟，用于纯截图录制（无音频）的回放。基于系统单调时钟按倍速推进。
final class VirtualReplayClock: ReplayClock {
    let duration: TimeInterval
    var rate: Float = 1.0

    private var playing = false
    private var anchorMediaTime: TimeInterval = 0
    private var anchorPlaybackTime: TimeInterval = 0

    init(duration: TimeInterval) {
        self.duration = max(0, duration)
    }

    var isPlaying: Bool { playing }

    var currentTime: TimeInterval {
        get {
            guard playing else { return anchorPlaybackTime }
            let elapsed = (CACurrentMediaTime() - anchorMediaTime) * Double(rate)
            return min(max(0, anchorPlaybackTime + elapsed), duration)
        }
        set {
            anchorPlaybackTime = min(max(0, newValue), duration)
            anchorMediaTime = CACurrentMediaTime()
        }
    }

    @discardableResult
    func play() -> Bool {
        guard !playing else { return true }
        anchorMediaTime = CACurrentMediaTime()
        playing = true
        return true
    }

    func pause() {
        guard playing else { return }
        anchorPlaybackTime = currentTime
        playing = false
    }
}
