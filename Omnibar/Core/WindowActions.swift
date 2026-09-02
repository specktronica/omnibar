import AppKit
import Foundation

enum WindowActions {
    static func raise(_ window: WindowInfo) {
        activate(pid: window.pid)
        if let element = element(for: window) {
            if window.isMinimized {
                AXBridge.setMinimized(element, false)
            }
            AXBridge.raise(element)
        }
        NSRunningApplication(processIdentifier: window.pid)?.activate(options: [.activateIgnoringOtherApps])
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
        let settings = SettingsStore.shared.settings
        switch item.kind {
        case .pinned(let bundleID, _, _, _):
            launch(bundleID: bundleID)
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
            } else if let first = windows.first(where: { !$0.isMinimized && !$0.isHidden }) ?? windows.first {
                raise(first)
            }
        }
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
