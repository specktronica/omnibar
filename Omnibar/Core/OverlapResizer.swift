import AppKit
import Foundation

/// What Omnibar remembers about one window so that zooming it a second time
/// puts back the size it had before the first zoom. Frames use top-left-origin
/// coordinates, as Accessibility and the window server report them.
nonisolated struct FitMemory: Equatable, Sendable {
    /// Last frame seen clear of the bar.
    var lastClear: CGRect?
    /// Frame the app reported after Omnibar shortened the window to clear the
    /// bar. Kept only while the window stays there.
    var fitted: CGRect?
    /// Frame from before the window covered the bar.
    var restore: CGRect?

    mutating func recordFit(_ frame: CGRect) {
        fitted = frame
        lastClear = frame
    }
}

nonisolated enum FitAction: Equatable, Sendable {
    case none
    /// Shorten the window to this height, keeping its top edge.
    case fit(height: CGFloat)
    /// Move and resize the window back to this frame.
    case restore(CGRect)
}

enum OverlapGeometry {
    static func shouldConsider(
        _ window: WindowInfo,
        skipBundles: Set<String>,
        skippedPIDs: Set<pid_t>
    ) -> Bool {
        if window.isFullscreen || window.isMinimized || window.isHidden { return false }
        if let bundle = window.bundleID, skipBundles.contains(bundle) { return false }
        if skippedPIDs.contains(window.pid) { return false }
        return true
    }

    static func proposedHeight(windowCocoa: CGRect, bar: CGRect) -> CGFloat? {
        let intersection = windowCocoa.intersection(bar)
        guard !intersection.isNull, intersection.height > 1 else { return nil }
        let newHeight = max(80, windowCocoa.height - intersection.height)
        guard abs(newHeight - windowCocoa.height) > 1 else { return nil }
        return newHeight
    }

    /// True when the window still covers more than `tolerance` points of the
    /// bar's height. `cgFrame` is what Accessibility and the window server
    /// report (top-left origin); `bar` is in Cocoa coordinates.
    static func overlapsBar(
        cgFrame: CGRect,
        bar: CGRect,
        primaryHeight: CGFloat,
        tolerance: CGFloat = 4
    ) -> Bool {
        let cocoa = ScreenGeometry.cocoaRect(fromCGRect: cgFrame, primaryHeight: primaryHeight)
        let intersection = cocoa.intersection(bar)
        return !intersection.isNull && intersection.height > tolerance
    }

    /// Decides what to do with a window after a scan. `proposedHeight` is nil
    /// when the window is clear of the bar.
    ///
    /// Zooming a window (double-clicking its title bar, or Fill) grows it over
    /// the bar, and Omnibar shortens it. macOS then no longer treats the window
    /// as zoomed, so zooming it again grows it again instead of shrinking it.
    /// When a window Omnibar shortened grows downward again, the frame from
    /// before the first zoom is put back.
    static func fitAction(
        cgFrame: CGRect,
        proposedHeight: CGFloat?,
        memory: inout FitMemory,
        tolerance: CGFloat = TilingGeometry.frameTolerance
    ) -> FitAction {
        guard let proposedHeight else {
            if let fitted = memory.fitted,
               !TilingGeometry.framesMatch(cgFrame, fitted, tolerance: tolerance) {
                // Moved or resized since the fit, by the user or by macOS
                // undoing the zoom itself.
                memory.fitted = nil
                memory.restore = nil
            }
            memory.lastClear = cgFrame
            return .none
        }
        if let fitted = memory.fitted {
            if grewDownward(cgFrame, from: fitted, tolerance: tolerance), let restore = memory.restore {
                memory.fitted = nil
                memory.restore = nil
                return .restore(restore)
            }
            // Dragged over the bar, or it opened over the bar and has no
            // earlier frame: shorten it again and keep any earlier frame.
            return .fit(height: proposedHeight)
        }
        memory.restore = memory.lastClear
        return .fit(height: proposedHeight)
    }

    /// The top edge stayed put or rose and the window got taller, as zooming
    /// does. Dragging by the title bar moves the top edge down instead.
    static func grewDownward(_ frame: CGRect, from fitted: CGRect, tolerance: CGFloat) -> Bool {
        frame.minY <= fitted.minY + tolerance && frame.height > fitted.height + tolerance
    }

    static func recordVerifyResult(
        stillOverlaps: Bool,
        pid: pid_t,
        failCounts: inout [pid_t: Int],
        skippedPIDs: inout Set<pid_t>
    ) {
        if stillOverlaps {
            let count = (failCounts[pid] ?? 0) + 1
            failCounts[pid] = count
            if count >= 2 {
                skippedPIDs.insert(pid)
            }
        } else {
            failCounts[pid] = 0
        }
    }
}

final class OverlapResizer {
    static let shared = OverlapResizer()

    private var failCounts: [pid_t: Int] = [:]
    private var lastResize: Date = .distantPast
    private var skippedPIDs: Set<pid_t> = []
    private var pending: [WindowInfo] = []
    private var debounceWork: DispatchWorkItem?
    private var memory: [CGWindowID: FitMemory] = [:]

    func handle(windows: [WindowInfo]) {
        pending = windows
        debounceWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                self?.resizeIfNeeded()
            }
        }
        debounceWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    /// Called while auto-resize is off, so windows zoomed in the meantime are
    /// fitted afresh rather than put back to an old frame.
    func reset() {
        failCounts.removeAll()
        skippedPIDs.removeAll()
        memory.removeAll()
    }

    private func resizeIfNeeded() {
        let settings = SettingsStore.shared.settings
        guard settings.autoResizeOverlapping else { return }
        let skip = Set(settings.overlapSkipBundleIDs)
        let height = CGFloat(settings.taskbarHeight)
        let windows = pending
        let liveIDs = Set(windows.map(\.id))
        memory = memory.filter { liveIDs.contains($0.key) }
        let bars: [(displayID: CGDirectDisplayID, frame: CGRect)] = NSScreen.screens.compactMap { screen in
            guard ScreenMonitor.shared.showsTaskbar(on: screen.displayID) else { return nil }
            return (screen.displayID, ScreenGeometry.taskbarFrame(on: screen, height: height))
        }

        for window in windows {
            guard OverlapGeometry.shouldConsider(
                window,
                skipBundles: skip,
                skippedPIDs: skippedPIDs
            ) else { continue }
            guard window.isOnScreen else { continue }
            let cocoa = ScreenGeometry.cocoaRect(fromCGRect: window.frame)
            var overlap: (bar: CGRect, height: CGFloat)?
            for bar in bars where window.screenID == bar.displayID || settings.showWindowsFromAllScreens {
                if let newHeight = OverlapGeometry.proposedHeight(windowCocoa: cocoa, bar: bar.frame) {
                    overlap = (bar.frame, newHeight)
                    break
                }
            }
            guard let overlap else {
                _ = OverlapGeometry.fitAction(
                    cgFrame: window.frame,
                    proposedHeight: nil,
                    memory: &memory[window.id, default: FitMemory()]
                )
                continue
            }
            guard let element = WindowTracker.shared.axElement(for: window.id)
                ?? AXBridge.element(forWindowID: window.id, pid: window.pid) else { continue }
            // A fixed-size window can never clear the bar. Trying would
            // count as a failure and stop resizing for the whole app.
            guard AXBridge.isSettable(element, attribute: kAXSizeAttribute as String) else { continue }

            switch OverlapGeometry.fitAction(
                cgFrame: window.frame,
                proposedHeight: overlap.height,
                memory: &memory[window.id, default: FitMemory()]
            ) {
            case .none:
                break
            case .restore(let frame):
                _ = AXBridge.setFrame(element, cgFrame: frame)
            case .fit(let newHeight):
                AXBridge.setSize(element, CGSize(width: cocoa.width, height: newHeight))
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                    self?.verify(window: window, bar: overlap.bar)
                }
            }
        }
    }

    private func verify(window: WindowInfo, bar: CGRect) {
        guard let element = WindowTracker.shared.axElement(for: window.id)
                ?? AXBridge.element(forWindowID: window.id, pid: window.pid),
              let frame = AXBridge.frame(of: element) else { return }
        let stillOverlaps = OverlapGeometry.overlapsBar(
            cgFrame: frame,
            bar: bar,
            primaryHeight: ScreenGeometry.cocoaPrimaryHeight
        )
        if !stillOverlaps {
            memory[window.id, default: FitMemory()].recordFit(frame)
        }
        OverlapGeometry.recordVerifyResult(
            stillOverlaps: stillOverlaps,
            pid: window.pid,
            failCounts: &failCounts,
            skippedPIDs: &skippedPIDs
        )
    }
}
