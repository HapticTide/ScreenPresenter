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
    var audioPlayer: AVAudioPlayer?
    var playbackTimer: Timer?
    private var keyboardMonitor: Any?
    var devicePanes: [DevicePane] = []
    var imageCache: [URL: NSImage] = [:]
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
        imageCache.removeAll()
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

        do {
            let player = try AVAudioPlayer(contentsOf: session.audioURL)
            player.enableRate = true
            player.rate = playbackRate
            player.prepareToPlay()
            audioPlayer = player
            setErrorMessage(nil)
            updatePlaybackControls(isEnabled: true)
            refreshPlaybackState(at: 0)
            startAutoPlayback()
        } catch {
            audioPlayer = nil
            setErrorMessage(L10n.recording.replayLoadFailed)
        }
    }

    func stopPlayback() {
        playbackTimer?.invalidate()
        playbackTimer = nil

        audioPlayer?.stop()
        audioPlayer = nil

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
