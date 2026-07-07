//
//  RecordingHistoryPopoverView.swift
//  ScreenPresenter
//
//  Created by Tank on 2026/07/02.
//

import AppKit

// MARK: - 录制历史弹框内容视图

final class RecordingHistoryPopoverView: NSView {
    // MARK: - 回调

    var onRevealDirectory: ((RecordingSession) -> Void)?
    var onReplay: ((RecordingSession) -> Void)?

    // MARK: - UI 组件

    private let scrollView = NSScrollView()
    private let tableView = NSTableView()
    private let emptyLabel = NSTextField(labelWithString: L10n.recording.noHistory)
    private var sessions: [RecordingSession] = []

    // MARK: - 格式化

    private static let startedAtFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    // MARK: - 初始化

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupUI()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: Metrics.preferredWidth, height: Metrics.preferredHeight)
    }

    override func layout() {
        super.layout()
        updateTableColumnWidth()
    }

    // MARK: - 公开方法

    func configure(sessions: [RecordingSession]) {
        self.sessions = sessions

        emptyLabel.isHidden = !sessions.isEmpty
        scrollView.isHidden = sessions.isEmpty
        tableView.reloadData()
        updateTableColumnWidth()
    }

    // MARK: - UI 设置

    private func setupUI() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        setupScrollView()
        setupEmptyState()
    }

    private func setupScrollView() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .noBorder
        addSubview(scrollView)

        tableView.headerView = nil
        tableView.rowHeight = Metrics.rowHeight
        tableView.intercellSpacing = NSSize(width: 0, height: Metrics.rowSpacing)
        tableView.backgroundColor = .clear
        tableView.selectionHighlightStyle = .none
        tableView.usesAlternatingRowBackgroundColors = false
        tableView.dataSource = self
        tableView.delegate = self

        let column = NSTableColumn(identifier: Metrics.columnIdentifier)
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        scrollView.documentView = tableView

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: topAnchor, constant: Metrics.contentInset),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Metrics.contentInset),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Metrics.contentInset),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Metrics.contentInset)
        ])
    }

    private func setupEmptyState() {
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        emptyLabel.font = NSFont.systemFont(ofSize: 13)
        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.alignment = .center
        addSubview(emptyLabel)

        NSLayoutConstraint.activate([
            emptyLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Metrics.contentInset),
            emptyLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Metrics.contentInset),
            emptyLabel.centerYAnchor.constraint(equalTo: centerYAnchor, constant: Metrics.emptyStateYOffset)
        ])
    }

    private func makeCell(for session: RecordingSession) -> NSTableCellView {
        let cell = NSTableCellView()
        cell.wantsLayer = true
        cell.layer?.backgroundColor = NSColor.clear.cgColor

        let row = HistoryRowView()
        row.configure(
            title: session.directory.lastPathComponent,
            subtitle: subtitleText(for: session),
            session: session
        )
        row.revealButton.target = self
        row.revealButton.action = #selector(revealDirectoryTapped(_:))
        row.replayButton.target = self
        row.replayButton.action = #selector(replayTapped(_:))
        row.replayButton.isEnabled = session.duration > 0
        row.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(row)

        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: cell.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: cell.trailingAnchor),
            row.topAnchor.constraint(equalTo: cell.topAnchor),
            row.bottomAnchor.constraint(equalTo: cell.bottomAnchor)
        ])

        return cell
    }

    private func updateTableColumnWidth() {
        guard let column = tableView.tableColumns.first else { return }
        column.width = max(scrollView.contentSize.width, Metrics.minimumContentWidth)
    }

    private func subtitleText(for session: RecordingSession) -> String {
        let startedAtText = session.startedAt > .distantPast
            ? Self.startedAtFormatter.string(from: session.startedAt)
            : session.directory.lastPathComponent
        let detailText = L10n.recording.historyDetail(
            RecordingReplayView.formatTime(session.duration),
            session.deviceTracks.count
        )
        return "\(startedAtText) · \(detailText)"
    }

    // MARK: - Actions

    @objc private func revealDirectoryTapped(_ sender: SessionButton) {
        guard let session = sender.session else {
            return
        }
        onRevealDirectory?(session)
    }

    @objc private func replayTapped(_ sender: SessionButton) {
        guard let session = sender.session else {
            return
        }
        onReplay?(session)
    }
}

// MARK: - 内部类型

private class SessionButton: NSButton {
    var session: RecordingSession?
}

private final class HistoryRowView: NSView {
    let revealButton = SessionIconButton(style: .secondary)
    let replayButton = SessionIconButton(style: .primary)

    private let titleLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(labelWithString: "")

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

        let textLeft = Metrics.rowHorizontalInset
        let midpoint = bounds.width * Metrics.actionAreaStartRatio
        let actionButtonSize = Metrics.iconButtonSize
        let actionSpacing = Metrics.iconButtonSpacing
        let actionsWidth = actionButtonSize.width * 2 + actionSpacing
        let actionsX = max(midpoint, bounds.width - actionsWidth - Metrics.actionRightInset)
        let buttonY = (bounds.height - actionButtonSize.height) / 2

        revealButton.frame = NSRect(
            x: actionsX,
            y: buttonY,
            width: actionButtonSize.width,
            height: actionButtonSize.height
        )
        replayButton.frame = NSRect(
            x: revealButton.frame.maxX + actionSpacing,
            y: buttonY,
            width: actionButtonSize.width,
            height: actionButtonSize.height
        )

        let textWidth = max(0, actionsX - textLeft - Metrics.textToActionSpacing)
        titleLabel.frame = NSRect(
            x: textLeft,
            y: bounds.midY + 3,
            width: textWidth,
            height: 20
        )
        subtitleLabel.frame = NSRect(
            x: textLeft,
            y: bounds.midY - 20,
            width: textWidth,
            height: 17
        )
    }

    func configure(title: String, subtitle: String, session: RecordingSession) {
        titleLabel.stringValue = title
        subtitleLabel.stringValue = subtitle
        revealButton.session = session
        replayButton.session = session
    }

    private func setupUI() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        titleLabel.font = NSFont.systemFont(ofSize: 14, weight: .semibold)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1
        addSubview(titleLabel)

        subtitleLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.lineBreakMode = .byTruncatingTail
        subtitleLabel.maximumNumberOfLines = 1
        addSubview(subtitleLabel)

        revealButton.image = NSImage(
            systemSymbolName: "folder",
            accessibilityDescription: L10n.recording.revealDirectory
        )
        revealButton.toolTip = L10n.recording.revealDirectory
        addSubview(revealButton)

        replayButton.image = NSImage(
            systemSymbolName: "play.fill",
            accessibilityDescription: L10n.recording.replay
        )
        replayButton.toolTip = L10n.recording.replay
        addSubview(replayButton)
    }
}

private final class SessionIconButton: SessionButton {
    enum Style {
        case primary
        case secondary
    }

    private let style: Style

    init(style: Style) {
        self.style = style
        super.init(frame: .zero)
        setupUI()
    }

    required init?(coder: NSCoder) {
        self.style = .secondary
        super.init(coder: coder)
        setupUI()
    }

    override var isEnabled: Bool {
        didSet {
            updateAppearance()
        }
    }

    override func layout() {
        super.layout()
        layer?.cornerRadius = bounds.height / 2
    }

    private func setupUI() {
        title = ""
        isBordered = false
        bezelStyle = .regularSquare
        imagePosition = .imageOnly
        imageScaling = .scaleProportionallyDown
        focusRingType = .none
        wantsLayer = true
        updateAppearance()
    }

    private func updateAppearance() {
        switch style {
        case .primary:
            layer?.backgroundColor = (isEnabled ? NSColor.systemBlue : NSColor.systemGray)
                .withAlphaComponent(isEnabled ? 0.95 : 0.35)
                .cgColor
            contentTintColor = .white
        case .secondary:
            layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.75).cgColor
            contentTintColor = isEnabled ? .labelColor : .disabledControlTextColor
        }
    }
}

// MARK: - NSTableViewDataSource / NSTableViewDelegate

extension RecordingHistoryPopoverView: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int {
        sessions.count
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        Metrics.rowHeight
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard sessions.indices.contains(row) else {
            return nil
        }

        return makeCell(for: sessions[row])
    }
}

private enum Metrics {
    static let preferredWidth: CGFloat = 520
    static let preferredHeight: CGFloat = 360
    static let minimumContentWidth: CGFloat = 320
    static let columnIdentifier = NSUserInterfaceItemIdentifier("recordingHistory")
    static let contentInset: CGFloat = 16
    static let rowSpacing: CGFloat = 8
    static let rowHeight: CGFloat = 72
    static let emptyStateYOffset: CGFloat = 14
    static let rowHorizontalInset: CGFloat = 8
    static let actionRightInset: CGFloat = 44
    static let actionAreaStartRatio: CGFloat = 0.5
    static let textToActionSpacing: CGFloat = 16
    static let iconButtonSize = NSSize(width: 42, height: 32)
    static let iconButtonSpacing: CGFloat = 12
}
