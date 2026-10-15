//
//  RecordingReplayView+DevicePane.swift
//  ScreenPresenter
//
//  Created by Tank on 2026/07/02.
//

import AVFoundation
import AppKit

// MARK: - 设备回放 Pane

extension RecordingReplayView {
    final class DevicePane {
        let track: RecordingDeviceTrack
        let container: DevicePaneContainerView
        let titleLabel: NSTextField
        let imageView: NSImageView
        let videoView: NSView
        let interruptedLabel: NSTextField
        let playerLayer: AVPlayerLayer
        var player: AVPlayer?
        var currentSnapshotURL: URL?
        var currentVideoURL: URL?

        init(track: RecordingDeviceTrack) {
            self.track = track

            container = DevicePaneContainerView()

            titleLabel = NSTextField(labelWithString: "\(track.platform.displayName) · \(track.deviceName)")
            titleLabel.font = NSFont.systemFont(ofSize: 12, weight: .medium)
            titleLabel.textColor = .secondaryLabelColor
            titleLabel.alignment = .center
            titleLabel.lineBreakMode = .byTruncatingTail

            imageView = NSImageView()
            imageView.imageScaling = .scaleProportionallyUpOrDown
            imageView.imageAlignment = .alignCenter

            videoView = NSView()
            videoView.wantsLayer = true
            videoView.isHidden = true

            interruptedLabel = NSTextField(labelWithString: L10n.recording.captureInterrupted)
            interruptedLabel.font = NSFont.systemFont(ofSize: 14, weight: .medium)
            interruptedLabel.textColor = .secondaryLabelColor
            interruptedLabel.alignment = .center
            interruptedLabel.isHidden = true

            playerLayer = AVPlayerLayer()
            playerLayer.videoGravity = .resizeAspect
            playerLayer.backgroundColor = NSColor.black.cgColor
            playerLayer.isHidden = true

            container.addSubview(imageView)
            container.addSubview(videoView)
            container.addSubview(interruptedLabel)
            container.addSubview(titleLabel)
            videoView.layer?.addSublayer(playerLayer)
            container.onLayout = { [weak self] bounds in
                guard let self else { return }
                self.titleLabel.frame = NSRect(
                    x: 10,
                    y: bounds.height - 30,
                    width: max(0, bounds.width - 20),
                    height: 18
                )
                self.imageView.frame = NSRect(
                    x: 10,
                    y: 10,
                    width: max(0, bounds.width - 20),
                    height: max(0, bounds.height - 48)
                )
                self.videoView.frame = self.imageView.frame
                self.interruptedLabel.frame = self.imageView.frame
                self.playerLayer.frame = self.videoView.bounds
            }
        }

        func clearImage() {
            currentSnapshotURL = nil
            imageView.image = nil
        }

        func showInterrupted() {
            player?.pause()
            videoView.isHidden = true
            imageView.isHidden = true
            interruptedLabel.isHidden = false
            currentSnapshotURL = nil
        }

        func showVideo(fileURL: URL, localTime: TimeInterval, isPlaying: Bool, rate: Float) {
            if currentVideoURL != fileURL {
                let player = AVPlayer(url: fileURL)
                player.isMuted = true
                player.automaticallyWaitsToMinimizeStalling = false
                self.player = player
                playerLayer.player = player
                currentVideoURL = fileURL
            }

            guard let player else { return }
            let currentTime = player.currentTime().seconds
            let drift = currentTime.isFinite ? abs(currentTime - localTime) : .infinity
            if drift > 0.15 {
                player.seek(
                    to: CMTime(seconds: localTime, preferredTimescale: 600),
                    toleranceBefore: .zero,
                    toleranceAfter: .zero
                )
            }

            interruptedLabel.isHidden = true
            imageView.isHidden = true
            videoView.isHidden = false
            playerLayer.isHidden = false
            if isPlaying {
                player.rate = rate
            } else {
                player.pause()
            }
        }

        func pauseVideo() {
            player?.pause()
        }

        func clearVideo() {
            player?.pause()
            player = nil
            playerLayer.player = nil
            playerLayer.isHidden = true
            videoView.isHidden = true
            currentVideoURL = nil
        }
    }

    func rebuildDevicePanes(for tracks: [RecordingDeviceTrack]) {
        deviceStackView.arrangedSubviews.forEach { view in
            deviceStackView.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        devicePanes.removeAll()

        emptyLabel.isHidden = !tracks.isEmpty
        deviceStackView.isHidden = tracks.isEmpty

        for track in tracks {
            let pane = DevicePane(track: track)
            devicePanes.append(pane)
            deviceStackView.addArrangedSubview(pane.container)
        }
        needsLayout = true
    }
}

// MARK: - 设备回放容器

final class DevicePaneContainerView: NSView {
    var onLayout: ((NSRect) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupUI()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
    }

    override func layout() {
        super.layout()
        onLayout?(bounds)
    }

    private func setupUI() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        layer?.cornerRadius = 8
    }
}
