import AppKit
import Foundation

/// Translucent outline of the tile a dragged window will snap to.
final class SnapPreviewPanel: NSPanel {
    private let fill = NSView()

    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        hidesOnDeactivate = false
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle, .fullScreenNone]
        animationBehavior = .none

        fill.wantsLayer = true
        fill.layer?.cornerRadius = 10
        fill.layer?.cornerCurve = .continuous
        fill.layer?.borderWidth = 2
        fill.autoresizingMask = [.width, .height]
        contentView = fill
        applyColors()
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Shows the preview at `frame` (Cocoa screen coordinates). Moves are
    /// animated when the panel is already visible.
    func show(frame: NSRect) {
        applyColors()
        if isVisible {
            guard self.frame != frame else { return }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.12
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                animator().setFrame(frame, display: true)
            }
        } else {
            setFrame(frame, display: false)
            orderFrontRegardless()
        }
    }

    func hide() {
        guard isVisible else { return }
        orderOut(nil)
    }

    private func applyColors() {
        let accent = NSColor.controlAccentColor
        fill.layer?.backgroundColor = accent.withAlphaComponent(0.18).cgColor
        fill.layer?.borderColor = accent.withAlphaComponent(0.9).cgColor
    }
}
