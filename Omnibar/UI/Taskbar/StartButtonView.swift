import AppKit
import Foundation
import QuartzCore

final class StartButtonView: NSView {
    var onLeftClick: (() -> Void)?
    var onRightClick: ((NSEvent) -> Void)?
    private var hovered = false
    private let logoView = StartLogoView()
    private var spinGeneration = 0

    override var isOpaque: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        addSubview(logoView)
    }

    required init?(coder: NSCoder) { nil }

    func apply(_ palette: StartLogoPalette) {
        logoView.apply(palette)
    }

    /// Clockwise full turn on open, reverse on close. Continues from the live
    /// angle so a second click mid-spin reverses instead of jumping.
    func spin(opening: Bool) {
        pinLogoAnchor()
        guard let layer = logoView.layer else { return }

        let from = currentRotation(of: layer)
        let to = StartButtonSpinMotion.targetAngle(from: from, opening: opening)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.transform = CATransform3DMakeRotation(from, 0, 0, 1)
        layer.removeAnimation(forKey: "spin")
        CATransaction.commit()

        let animation = CABasicAnimation(keyPath: "transform.rotation.z")
        animation.fromValue = from
        animation.toValue = to
        animation.duration = StartButtonSpinMotion.duration(from: from, to: to)
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)

        spinGeneration += 1
        let generation = spinGeneration
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.transform = CATransform3DMakeRotation(to, 0, 0, 1)
        CATransaction.commit()

        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self] in
            Task { @MainActor in
                guard let self, self.spinGeneration == generation else { return }
                guard let layer = self.logoView.layer else { return }
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                layer.transform = CATransform3DIdentity
                CATransaction.commit()
            }
        }
        layer.add(animation, forKey: "spin")
        CATransaction.commit()
    }

    override func layout() {
        super.layout()
        if logoView.frame != bounds {
            logoView.frame = bounds
        }
        pinLogoAnchor()
    }

    // `point` is in the superview, so hit-test `frame` rather than local `bounds`.
    override func hitTest(_ point: NSPoint) -> NSView? {
        frame.contains(point) ? self : nil
    }

    // Taskbar cannot become key; without this, clicks are dropped once Omnibar is active.
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
        onLeftClick?()
    }

    override func rightMouseDown(with event: NSEvent) {
        onRightClick?(event)
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .arrow)
    }

    override func draw(_ dirtyRect: NSRect) {
        if hovered {
            NSColor.labelColor.withAlphaComponent(0.12).setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 3), xRadius: 6, yRadius: 6).fill()
        }
    }

    private func pinLogoAnchor() {
        guard let layer = logoView.layer else { return }
        let center = CGPoint(x: logoView.frame.midX, y: logoView.frame.midY)
        let midpoint = CGPoint(x: 0.5, y: 0.5)
        guard layer.anchorPoint != midpoint || layer.position != center else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.anchorPoint = midpoint
        layer.position = center
        CATransaction.commit()
    }

    private func currentRotation(of layer: CALayer) -> CGFloat {
        if let value = layer.presentation()?.value(forKeyPath: "transform.rotation.z") as? NSNumber {
            return CGFloat(truncating: value)
        }
        return atan2(layer.transform.m12, layer.transform.m11)
    }
}

private final class StartLogoView: NSView {
    private var palette: StartLogoPalette = SettingsStore.shared.settings.startLogo

    override var isOpaque: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = false
    }

    required init?(coder: NSCoder) { nil }

    func apply(_ palette: StartLogoPalette) {
        guard palette != self.palette else { return }
        self.palette = palette
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let pad: CGFloat = 6
        let side = min(bounds.width, bounds.height) - pad * 2
        guard side > 0 else { return }
        let rect = CGRect(
            x: (bounds.width - side) / 2,
            y: (bounds.height - side) / 2,
            width: side,
            height: side
        )
        StartLogoRenderer.draw(in: rect, palette: palette)
    }
}

nonisolated enum StartButtonSpinMotion: Sendable {
    static let turn = 2 * CGFloat.pi
    static let fullTurnDuration: CFTimeInterval = 0.45

    /// Next rest angle (`k * 2π`) in the open (clockwise) or close (reverse) direction.
    static func targetAngle(from: CGFloat, opening: Bool) -> CGFloat {
        let tau = turn
        if opening {
            var to = floor((from - 0.001) / tau) * tau
            if abs(to - from) < 0.01 { to -= tau }
            return to
        }
        var to = ceil((from + 0.001) / tau) * tau
        if abs(to - from) < 0.01 { to += tau }
        return to
    }

    static func duration(from: CGFloat, to: CGFloat) -> CFTimeInterval {
        max(0.18, fullTurnDuration * Double(abs(to - from) / turn))
    }
}
