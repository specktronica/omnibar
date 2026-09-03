import AppKit
import Foundation

final class AppListView: NSScrollView {
    var onLaunch: ((AppCatalog.CatalogApp) -> Void)?
    private let document = FlippedView()
    private var headers: [NSTextField] = []
    private var rows: [AppRow] = []
    private var contentHeight: CGFloat = 1
    private var renderedIDs: [String] = []

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        drawsBackground = false
        contentView.drawsBackground = false
        borderType = .noBorder
        hasVerticalScroller = true
        hasHorizontalScroller = false
        autohidesScrollers = true
        documentView = document
    }

    required init?(coder: NSCoder) { nil }

    func update(_ groups: [(letter: String, apps: [AppCatalog.CatalogApp])]) {
        let ids = groups.flatMap { group in
            [group.letter] + group.apps.map(\.id)
        }
        if ids == renderedIDs {
            contentView.scroll(to: .zero)
            return
        }
        renderedIDs = ids
        rebuild(groups)
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
                extra.removeFromSuperview()
            }
        }
        headers = nextHeaders
        rows = nextRows
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
}

private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

private final class AppRow: NSView {
    var onLaunch: ((AppCatalog.CatalogApp) -> Void)?
    private var app: AppCatalog.CatalogApp
    private let icon = NSImageView()
    private let label = NSTextField(labelWithString: "")

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

    override func layout() {
        super.layout()
        icon.frame = NSRect(x: 6, y: 4, width: 20, height: 20)
        label.frame = NSRect(x: 32, y: 4, width: max(bounds.width - 40, 0), height: 20)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        ))
    }

    override func mouseEntered(with event: NSEvent) {
        layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.08).cgColor
    }

    override func mouseExited(with event: NSEvent) {
        layer?.backgroundColor = nil
    }

    override func mouseDown(with event: NSEvent) {}

    override func mouseUp(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        if bounds.contains(location) {
            onLaunch?(app)
        }
    }
}
