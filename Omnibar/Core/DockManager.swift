import AppKit
import Foundation

final class DockManager {
    static let shared = DockManager()

    private let domain = "com.apple.dock"
    private let backupKey = "omnibar.dock.backup.v1"
    private var appliedFullyHidden = false
    private var isMutating = false

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
        restartDock()
        appliedFullyHidden = true
    }

    func revertIfNeeded() {
        isMutating = true
        defer { isMutating = false }
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
            UserDefaults.standard.removeObject(forKey: backupKey)
        } else {
            writeDock("autohide-delay", 0.5)
        }
        restartDock()
        appliedFullyHidden = false
    }

    private func backupIfNeeded() {
        guard UserDefaults.standard.dictionary(forKey: backupKey) == nil else { return }
        let defaults = UserDefaults(suiteName: domain)
        var backup: [String: Any] = [:]
        backup["autohide"] = defaults?.object(forKey: "autohide") as? Bool ?? false
        backup["autohide-delay"] = defaults?.object(forKey: "autohide-delay") as? Double ?? 0.5
        backup["autohide-time-modifier"] = defaults?.object(forKey: "autohide-time-modifier") as? Double ?? 1.0
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
