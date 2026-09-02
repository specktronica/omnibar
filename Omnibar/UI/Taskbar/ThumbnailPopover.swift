import AppKit
import Foundation

final class ThumbnailPopover: NSPanel {
    private let effect = NSVisualEffectView()
    private let imageView = NSImageView()
    private let titleField = NSTextField(labelWithString: "")
    private let fallbackIcon = NSImageView()
    private var tracking: NSTrackingArea?
    private(set) var isHovered = false
    private var currentWindow: WindowInfo?
    private var refreshTask: Task<Void, Never>?

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
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.popUpMenuWindow)))
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        effect.material = .popover
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 10
        contentView = effect
        imageView.imageScaling = .scaleProportionallyUpOrDown
        fallbackIcon.imageScaling = .scaleProportionallyUpOrDown
        titleField.lineBreakMode = .byTruncatingTail
        titleField.alignment = .center
        effect.addSubview(imageView)
        effect.addSubview(fallbackIcon)
        effect.addSubview(titleField)
    }

    override var canBecomeKey: Bool { false }

    func present(window: WindowInfo, item: TaskItem, anchor: NSRect) {
        currentWindow = window
        let settings = SettingsStore.shared.settings
        let size = CGFloat(settings.thumbnailSize)
        let titleHeight: CGFloat = settings.showTitleInThumbnail ? 22 : 0
        let height = size * 0.66 + titleHeight + 16
        let width = size
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
        titleField.isHidden = !settings.showTitleInThumbnail
        titleField.stringValue = window.displayTitle
        titleField.frame = NSRect(x: 8, y: height - titleHeight - 4, width: width - 16, height: titleHeight)
        imageView.frame = NSRect(x: 8, y: 8, width: width - 16, height: height - 16 - titleHeight)
        fallbackIcon.frame = NSRect(x: (width - 48) / 2, y: (height - 48) / 2, width: 48, height: 48)
        fallbackIcon.image = item.bundleID.flatMap { IconCache.icon(forBundleID: $0) }
        if let cached = ThumbnailService.shared.cached(windowID: window.id) {
            imageView.image = cached
            imageView.isHidden = false
            fallbackIcon.isHidden = true
        } else {
            imageView.isHidden = true
            fallbackIcon.isHidden = false
        }
        installTracking()
        orderFrontRegardless()
        refreshTask?.cancel()
        let windowID = window.id
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                let image = await ThumbnailService.shared.capture(windowID: windowID, maxSize: size)
                await MainActor.run {
                    if let image {
                        self?.imageView.image = image
                        self?.imageView.isHidden = false
                        self?.fallbackIcon.isHidden = true
                    }
                }
                try? await Task.sleep(for: .milliseconds(400))
            }
        }
    }

    func dismiss() {
        refreshTask?.cancel()
        refreshTask = nil
        isHovered = false
        orderOut(nil)
    }

    override func mouseDown(with event: NSEvent) {
        if let window = currentWindow {
            WindowActions.raise(window)
        }
        dismiss()
        _ = event
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        dismiss()
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
}
