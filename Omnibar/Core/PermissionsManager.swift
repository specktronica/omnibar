import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
import Observation

/// Screen Recording TCC vs what ScreenCaptureKit can actually do in this process.
///
/// `CGPreflightScreenCaptureAccess()` stays false until relaunch after a new
/// grant. Other processes' `kCGWindowName` values appear as soon as the toggle
/// is on, so that is the in-session signal that TCC listed us (`tccListed`).
enum ScreenRecordingAccess: Equatable {
    case denied
    case pendingRestart
    case trusted

    static func resolve(trustedAtLaunch: Bool, preflight: Bool, tccListed: Bool) -> ScreenRecordingAccess {
        if trustedAtLaunch {
            return preflight ? .trusted : .denied
        }
        if preflight || tccListed {
            return .pendingRestart
        }
        return .denied
    }

    static func titlesIndicateTCCGrant(windows: [[String: Any]], selfPID: pid_t) -> Bool {
        for window in windows {
            let pid = (window[kCGWindowOwnerPID as String] as? NSNumber)?.intValue ?? 0
            if pid == 0 || pid == Int(selfPID) { continue }
            let name = window[kCGWindowName as String] as? String
            if let name, !name.isEmpty { return true }
        }
        return false
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
    private var observedScreenRecordingGrant = false
    private var pollTimer: Timer?

    init() {
        accessibilityTrusted = AXIsProcessTrusted()
        let preflight = CGPreflightScreenCaptureAccess()
        screenRecordingTrustedAtLaunch = preflight
        let access = ScreenRecordingAccess.resolve(
            trustedAtLaunch: preflight,
            preflight: preflight,
            tccListed: false
        )
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
        let preflight = CGPreflightScreenCaptureAccess()
        if screenRecordingTrustedAtLaunch && !preflight {
            observedScreenRecordingGrant = false
        } else if preflight || Self.screenRecordingListedInTCC() {
            observedScreenRecordingGrant = true
        }
        let access = ScreenRecordingAccess.resolve(
            trustedAtLaunch: screenRecordingTrustedAtLaunch,
            preflight: preflight,
            tccListed: observedScreenRecordingGrant
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
        // AXIsProcessTrustedWithOptions only presents once per process. Open the
        // pane on every click so a dismissed Settings window can be brought back.
        Self.openPrivacySettings(anchor: "Privacy_Accessibility")
        startPolling()
        return trusted
    }

    @discardableResult
    func promptScreenRecording() -> Bool {
        _ = CGRequestScreenCaptureAccess()
        Self.openPrivacySettings(anchor: "Privacy_ScreenCapture")
        startPolling()
        refresh()
        return screenRecordingTrusted
    }

    static func privacySettingsURLStrings(anchor: String) -> [String] {
        [
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?\(anchor)",
            "x-apple.systempreferences:com.apple.preference.security?\(anchor)",
        ]
    }

    static func openPrivacySettings(anchor: String) {
        for string in privacySettingsURLStrings(anchor: anchor) {
            guard let url = URL(string: string) else { continue }
            if NSWorkspace.shared.open(url) { return }
        }
    }

    private static func screenRecordingListedInTCC() -> Bool {
        let windows = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]] ?? []
        return ScreenRecordingAccess.titlesIndicateTCCGrant(
            windows: windows,
            selfPID: ProcessInfo.processInfo.processIdentifier
        )
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
