import AppKit
import Foundation

final class TaskItemView: NSView {
    private(set) var item: TaskItem
    var onClick: ((TaskItem) -> Void)?
    var onMiddleClick: ((TaskItem) -> Void)?
    var onRightClick: ((TaskItem, NSEvent) -> Void)?
    var onHover: ((TaskItem) -> Void)?
    var onHoverEnd: (() -> Void)?
    var onDragBegan: ((TaskItemView, NSEvent) -> Void)?
    var onDragged: ((TaskItemView, NSEvent) -> Void)?
    var onDragEnded: ((TaskItemView, NSEvent) -> Void)?

    private let iconView = NSImageView()
    private let badgeView = BadgeView()
    private let titleView = NSTextField(labelWithString: "")
    private let dotsView = WindowDotsView()
    private var hovered = false
    private var mouseDownEvent: NSEvent?
    private var dragging = false
    private var settings: AppSettings
    private var appliedToken = 0

    init(item: TaskItem, settings: AppSettings) {
        self.item = item
        self.settings = settings
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 8
        iconView.imageScaling = .scaleProportionallyUpOrDown
        let cell = VerticallyCenteredTextFieldCell(textCell: "")
        cell.isEditable = false
        cell.isSelectable = false
        cell.isBezeled = false
        cell.drawsBackground = false
        cell.lineBreakMode = .byTruncatingTail
        cell.usesSingleLineMode = true
        cell.truncatesLastVisibleLine = true
        titleView.cell = cell
        titleView.lineBreakMode = .byTruncatingTail
        titleView.maximumNumberOfLines = 1
        titleView.usesSingleLineMode = true
        titleView.isSelectable = false
        addSubview(iconView)
        addSubview(titleView)
        addSubview(dotsView)
        addSubview(badgeView)
        refresh()
        appliedToken = Self.displayToken(item: item, settings: settings)
    }

    required init?(coder: NSCoder) { nil }

    func apply(item: TaskItem, settings: AppSettings) {
        let token = Self.displayToken(item: item, settings: settings)
        if token == appliedToken { return }
        appliedToken = token
        self.item = item
        self.settings = settings
        refresh()
        needsLayout = true
        needsDisplay = true
    }

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
        hovered = true
        needsDisplay = true
        NSCursor.arrow.set()
        onHover?(item)
    }

    override func mouseExited(with event: NSEvent) {
        hovered = false
        needsDisplay = true
        onHoverEnd?()
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(point) ? self : nil
    }

    override func mouseDown(with event: NSEvent) {
        mouseDownEvent = event
        dragging = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard settings.allowDragReorder, let start = mouseDownEvent else { return }
        let delta = hypot(event.locationInWindow.x - start.locationInWindow.x, event.locationInWindow.y - start.locationInWindow.y)
        if !dragging, delta > 4 {
            dragging = true
            onDragBegan?(self, event)
        }
        if dragging {
            onDragged?(self, event)
        }
    }

    override func mouseUp(with event: NSEvent) {
        if dragging {
            onDragEnded?(self, event)
        } else if event.clickCount == 1 {
            onClick?(item)
        }
        dragging = false
        mouseDownEvent = nil
    }

    override func rightMouseDown(with event: NSEvent) {
        onRightClick?(item, event)
    }

    override func otherMouseDown(with event: NSEvent) {
        guard event.buttonNumber == 2 else {
            super.otherMouseDown(with: event)
            return
        }
        onMiddleClick?(item)
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .arrow)
    }

    override func layout() {
        super.layout()
        let padding: CGFloat = 8
        let showRunningMark = dotsView.count > 0
        let compact = settings.compactItems || item.isPinnedLauncher
        let icon = Self.iconLength(tileHeight: bounds.height)
        if compact {
            titleView.isHidden = true
            iconView.frame = CGRect(
                x: (bounds.width - icon) / 2,
                y: (bounds.height - icon) / 2,
                width: icon,
                height: icon
            )
            if showRunningMark {
                let band = WindowDotsView.bandHeight
                dotsView.isHidden = false
                dotsView.frame = CGRect(
                    x: iconView.frame.minX,
                    y: max(0, (iconView.frame.minY - band) / 2),
                    width: icon,
                    height: band
                )
            } else {
                dotsView.isHidden = true
            }
        } else {
            titleView.isHidden = false
            dotsView.isHidden = true
            iconView.frame = CGRect(x: padding, y: (bounds.height - icon) / 2, width: icon, height: icon)
            let x = iconView.frame.maxX + 6
            titleView.frame = CGRect(x: x, y: 0, width: max(0, bounds.width - x - padding), height: bounds.height)
        }
        let badge = Self.badgeLength(iconLength: icon)
        let badgeInset = badge * (8 / 14)
        badgeView.frame = CGRect(
            x: iconView.frame.maxX - badgeInset,
            y: iconView.frame.maxY - badgeInset,
            width: badge,
            height: badge
        )
        badgeView.isHidden = item.badge == nil
    }

    /// Icons grow with the taskbar: fill the tile minus a 6pt inset on each edge.
    static func iconLength(tileHeight: CGFloat) -> CGFloat {
        max(16, tileHeight - 12)
    }

    static func badgeLength(iconLength: CGFloat) -> CGFloat {
        max(14, (iconLength * 14 / 26).rounded())
    }

    static func displayToken(item: TaskItem, settings: AppSettings) -> Int {
        var hasher = Hasher()
        hasher.combine(item.uiKey)
        hasher.combine(settings.compactItems)
        hasher.combine(settings.fontSize)
        hasher.combine(settings.indicateMinimizedHidden)
        hasher.combine(settings.iconOnly)
        hasher.combine(settings.groupByApplication)
        hasher.combine(item.bundleID)
        return hasher.finalize()
    }

    override func draw(_ dirtyRect: NSRect) {
        let dim = settings.indicateMinimizedHidden && item.isMinimizedOrHidden
        let tile = bounds.insetBy(dx: 2, dy: 3)
        let stacked = item.windows.count > 1 && (hovered || item.isActive)
        if stacked {
            let peek: CGFloat = 6
            let radius: CGFloat = 8
            let front = CGRect(
                x: tile.minX,
                y: tile.minY,
                width: tile.width - peek,
                height: tile.height
            )
            let back = CGRect(
                x: tile.minX + peek,
                y: tile.minY,
                width: tile.width - peek,
                height: tile.height
            )
            let frontPath = NSBezierPath(roundedRect: front, xRadius: radius, yRadius: radius)
            let backPath = NSBezierPath(roundedRect: back, xRadius: radius, yRadius: radius)
            let peekRect = CGRect(x: front.maxX, y: tile.minY, width: peek, height: tile.height)
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(rect: peekRect).addClip()
            backPath.addClip()
            NSColor.labelColor.withAlphaComponent(0.18).setFill()
            backPath.fill()
            if let gradient = NSGradient(colors: [
                NSColor.black.withAlphaComponent(0.32),
                NSColor.black.withAlphaComponent(0)
            ]) {
                gradient.draw(in: peekRect, angle: 0)
            }
            NSGraphicsContext.restoreGraphicsState()
            NSColor.labelColor.withAlphaComponent(0.10).setFill()
            frontPath.fill()
        } else if hovered {
            NSColor.labelColor.withAlphaComponent(0.10).setFill()
            NSBezierPath(roundedRect: tile, xRadius: 8, yRadius: 8).fill()
        }
        alphaValue = dim ? 0.55 : 1
    }

    private func refresh() {
        iconView.image = icon()
        badgeView.text = item.badge
        if item.isPinnedLauncher || !settings.compactItems || item.windows.isEmpty {
            dotsView.count = 0
            dotsView.activeIndex = nil
        } else {
            dotsView.count = 1
            dotsView.activeIndex = item.isActive ? 0 : nil
        }
        let fontSize = CGFloat(settings.fontSize)
        let base = NSFont.systemFont(ofSize: fontSize)
        let bold = NSFont.boldSystemFont(ofSize: fontSize)
        let title = attributedTitle(base: base, bold: bold)
        titleView.attributedStringValue = title
        titleView.font = item.isActive ? bold : base
        toolTip = title.string.isEmpty ? nil : title.string
    }

    private func icon() -> NSImage? {
        switch item.kind {
        case .window(let window):
            return window.bundleID.flatMap { IconCache.icon(forBundleID: $0) }
        case .grouped(let bundleID, _, _, _):
            return bundleID.flatMap { IconCache.icon(forBundleID: $0) }
        case .pinned(_, _, let icon, _):
            return icon
        }
    }

    private func attributedTitle(base: NSFont, bold: NSFont) -> NSAttributedString {
        let color = NSColor.labelColor
        let secondary = NSColor.secondaryLabelColor
        let font = item.isActive ? bold : base
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        switch item.kind {
        case .window(let window):
            return label(
                name: window.appName,
                description: windowTitle(window),
                font: font,
                base: base,
                color: color,
                secondary: secondary,
                paragraph: paragraph
            )
        case .grouped(_, let appName, let windows, _):
            let extra = windows.count > 1 ? " (\(windows.count))" : ""
            let primary = windows.first(where: \.isActive) ?? windows.first
            return label(
                name: appName + extra,
                description: primary.flatMap(windowTitle),
                font: font,
                base: base,
                color: color,
                secondary: secondary,
                paragraph: paragraph
            )
        case .pinned(_, let name, _, _):
            return NSAttributedString(string: name, attributes: [
                .font: base,
                .foregroundColor: color,
                .paragraphStyle: paragraph
            ])
        }
    }

    private func windowTitle(_ window: WindowInfo) -> String? {
        let title = window.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, title != window.appName else { return nil }
        return title
    }

    private func label(
        name: String,
        description: String?,
        font: NSFont,
        base: NSFont,
        color: NSColor,
        secondary: NSColor,
        paragraph: NSParagraphStyle
    ) -> NSAttributedString {
        let result = NSMutableAttributedString(string: name, attributes: [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ])
        if let description {
            result.append(NSAttributedString(string: " - ", attributes: [
                .font: base,
                .foregroundColor: secondary,
                .paragraphStyle: paragraph
            ]))
            result.append(NSAttributedString(string: description, attributes: [
                .font: base,
                .foregroundColor: secondary,
                .paragraphStyle: paragraph
            ]))
        }
        return result
    }
}

private final class VerticallyCenteredTextFieldCell: NSTextFieldCell {
    override func drawingRect(forBounds rect: NSRect) -> NSRect {
        let proposed = super.drawingRect(forBounds: rect)
        let textSize = cellSize(forBounds: rect)
        let dy = (proposed.height - textSize.height) / 2
        return NSRect(x: proposed.origin.x, y: proposed.origin.y + dy, width: proposed.width, height: textSize.height)
    }
}

private final class WindowDotsView: NSView {
    static let bandHeight: CGFloat = 6

    var count: Int = 0 {
        didSet {
            if count != oldValue {
                needsDisplay = true
                isHidden = count < 1
            }
        }
    }

    var activeIndex: Int? {
        didSet {
            if activeIndex != oldValue {
                needsDisplay = true
            }
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        guard count >= 1 else { return }
        let active = activeIndex != nil
        let height: CGFloat = 3
        let width: CGFloat = bounds.width * (active ? 22 / 26 : 12 / 26)
        let rect = CGRect(
            x: (bounds.width - width) / 2,
            y: (bounds.height - height) / 2,
            width: width,
            height: height
        )
        NSColor.systemBlue.withAlphaComponent(active ? 1 : 0.55).setFill()
        NSBezierPath(roundedRect: rect, xRadius: height / 2, yRadius: height / 2).fill()
    }
}

private final class BadgeView: NSView {
    var text: String? {
        didSet { needsDisplay = true; isHidden = text == nil }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let text, !text.isEmpty else { return }
        NSColor.systemRed.setFill()
        NSBezierPath(ovalIn: bounds).fill()
        let fontSize = max(8, bounds.height * 8 / 14)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: fontSize),
            .foregroundColor: NSColor.white
        ]
        let string = NSString(string: text)
        let size = string.size(withAttributes: attrs)
        string.draw(
            at: CGPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2 - 1),
            withAttributes: attrs
        )
    }
}
