//
//  RecordingReplayView+Playback.swift
//  ScreenPresenter
//
//  Created by Tank on 2026/07/02.
//

import AppKit

// MARK: - 播放控制

extension RecordingReplayView {
    func seek(to time: TimeInterval) {
        let duration = session?.duration ?? clock?.duration ?? 0
        let clampedTime = min(max(0, time), duration)
        clock?.currentTime = clampedTime
        refreshPlaybackState(at: clampedTime)
    }

    func refreshPlaybackState(at time: TimeInterval) {
        currentTimeLabel.stringValue = "\(Self.formatTime(time)) / \(Self.formatTime(session?.duration ?? 0))"
        progressSlider.doubleValue = min(max(progressSlider.minValue, time), progressSlider.maxValue)
        refreshSnapshots(at: Int(floor(time)))
    }

    func startPlaybackTimer() {
        playbackTimer?.invalidate()
        playbackTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            self?.playbackTimerFired()
        }
    }

    /// 播放按钮的三种形态:播放中(暂停图标)、已暂停(播放图标)、已播完(重播图标)。
    enum PlaybackButtonState {
        case playing
        case paused
        case ended
    }

    func updatePlayPauseButton(_ state: PlaybackButtonState) {
        let symbolName: String
        let title: String
        switch state {
        case .playing:
            symbolName = "pause.fill"
            title = L10n.recording.pause
        case .paused:
            symbolName = "play.fill"
            title = L10n.recording.play
        case .ended:
            symbolName = "arrow.counterclockwise"
            title = L10n.recording.replay
        }
        playPauseButton.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: title)
        playPauseButton.toolTip = title
    }

    func startAutoPlayback() {
        guard let clock else { return }

        clock.rate = playbackRate
        if clock.play() {
            startPlaybackTimer()
            updatePlayPauseButton(.playing)
        } else {
            updatePlayPauseButton(.paused)
        }
    }

    func updateSpeedButtonTitle() {
        speedButton.title = String(format: "%.1fx", playbackRate)
    }

    func updatePlaybackControls(isEnabled: Bool) {
        rewindButton.isEnabled = isEnabled
        playPauseButton.isEnabled = isEnabled
        forwardButton.isEnabled = isEnabled
        speedButton.isEnabled = isEnabled
        progressSlider.isEnabled = isEnabled
    }

    func setErrorMessage(_ message: String?) {
        if let message {
            emptyLabel.stringValue = message
            emptyLabel.isHidden = false
        } else {
            emptyLabel.stringValue = L10n.recording.noSnapshots
            emptyLabel.isHidden = !(session?.deviceTracks.isEmpty ?? true)
        }
    }

    func refreshSnapshots(at elapsedSecond: Int) {
        for pane in devicePanes {
            guard let snapshot = pane.track.snapshot(at: elapsedSecond) else {
                pane.clearImage()
                continue
            }

            updateSnapshot(for: pane, fileURL: snapshot.fileURL)
        }
    }

    func updateSnapshot(for pane: DevicePane, fileURL: URL) {
        // 同一秒内定时器会多次触发；URL 没变时直接跳过磁盘读取和 imageView 赋值。
        if pane.currentSnapshotURL == fileURL {
            return
        }

        pane.currentSnapshotURL = fileURL
        let key = fileURL as NSURL
        if let cachedImage = imageCache.object(forKey: key) {
            pane.imageView.image = cachedImage
            return
        }

        guard let image = NSImage(contentsOf: fileURL) else {
            pane.imageView.image = nil
            return
        }

        imageCache.setObject(image, forKey: key, cost: image.estimatedByteCost)
        pane.imageView.image = image
    }

    @objc func backTapped() {
        stopPlayback()
        onBack?()
    }

    @objc func playPauseTapped() {
        guard let clock else { return }

        if clock.isPlaying {
            clock.pause()
            playbackTimer?.invalidate()
            playbackTimer = nil
            updatePlayPauseButton(.paused)
        } else {
            if clock.currentTime >= clock.duration {
                seek(to: 0)
            }
            clock.rate = playbackRate
            clock.play()
            startPlaybackTimer()
            updatePlayPauseButton(.playing)
        }
    }

    @objc func rewindTapped() {
        seek(to: (clock?.currentTime ?? progressSlider.doubleValue) - 5)
    }

    @objc func forwardTapped() {
        seek(to: (clock?.currentTime ?? progressSlider.doubleValue) + 5)
    }

    @objc func speedTapped() {
        switch playbackRate {
        case 1.0:
            playbackRate = 1.5
        case 1.5:
            playbackRate = 2.0
        case 2.0:
            playbackRate = 0.5
        default:
            playbackRate = 1.0
        }

        clock?.rate = playbackRate
        updateSpeedButtonTitle()
    }

    @objc func progressChanged() {
        seek(to: progressSlider.doubleValue)
    }

    @objc func playbackTimerFired() {
        guard let clock else { return }

        refreshPlaybackState(at: clock.currentTime)

        // 手动暂停会在 playPauseTapped 中同步失效定时器，不会走到这里；
        // 因此定时器一旦观测到「不再播放」或「已到末尾」，必定是自然播完。
        // 音频时钟播完后 isPlaying 变 false；虚拟时钟无自停机制，靠 currentTime 到达 duration 判定。
        let reachedEnd = !clock.isPlaying || clock.currentTime >= clock.duration
        guard reachedEnd else { return }

        clock.pause() // 冻结虚拟时钟于末尾；对音频时钟是空操作。
        playbackTimer?.invalidate()
        playbackTimer = nil
        // 对齐进度条与时间标签到末尾，避免停在 24.75s / 25s 这类中间态。
        refreshPlaybackState(at: clock.duration)
        updatePlayPauseButton(.ended)
    }
}
