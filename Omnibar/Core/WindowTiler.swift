import AppKit
import ApplicationServices
import Foundation

/// Applies tiles to windows through Accessibility and remembers the last tile
/// per window so keyboard presses can cycle even when the app clamps its size.
final class WindowTiler {
    static let shared = WindowTiler()

    private var memory: [CGWindowID: AppliedTile] = [:]
    private var snapshotObserver: NSObjectProtocol?

    init() {
        snapshotObserver = NotificationCenter.default.addObserver(
            forName: .omnibarSnapshotDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.pruneMemory()
            }
        }
    }

    /// Tiles the focused window of the frontmost app. Omnibar's own windows,
    /// dialogs, sheets, fullscreen and minimized windows, and windows whose
    /// frame is not settable are ignored.
    func tileFocusedWindow(_ direction: TileDirection) {
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              let window = AXBridge.focusedWindow(forApp: app.processIdentifier),
              Self.isTileable(window),
              let cgFrame = AXBridge.frame(of: window),
              let screen = Self.screen(containingCGRect: cgFrame) else {
            return
        }
        let usable = usableFrame(on: screen)
        let current = ScreenGeometry.cocoaRect(fromCGRect: cgFrame)
        let windowID = AXBridge.cgWindowID(for: window)
        let remembered = windowID.flatMap { memory[$0] }
        let tile = TilingGeometry.nextTile(
            direction: direction,
            currentFrame: current,
            usable: usable,
            remembered: remembered
        )
        apply(tile, to: window, windowID: windowID, on: screen)
    }

    /// Moves `window` onto `tile` within the usable area of `screen`. Returns
    /// the frame the app reports afterwards, in Cocoa coordinates.
    @discardableResult
    func apply(_ tile: Tile, to window: AXUIElement, windowID: CGWindowID?, on screen: NSScreen) -> CGRect? {
        let target = tile.frame(in: usableFrame(on: screen))
        let cgTarget = TilingGeometry.cgRect(
            fromCocoaRect: target,
            primaryHeight: ScreenGeometry.cocoaPrimaryHeight
        )
        guard let observed = AXBridge.setFrame(window, cgFrame: cgTarget) else { return nil }
        let observedCocoa = ScreenGeometry.cocoaRect(fromCGRect: observed)
        if let windowID {
            memory[windowID] = AppliedTile(tile: tile, frame: observedCocoa)
        }
        return observedCocoa
    }

    /// Usable area on `screen` in Cocoa coordinates: the visible frame with
    /// the Taskbar strip removed when Omnibar shows a bar there.
    func usableFrame(on screen: NSScreen) -> CGRect {
        let settings = SettingsStore.shared.settings
        return TilingGeometry.usableFrame(
            screenFrame: screen.frame,
            visibleFrame: screen.visibleFrame,
            taskbarHeight: CGFloat(settings.taskbarHeight),
            taskbarPresent: ScreenMonitor.shared.showsTaskbar(on: screen.displayID)
        )
    }

    static func isTileable(_ window: AXUIElement) -> Bool {
        AXBridge.role(of: window) == (kAXWindowRole as String)
            && AXBridge.subrole(of: window) == (kAXStandardWindowSubrole as String)
            && !AXBridge.isFullscreen(window)
            && !AXBridge.isMinimized(window)
            && AXBridge.isSettable(window, attribute: kAXPositionAttribute as String)
            && AXBridge.isSettable(window, attribute: kAXSizeAttribute as String)
    }

    static func screen(containingCGRect rect: CGRect) -> NSScreen? {
        if let id = ScreenGeometry.displayID(containingCGRect: rect),
           let screen = NSScreen.screens.first(where: { $0.displayID == id }) {
            return screen
        }
        return NSScreen.main ?? NSScreen.screens.first
    }

    private func pruneMemory() {
        guard !memory.isEmpty else { return }
        let live = Set(WindowTracker.shared.snapshot.windows.map(\.id))
        memory = memory.filter { live.contains($0.key) }
    }
}
