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

        if OnboardingLogic.launchPath(
            accessibilityTrusted: PermissionsManager.shared.accessibilityTrusted
        ) == .startTaskbar {
            startIfPossible()
        } else {
            OnboardingWindow.show()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        switch OnboardingLogic.reopenAction(
            suppressReopen: OnboardingWindow.shouldIgnoreReopen,
            onboardingShowing: OnboardingWindow.isShowing,
            accessibilityTrusted: PermissionsManager.shared.accessibilityTrusted
        ) {
        case .ignore, .none:
            break
        case .revealOnboarding:
            OnboardingWindow.reveal()
        case .showSettings:
            SettingsWindow.show()
        }
        return false
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        PermissionsManager.shared.refreshConflictingCopy()
        PermissionsManager.shared.refresh()
        if OnboardingWindow.isShowing {
            OnboardingWindow.reveal()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        DockManager.shared.revertIfNeeded()
        TilingHotkeys.shared.stop()
        WindowTracker.shared.stop()
        ScreenMonitor.shared.stop()
        AppCatalog.shared.stop()
    }

    private func startIfPossible() {
        PermissionsManager.shared.refresh()
        guard OnboardingLogic.shouldStartTaskbar(
            accessibilityTrusted: PermissionsManager.shared.accessibilityTrusted,
            onboardingShowing: OnboardingWindow.isShowing,
            relaunchInProgress: AppRelaunch.isInProgress,
            alreadyStarted: started
        ) else { return }
        started = true
        WindowTracker.shared.start()
        ScreenMonitor.shared.start()
        TilingHotkeys.shared.start()
    }
}
