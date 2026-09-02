import AppKit
import Foundation

final class StartButtonView: NSView {
    var onLeftClick: (() -> Void)?
    var onRightClick: ((NSEvent) -> Void)?
    private var hovered = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { nil }

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
    }

    override func mouseExited(with event: NSEvent) {
        hovered = false
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        onLeftClick?()
    }

    override func rightMouseDown(with event: NSEvent) {
        onRightClick?(event)
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .arrow)
    }

    override func draw(_ dirtyRect: NSRect) {
        let pad: CGFloat = 4
        if hovered {
            NSColor.labelColor.withAlphaComponent(0.12).setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 3), xRadius: 6, yRadius: 6).fill()
        }
        let grid = bounds.insetBy(dx: pad + 3, dy: pad + 3)
        let gap: CGFloat = 2
        let cell = min((grid.width - gap) / 2, (grid.height - gap) / 2)
        let colors: [NSColor] = [
            NSColor(srgbRed: 0.20, green: 0.48, blue: 0.96, alpha: 1),
            NSColor(srgbRed: 0.20, green: 0.78, blue: 0.35, alpha: 1),
            NSColor(srgbRed: 1.00, green: 0.80, blue: 0.00, alpha: 1),
            NSColor(srgbRed: 1.00, green: 0.27, blue: 0.23, alpha: 1)
        ]
        let originX = grid.midX - cell - gap / 2
        let originY = grid.midY - cell - gap / 2
        let positions = [
            CGPoint(x: originX, y: originY + cell + gap),
            CGPoint(x: originX + cell + gap, y: originY + cell + gap),
            CGPoint(x: originX, y: originY),
            CGPoint(x: originX + cell + gap, y: originY)
        ]
        for (color, point) in zip(colors, positions) {
            color.setFill()
            NSBezierPath(roundedRect: CGRect(origin: point, size: CGSize(width: cell, height: cell)), xRadius: 2, yRadius: 2).fill()
        }
    }
}
