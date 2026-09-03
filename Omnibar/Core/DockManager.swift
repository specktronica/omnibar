import AppKit
import CoreGraphics
import Foundation

nonisolated enum DockOrientation: Sendable {
    static let top = "top"
    static let bottom = "bottom"

    static func normalized(_ value: String?) -> String {
        switch value {
        case "top": return "top"
        case "left": return "left"
        case "right": return "right"
        case "bottom": return "bottom"
        default: return bottom
        }
    }
}

nonisolated enum DockStripHiding: Sendable {
    static let dockWindowLevel = Int32(CGWindowLevelForKey(.dockWindow))
    static let buriedLevel = Int32(CGWindowLevelForKey(.desktopWindow)) - 2

    static func isStrip(name: String, layer: Int32) -> Bool {
        if name.hasPrefix("Wallpaper") { return false }
        return layer == dockWindowLevel
    }

    static func stripWindowIDs(from windows: [[String: Any]], dockPID: pid_t) -> [CGWindowID] {
        var ids: [CGWindowID] = []
        for info in windows {
            let pid = pid_t((info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value ?? 0)
            guard pid == dockPID else { continue }
            let name = info[kCGWindowName as String] as? String ?? ""
            let layer = (info[kCGWindowLayer as String] as? NSNumber)?.int32Value ?? 0
            guard isStrip(name: name, layer: layer) else { continue }
            guard let id = (info[kCGWindowNumber as String] as? NSNumber)?.uint32Value else { continue }
            ids.append(id)
        }
        return ids
    }
}

final class DockManager {
    static let shared = DockManager()

    private let domain = "com.apple.dock"
    private let backupKey = "omnibar.dock.backup.v1"
    private var appliedFullyHidden = false
    private var isMutating = false
    private var hideTimer: Timer?
    private var buriedLevels: [CGWindowID: Int32] = [:]

    func applyFromSettings() {
        guard !isMutating else { return }
        let hide = SettingsStore.shared.settings.fullyHideDock
        if hide, !appliedFullyHidden {
            applyFullyHidden()
        } else if !hide, appliedFullyHidden {
            revertIfNeeded()
        }
    }

    func applyFullyHidden() {
        backupIfNeeded()
        writeDock("autohide", true)
        writeDock("autohide-delay", 1000.0)
        writeDock("autohide-time-modifier", 0.0)
        // Top keeps a Mission Control flash off Omnibar's bottom edge.
        writeDock("orientation", DockOrientation.top)
        restartDock()
        appliedFullyHidden = true
        startMissionControlHiding()
    }

    func revertIfNeeded() {
        isMutating = true
        defer { isMutating = false }
        stopMissionControlHiding()
        guard appliedFullyHidden || UserDefaults.standard.dictionary(forKey: backupKey) != nil else { return }
        if let backup = UserDefaults.standard.dictionary(forKey: backupKey) {
            if let autohide = backup["autohide"] as? Bool {
                writeDock("autohide", autohide)
            }
            if let delay = backup["autohide-delay"] as? Double {
                writeDock("autohide-delay", delay)
            }
            if let modifier = backup["autohide-time-modifier"] as? Double {
                writeDock("autohide-time-modifier", modifier)
            }
            if let orientation = backup["orientation"] as? String {
                writeDock("orientation", DockOrientation.normalized(orientation))
            }
            UserDefaults.standard.removeObject(forKey: backupKey)
        } else {
            writeDock("autohide-delay", 0.5)
            writeDock("orientation", DockOrientation.bottom)
        }
        restartDock()
        appliedFullyHidden = false
    }

    // Mission Control still composites the Dock at dock-window level even with a huge autohide delay.
    private func startMissionControlHiding() {
        stopMissionControlHiding()
        hideTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.hideDockStripIfNeeded()
            }
        }
        hideTimer?.tolerance = 0.02
        hideDockStripIfNeeded()
    }

    private func stopMissionControlHiding() {
        hideTimer?.invalidate()
        hideTimer = nil
        restoreBuriedDockWindows()
    }

    private func hideDockStripIfNeeded() {
        guard appliedFullyHidden else { return }
        guard let dockPID = NSWorkspace.shared.runningApplications
            .first(where: { $0.bundleIdentifier == "com.apple.dock" })?
            .processIdentifier else {
            restoreBuriedDockWindows()
            return
        }
        let list = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []
        let strip = Set(DockStripHiding.stripWindowIDs(from: list, dockPID: dockPID))
        for id in strip {
            if buriedLevels[id] == nil {
                buriedLevels[id] = CGSBridge.shared.windowLevel(of: id) ?? DockStripHiding.dockWindowLevel
            }
            CGSBridge.shared.setWindowLevel(id, level: DockStripHiding.buriedLevel)
        }
        for (id, original) in buriedLevels where !strip.contains(id) {
            CGSBridge.shared.setWindowLevel(id, level: original)
            buriedLevels.removeValue(forKey: id)
        }
    }

    private func restoreBuriedDockWindows() {
        for (id, original) in buriedLevels {
            CGSBridge.shared.setWindowLevel(id, level: original)
        }
        buriedLevels.removeAll()
    }

    private func backupIfNeeded() {
        var backup = UserDefaults.standard.dictionary(forKey: backupKey) ?? [:]
        let defaults = UserDefaults(suiteName: domain)
        if backup["autohide"] == nil {
            backup["autohide"] = defaults?.object(forKey: "autohide") as? Bool ?? false
        }
        if backup["autohide-delay"] == nil {
            backup["autohide-delay"] = defaults?.object(forKey: "autohide-delay") as? Double ?? 0.5
        }
        if backup["autohide-time-modifier"] == nil {
            backup["autohide-time-modifier"] = defaults?.object(forKey: "autohide-time-modifier") as? Double ?? 1.0
        }
        if backup["orientation"] == nil {
            backup["orientation"] = DockOrientation.normalized(defaults?.string(forKey: "orientation"))
        }
        UserDefaults.standard.set(backup, forKey: backupKey)
    }

    private func writeDock(_ key: String, _ value: Any) {
        CFPreferencesSetAppValue(key as CFString, value as CFPropertyList, domain as CFString)
        CFPreferencesAppSynchronize(domain as CFString)
    }

    private func restartDock() {
        NSWorkspace.shared.runningApplications
            .filter { $0.bundleIdentifier == "com.apple.dock" }
            .forEach { $0.terminate() }
    }
}
