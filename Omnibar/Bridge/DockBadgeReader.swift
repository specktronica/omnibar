import AppKit
import ApplicationServices
import Foundation

final class DockBadgeReader {
    static let shared = DockBadgeReader()

    private var badges: [String: String] = [:]
    private var timer: Timer?
    private var nameToBundle: [String: String] = [:]

    func start() {
        stop()
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func badge(forBundleID bundleID: String) -> String? {
        badges[bundleID]
    }

    func refresh() {
        guard PermissionsManager.shared.accessibilityTrusted || AXIsProcessTrusted() else { return }
        guard let dock = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == "com.apple.dock" }) else {
            return
        }
        rebuildNameMap()
        let app = AXBridge.application(pid: dock.processIdentifier)
        let lists = AXBridge.copyElements(app, attribute: kAXChildrenAttribute as String)
        var next: [String: String] = [:]
        for list in lists {
            collect(from: list, into: &next)
        }
        if next != badges {
            badges = next
            NotificationCenter.default.post(name: .omnibarBadgesDidChange, object: nil)
        }
    }

    private func collect(from element: AXUIElement, into result: inout [String: String]) {
        let role = AXBridge.role(of: element)
        let title = AXBridge.title(of: element)
        let label = AXBridge.copyString(element, attribute: "AXStatusLabel")
            ?? AXBridge.copyString(element, attribute: kAXDescriptionAttribute as String)
        if role.contains("DockItem") || role == "AXApplicationDockItem" {
            if let label, !label.isEmpty, isBadge(label) {
                if let bundleID = bundleID(forDockTitle: title, element: element) {
                    result[bundleID] = label
                }
            }
        }
        for child in AXBridge.copyElements(element, attribute: kAXChildrenAttribute as String) {
            collect(from: child, into: &result)
        }
    }

    private func isBadge(_ value: String) -> Bool {
        if Int(value) != nil { return true }
        return value == "•" || value.lowercased() == "new"
    }

    private func bundleID(forDockTitle title: String, element: AXUIElement) -> String? {
        if let url = AXBridge.copyURL(element, attribute: kAXURLAttribute as String)
            ?? AXBridge.copyURL(element, attribute: "AXURL") {
            if let bundle = Bundle(url: url), let id = bundle.bundleIdentifier {
                return id
            }
            if url.path.hasSuffix(".app") {
                return Bundle(url: url)?.bundleIdentifier
            }
        }
        return nameToBundle[title.lowercased()]
    }

    private func rebuildNameMap() {
        var map: [String: String] = [:]
        for app in NSWorkspace.shared.runningApplications {
            if let name = app.localizedName, let id = app.bundleIdentifier {
                map[name.lowercased()] = id
            }
        }
        for id in PinStore.shared.pinnedBundleIDs {
            map[IconCache.appName(for: id).lowercased()] = id
        }
        nameToBundle = map
    }
}
