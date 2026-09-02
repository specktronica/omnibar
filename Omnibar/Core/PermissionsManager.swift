import AppKit
import ApplicationServices
import Foundation

final class PermissionsManager {
    static let shared = PermissionsManager()

    private(set) var accessibilityTrusted: Bool
    private(set) var screenRecordingTrusted: Bool

    init() {
        accessibilityTrusted = AXIsProcessTrusted()
        screenRecordingTrusted = CGPreflightScreenCaptureAccess()
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
    }

    func refresh() {
        let ax = AXIsProcessTrusted()
        let screen = CGPreflightScreenCaptureAccess()
        let changed = ax != accessibilityTrusted || screen != screenRecordingTrusted
        accessibilityTrusted = ax
        screenRecordingTrusted = screen
        if changed {
            NotificationCenter.default.post(name: .omnibarPermissionsDidChange, object: nil)
        }
    }

    @discardableResult
    func promptAccessibility() -> Bool {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)
        accessibilityTrusted = trusted
        return trusted
    }

    @discardableResult
    func promptScreenRecording() -> Bool {
        let granted = CGRequestScreenCaptureAccess()
        screenRecordingTrusted = granted || CGPreflightScreenCaptureAccess()
        return screenRecordingTrusted
    }
}
