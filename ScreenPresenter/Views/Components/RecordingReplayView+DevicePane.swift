//
//  RecordingReplayView+DevicePane.swift
//  ScreenPresenter
//
//  Created by Tank on 2026/07/02.
//

import AppKit

// MARK: - 设备截图 Pane

extension RecordingReplayView {
    final class DevicePane {
        let track: RecordingDeviceTrack
        let container: DevicePaneContainerView
        let titleLabel: NSTextField
        let imageView: NSImageView
        var currentSnapshotURL: URL?

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

            container.addSubview(titleLabel)
            container.addSubview(imageView)
            container.onLayout = { [weak titleLabel, weak imageView] bounds in
                titleLabel?.frame = NSRect(
                    x: 10,
                    y: bounds.height - 30,
                    width: max(0, bounds.width - 20),
                    height: 18
                )
                imageView?.frame = NSRect(
                    x: 10,
                    y: 10,
                    width: max(0, bounds.width - 20),
                    height: max(0, bounds.height - 48)
                )
            }
        }

        func clearImage() {
            currentSnapshotURL = nil
            imageView.image = nil
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

// MARK: - 设备截图容器

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
