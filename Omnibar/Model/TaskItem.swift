import AppKit
import CoreGraphics
import Foundation

struct TaskItem: Identifiable {
    enum Kind {
        case window(WindowInfo)
        case grouped(bundleID: String?, appName: String, windows: [WindowInfo], badge: String?)
        case pinned(bundleID: String, appName: String, icon: NSImage?, badge: String?)
    }

    let id: String
    let kind: Kind

    var bundleID: String? {
        switch kind {
        case .window(let w): w.bundleID
        case .grouped(let id, _, _, _): id
        case .pinned(let id, _, _, _): id
        }
    }

    var appName: String {
        switch kind {
        case .window(let w): w.appName
        case .grouped(_, let name, _, _): name
        case .pinned(_, let name, _, _): name
        }
    }

    var pid: pid_t? {
        switch kind {
        case .window(let w): w.pid
        case .grouped(_, _, let windows, _): windows.first?.pid
        case .pinned: nil
        }
    }

    var isActive: Bool {
        switch kind {
        case .window(let w): w.isActive
        case .grouped(_, _, let windows, _): windows.contains(where: \.isActive)
        case .pinned: false
        }
    }

    var isMinimizedOrHidden: Bool {
        switch kind {
        case .window(let w): w.isMinimized || w.isHidden
        case .grouped(_, _, let windows, _): windows.allSatisfy { $0.isMinimized || $0.isHidden }
        case .pinned: false
        }
    }

    var badge: String? {
        switch kind {
        case .window(let w):
            w.bundleID.flatMap { DockBadgeReader.shared.badge(forBundleID: $0) }
        case .grouped(_, _, _, let badge): badge
        case .pinned(_, _, _, let badge): badge
        }
    }

    var primaryWindow: WindowInfo? {
        switch kind {
        case .window(let w): w
        case .grouped(_, _, let windows, _): windows.first(where: \.isActive) ?? windows.first
        case .pinned: nil
        }
    }

    var windows: [WindowInfo] {
        switch kind {
        case .window(let w): [w]
        case .grouped(_, _, let windows, _): windows
        case .pinned: []
        }
    }

    var isPinnedLauncher: Bool {
        if case .pinned = kind { return true }
        return false
    }

    var uiKey: String {
        switch kind {
        case .window(let window):
            return "w:\(id):\(window.title):\(window.isActive):\(window.isMinimized):\(window.isHidden):\(badge ?? "")"
        case .grouped(let bundleID, let appName, let windows, let badge):
            let parts = windows.map {
                "\($0.id):\($0.title):\($0.isActive):\($0.isMinimized):\($0.isHidden)"
            }.joined(separator: ",")
            return "g:\(id):\(bundleID ?? ""):\(appName):\(badge ?? ""):\(parts)"
        case .pinned(let bundleID, let name, _, let badge):
            return "p:\(id):\(bundleID):\(name):\(badge ?? "")"
        }
    }
}
