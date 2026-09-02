import AppKit
import Foundation

final class ThumbnailPopover: NSPanel {
    private static let maxVisibleCards = 3
    private static let cardGap: CGFloat = 8

    private let effect = ThumbnailRootView()
    private let cards: [ThumbnailCardView] = (0..<maxVisibleCards).map { _ in ThumbnailCardView() }
    private let reel = ReelOverlayView()
    private var tracking: NSTrackingArea?
    private var flagsMonitor: Any?
    private var globalFlagsMonitor: Any?
    private(set) var isHovered = false
    private var windows: [WindowInfo] = []
    private var item: TaskItem?
    private var offset = 0
    private var thumbnailSize: CGFloat = 240
    private var refreshTask: Task<Void, Never>?
    private var hoverFocusWork: DispatchWorkItem?
    private var hoverFocusedWindowID: CGWindowID?

    private var visibleCount: Int { min(Self.maxVisibleCards, windows.count) }

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 240, height: 160),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        isFloatingPanel = true
        // Stay above the taskbar, but below NSMenu so the item context menu is not covered.
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.popUpMenuWindow)) - 1)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        effect.material = .popover
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 10
        effect.layer?.masksToBounds = true
        contentView = effect
        for card in cards {
            effect.addSubview(card)
            card.onHover = { [weak self] window in
                self?.focusHoveredPreview(window)
            }
            card.onRaise = { [weak self] window in
                WindowActions.raise(window)
                self?.dismiss()
            }
            card.onClose = { [weak self] window in
                WindowActions.close(window)
                self?.dismiss()
            }
            card.onMinimize = { [weak self] window in
                WindowActions.minimize(window)
                self?.dismiss()
            }
            card.onZoom = { [weak self] window in
                if NSEvent.modifierFlags.contains(.option) || window.isFullscreen {
                    WindowActions.fullscreen(window)
                } else {
                    WindowActions.zoom(window)
                }
                self?.dismiss()
            }
        }
        reel.onPage = { [weak self] delta in
            self?.page(by: delta)
        }
        effect.addSubview(reel)
    }

    override var canBecomeKey: Bool { false }

    func present(item: TaskItem, anchor: NSRect) {
        guard !item.windows.isEmpty else { return }
        hoverFocusWork?.cancel()
        hoverFocusWork = nil
        hoverFocusedWindowID = item.windows.first(where: \.isActive)?.id
        self.item = item
        windows = item.windows
        let visible = visibleCount
        let activeIndex = windows.firstIndex(where: \.isActive) ?? 0
        let maxOffset = max(0, windows.count - visible)
        if activeIndex >= visible {
            offset = min(activeIndex - visible + 1, maxOffset)
        } else {
            offset = 0
        }

        let settings = SettingsStore.shared.settings
        thumbnailSize = CGFloat(settings.thumbnailSize)
        let cardSize = ThumbnailCardView.preferredSize(for: thumbnailSize)
        let inset = ThumbnailCardView.contentInset
        let width = inset + CGFloat(visible) * cardSize.width + CGFloat(max(0, visible - 1)) * Self.cardGap + inset
        let height = cardSize.height + inset * 2
        var frame = NSRect(
            x: anchor.midX - width / 2,
            y: anchor.maxY + 8,
            width: width,
            height: height
        )
        if let screen = NSScreen.screens.first(where: { $0.frame.intersects(anchor) }) ?? NSScreen.main {
            if frame.maxX > screen.visibleFrame.maxX {
                frame.origin.x = screen.visibleFrame.maxX - width - 8
            }
            if frame.minX < screen.visibleFrame.minX {
                frame.origin.x = screen.visibleFrame.minX + 8
            }
        }
        setFrame(frame, display: true)
        layoutCards()
        reel.setVisible(false)
        installTracking()
        installFlagsMonitor()
        orderFrontRegardless()
        startRefresh()
    }

    func dismiss() {
        hoverFocusWork?.cancel()
        hoverFocusWork = nil
        hoverFocusedWindowID = nil
        refreshTask?.cancel()
        refreshTask = nil
        isHovered = false
        reel.setVisible(false)
        removeFlagsMonitor()
        orderOut(nil)
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        reel.setVisible(windows.count > 3)
    }

    override func mouseExited(with event: NSEvent) {
        // Nested tracking areas on the traffic lights can send a false exit.
        guard !frame.contains(NSEvent.mouseLocation) else { return }
        isHovered = false
        reel.setVisible(false)
        dismiss()
    }

    private func focusHoveredPreview(_ window: WindowInfo) {
        guard window.id != hoverFocusedWindowID else { return }
        hoverFocusWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.isVisible else { return }
            WindowActions.raise(window)
            self.hoverFocusedWindowID = window.id
            self.orderFrontRegardless()
        }
        hoverFocusWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: work)
    }

    private func page(by delta: Int) {
        let maxOffset = max(0, windows.count - visibleCount)
        let next = min(max(0, offset + delta), maxOffset)
        guard next != offset else { return }
        hoverFocusWork?.cancel()
        hoverFocusWork = nil
        offset = next
        layoutCards()
        startRefresh()
    }

    private func layoutCards() {
        guard let item else { return }
        let settings = SettingsStore.shared.settings
        let cardSize = ThumbnailCardView.preferredSize(for: thumbnailSize)
        let inset = ThumbnailCardView.contentInset
        let visible = visibleCount
        let showTitle = settings.showTitleInThumbnail
        let option = NSEvent.modifierFlags.contains(.option)
        for index in 0..<cards.count {
            let card = cards[index]
            if index < visible {
                let window = windows[offset + index]
                card.isHidden = false
                card.optionHeld = option
                card.frame = NSRect(
                    x: inset + CGFloat(index) * (cardSize.width + Self.cardGap),
                    y: inset,
                    width: cardSize.width,
                    height: cardSize.height
                )
                card.configure(window: window, item: item, size: thumbnailSize, showTitle: showTitle)
            } else {
                card.isHidden = true
            }
        }
        reel.frame = effect.bounds
        reel.update(windowCount: windows.count, offset: offset, visibleCount: visible)
    }

    private func startRefresh() {
        refreshTask?.cancel()
        let size = thumbnailSize
        let windowIDs = Array(windows[offset..<(offset + visibleCount)].map(\.id))
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                for (index, windowID) in windowIDs.enumerated() {
                    let image = await ThumbnailService.shared.capture(windowID: windowID, maxSize: size)
                    await MainActor.run {
                        guard let self, index < self.cards.count, self.cards[index].windowID == windowID else { return }
                        if let image {
                            self.cards[index].update(image: image)
                        }
                    }
                }
                try? await Task.sleep(for: .milliseconds(400))
            }
        }
    }

    private func installTracking() {
        if let tracking { contentView?.removeTrackingArea(tracking) }
        let area = NSTrackingArea(
            rect: contentView?.bounds ?? .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        contentView?.addTrackingArea(area)
        tracking = area
    }

    private func installFlagsMonitor() {
        removeFlagsMonitor()
        flagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.applyOptionHeld(event.modifierFlags.contains(.option))
            return event
        }
        globalFlagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            let option = event.modifierFlags.contains(.option)
            Task { @MainActor in
                self?.applyOptionHeld(option)
            }
        }
    }

    private func applyOptionHeld(_ option: Bool) {
        for card in cards {
            card.optionHeld = option
        }
    }

    private func removeFlagsMonitor() {
        if let flagsMonitor {
            NSEvent.removeMonitor(flagsMonitor)
            self.flagsMonitor = nil
        }
        if let globalFlagsMonitor {
            NSEvent.removeMonitor(globalFlagsMonitor)
            self.globalFlagsMonitor = nil
        }
    }
}

private final class ThumbnailRootView: NSVisualEffectView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

private final class ReelOverlayView: NSView {
    var onPage: ((Int) -> Void)?

    private let leftButton = ReelArrowButton(symbolName: "arrowtriangle.left.fill")
    private let rightButton = ReelArrowButton(symbolName: "arrowtriangle.right.fill")
    private var windowCount = 0
    private var offset = 0
    private var visibleCount = 0
    private var pagingEnabled = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        alphaValue = 0
        leftButton.onClick = { [weak self] in self?.onPage?(-1) }
        rightButton.onClick = { [weak self] in self?.onPage?(1) }
        addSubview(leftButton)
        addSubview(rightButton)
    }

    required init?(coder: NSCoder) { nil }

    func update(windowCount: Int, offset: Int, visibleCount: Int) {
        self.windowCount = windowCount
        self.offset = offset
        self.visibleCount = visibleCount
        let canPage = windowCount > 3
        leftButton.isEnabled = canPage && offset > 0
        rightButton.isEnabled = canPage && offset < max(0, windowCount - visibleCount)
        if !canPage {
            setVisible(false)
        }
        needsLayout = true
    }

    func setVisible(_ visible: Bool) {
        let show = visible && windowCount > 3
        pagingEnabled = show
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            animator().alphaValue = show ? 1 : 0
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard pagingEnabled, windowCount > 3 else { return nil }
        if leftButton.frame.contains(point) { return leftButton }
        if rightButton.frame.contains(point) { return rightButton }
        return nil
    }

    override func layout() {
        super.layout()
        let size = ReelArrowButton.diameter
        let inset: CGFloat = 8
        let y = (bounds.height - size) / 2
        leftButton.frame = NSRect(x: inset, y: y, width: size, height: size)
        rightButton.frame = NSRect(x: bounds.width - inset - size, y: y, width: size, height: size)
    }
}

private final class ReelArrowButton: NSView {
    static let diameter: CGFloat = 28

    var onClick: (() -> Void)?
    var isEnabled = true {
        didSet {
            if isEnabled != oldValue {
                alphaValue = isEnabled ? 1 : 0.35
                needsDisplay = true
            }
        }
    }

    private let iconView = NSImageView()
    private var hovered = false
    private var pressed = false

    init(symbolName: String) {
        super.init(frame: .zero)
        wantsLayer = true
        iconView.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)
        iconView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 11, weight: .bold)
        iconView.contentTintColor = .white
        iconView.imageScaling = .scaleProportionallyUpOrDown
        addSubview(iconView)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(symbolName.contains("left") ? "Previous windows" : "Next windows")
    }

    required init?(coder: NSCoder) { nil }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(point) ? self : nil
    }

    override func layout() {
        super.layout()
        iconView.frame = bounds.insetBy(dx: 6, dy: 6)
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

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }

    override func mouseEntered(with event: NSEvent) {
        hovered = true
        needsDisplay = true
        _ = event
    }

    override func mouseExited(with event: NSEvent) {
        hovered = false
        pressed = false
        needsDisplay = true
        _ = event
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        pressed = true
        needsDisplay = true
        _ = event
    }

    override func mouseUp(with event: NSEvent) {
        let inside = bounds.contains(convert(event.locationInWindow, from: nil))
        if isEnabled, pressed, inside {
            onClick?()
        }
        pressed = false
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let fill = NSColor.black.withAlphaComponent(pressed ? 0.62 : (hovered ? 0.52 : 0.42))
        fill.setFill()
        NSBezierPath(ovalIn: bounds).fill()
    }
}
