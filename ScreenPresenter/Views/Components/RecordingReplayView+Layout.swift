//
//  RecordingReplayView+Layout.swift
//  ScreenPresenter
//
//  Created by Tank on 2026/07/02.
//

import AppKit

// MARK: - 布局

extension RecordingReplayView {
    struct ControlButtonLayout {
        let maxX: CGFloat
        let originY: CGFloat
        let spacing: CGFloat
    }

    func layoutReplayView() {
        let viewBounds = bounds
        let horizontalInset: CGFloat = 20
        let headerHeight: CGFloat = 58
        let controlsHeight: CGFloat = 58

        headerContainer.frame = NSRect(
            x: 0,
            y: viewBounds.height - headerHeight,
            width: viewBounds.width,
            height: headerHeight
        )
        controlsContainer.frame = NSRect(x: 0, y: 0, width: viewBounds.width, height: controlsHeight)
        contentContainer.frame = NSRect(
            x: 0,
            y: controlsHeight,
            width: viewBounds.width,
            height: max(0, viewBounds.height - headerHeight - controlsHeight)
        )

        layoutHeader(inset: horizontalInset)
        layoutContent(inset: horizontalInset)
        layoutControls(inset: horizontalInset)
    }

    func layoutHeader(inset: CGFloat) {
        let buttonWidth: CGFloat = 36
        backButton.frame = NSRect(
            x: inset,
            y: (headerContainer.bounds.height - 30) / 2,
            width: buttonWidth,
            height: 30
        )

        let titleOriginX = backButton.frame.maxX + 14
        let titleWidth = max(0, headerContainer.bounds.width - titleOriginX - inset)
        titleLabel.frame = NSRect(x: titleOriginX, y: 30, width: titleWidth, height: 20)
        deviceCountLabel.frame = NSRect(x: titleOriginX, y: 12, width: titleWidth, height: 16)
    }

    func layoutContent(inset: CGFloat) {
        let contentBounds = contentContainer.bounds.insetBy(dx: inset, dy: 16)
        emptyLabel.frame = NSRect(
            x: inset,
            y: (contentContainer.bounds.height - 24) / 2,
            width: max(0, contentContainer.bounds.width - inset * 2),
            height: 24
        )
        deviceStackView.frame = contentBounds
    }

    func layoutControls(inset: CGFloat) {
        let controlOriginY = (controlsContainer.bounds.height - 28) / 2
        let timeWidth: CGFloat = 104
        let buttonWidth: CGFloat = 42
        let playWidth: CGFloat = 42
        let speedWidth: CGFloat = 58
        let spacing: CGFloat = 8

        let maxControlX = layoutTimeLabel(
            inset: inset,
            originY: controlOriginY,
            timeWidth: timeWidth,
            spacing: spacing
        )
        let buttonLayout = ControlButtonLayout(
            maxX: maxControlX,
            originY: controlOriginY,
            spacing: spacing
        )
        var nextControlOriginX = inset
        nextControlOriginX = layoutButton(
            rewindButton,
            originX: nextControlOriginX,
            width: buttonWidth,
            layout: buttonLayout
        )
        nextControlOriginX = layoutButton(
            playPauseButton,
            originX: nextControlOriginX,
            width: playWidth,
            layout: buttonLayout
        )
        nextControlOriginX = layoutButton(
            forwardButton,
            originX: nextControlOriginX,
            width: buttonWidth,
            layout: buttonLayout
        )
        nextControlOriginX = layoutButton(
            speedButton,
            originX: nextControlOriginX,
            width: speedWidth,
            layout: buttonLayout
        )

        let sliderOriginX = nextControlOriginX
        let sliderWidth = max(0, maxControlX - sliderOriginX)
        progressSlider.isHidden = sliderWidth == 0
        progressSlider.frame = NSRect(x: sliderOriginX, y: controlOriginY + 3, width: sliderWidth, height: 22)
    }

    func layoutTimeLabel(
        inset: CGFloat,
        originY: CGFloat,
        timeWidth: CGFloat,
        spacing: CGFloat
    ) -> CGFloat {
        totalTimeLabel.isHidden = true
        totalTimeLabel.frame = .zero

        currentTimeLabel.frame = NSRect(
            x: controlsContainer.bounds.width - inset - timeWidth,
            y: originY + 5,
            width: timeWidth,
            height: 18
        )

        let canShowTime = currentTimeLabel.frame.minX >= inset + spacing
        currentTimeLabel.isHidden = !canShowTime

        let rightLimit = canShowTime ? currentTimeLabel.frame.minX : controlsContainer.bounds.width - inset
        return rightLimit - spacing
    }

    func layoutButton(
        _ button: NSButton,
        originX: CGFloat,
        width: CGFloat,
        layout: ControlButtonLayout
    ) -> CGFloat {
        guard originX + width <= layout.maxX else {
            button.isHidden = true
            button.frame = .zero
            return originX
        }

        button.isHidden = false
        button.frame = NSRect(x: originX, y: layout.originY, width: width, height: 28)
        return button.frame.maxX + layout.spacing
    }
}
