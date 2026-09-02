import AppKit
import Foundation

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let statusItem = StatusItemController()
    private var started = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        if NSClassFromString("XCTestCase") != nil { return }
        SettingsStore.shared.load()
        statusItem.setup()
        AppCatalog.shared.start()
        DockManager.shared.applyFromSettings()

        NotificationCenter.default.addObserver(
            forName: .omnibarPermissionsDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.startIfPossible()
            }
        }
        NotificationCenter.default.addObserver(
            forName: .omnibarRequestSettings,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                SettingsWindow.show()
            }
        }

        if PermissionsManager.shared.accessibilityTrusted {
            startIfPossible()
        } else {
            OnboardingWindow.show()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !PermissionsManager.shared.accessibilityTrusted {
            OnboardingWindow.show()
        } else {
            SettingsWindow.show()
        }
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        DockManager.shared.revertIfNeeded()
        WindowTracker.shared.stop()
        ScreenMonitor.shared.stop()
        AppCatalog.shared.stop()
    }

    private func startIfPossible() {
        PermissionsManager.shared.refresh()
        guard PermissionsManager.shared.accessibilityTrusted else {
            OnboardingWindow.show()
            return
        }
        OnboardingWindow.closeIfTrusted()
        guard !started else { return }
        started = true
        WindowTracker.shared.start()
        ScreenMonitor.shared.start()
    }
}
