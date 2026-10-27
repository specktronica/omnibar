import AppKit
import Foundation

nonisolated enum WindowSpaceState: Equatable {
    case visible
    case hidden(UInt64)
    case unknown

    init(windowSpaces: [UInt64], visibleSpaces: Set<UInt64>) {
        let assigned = windowSpaces.filter { $0 != 0 }
        let visible = visibleSpaces.subtracting([0])
        guard let first = assigned.first, !visible.isEmpty else {
            self = .unknown
            return
        }
        // A window assigned to several Spaces needs no switch if any is visible.
        self = assigned.contains(where: visible.contains) ? .visible : .hidden(first)
    }
}

/// Activation can bring an app's windows onto the current Space. Wait until the
/// destination is visible before unminimizing, unhiding, or activating the app.
struct WindowFocusController {
    private struct PendingFocus {
        let id: CGWindowID
        let pid: pid_t
        let expiresAt: Date
    }

    private var pending: PendingFocus?
    var hasPendingFocus: Bool { pending != nil }

    mutating func cancel() {
        pending = nil
    }

    mutating func raise(
        _ window: WindowInfo,
        spaceState: WindowSpaceState,
        now: Date = Date(),
        switchToSpace: (UInt64) -> Bool,
        focus: (WindowInfo) -> Bool
    ) {
        pending = nil
        switch spaceState {
        case .hidden(let space):
            if switchToSpace(space) {
                pending = PendingFocus(id: window.id, pid: window.pid, expiresAt: now.addingTimeInterval(5))
            }
        case .visible, .unknown:
            _ = focus(window)
        }
    }

    mutating func completePendingFocus(
        windows: [WindowInfo],
        visibleSpaces: Set<UInt64>,
        now: Date = Date(),
        focus: (WindowInfo) -> Bool
    ) {
        guard let pending else { return }
        guard now < pending.expiresAt else {
            self.pending = nil
            return
        }
        guard let window = windows.first(where: { $0.id == pending.id && $0.pid == pending.pid }),
              WindowSpaceState(windowSpaces: window.spaces, visibleSpaces: visibleSpaces) == .visible else {
            return
        }
        if focus(window) {
            self.pending = nil
        }
    }
}

enum WindowActions {
    private static var focusController = WindowFocusController()

    static func raise(_ window: WindowInfo) {
        focusController.raise(
            window,
            spaceState: CGSBridge.shared.spaceState(forWindow: window.spaces),
            switchToSpace: { CGSBridge.shared.switchToSpace($0) },
            focus: focus
        )
        if focusController.hasPendingFocus {
            WindowTracker.shared.requestScan(immediate: true)
        }
    }

    /// Raises a window that was clicked on another Space, once a later scan can see it.
    static func completePendingFocus(windows: [WindowInfo], currentSpaces: [CGDirectDisplayID: UInt64]) {
        focusController.completePendingFocus(
            windows: windows,
            visibleSpaces: Set(currentSpaces.values),
            focus: focus
        )
    }

    /// Prefer a window already on the visible Space, then any open window.
    static func windowToRaise(in windows: [WindowInfo]) -> WindowInfo? {
        let open = windows.filter { !$0.isMinimized && !$0.isHidden }
        return open.first(where: \.isOnScreen) ?? open.first ?? windows.first
    }

    static func windowToRaise(forPinnedBundleID bundleID: String, windows: [WindowInfo]) -> WindowInfo? {
        windowToRaise(in: windows.filter { $0.bundleID == bundleID })
    }

    static func restack(frontToBack: [(id: CGWindowID, pid: pid_t)]) {
        for window in frontToBack.reversed() {
            let element = WindowTracker.shared.axElement(for: window.id)
                ?? AXBridge.element(forWindowID: window.id, pid: window.pid)
            if let element {
                AXBridge.raise(element)
            }
        }
    }

    static func minimize(_ window: WindowInfo) {
        if let element = element(for: window) {
            AXBridge.setMinimized(element, true)
        }
    }

    static func unminimize(_ window: WindowInfo) {
        if let element = element(for: window) {
            AXBridge.setMinimized(element, false)
        }
    }

    static func zoom(_ window: WindowInfo) {
        if let element = element(for: window) {
            AXBridge.pressZoomButton(element)
        }
    }

    static func hideApp(pid: pid_t) {
        NSRunningApplication(processIdentifier: pid)?.hide()
    }

    /// Close from Omnibar. With `quitAppOnLastWindowClose` on, closing the app's
    /// only window quits the app instead, so it can still ask about unsaved changes.
    static func close(_ window: WindowInfo) {
        if shouldQuitInsteadOfClosing(
            window,
            windows: WindowTracker.shared.snapshot.windows,
            settings: SettingsStore.shared.settings
        ) {
            quit(pid: window.pid)
            return
        }
        if let element = element(for: window) {
            AXBridge.pressCloseButton(element)
        }
    }

    /// Finder keeps the desktop alive, so it is never quit this way.
    static let neverQuitOnLastWindowClose: Set<String> = ["com.apple.finder"]

    /// `windows` is every window Omnibar tracks, on all screens and Spaces,
    /// not just the tiles on one bar.
    static func shouldQuitInsteadOfClosing(
        _ window: WindowInfo,
        windows: [WindowInfo],
        settings: AppSettings
    ) -> Bool {
        guard settings.quitAppOnLastWindowClose else { return false }
        if let bundleID = window.bundleID, neverQuitOnLastWindowClose.contains(bundleID) {
            return false
        }
        return !windows.contains { $0.pid == window.pid && $0.id != window.id }
    }

    static func fullscreen(_ window: WindowInfo) {
        if let element = element(for: window) {
            AXBridge.setFullscreen(element, !window.isFullscreen)
        }
    }

    static func quit(pid: pid_t) {
        NSRunningApplication(processIdentifier: pid)?.terminate()
    }

    static func launch(bundleID: String) {
        AppCatalog.shared.launch(bundleID: bundleID)
    }

    static func newWindow(pid: pid_t?, bundleID: String?) {
        if let pid {
            activate(pid: pid)
            if let item = AXBridge.findMenuItem(pid: pid, titles: ["New Window", "New Document", "New"]) {
                AXBridge.press(item)
                return
            }
            postCommandN()
            return
        }
        if let bundleID {
            launch(bundleID: bundleID)
        }
    }

    static func handlePrimaryClick(_ item: TaskItem) {
        focusController.cancel()
        let settings = SettingsStore.shared.settings
        switch item.kind {
        case .pinned(let bundleID, _, _, _):
            // A pin can look like a launcher when its windows are filtered out
            // on this taskbar. Reopen only when there are no windows anywhere.
            if let window = windowToRaise(
                forPinnedBundleID: bundleID,
                windows: WindowTracker.shared.snapshot.windows
            ) {
                raise(window)
            } else {
                launch(bundleID: bundleID)
            }
        case .window(let window):
            if window.isActive {
                if settings.hideOnClickInsteadOfMinimize {
                    hideApp(pid: window.pid)
                } else {
                    minimize(window)
                }
            } else {
                raise(window)
            }
        case .grouped(_, _, let windows, _):
            if let active = windows.first(where: \.isActive) {
                if settings.hideOnClickInsteadOfMinimize {
                    hideApp(pid: active.pid)
                } else {
                    minimize(active)
                }
            } else if let window = windowToRaise(in: windows) {
                raise(window)
            }
        }
    }

    static func handleMiddleClick(_ item: TaskItem) {
        newWindow(pid: item.pid, bundleID: item.bundleID)
    }

    @discardableResult
    private static func focus(_ window: WindowInfo) -> Bool {
        guard let element = element(for: window) else { return false }
        activate(pid: window.pid)
        if window.isMinimized {
            AXBridge.setMinimized(element, false)
        }
        AXBridge.raise(element)
        return true
    }

    private static func element(for window: WindowInfo) -> AXUIElement? {
        WindowTracker.shared.axElement(for: window.id)
            ?? AXBridge.element(forWindowID: window.id, pid: window.pid)
    }

    private static func activate(pid: pid_t) {
        NSRunningApplication(processIdentifier: pid)?.unhide()
        NSRunningApplication(processIdentifier: pid)?.activate(options: [.activateIgnoringOtherApps])
    }

    private static func postCommandN() {
        let source = CGEventSource(stateID: .hidSystemState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x2D, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x2D, keyDown: false)
        keyDown?.flags = .maskCommand
        keyUp?.flags = .maskCommand
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }
}
