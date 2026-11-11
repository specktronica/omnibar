import AppKit
import CoreGraphics
import Foundation
import os

/// Temporary diagnostics for quitting on the red close button. Read with:
/// log show --last 10m --predicate 'subsystem == "io.specktronica.omnibar" AND category == "close-button"'
nonisolated enum CloseButtonLog {
    static let logger = Logger(subsystem: "io.specktronica.omnibar", category: "close-button")

    static func log(_ message: String) {
        logger.notice("\(message, privacy: .public)")
    }

    /// What Accessibility reports at a click that did not resolve to a close button.
    static func describeHit(at point: CGPoint) {
        var hit: AXUIElement?
        let err = AXUIElementCopyElementAtPosition(AXUIElementCreateSystemWide(), Float(point.x), Float(point.y), &hit)
        guard err == .success, let hit else {
            log("hit-test at \(point) failed: AXError \(err.rawValue)")
            return
        }
        var pid: pid_t = 0
        _ = AXUIElementGetPid(hit, &pid)
        var chain: [String] = []
        var element: AXUIElement? = hit
        for _ in 0..<6 {
            guard let current = element else { break }
            chain.append("\(AXBridge.role(of: current))/\(AXBridge.subrole(of: current))")
            element = AXBridge.copyElement(current, attribute: kAXParentAttribute as String)
        }
        let window = AXBridge.copyElement(hit, attribute: kAXWindowAttribute as String)
        let windowID = window.flatMap(AXBridge.cgWindowID(for:))
        log("hit-test at \(point): pid \(pid), no close button. element > parents: \(chain.joined(separator: " > ")); "
            + "AXWindow \(window == nil ? "nil" : "found"), window id \(windowID.map(String.init) ?? "nil")")
    }
}

/// Decides when a click on an app's own red close button should quit the app:
/// once the clicked window is gone and Omnibar lists no other window for it.
struct CloseButtonQuitTracker {
    struct Pending: Equatable {
        let windowID: CGWindowID
        let pid: pid_t
        let expiresAt: Date
        /// Every window Omnibar has listed for the app while waiting, the
        /// clicked one included.
        var knownWindowIDs: Set<CGWindowID>
        var closedAt: Date?
    }

    /// Long enough to answer a "save changes?" dialog before the window closes.
    static let closeTimeout: TimeInterval = 60
    /// After the clicked window is gone, how long to wait for the app's other
    /// windows to go too. Tabs in that window close with it, possibly a scan later.
    static let settleTime: TimeInterval = 3

    private(set) var pending: [Pending] = []
    var hasPending: Bool { !pending.isEmpty }

    /// Only windows Omnibar lists, so a palette, a blacklisted app, or a system
    /// window is never watched.
    static func shouldWatch(
        windowID: CGWindowID,
        pid: pid_t,
        windows: [WindowInfo],
        settings: AppSettings
    ) -> Bool {
        guard settings.quitAppOnLastWindowClose,
              let window = windows.first(where: { $0.id == windowID && $0.pid == pid }) else {
            return false
        }
        if let bundleID = window.bundleID, WindowActions.neverQuitOnLastWindowClose.contains(bundleID) {
            return false
        }
        return true
    }

    mutating func watch(windowID: CGWindowID, pid: pid_t, windows: [WindowInfo], now: Date = Date()) {
        pending.removeAll { $0.windowID == windowID && $0.pid == pid }
        let known = Set(windows.filter { $0.pid == pid }.map(\.id)).union([windowID])
        pending.append(Pending(
            windowID: windowID,
            pid: pid,
            expiresAt: now.addingTimeInterval(Self.closeTimeout),
            knownWindowIDs: known
        ))
    }

    mutating func cancelAll() {
        pending.removeAll()
    }

    /// Call after each scan. `confirm` double-checks a quit against the
    /// window server and the app, since a scan can miss windows of a slow app.
    mutating func update(
        windows: [WindowInfo],
        now: Date = Date(),
        confirm: (Pending) -> Bool,
        quit: (pid_t) -> Void
    ) {
        var kept: [Pending] = []
        var quitPIDs = Set<pid_t>()
        for var entry in pending {
            if quitPIDs.contains(entry.pid) { continue }
            let appWindows = windows.filter { $0.pid == entry.pid }
            entry.knownWindowIDs.formUnion(appWindows.map(\.id))

            if appWindows.contains(where: { $0.id == entry.windowID }) {
                // Still open, or back after a scan that missed it.
                entry.closedAt = nil
                if now < entry.expiresAt {
                    kept.append(entry)
                }
                continue
            }

            let closedAt = entry.closedAt ?? now
            entry.closedAt = closedAt
            if appWindows.isEmpty, confirm(entry) {
                quitPIDs.insert(entry.pid)
                quit(entry.pid)
                continue
            }
            if now < closedAt.addingTimeInterval(Self.settleTime) {
                kept.append(entry)
            }
        }
        pending = kept.filter { !quitPIDs.contains($0.pid) }
    }
}

/// Watches clicks on other apps' red close buttons. With
/// `quitAppOnLastWindowClose` on, the app quits once that click has closed its
/// last window. The click itself always goes through, so the app closes the
/// window as usual and can ask about unsaved changes first.
final class CloseButtonMonitor {
    static let shared = CloseButtonMonitor()

    private var monitor: Any?
    private var tracker = CloseButtonQuitTracker()
    private let hitTestQueue = DispatchQueue(label: "io.specktronica.omnibar.close-button", qos: .userInitiated)

    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { event in
            let location = closeButtonClickLocation(event)
            Task { @MainActor in
                CloseButtonMonitor.shared.handleClick(at: location)
            }
        }
        CloseButtonLog.log("monitor started: \(monitor != nil)")
    }

    func stop() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
        tracker.cancelAll()
    }

    /// Called by `WindowTracker` after every scan.
    func scanDidFinish(windows: [WindowInfo]) {
        guard tracker.hasPending else { return }
        guard SettingsStore.shared.settings.quitAppOnLastWindowClose else {
            CloseButtonLog.log("scan: setting is off, dropping \(tracker.pending.count) watched window(s)")
            tracker.cancelAll()
            return
        }
        for entry in tracker.pending {
            let appIDs = windows.filter { $0.pid == entry.pid }.map(\.id).sorted()
            let closed = entry.closedAt.map { String(format: "%.1fs ago", -$0.timeIntervalSinceNow) } ?? "not yet"
            CloseButtonLog.log("scan: window \(entry.windowID) pid \(entry.pid) still listed: "
                + "\(appIDs.contains(entry.windowID)); app's listed windows \(appIDs); gone since \(closed)")
        }
        let before = tracker.pending.count
        tracker.update(windows: windows, confirm: Self.confirmClosed, quit: { pid in
            CloseButtonLog.log("quitting pid \(pid)")
            WindowActions.quit(pid: pid)
        })
        if tracker.pending.count != before {
            CloseButtonLog.log("scan: watched windows \(before) -> \(tracker.pending.count)")
        }
    }

    private func handleClick(at location: CGPoint?) {
        guard SettingsStore.shared.settings.quitAppOnLastWindowClose else {
            CloseButtonLog.log("click ignored: setting is off")
            return
        }
        guard let location else {
            CloseButtonLog.log("click ignored: event has no location")
            return
        }
        let windows = WindowTracker.shared.snapshot.windows
        // A close button sits inside its window, so skip clicks over nothing Omnibar lists.
        let onScreen = windows.filter(\.isOnScreen)
        guard let target = onScreen.first(where: { $0.frame.contains(location) }) else {
            CloseButtonLog.log("click at \(location) ignored: not over a listed on-screen window "
                + "(\(onScreen.count) on screen, \(windows.count) listed)")
            return
        }
        CloseButtonLog.log("click at \(location) over \(target.appName) window \(target.id) frame \(target.frame)")
        // Hit-testing asks the clicked app, which can be slow, so keep it off the main thread.
        hitTestQueue.async {
            guard let hit = AXBridge.closeButtonWindow(at: location) else {
                CloseButtonLog.describeHit(at: location)
                return
            }
            CloseButtonLog.log("close button hit: pid \(hit.pid) window \(hit.windowID)")
            Task { @MainActor in
                CloseButtonMonitor.shared.watch(pid: hit.pid, windowID: hit.windowID, windows: windows)
            }
        }
    }

    /// `windows` is the list at click time, in case a scan finished in between.
    private func watch(pid: pid_t, windowID: CGWindowID, windows: [WindowInfo]) {
        guard pid != ProcessInfo.processInfo.processIdentifier else {
            CloseButtonLog.log("not watching: Omnibar's own window")
            return
        }
        guard CloseButtonQuitTracker.shouldWatch(
            windowID: windowID,
            pid: pid,
            windows: windows,
            settings: SettingsStore.shared.settings
        ) else {
            let listed = windows.first { $0.id == windowID }
                .map { "\($0.appName) pid \($0.pid) bundle \($0.bundleID ?? "nil")" } ?? "not listed"
            CloseButtonLog.log("not watching window \(windowID) pid \(pid): listed as \(listed)")
            return
        }
        tracker.watch(windowID: windowID, pid: pid, windows: windows)
        let appIDs = windows.filter { $0.pid == pid }.map(\.id).sorted()
        CloseButtonLog.log("watching window \(windowID) pid \(pid); app's listed windows \(appIDs)")
    }

    /// The window server must agree the clicked window is gone, and the app
    /// must answer and report none of the windows Omnibar saw for it.
    private static func confirmClosed(_ entry: CloseButtonQuitTracker.Pending) -> Bool {
        let orderedIn = CGSBridge.shared.isWindowOrderedIn(entry.windowID)
        if orderedIn == true {
            CloseButtonLog.log("confirm \(entry.windowID): window server says it is still ordered in")
            return false
        }
        guard let open = AXBridge.windowIDsIfAnswered(forApp: entry.pid) else {
            CloseButtonLog.log("confirm \(entry.windowID): pid \(entry.pid) did not answer kAXWindows")
            return false
        }
        let overlap = open.intersection(entry.knownWindowIDs)
        CloseButtonLog.log("confirm \(entry.windowID): ordered in \(orderedIn.map(String.init) ?? "unknown"), "
            + "app reports \(open.sorted()), known \(entry.knownWindowIDs.sorted()), overlap \(overlap.sorted())")
        return overlap.isEmpty
    }
}

/// Global CG coordinates (top-left origin), the space Accessibility hit-tests in.
private nonisolated func closeButtonClickLocation(_ event: NSEvent) -> CGPoint? {
    event.cgEvent?.location
}
