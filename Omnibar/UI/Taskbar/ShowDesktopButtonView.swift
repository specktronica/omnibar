import AppKit
import Foundation

final class ShowDesktopButtonView: NSView {
    var onClick: (() -> Void)?

    private var hovered = false
    private var pressed = false

    override var isOpaque: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        toolTip = "Show desktop"
        setAccessibilityRole(.button)
        setAccessibilityLabel("Show desktop")
    }

    required init?(coder: NSCoder) { nil }

    override func hitTest(_ point: NSPoint) -> NSView? {
        frame.contains(point) ? self : nil
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
        hovered = true
        needsDisplay = true
        NSCursor.arrow.set()
    }

    override func mouseExited(with event: NSEvent) {
        hovered = false
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        pressed = true
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        let wasPressed = pressed
        pressed = false
        needsDisplay = true
        let local = convert(event.locationInWindow, from: nil)
        if wasPressed, bounds.contains(local) {
            onClick?()
        }
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .arrow)
    }

    override func draw(_ dirtyRect: NSRect) {
        if hovered || pressed {
            NSColor.labelColor.withAlphaComponent(pressed ? 0.18 : 0.10).setFill()
            bounds.fill()
        }
        NSColor.labelColor.withAlphaComponent(hovered || pressed ? 0.55 : 0.28).setFill()
        NSRect(x: 0, y: 0, width: 1, height: bounds.height).fill()
    }
}
