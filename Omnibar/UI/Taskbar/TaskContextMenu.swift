import AppKit
import Foundation

enum TaskContextMenu {
    static func build(item: TaskItem, displayID: CGDirectDisplayID) -> NSMenu {
        let menu = NSMenu()
        let taskbar = NSMenuItem(title: "Taskbar", action: nil, keyEquivalent: "")
        taskbar.submenu = taskbarSubmenu(displayID: displayID)
        menu.addItem(taskbar)
        menu.addItem(.separator())

        let keep = NSMenuItem(title: "Keep in Taskbar", action: #selector(Target.togglePin(_:)), keyEquivalent: "")
        if let bundle = item.bundleID, !bundle.isEmpty {
            keep.state = PinStore.shared.isPinned(bundle) ? .on : .off
            keep.representedObject = item
            keep.target = Target.shared
        } else {
            keep.isEnabled = false
        }
        menu.addItem(keep)

        let newWindow = NSMenuItem(title: "New Window", action: #selector(Target.newWindow(_:)), keyEquivalent: "")
        newWindow.representedObject = item
        newWindow.target = Target.shared
        menu.addItem(newWindow)

        let hide = NSMenuItem(title: "Hide", action: #selector(Target.hideApp(_:)), keyEquivalent: "")
        hide.representedObject = item
        hide.target = Target.shared
        hide.isEnabled = item.pid != nil
        menu.addItem(hide)

        let blacklist = NSMenuItem(title: "Add to Blacklist", action: #selector(Target.blacklist(_:)), keyEquivalent: "")
        blacklist.representedObject = item
        blacklist.target = Target.shared
        blacklist.isEnabled = item.bundleID != nil
        menu.addItem(blacklist)

        let quit = NSMenuItem(title: "Quit", action: #selector(Target.quit(_:)), keyEquivalent: "")
        quit.representedObject = item
        quit.target = Target.shared
        quit.isEnabled = item.pid != nil
        menu.addItem(quit)

        menu.addItem(.separator())

        let fullscreen = NSMenuItem(title: "Fullscreen", action: #selector(Target.fullscreen(_:)), keyEquivalent: "")
        fullscreen.representedObject = item
        fullscreen.target = Target.shared
        fullscreen.isEnabled = item.primaryWindow != nil
        menu.addItem(fullscreen)

        let minimize = NSMenuItem(title: "Minimize", action: #selector(Target.minimize(_:)), keyEquivalent: "")
        minimize.representedObject = item
        minimize.target = Target.shared
        minimize.isEnabled = item.primaryWindow != nil
        menu.addItem(minimize)

        let close = NSMenuItem(title: "Close", action: #selector(Target.close(_:)), keyEquivalent: "")
        close.representedObject = item
        close.target = Target.shared
        close.isEnabled = item.primaryWindow != nil
        menu.addItem(close)

        if case .grouped(_, _, let windows, _) = item.kind, windows.count > 1 {
            menu.addItem(.separator())
            for window in windows {
                let title = window.displayTitle
                let sub = NSMenuItem(title: title, action: #selector(Target.raiseWindow(_:)), keyEquivalent: "")
                sub.representedObject = window.orderKey
                sub.state = window.isActive ? .on : .off
                sub.target = Target.shared
                menu.addItem(sub)
            }
        }

        return menu
    }

    private static func taskbarSubmenu(displayID: CGDirectDisplayID) -> NSMenu {
        let menu = NSMenu()
        let settings = NSMenuItem(title: "Settings…", action: #selector(Target.openSettings), keyEquivalent: ",")
        settings.target = Target.shared
        menu.addItem(settings)

        let hide = NSMenuItem(title: "Hide Taskbar on This Display", action: #selector(Target.hideDisplay(_:)), keyEquivalent: "")
        hide.representedObject = NSNumber(value: displayID)
        hide.target = Target.shared
        menu.addItem(hide)

        let dock = NSMenuItem(title: "Fully Hide Dock", action: #selector(Target.toggleDock), keyEquivalent: "")
        dock.state = SettingsStore.shared.settings.fullyHideDock ? .on : .off
        dock.target = Target.shared
        menu.addItem(dock)

        let allScreens = NSMenuItem(title: "Show Windows From All Screens", action: #selector(Target.toggleAllScreens), keyEquivalent: "")
        allScreens.state = SettingsStore.shared.settings.showWindowsFromAllScreens ? .on : .off
        allScreens.target = Target.shared
        menu.addItem(allScreens)

        menu.addItem(.separator())
        let reset = NSMenuItem(title: "Reset Settings", action: #selector(Target.reset), keyEquivalent: "")
        reset.target = Target.shared
        menu.addItem(reset)
        let quit = NSMenuItem(title: "Quit Omnibar", action: #selector(Target.quitOmnibar), keyEquivalent: "q")
        quit.target = Target.shared
        menu.addItem(quit)
        return menu
    }

    final class Target: NSObject {
        static let shared = Target()

        @objc func openSettings() {
            NotificationCenter.default.post(name: .omnibarRequestSettings, object: nil)
        }

        @objc func hideDisplay(_ sender: NSMenuItem) {
            guard let id = (sender.representedObject as? NSNumber)?.uint32Value else { return }
            SettingsStore.shared.update { settings in
                if !settings.hiddenDisplayIDs.contains(id) {
                    settings.hiddenDisplayIDs.append(id)
                }
            }
        }

        @objc func toggleDock() {
            SettingsStore.shared.update { $0.fullyHideDock.toggle() }
        }

        @objc func toggleAllScreens() {
            SettingsStore.shared.update { $0.showWindowsFromAllScreens.toggle() }
        }

        @objc func reset() {
            SettingsStore.shared.resetToDefaults()
            DockManager.shared.revertIfNeeded()
        }

        @objc func quitOmnibar() {
            NSApp.terminate(nil)
        }

        @objc func togglePin(_ sender: NSMenuItem) {
            guard let item = sender.representedObject as? TaskItem, let bundle = item.bundleID else { return }
            PinStore.shared.toggle(bundle)
        }

        @objc func newWindow(_ sender: NSMenuItem) {
            guard let item = sender.representedObject as? TaskItem else { return }
            WindowActions.newWindow(pid: item.pid, bundleID: item.bundleID)
        }

        @objc func hideApp(_ sender: NSMenuItem) {
            guard let item = sender.representedObject as? TaskItem, let pid = item.pid else { return }
            WindowActions.hideApp(pid: pid)
        }

        @objc func blacklist(_ sender: NSMenuItem) {
            guard let item = sender.representedObject as? TaskItem, let bundle = item.bundleID else { return }
            BlacklistStore.shared.add(bundle)
        }

        @objc func quit(_ sender: NSMenuItem) {
            guard let item = sender.representedObject as? TaskItem, let pid = item.pid else { return }
            WindowActions.quit(pid: pid)
        }

        @objc func fullscreen(_ sender: NSMenuItem) {
            guard let item = sender.representedObject as? TaskItem, let window = item.primaryWindow else { return }
            WindowActions.fullscreen(window)
        }

        @objc func minimize(_ sender: NSMenuItem) {
            guard let item = sender.representedObject as? TaskItem, let window = item.primaryWindow else { return }
            WindowActions.minimize(window)
        }

        @objc func close(_ sender: NSMenuItem) {
            guard let item = sender.representedObject as? TaskItem, let window = item.primaryWindow else { return }
            WindowActions.close(window)
        }

        @objc func raiseWindow(_ sender: NSMenuItem) {
            guard let key = sender.representedObject as? String else { return }
            if let window = WindowTracker.shared.snapshot.windows.first(where: { $0.orderKey == key }) {
                WindowActions.raise(window)
            }
        }
    }
}
