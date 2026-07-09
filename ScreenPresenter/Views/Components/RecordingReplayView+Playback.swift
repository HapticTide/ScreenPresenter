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

    func updatePlayPauseButton(isPlaying: Bool) {
        let title = isPlaying ? L10n.recording.pause : L10n.recording.play
        let symbolName = isPlaying ? "pause.fill" : "play.fill"
        playPauseButton.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: title)
        playPauseButton.toolTip = title
    }

    func startAutoPlayback() {
        guard let clock else { return }

        clock.rate = playbackRate
        if clock.play() {
            startPlaybackTimer()
            updatePlayPauseButton(isPlaying: true)
        } else {
            updatePlayPauseButton(isPlaying: false)
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
            updatePlayPauseButton(isPlaying: false)
        } else {
            if clock.currentTime >= clock.duration {
                seek(to: 0)
            }
            clock.rate = playbackRate
            clock.play()
            startPlaybackTimer()
            updatePlayPauseButton(isPlaying: true)
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
        if !clock.isPlaying {
            playbackTimer?.invalidate()
            playbackTimer = nil
            updatePlayPauseButton(isPlaying: false)
        }
    }
}
