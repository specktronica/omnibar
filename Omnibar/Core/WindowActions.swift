import AppKit
import Foundation

enum WindowActions {
    enum PrimaryClickAction: Equatable {
        case launch(bundleID: String)
        case raise(WindowInfo)
        case minimize(WindowInfo)
        case hide(pid: pid_t)
    }

    static func raise(_ window: WindowInfo, activateApp: Bool = true) {
        if activateApp {
            activate(pid: window.pid)
        }
        if let element = element(for: window) {
            if window.isMinimized {
                AXBridge.setMinimized(element, false)
            }
            AXBridge.raise(element)
        }
        if activateApp {
            activate(pid: window.pid)
        }
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

    static func zoom(_ window: WindowInfo) {
        if let element = element(for: window) {
            AXBridge.pressZoomButton(element)
        }
    }

    static func hideApp(pid: pid_t) {
        NSRunningApplication(processIdentifier: pid)?.hide()
    }

    static func close(_ window: WindowInfo) {
        if let element = element(for: window) {
            AXBridge.pressCloseButton(element)
        }
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
        let pids = Set(item.windows.map(\.pid))
        let zOrder = CGSBridge.shared.onScreenFrontToBackIDs(ownerPIDs: pids).map(\.id)
        let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        switch primaryClickAction(
            for: item,
            hideOnClickInsteadOfMinimize: SettingsStore.shared.settings.hideOnClickInsteadOfMinimize,
            frontmostPID: frontmostPID,
            frontToBackIDs: zOrder
        ) {
        case .launch(let bundleID):
            launch(bundleID: bundleID)
        case .raise(let window):
            raise(window)
        case .minimize(let window):
            minimize(window)
        case .hide(let pid):
            hideApp(pid: pid)
        case .none:
            break
        }
    }

    /// Snapshot `isActive` lags behind the live frontmost app (Omnibar itself
    /// becomes frontmost after the Start Menu, and scans run on a timer). Left
    /// click focuses unless this exact window/app is frontmost right now.
    static func primaryClickAction(
        for item: TaskItem,
        hideOnClickInsteadOfMinimize: Bool,
        frontmostPID: pid_t?,
        frontToBackIDs: [CGWindowID]
    ) -> PrimaryClickAction? {
        switch item.kind {
        case .pinned(let bundleID, _, _, _):
            return .launch(bundleID: bundleID)
        case .window(let window):
            if shouldCollapse(window, frontmostPID: frontmostPID) {
                return collapseAction(window, hide: hideOnClickInsteadOfMinimize)
            }
            return .raise(window)
        case .grouped(_, _, let windows, _):
            guard let target = preferredWindow(from: windows, frontToBackIDs: frontToBackIDs) else {
                return nil
            }
            let hasVisible = windows.contains { !$0.isMinimized && !$0.isHidden }
            if frontmostPID == target.pid, hasVisible {
                let focused = windows.first(where: \.isActive) ?? target
                return collapseAction(focused, hide: hideOnClickInsteadOfMinimize)
            }
            return .raise(target)
        }
    }

    static func preferredWindow(from windows: [WindowInfo], frontToBackIDs: [CGWindowID]) -> WindowInfo? {
        let visible = windows.filter { !$0.isMinimized && !$0.isHidden }
        let pool = visible.isEmpty ? windows : visible
        guard !pool.isEmpty else { return nil }
        if !frontToBackIDs.isEmpty {
            let ids = Set(pool.map(\.id))
            if let id = frontToBackIDs.first(where: { ids.contains($0) }),
               let match = pool.first(where: { $0.id == id }) {
                return match
            }
        }
        return pool.first
    }

    static func handleMiddleClick(_ item: TaskItem) {
        newWindow(pid: item.pid, bundleID: item.bundleID)
    }

    private static func element(for window: WindowInfo) -> AXUIElement? {
        WindowTracker.shared.axElement(for: window.id)
            ?? AXBridge.element(forWindowID: window.id, pid: window.pid)
    }

    private static func shouldCollapse(_ window: WindowInfo, frontmostPID: pid_t?) -> Bool {
        frontmostPID == window.pid && window.isActive && !window.isMinimized && !window.isHidden
    }

    private static func collapseAction(_ window: WindowInfo, hide: Bool) -> PrimaryClickAction {
        hide ? .hide(pid: window.pid) : .minimize(window)
    }

    private static func activate(pid: pid_t) {
        guard let app = NSRunningApplication(processIdentifier: pid), !app.isTerminated else { return }
        activate(app)
    }

    /// Accessory, nonactivating panels cannot use cooperative `activate()`.
    /// Yield to the target and activate from the live front app so key focus
    /// actually moves on macOS 14+.
    static func activate(_ app: NSRunningApplication) {
        app.unhide()
        NSApp.yieldActivation(to: app)
        if let front = NSWorkspace.shared.frontmostApplication,
           front.processIdentifier != app.processIdentifier {
            if app.activate(from: front) { return }
        }
        _ = app.activate()
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
