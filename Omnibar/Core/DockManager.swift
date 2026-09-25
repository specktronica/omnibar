import AppKit
import Foundation

nonisolated enum DockOrientation: Sendable {
    static let top = "top"
    static let bottom = "bottom"
    static let left = "left"
    static let right = "right"

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

nonisolated struct DockPreferences: Equatable, Sendable {
    var autohide: Bool
    var autohideDelay: Double
    var autohideTimeModifier: Double
    var orientation: String

    static let standardDelay = 0.5
    static let standardTimeModifier = 1.0

    func matches(_ other: DockPreferences) -> Bool {
        autohide == other.autohide
            && orientation == other.orientation
            && abs(autohideDelay - other.autohideDelay) < 0.001
            && abs(autohideTimeModifier - other.autohideTimeModifier) < 0.001
    }
}

nonisolated enum DockRelocation {
    /// Previous builds hid the Dock on the top edge with this autohide delay.
    static let legacyHiddenDelay = 1000.0

    static func isLegacyHiddenSignature(delay: Double, orientation: String) -> Bool {
        abs(delay - legacyHiddenDelay) < 0.001
            && DockOrientation.normalized(orientation) == DockOrientation.top
    }

    /// Preferences worth restoring. A legacy hidden signature is not the user's
    /// Dock: that build forced a 1000s delay and the top edge.
    static func backup(from live: DockPreferences) -> DockPreferences {
        guard isLegacyHiddenSignature(delay: live.autohideDelay, orientation: live.orientation) else {
            return live
        }
        return DockPreferences(
            autohide: live.autohide,
            autohideDelay: DockPreferences.standardDelay,
            autohideTimeModifier: DockPreferences.standardTimeModifier,
            orientation: DockOrientation.bottom
        )
    }

    /// Right edge, hidden. A leftover fully-hidden delay is reset so the Dock
    /// can still appear when the pointer reaches that edge.
    static func placedOnRight(_ backup: DockPreferences) -> DockPreferences {
        var placed = backup
        placed.orientation = DockOrientation.right
        placed.autohide = true
        if abs(placed.autohideDelay - legacyHiddenDelay) < 0.001 {
            placed.autohideDelay = DockPreferences.standardDelay
            placed.autohideTimeModifier = DockPreferences.standardTimeModifier
        }
        return placed
    }
}

final class DockManager {
    static let shared = DockManager()

    private let domain = "com.apple.dock"
    private let backupKey = "omnibar.dock.backup.v1"
    private var appliedRightDock = false
    private var isMutating = false

    func applyFromSettings() {
        guard !isMutating else { return }
        let move = SettingsStore.shared.settings.moveDockToRight
        if move, !appliedRightDock {
            applyRightDock()
        } else if !move, appliedRightDock {
            revertIfNeeded()
        }
    }

    func applyRightDock() {
        backupIfNeeded()
        let desired = DockRelocation.placedOnRight(currentBackup() ?? DockRelocation.backup(from: readLive()))
        appliedRightDock = true
        guard !readLive().matches(desired) else { return }
        write(desired)
        restartDock()
    }

    func revertIfNeeded() {
        isMutating = true
        defer { isMutating = false }
        guard appliedRightDock || UserDefaults.standard.dictionary(forKey: backupKey) != nil else { return }
        if let backup = currentBackup() {
            write(backup)
            UserDefaults.standard.removeObject(forKey: backupKey)
        } else {
            writeDock("autohide-delay", DockPreferences.standardDelay)
            writeDock("orientation", DockOrientation.bottom)
        }
        restartDock()
        appliedRightDock = false
    }

    private func backupIfNeeded() {
        var backup = UserDefaults.standard.dictionary(forKey: backupKey) ?? [:]
        let captured = DockRelocation.backup(from: readLive())
        if backup["autohide"] == nil {
            backup["autohide"] = captured.autohide
        }
        if backup["autohide-delay"] == nil {
            backup["autohide-delay"] = captured.autohideDelay
        }
        if backup["autohide-time-modifier"] == nil {
            backup["autohide-time-modifier"] = captured.autohideTimeModifier
        }
        if backup["orientation"] == nil {
            backup["orientation"] = captured.orientation
        }
        UserDefaults.standard.set(backup, forKey: backupKey)
    }

    private func currentBackup() -> DockPreferences? {
        guard let backup = UserDefaults.standard.dictionary(forKey: backupKey) else { return nil }
        let live = readLive()
        return DockPreferences(
            autohide: backup["autohide"] as? Bool ?? live.autohide,
            autohideDelay: backup["autohide-delay"] as? Double ?? live.autohideDelay,
            autohideTimeModifier: backup["autohide-time-modifier"] as? Double ?? live.autohideTimeModifier,
            orientation: DockOrientation.normalized(backup["orientation"] as? String ?? live.orientation)
        )
    }

    private func readLive() -> DockPreferences {
        let defaults = UserDefaults(suiteName: domain)
        return DockPreferences(
            autohide: defaults?.object(forKey: "autohide") as? Bool ?? false,
            autohideDelay: defaults?.object(forKey: "autohide-delay") as? Double ?? DockPreferences.standardDelay,
            autohideTimeModifier: defaults?.object(forKey: "autohide-time-modifier") as? Double
                ?? DockPreferences.standardTimeModifier,
            orientation: DockOrientation.normalized(defaults?.string(forKey: "orientation"))
        )
    }

    private func write(_ prefs: DockPreferences) {
        writeDock("autohide", prefs.autohide)
        writeDock("autohide-delay", prefs.autohideDelay)
        writeDock("autohide-time-modifier", prefs.autohideTimeModifier)
        writeDock("orientation", DockOrientation.normalized(prefs.orientation))
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
