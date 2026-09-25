import AppKit
import Foundation

enum TaskListLogic {
    static func excludingBlacklisted(_ windows: [WindowInfo], bundleIDs: Set<String>) -> [WindowInfo] {
        guard !bundleIDs.isEmpty else { return windows }
        return windows.filter { window in
            guard let bundleID = window.bundleID else { return true }
            return !bundleIDs.contains(bundleID)
        }
    }

    static func windows(
        from windows: [WindowInfo],
        onScreen screenID: CGDirectDisplayID,
        currentSpace: UInt64?,
        settings: AppSettings
    ) -> [WindowInfo] {
        var filtered = windows.filter { window in
            if Self.onThisTaskbarSpace(window, screenID: screenID, currentSpace: currentSpace) {
                return true
            }
            // All screens keeps every display's visible Space. All Spaces adds
            // desktops that are not visible. Together they list every window.
            let onThisScreen = window.screenID == screenID || window.screenID == nil
            if settings.showWindowsFromAllSpaces && settings.showWindowsFromAllScreens {
                return true
            }
            if settings.showWindowsFromAllSpaces && onThisScreen {
                return true
            }
            if settings.showWindowsFromAllScreens && (window.isOnScreen || window.isMinimized) {
                return true
            }
            return false
        }

        if !settings.showTabsAsItems {
            var seen = Set<String>()
            filtered = filtered.filter { window in
                let key = "\(window.pid)|\(window.title)"
                if seen.contains(key) { return false }
                seen.insert(key)
                return true
            }
        }
        return filtered
    }

    /// Minimized windows stay on their last screen. Everyone else must belong to
    /// this display's current Space, or to this screen when Space ids are missing.
    static func onThisTaskbarSpace(
        _ window: WindowInfo,
        screenID: CGDirectDisplayID,
        currentSpace: UInt64?
    ) -> Bool {
        let onThisScreen = window.screenID == screenID || window.screenID == nil
        if window.isMinimized {
            return onThisScreen
        }
        if let currentSpace, !window.spaces.isEmpty {
            return window.spaces.contains(currentSpace)
        }
        return onThisScreen
    }

    static func items(
        windows: [WindowInfo],
        pinnedBundleIDs: [String],
        settings: AppSettings,
        badge: (String) -> String?,
        icon: (String) -> NSImage?,
        appName: (String) -> String
    ) -> [TaskItem] {
        let windowsByBundle = Dictionary(grouping: windows, by: { $0.bundleID ?? "pid:\($0.pid)" })
        let presentBundles = Set(windows.compactMap(\.bundleID))

        var placed = Set<String>()
        var items: [TaskItem] = []

        func append(group: [WindowInfo], groupKey: String) {
            let sortedWindows = OrderStore.shared.sorted(group) { $0.orderKey }
            if settings.groupByApplication, let first = sortedWindows.first {
                items.append(TaskItem(
                    id: "group-\(groupKey)",
                    kind: .grouped(
                        bundleID: first.bundleID,
                        appName: first.appName,
                        windows: sortedWindows,
                        badge: first.bundleID.flatMap(badge)
                    )
                ))
            } else {
                for window in sortedWindows {
                    items.append(TaskItem(id: window.orderKey, kind: .window(window)))
                }
            }
        }

        for pin in pinnedBundleIDs {
            if presentBundles.contains(pin) {
                if let group = windowsByBundle[pin] {
                    placed.insert(pin)
                    append(group: group, groupKey: pin)
                }
            } else {
                items.append(TaskItem(
                    id: "pin-\(pin)",
                    kind: .pinned(
                        bundleID: pin,
                        appName: appName(pin),
                        icon: icon(pin),
                        badge: badge(pin)
                    )
                ))
            }
        }

        let remainingKeys = windowsByBundle.keys.filter { !placed.contains($0) }
        let orderedKeys = OrderStore.shared.sorted(Array(remainingKeys)) { $0 }
        for key in orderedKeys {
            guard let group = windowsByBundle[key] else { continue }
            append(group: group, groupKey: key)
        }
        return items
    }
}
