import AppKit
import Foundation

final class TaskItemView: NSView {
    private(set) var item: TaskItem
    var onClick: ((TaskItem) -> Void)?
    var onRightClick: ((TaskItem, NSEvent) -> Void)?
    var onHover: ((TaskItem) -> Void)?
    var onHoverEnd: (() -> Void)?
    var onDragBegan: ((TaskItemView, NSEvent) -> Void)?
    var onDragged: ((TaskItemView, NSEvent) -> Void)?
    var onDragEnded: ((TaskItemView, NSEvent) -> Void)?

    private let iconView = NSImageView()
    private let badgeView = BadgeView()
    private let titleView = NSTextField(labelWithString: "")
    private var hovered = false
    private var mouseDownEvent: NSEvent?
    private var dragging = false
    private var settings: AppSettings

    init(item: TaskItem, settings: AppSettings) {
        self.item = item
        self.settings = settings
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 8
        iconView.imageScaling = .scaleProportionallyUpOrDown
        titleView.lineBreakMode = .byTruncatingTail
        titleView.maximumNumberOfLines = 1
        titleView.isSelectable = false
        addSubview(iconView)
        addSubview(titleView)
        addSubview(badgeView)
        refresh()
    }

    required init?(coder: NSCoder) { nil }

    func apply(item: TaskItem, settings: AppSettings) {
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

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .arrow)
    }

    override func layout() {
        super.layout()
        let icon = max(16, min(bounds.height - 10, 28))
        let padding: CGFloat = 8
        iconView.frame = CGRect(x: padding, y: (bounds.height - icon) / 2, width: icon, height: icon)
        badgeView.frame = CGRect(x: iconView.frame.maxX - 8, y: iconView.frame.maxY - 8, width: 14, height: 14)
        if settings.iconOnly || item.isPinnedLauncher {
            titleView.isHidden = true
        } else {
            titleView.isHidden = false
            let x = iconView.frame.maxX + 6
            titleView.frame = CGRect(x: x, y: 0, width: max(0, bounds.width - x - padding), height: bounds.height)
        }
        badgeView.isHidden = item.badge == nil
    }

    override func draw(_ dirtyRect: NSRect) {
        let active = item.isActive
        let dim = settings.indicateMinimizedHidden && item.isMinimizedOrHidden
        if active {
            NSColor.controlBackgroundColor.withAlphaComponent(0.95).setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 3), xRadius: 8, yRadius: 8).fill()
        } else if hovered {
            NSColor.labelColor.withAlphaComponent(0.10).setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 3), xRadius: 8, yRadius: 8).fill()
        }
        alphaValue = dim ? 0.55 : 1
    }

    private func refresh() {
        iconView.image = icon()
        badgeView.text = item.badge
        let fontSize = CGFloat(settings.fontSize)
        let base = NSFont.systemFont(ofSize: fontSize)
        let bold = NSFont.boldSystemFont(ofSize: fontSize)
        titleView.attributedStringValue = attributedTitle(base: base, bold: bold)
        titleView.font = item.isActive ? bold : base
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
        switch item.kind {
        case .window(let window):
            return Self.windowTitle(window, settings: settings, base: base, bold: bold, color: color)
        case .grouped(_, let appName, let windows, _):
            let extra = windows.count > 1 ? " (\(windows.count))" : ""
            return NSAttributedString(string: appName + extra, attributes: [
                .font: item.isActive ? bold : base,
                .foregroundColor: color
            ])
        case .pinned(_, let name, _, _):
            return NSAttributedString(string: name, attributes: [.font: base, .foregroundColor: color])
        }
    }

    static func windowTitle(
        _ window: WindowInfo,
        settings: AppSettings,
        base: NSFont,
        bold: NSFont,
        color: NSColor
    ) -> NSAttributedString {
        let title = settings.indicateMinimizedHidden ? window.indicatedTitle : window.displayTitle
        let result = NSMutableAttributedString()
        result.append(NSAttributedString(string: title, attributes: [
            .font: window.isActive ? bold : base,
            .foregroundColor: color
        ]))
        if window.displayTitle != window.appName {
            result.append(NSAttributedString(string: " - ", attributes: [.font: base, .foregroundColor: color]))
            result.append(NSAttributedString(string: window.appName, attributes: [
                .font: bold,
                .foregroundColor: color
            ]))
        }
        return result
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
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: 8),
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
