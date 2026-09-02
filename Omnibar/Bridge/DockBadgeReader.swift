import AppKit
import ApplicationServices
import Foundation

final class DockBadgeReader {
    static let shared = DockBadgeReader()

    private var badges: [String: String] = [:]
    private var timer: Timer?
    private var nameToBundle: [String: String] = [:]
    private var nameMapAppPIDs: Set<pid_t> = []
    private var nameMapPins: [String] = []
    private var refreshInFlight = false
    private var refreshQueued = false

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
        refreshInFlight = false
        refreshQueued = false
    }

    func badge(forBundleID bundleID: String) -> String? {
        badges[bundleID]
    }

    func refresh() {
        guard PermissionsManager.shared.accessibilityTrusted || AXIsProcessTrusted() else { return }
        guard let dock = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == "com.apple.dock" }) else {
            return
        }
        if refreshInFlight {
            refreshQueued = true
            return
        }
        refreshInFlight = true
        rebuildNameMapIfNeeded()
        let pid = dock.processIdentifier
        let nameMap = nameToBundle
        Task {
            let next = await WindowScanner.shared.readDockBadges(dockPID: pid, nameMap: nameMap)
            await MainActor.run {
                self.refreshInFlight = false
                if next != self.badges {
                    self.badges = next
                    NotificationCenter.default.post(name: .omnibarBadgesDidChange, object: nil)
                }
                if self.refreshQueued {
                    self.refreshQueued = false
                    self.refresh()
                }
            }
        }
    }

    nonisolated static func isBadgeLabel(_ value: String) -> Bool {
        if Int(value) != nil { return true }
        return value == "•" || value.lowercased() == "new"
    }

    private func rebuildNameMapIfNeeded() {
        let pids = Set(NSWorkspace.shared.runningApplications.map(\.processIdentifier))
        let pins = PinStore.shared.pinnedBundleIDs
        if pids == nameMapAppPIDs && pins == nameMapPins { return }
        nameMapAppPIDs = pids
        nameMapPins = pins
        var map: [String: String] = [:]
        for app in NSWorkspace.shared.runningApplications {
            if let name = app.localizedName, let id = app.bundleIdentifier {
                map[name.lowercased()] = id
            }
        }
        for id in pins {
            map[IconCache.appName(for: id).lowercased()] = id
        }
        nameToBundle = map
    }
}
