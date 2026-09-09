import AppKit
import Foundation

nonisolated enum StartMenuListNavigation: Sendable {
    static func indexAfterMove(current: Int?, count: Int, delta: Int) -> Int? {
        guard count > 0 else { return nil }
        if let current {
            return min(max(current + delta, 0), count - 1)
        }
        return delta >= 0 ? 0 : count - 1
    }

    static func indexAfterReload(previousID: String?, ids: [String], autoselectFirst: Bool) -> Int? {
        if let previousID, let index = ids.firstIndex(of: previousID) {
            return index
        }
        if autoselectFirst, !ids.isEmpty {
            return 0
        }
        return nil
    }
}

final class AppListView: NSScrollView {
    var onLaunch: ((AppCatalog.CatalogApp) -> Void)?
    private let document = FlippedView()
    private var headers: [NSTextField] = []
    private var rows: [AppRow] = []
    private var contentHeight: CGFloat = 1
    private var renderedIDs: [String] = []
    private var hoveredRow: AppRow?
    private var listTracking: NSTrackingArea?
    private var highlightSource: HighlightSource = .mouse
    private var frozenMouseLocation: NSPoint?

    private enum HighlightSource {
        case mouse
        case keyboard
    }

    var highlightedAppNames: [String] {
        rows.filter(\.isHovered).map(\.appName)
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        drawsBackground = false
        contentView.drawsBackground = false
        borderType = .noBorder
        hasVerticalScroller = true
        hasHorizontalScroller = false
        autohidesScrollers = true
        documentView = document
        contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(clipViewBoundsDidChange),
            name: NSView.boundsDidChangeNotification,
            object: contentView
        )
    }

    required init?(coder: NSCoder) { nil }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func update(
        _ groups: [(letter: String, apps: [AppCatalog.CatalogApp])],
        autoselectFirst: Bool = false
    ) {
        let previousID = hoveredRow.map(\.catalogApp.id)
        let ids = groups.flatMap { group in
            [group.letter] + group.apps.map(\.id)
        }
        if ids == renderedIDs {
            contentView.scroll(to: .zero)
            applyReloadSelection(previousID: previousID, autoselectFirst: autoselectFirst)
            return
        }
        renderedIDs = ids
        rebuild(groups)
        applyReloadSelection(previousID: previousID, autoselectFirst: autoselectFirst)
    }

    func moveSelection(delta: Int) {
        let current = hoveredRow.flatMap { row in
            rows.firstIndex { $0 === row }
        }
        guard let index = StartMenuListNavigation.indexAfterMove(
            current: current,
            count: rows.count,
            delta: delta
        ) else { return }
        setKeyboardHighlight(rows[index])
    }

    func launchSelected() {
        guard let hoveredRow else { return }
        onLaunch?(hoveredRow.catalogApp)
    }

    private func rebuild(_ groups: [(letter: String, apps: [AppCatalog.CatalogApp])]) {
        var y: CGFloat = 0
        let width = max(contentView.bounds.width, bounds.width, 1)
        var headerIndex = 0
        var rowIndex = 0
        var nextHeaders: [NSTextField] = []
        var nextRows: [AppRow] = []

        for group in groups {
            let header: NSTextField
            if headerIndex < headers.count {
                header = headers[headerIndex]
                if header.stringValue != group.letter {
                    header.stringValue = group.letter
                }
            } else {
                header = NSTextField(labelWithString: group.letter)
                header.font = .boldSystemFont(ofSize: 13)
                header.textColor = .secondaryLabelColor
                document.addSubview(header)
            }
            header.frame = NSRect(x: 6, y: y, width: max(width - 12, 0), height: 22)
            nextHeaders.append(header)
            headerIndex += 1
            y += 24

            for app in group.apps {
                let row: AppRow
                if rowIndex < rows.count {
                    row = rows[rowIndex]
                    row.apply(app)
                } else {
                    row = AppRow(app: app)
                    row.onLaunch = { [weak self] launched in self?.onLaunch?(launched) }
                    document.addSubview(row)
                }
                row.frame = NSRect(x: 0, y: y, width: width, height: 28)
                nextRows.append(row)
                rowIndex += 1
                y += 30
            }
        }

        if headerIndex < headers.count {
            for extra in headers[headerIndex...] {
                extra.removeFromSuperview()
            }
        }
        if rowIndex < rows.count {
            for extra in rows[rowIndex...] {
                extra.setHovered(false)
                extra.removeFromSuperview()
            }
        }
        headers = nextHeaders
        rows = nextRows
        if let hoveredRow, !rows.contains(where: { $0 === hoveredRow }) {
            hoveredRow.setHovered(false)
            self.hoveredRow = nil
        }
        contentHeight = max(y, 1)
        document.frame = NSRect(x: 0, y: 0, width: width, height: contentHeight)
        contentView.scroll(to: .zero)
        reflectScrolledClipView(contentView)
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let width = max(contentView.bounds.width, 1)
        for header in headers {
            var frame = header.frame
            frame.size.width = max(width - 12, 0)
            header.frame = frame
        }
        for row in rows {
            var frame = row.frame
            frame.size.width = width
            row.frame = frame
        }
        document.frame = NSRect(x: 0, y: 0, width: width, height: contentHeight)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateHoverFromMouse()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let listTracking {
            removeTrackingArea(listTracking)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        listTracking = area
        addTrackingArea(area)
    }

    override func mouseEntered(with event: NSEvent) {
        handleMouseMovement(atWindowPoint: event.locationInWindow)
    }

    override func mouseMoved(with event: NSEvent) {
        handleMouseMovement(atWindowPoint: event.locationInWindow)
    }

    override func mouseExited(with event: NSEvent) {
        // Recompute instead of blindly clearing: AppKit can emit a spurious
        // exit when scrolling rebuilds the tracking area while the cursor is
        // still inside the list.
        updateHoverFromMouse()
    }

    override func reflectScrolledClipView(_ clipView: NSClipView) {
        super.reflectScrolledClipView(clipView)
        updateHoverFromMouse()
    }

    @objc private func clipViewBoundsDidChange() {
        updateHoverFromMouse()
    }

    func documentPoint(forAppName name: String) -> NSPoint? {
        rows.first { $0.appName == name }.map { NSPoint(x: $0.frame.midX, y: $0.frame.midY) }
    }

    func updateHoverFromMouse() {
        if highlightSource == .keyboard { return }
        guard let window else {
            syncHover(atDocumentPoint: nil)
            return
        }
        applyHover(atWindowPoint: window.mouseLocationOutsideOfEventStream)
    }

    func syncHover(atDocumentPoint point: NSPoint?) {
        highlightSource = .mouse
        frozenMouseLocation = nil
        let row = point.flatMap { location in
            rows.first { $0.frame.contains(location) }
        }
        setHoveredRow(row)
    }

    private func applyHover(atWindowPoint mouseInWindow: NSPoint) {
        let local = convert(mouseInWindow, from: nil)
        guard visibleRect.contains(local) else {
            syncHover(atDocumentPoint: nil)
            return
        }
        syncHover(atDocumentPoint: document.convert(mouseInWindow, from: nil))
    }

    private func handleMouseMovement(atWindowPoint point: NSPoint) {
        if highlightSource == .keyboard, frozenMouseLocation == point {
            return
        }
        highlightSource = .mouse
        frozenMouseLocation = nil
        applyHover(atWindowPoint: point)
    }

    private func applyReloadSelection(previousID: String?, autoselectFirst: Bool) {
        let ids = rows.map(\.catalogApp.id)
        let index = StartMenuListNavigation.indexAfterReload(
            previousID: previousID,
            ids: ids,
            autoselectFirst: autoselectFirst
        )
        if autoselectFirst || highlightSource == .keyboard {
            if let index {
                setKeyboardHighlight(rows[index])
            } else {
                highlightSource = .keyboard
                frozenMouseLocation = window?.mouseLocationOutsideOfEventStream
                setHoveredRow(nil)
            }
            return
        }
        updateHoverFromMouse()
    }

    private func setKeyboardHighlight(_ row: AppRow) {
        highlightSource = .keyboard
        frozenMouseLocation = window?.mouseLocationOutsideOfEventStream
        setHoveredRow(row)
        row.scrollToVisible(row.bounds)
    }

    private func setHoveredRow(_ row: AppRow?) {
        guard hoveredRow !== row else { return }
        hoveredRow?.setHovered(false)
        hoveredRow = row
        hoveredRow?.setHovered(true)
    }
}

private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

private final class AppRow: NSView {
    var onLaunch: ((AppCatalog.CatalogApp) -> Void)?
    private var app: AppCatalog.CatalogApp
    private let icon = NSImageView()
    private let label = NSTextField(labelWithString: "")
    private(set) var isHovered = false

    var appName: String { app.name }
    var catalogApp: AppCatalog.CatalogApp { app }

    init(app: AppCatalog.CatalogApp) {
        self.app = app
        super.init(frame: NSRect(x: 0, y: 0, width: 200, height: 28))
        wantsLayer = true
        layer?.cornerRadius = 6
        icon.imageScaling = .scaleProportionallyUpOrDown
        label.font = .systemFont(ofSize: 13)
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 1
        addSubview(icon)
        addSubview(label)
        apply(app)
    }

    required init?(coder: NSCoder) { nil }

    func apply(_ app: AppCatalog.CatalogApp) {
        if self.app.id == app.id {
            self.app = app
            if label.stringValue != app.name {
                label.stringValue = app.name
            }
            return
        }
        self.app = app
        icon.image = IconCache.icon(for: app.url)
        label.stringValue = app.name
    }

    func setHovered(_ hovered: Bool) {
        guard isHovered != hovered else { return }
        isHovered = hovered
        layer?.backgroundColor = hovered
            ? NSColor.labelColor.withAlphaComponent(0.08).cgColor
            : nil
    }

    override func layout() {
        super.layout()
        icon.frame = NSRect(x: 6, y: 4, width: 20, height: 20)
        label.frame = NSRect(x: 32, y: 4, width: max(bounds.width - 40, 0), height: 20)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {}

    override func mouseUp(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        if bounds.contains(location) {
            onLaunch?(app)
        }
    }
}
