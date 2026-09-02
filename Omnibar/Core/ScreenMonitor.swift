import AppKit
import Foundation

final class ScreenMonitor {
    static let shared = ScreenMonitor()

    private var panels: [CGDirectDisplayID: TaskbarPanel] = [:]
    private var observers: [NSObjectProtocol] = []
    private var globalMouse: Any?
    private var localMouse: Any?
    private var hideWork: DispatchWorkItem?

    func start() {
        stop()
        rebuild()
        let names: [Notification.Name] = [
            NSApplication.didChangeScreenParametersNotification,
            NSWorkspace.didWakeNotification,
            NSWorkspace.screensDidWakeNotification,
            .omnibarSettingsDidChange,
            .omnibarSnapshotDidChange
        ]
        for name in names {
            let center: NotificationCenter = (name == NSWorkspace.didWakeNotification || name == NSWorkspace.screensDidWakeNotification)
                ? NSWorkspace.shared.notificationCenter
                : .default
            let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    if name == NSApplication.didChangeScreenParametersNotification
                        || name == NSWorkspace.didWakeNotification
                        || name == NSWorkspace.screensDidWakeNotification {
                        self?.rebuild(recreate: true)
                    } else {
                        self?.apply()
                    }
                }
            }
            observers.append(token)
        }
        globalMouse = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] event in
            Task { @MainActor in
                self?.handleMouse(event.locationInWindow, global: true, event: event)
            }
        }
        localMouse = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] event in
            Task { @MainActor in
                self?.handleMouse(event.locationInWindow, global: false, event: event)
            }
            return event
        }
    }

    func stop() {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        observers.removeAll()
        if let globalMouse { NSEvent.removeMonitor(globalMouse) }
        if let localMouse { NSEvent.removeMonitor(localMouse) }
        globalMouse = nil
        localMouse = nil
        panels.values.forEach { $0.orderOut(nil) }
        panels.removeAll()
    }

    func panel(for displayID: CGDirectDisplayID) -> TaskbarPanel? {
        panels[displayID]
    }

    func rebuild(recreate: Bool = false) {
        if recreate {
            panels.values.forEach { $0.close() }
            panels.removeAll()
        }
        let settings = SettingsStore.shared.settings
        let screens: [NSScreen]
        if settings.mainDisplayOnly {
            screens = [NSScreen.main ?? NSScreen.screens.first].compactMap { $0 }
        } else {
            screens = NSScreen.screens
        }
        let wanted = Set(screens.map(\.displayID))
        for id in panels.keys where !wanted.contains(id) {
            panels[id]?.close()
            panels.removeValue(forKey: id)
        }
        for screen in screens {
            if panels[screen.displayID] == nil {
                let panel = TaskbarPanel(screen: screen)
                panels[screen.displayID] = panel
            } else {
                panels[screen.displayID]?.updateScreen(screen)
            }
        }
        apply()
    }

    func apply() {
        let settings = SettingsStore.shared.settings
        let snapshot = WindowTracker.shared.snapshot
        for (id, panel) in panels {
            let hidden = settings.isDisplayHidden(id)
            let fullscreen = snapshot.isFullscreen(id)
            panel.applySnapshot(snapshot)
            panel.setSuppressed(hidden || fullscreen)
        }
        updateAutoHide(cursor: NSEvent.mouseLocation)
    }

    private func handleMouse(_ location: NSPoint, global: Bool, event: NSEvent) {
        let point = global ? NSEvent.mouseLocation : NSEvent.mouseLocation
        updateAutoHide(cursor: point)
        _ = location
        _ = event
    }

    private func updateAutoHide(cursor: NSPoint) {
        let settings = SettingsStore.shared.settings
        guard settings.autoHide else {
            for panel in panels.values where !panel.isSuppressed {
                panel.setAutoHidden(false)
            }
            return
        }
        hideWork?.cancel()
        for (id, panel) in panels {
            if panel.isSuppressed {
                panel.setAutoHidden(true)
                continue
            }
            guard let screen = NSScreen.screens.first(where: { $0.displayID == id }) else { continue }
            let inPanel = panel.frame.insetBy(dx: 0, dy: -2).contains(cursor)
            let inRelated = panel.ownsCursor(cursor)
            let hot = CGRect(x: screen.frame.minX, y: screen.frame.minY, width: screen.frame.width, height: 3)
            let inHot = hot.contains(cursor)
            if inPanel || inRelated || inHot {
                panel.setAutoHidden(false)
            } else {
                let work = DispatchWorkItem { [weak panel] in
                    panel?.setAutoHidden(true)
                }
                hideWork = work
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
            }
        }
    }
}
