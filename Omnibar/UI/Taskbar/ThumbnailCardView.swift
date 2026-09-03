import AppKit
import Foundation

final class ThumbnailCardView: NSView {
    static let chromeHeight: CGFloat = 28
    static let contentInset: CGFloat = 6

    var onHover: ((WindowInfo) -> Void)?
    var onHoverEnd: (() -> Void)?
    var onRaise: ((WindowInfo) -> Void)?
    var onClose: ((WindowInfo) -> Void)?
    var onMinimize: ((WindowInfo) -> Void)?
    var onZoom: ((WindowInfo) -> Void)?

    private(set) var windowInfo: WindowInfo?
    var windowID: CGWindowID? { windowInfo?.id }

    var optionHeld = false {
        didSet { trafficLights.optionHeld = optionHeld }
    }

    private let imageView = PassthroughImageView()
    private let fallbackIcon = PassthroughImageView()
    private let titleField = PassthroughTextField(labelWithString: "")
    private let trafficLights = TrafficLightsView()
    private let separator = ChromeSeparator()

    static func preferredSize(for size: CGFloat) -> NSSize {
        let imageWidth = max(1, size - contentInset * 2)
        let imageHeight = imageWidth * (9.0 / 16.0)
        return NSSize(width: size, height: imageHeight + chromeHeight + contentInset)
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.masksToBounds = true
        imageView.imageScaling = .scaleProportionallyUpOrDown
        fallbackIcon.imageScaling = .scaleProportionallyUpOrDown
        titleField.lineBreakMode = .byTruncatingTail
        titleField.alignment = .center
        titleField.font = .systemFont(ofSize: 11)
        addSubview(imageView)
        addSubview(fallbackIcon)
        addSubview(separator)
        addSubview(titleField)
        addSubview(trafficLights)
        trafficLights.onClose = { [weak self] in
            guard let self, let window = self.windowInfo else { return }
            self.onClose?(window)
        }
        trafficLights.onMinimize = { [weak self] in
            guard let self, let window = self.windowInfo else { return }
            self.onMinimize?(window)
        }
        trafficLights.onZoom = { [weak self] in
            guard let self, let window = self.windowInfo else { return }
            self.onZoom?(window)
        }
    }

    required init?(coder: NSCoder) { nil }

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
        if let windowInfo {
            onHover?(windowInfo)
        }
        _ = event
    }

    override func mouseExited(with event: NSEvent) {
        if let window {
            let screenRect = window.convertToScreen(convert(bounds, to: nil))
            if screenRect.contains(NSEvent.mouseLocation) { return }
        }
        onHoverEnd?()
        _ = event
    }

    override func mouseDown(with event: NSEvent) {
        if let windowInfo {
            onRaise?(windowInfo)
        }
        _ = event
    }

    override func otherMouseDown(with event: NSEvent) {
        guard event.buttonNumber == 2 else {
            super.otherMouseDown(with: event)
            return
        }
        handleMiddleClick()
    }

    func handleMiddleClick() {
        if let windowInfo {
            onClose?(windowInfo)
        }
    }

    func configure(window: WindowInfo, item: TaskItem, size _: CGFloat, showTitle: Bool) {
        windowInfo = window
        titleField.isHidden = !showTitle
        titleField.stringValue = window.displayTitle
        trafficLights.isFullscreen = window.isFullscreen
        trafficLights.optionHeld = optionHeld
        fallbackIcon.image = item.bundleID.flatMap { IconCache.icon(forBundleID: $0) }
        if let cached = ThumbnailService.shared.cached(windowID: window.id) {
            imageView.image = cached
            imageView.isHidden = false
            fallbackIcon.isHidden = true
        } else {
            imageView.image = nil
            imageView.isHidden = true
            fallbackIcon.isHidden = false
        }
        needsLayout = true
    }

    func update(image: NSImage) {
        imageView.image = image
        imageView.isHidden = false
        fallbackIcon.isHidden = true
    }

    override func layout() {
        super.layout()
        let chrome = Self.chromeHeight
        let inset = Self.contentInset
        let width = bounds.width
        let height = bounds.height
        let lightsSize = TrafficLightsView.fittingSize
        let lightsY = height - chrome + (chrome - lightsSize.height) / 2
        trafficLights.frame = NSRect(x: 10, y: lightsY, width: lightsSize.width, height: lightsSize.height)
        separator.frame = NSRect(x: 0, y: height - chrome, width: width, height: 1)
        let titleX = trafficLights.frame.maxX + 6
        titleField.frame = NSRect(x: titleX, y: height - chrome, width: max(0, width - titleX - 10), height: chrome)
        let imageFrame = NSRect(x: inset, y: inset, width: max(0, width - inset * 2), height: max(0, height - chrome - inset))
        imageView.frame = imageFrame
        fallbackIcon.frame = NSRect(
            x: imageFrame.midX - 24,
            y: imageFrame.midY - 24,
            width: 48,
            height: 48
        )
    }
}

private final class PassthroughImageView: NSImageView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

private final class PassthroughTextField: NSTextField {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

private final class ChromeSeparator: NSView {
    override func draw(_ dirtyRect: NSRect) {
        NSColor.separatorColor.withAlphaComponent(0.45).setFill()
        bounds.fill()
    }
}

final class TrafficLightsView: NSView {
    static let buttonDiameter: CGFloat = 12
    static let buttonSpacing: CGFloat = 8
    static var fittingSize: NSSize {
        NSSize(
            width: buttonDiameter * 3 + buttonSpacing * 2,
            height: buttonDiameter + 4
        )
    }

    var onClose: (() -> Void)?
    var onMinimize: (() -> Void)?
    var onZoom: (() -> Void)?

    var optionHeld = false {
        didSet { if optionHeld != oldValue { needsDisplay = true; refreshAccessibility() } }
    }
    var isFullscreen = false {
        didSet { if isFullscreen != oldValue { needsDisplay = true; refreshAccessibility() } }
    }

    private var clusterHovered = false
    private var highlighted: Kind?
    private var pressed: Kind?

    private enum Kind: CaseIterable {
        case close, minimize, zoom
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("Window controls")
    }

    required init?(coder: NSCoder) { nil }

    override var isFlipped: Bool { false }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        ))
        removeAllToolTips()
        for kind in Kind.allCases {
            addToolTip(rect(for: kind).insetBy(dx: -3, dy: -3), owner: self, userData: nil)
        }
    }

    @objc func view(_ view: NSView, stringForToolTip tag: NSView.ToolTipTag, point: NSPoint, userData data: UnsafeMutableRawPointer?) -> String {
        switch kind(at: point) ?? highlighted {
        case .close: "Close"
        case .minimize: "Minimize"
        case .zoom:
            if isFullscreen { "Exit Full Screen" }
            else if optionHeld { "Full Screen" }
            else { "Zoom" }
        case nil: ""
        }
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }

    override func mouseEntered(with event: NSEvent) {
        clusterHovered = true
        highlighted = kind(at: convert(event.locationInWindow, from: nil))
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        clusterHovered = false
        highlighted = nil
        pressed = nil
        needsDisplay = true
        _ = event
    }

    override func mouseMoved(with event: NSEvent) {
        let next = kind(at: convert(event.locationInWindow, from: nil))
        if next != highlighted {
            highlighted = next
            needsDisplay = true
        }
    }

    override func mouseDown(with event: NSEvent) {
        pressed = kind(at: convert(event.locationInWindow, from: nil))
        needsDisplay = true
    }

    override func otherMouseDown(with event: NSEvent) {
        nextResponder?.otherMouseDown(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        let kind = kind(at: convert(event.locationInWindow, from: nil))
        if kind != nil, kind == pressed {
            switch kind {
            case .close: onClose?()
            case .minimize: onMinimize?()
            case .zoom: onZoom?()
            case nil: break
            }
        }
        pressed = nil
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        for kind in Kind.allCases {
            drawButton(kind, in: rect(for: kind))
        }
    }

    override func accessibilityRole() -> NSAccessibility.Role? { .group }

    override func isAccessibilityElement() -> Bool { true }

    override func accessibilityLabel() -> String? { "Window controls" }

    private func refreshAccessibility() {
        setAccessibilityHelp(zoomHelp)
    }

    private var zoomHelp: String {
        if isFullscreen { return "Close, Minimize, Exit Full Screen" }
        if optionHeld { return "Close, Minimize, Full Screen" }
        return "Close, Minimize, Zoom"
    }

    private func rect(for kind: Kind) -> CGRect {
        let diameter = Self.buttonDiameter
        let y = (bounds.height - diameter) / 2
        let index: CGFloat
        switch kind {
        case .close: index = 0
        case .minimize: index = 1
        case .zoom: index = 2
        }
        let x = index * (diameter + Self.buttonSpacing)
        return CGRect(x: x, y: y, width: diameter, height: diameter)
    }

    private func kind(at point: NSPoint) -> Kind? {
        Kind.allCases.first { rect(for: $0).insetBy(dx: -3, dy: -3).contains(point) }
    }

    private func drawButton(_ kind: Kind, in rect: CGRect) {
        let fill: NSColor
        let stroke: NSColor
        let glyph: NSColor
        switch kind {
        case .close:
            fill = NSColor(srgbRed: 1, green: 0.373, blue: 0.341, alpha: 1)
            stroke = NSColor(srgbRed: 0.839, green: 0.212, blue: 0.184, alpha: 1)
            glyph = NSColor(srgbRed: 0.302, green: 0.024, blue: 0.024, alpha: 0.9)
        case .minimize:
            fill = NSColor(srgbRed: 1, green: 0.741, blue: 0.180, alpha: 1)
            stroke = NSColor(srgbRed: 0.875, green: 0.608, blue: 0.106, alpha: 1)
            glyph = NSColor(srgbRed: 0.545, green: 0.322, blue: 0.004, alpha: 0.9)
        case .zoom:
            fill = NSColor(srgbRed: 0.157, green: 0.784, blue: 0.251, alpha: 1)
            stroke = NSColor(srgbRed: 0.149, green: 0.682, blue: 0.220, alpha: 1)
            glyph = NSColor(srgbRed: 0.004, green: 0.384, blue: 0.067, alpha: 0.9)
        }

        let circle = NSBezierPath(ovalIn: rect)
        fill.setFill()
        circle.fill()
        if highlighted == kind || pressed == kind {
            NSColor.black.withAlphaComponent(pressed == kind ? 0.18 : 0.08).setFill()
            circle.fill()
        }
        stroke.setStroke()
        circle.lineWidth = 0.5
        circle.stroke()

        guard clusterHovered else { return }
        glyph.setStroke()
        glyph.setFill()
        switch kind {
        case .close:
            drawCloseGlyph(in: rect)
        case .minimize:
            drawMinimizeGlyph(in: rect)
        case .zoom:
            if optionHeld || isFullscreen {
                drawFullscreenGlyph(in: rect, exit: isFullscreen && !optionHeld)
            } else {
                drawZoomGlyph(in: rect)
            }
        }
    }

    private func drawCloseGlyph(in rect: CGRect) {
        let inset = rect.width * 0.28
        let path = NSBezierPath()
        path.move(to: CGPoint(x: rect.minX + inset, y: rect.minY + inset))
        path.line(to: CGPoint(x: rect.maxX - inset, y: rect.maxY - inset))
        path.move(to: CGPoint(x: rect.maxX - inset, y: rect.minY + inset))
        path.line(to: CGPoint(x: rect.minX + inset, y: rect.maxY - inset))
        path.lineWidth = 1
        path.lineCapStyle = .round
        path.stroke()
    }

    private func drawMinimizeGlyph(in rect: CGRect) {
        let inset = rect.width * 0.25
        let path = NSBezierPath()
        path.move(to: CGPoint(x: rect.minX + inset, y: rect.midY))
        path.line(to: CGPoint(x: rect.maxX - inset, y: rect.midY))
        path.lineWidth = 1
        path.lineCapStyle = .round
        path.stroke()
    }

    private func drawZoomGlyph(in rect: CGRect) {
        let inset = rect.width * 0.25
        let path = NSBezierPath()
        path.move(to: CGPoint(x: rect.minX + inset, y: rect.midY))
        path.line(to: CGPoint(x: rect.maxX - inset, y: rect.midY))
        path.move(to: CGPoint(x: rect.midX, y: rect.minY + inset))
        path.line(to: CGPoint(x: rect.midX, y: rect.maxY - inset))
        path.lineWidth = 1
        path.lineCapStyle = .round
        path.stroke()
    }

    private func drawFullscreenGlyph(in rect: CGRect, exit: Bool) {
        let inset = rect.width * 0.22
        let arm = rect.width * 0.22
        let path = NSBezierPath()
        path.lineWidth = 1
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        if exit {
            addCornerArrow(path, tip: CGPoint(x: rect.midX - 0.5, y: rect.midY + 0.5), outward: CGPoint(x: -1, y: 1), arm: arm)
            addCornerArrow(path, tip: CGPoint(x: rect.midX + 0.5, y: rect.midY - 0.5), outward: CGPoint(x: 1, y: -1), arm: arm)
        } else {
            addCornerArrow(path, tip: CGPoint(x: rect.minX + inset, y: rect.maxY - inset), outward: CGPoint(x: -1, y: 1), arm: arm)
            addCornerArrow(path, tip: CGPoint(x: rect.maxX - inset, y: rect.minY + inset), outward: CGPoint(x: 1, y: -1), arm: arm)
        }
        path.stroke()
    }

    private func addCornerArrow(_ path: NSBezierPath, tip: CGPoint, outward: CGPoint, arm: CGFloat) {
        path.move(to: CGPoint(x: tip.x - outward.x * arm, y: tip.y))
        path.line(to: tip)
        path.line(to: CGPoint(x: tip.x, y: tip.y - outward.y * arm))
    }
}
