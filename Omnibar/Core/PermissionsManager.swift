import AppKit
import ApplicationServices
import Foundation
import Observation

/// Screen Recording TCC vs what ScreenCaptureKit can actually do in this process.
///
/// `CGPreflightScreenCaptureAccess()` becomes true as soon as the user flips the
/// System Settings toggle, but capture APIs stay inert until relaunch. A grant
/// that appears after this process started is therefore `pendingRestart`, not
/// `trusted`.
enum ScreenRecordingAccess: Equatable {
    case denied
    case pendingRestart
    case trusted

    static func resolve(trustedAtLaunch: Bool, preflight: Bool) -> ScreenRecordingAccess {
        if !preflight { return .denied }
        if !trustedAtLaunch { return .pendingRestart }
        return .trusted
    }
}

@Observable
final class PermissionsManager {
    static let shared = PermissionsManager()

    private(set) var accessibilityTrusted: Bool
    /// True only when Screen Recording was already granted at process start.
    private(set) var screenRecordingTrusted: Bool
    private(set) var screenRecordingNeedsRestart: Bool

    private let screenRecordingTrustedAtLaunch: Bool
    private var pollTimer: Timer?

    init() {
        accessibilityTrusted = AXIsProcessTrusted()
        let preflight = CGPreflightScreenCaptureAccess()
        screenRecordingTrustedAtLaunch = preflight
        let access = ScreenRecordingAccess.resolve(trustedAtLaunch: preflight, preflight: preflight)
        screenRecordingTrusted = access == .trusted
        screenRecordingNeedsRestart = access == .pendingRestart
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.apple.accessibility.api"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(400))
                self?.refresh()
                try? await Task.sleep(for: .milliseconds(800))
                self?.refresh()
            }
        }
    }

    func refresh() {
        let ax = Self.readAccessibilityTrusted()
        let access = ScreenRecordingAccess.resolve(
            trustedAtLaunch: screenRecordingTrustedAtLaunch,
            preflight: CGPreflightScreenCaptureAccess()
        )
        let screenTrusted = access == .trusted
        let needsRestart = access == .pendingRestart
        let changed = ax != accessibilityTrusted
            || screenTrusted != screenRecordingTrusted
            || needsRestart != screenRecordingNeedsRestart
        accessibilityTrusted = ax
        screenRecordingTrusted = screenTrusted
        screenRecordingNeedsRestart = needsRestart
        if changed {
            NotificationCenter.default.post(name: .omnibarPermissionsDidChange, object: nil)
        }
    }

    func startPolling() {
        guard pollTimer == nil else { return }
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
        pollTimer?.tolerance = 0.2
        refresh()
    }

    func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    @discardableResult
    func promptAccessibility() -> Bool {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)
        accessibilityTrusted = trusted
        startPolling()
        return trusted
    }

    @discardableResult
    func promptScreenRecording() -> Bool {
        _ = CGRequestScreenCaptureAccess()
        startPolling()
        refresh()
        return screenRecordingTrusted
    }

    private static func readAccessibilityTrusted() -> Bool {
        if AXIsProcessTrusted() { return true }
        let options = ["AXTrustedCheckOptionPrompt": false] as CFDictionary
        if AXIsProcessTrustedWithOptions(options) { return true }
        // AXIsProcessTrusted() can stay false until relaunch after a new grant.
        // Probe another process: that requires Accessibility and does not depend
        // on whether Omnibar itself is focused (unlike AXFocusedApplication).
        return canInspectOtherProcess()
    }

    private static func canInspectOtherProcess() -> Bool {
        let selfPID = ProcessInfo.processInfo.processIdentifier
        guard let other = NSWorkspace.shared.runningApplications.first(where: {
            $0.processIdentifier != selfPID && $0.activationPolicy == .regular && !$0.isTerminated
        }) else {
            return false
        }
        let element = AXUIElementCreateApplication(other.processIdentifier)
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &value)
        return result == .success
    }
}
