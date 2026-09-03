import AppKit
import Foundation

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

    func reset() {
        failCounts.removeAll()
        skippedPIDs.removeAll()
    }

    private func resizeIfNeeded() {
        let settings = SettingsStore.shared.settings
        guard settings.autoResizeOverlapping else { return }
        let skip = Set(settings.overlapSkipBundleIDs)
        let height = CGFloat(settings.taskbarHeight)
        let windows = pending

        for screen in NSScreen.screens {
            let bar = ScreenGeometry.taskbarFrame(on: screen, height: height)
            for window in windows {
                guard OverlapGeometry.shouldConsider(
                    window,
                    skipBundles: skip,
                    skippedPIDs: skippedPIDs
                ) else { continue }
                guard window.screenID == screen.displayID || settings.showWindowsFromAllScreens else { continue }
                let cocoa = ScreenGeometry.cocoaRect(fromCGRect: window.frame)
                guard let newHeight = OverlapGeometry.proposedHeight(windowCocoa: cocoa, bar: bar) else { continue }
                guard let element = WindowTracker.shared.axElement(for: window.id)
                    ?? AXBridge.element(forWindowID: window.id, pid: window.pid) else { continue }

                AXBridge.setSize(element, CGSize(width: cocoa.width, height: newHeight))

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                    self?.verify(window: window, bar: bar)
                }
            }
        }
    }

    private func verify(window: WindowInfo, bar: CGRect) {
        guard let element = WindowTracker.shared.axElement(for: window.id)
                ?? AXBridge.element(forWindowID: window.id, pid: window.pid),
              let frame = AXBridge.frame(of: element) else { return }
        let cocoa: CGRect
        if frame.origin.y < 0 || frame.maxY > ScreenGeometry.cocoaPrimaryHeight * 1.5 {
            cocoa = ScreenGeometry.cocoaRect(fromCGRect: frame)
        } else {
            cocoa = CGRect(
                x: frame.origin.x,
                y: frame.origin.y - frame.height,
                width: frame.width,
                height: frame.height
            )
        }
        let intersection = cocoa.intersection(bar)
        let stillOverlaps = !intersection.isNull && intersection.height > 4
        OverlapGeometry.recordVerifyResult(
            stillOverlaps: stillOverlaps,
            pid: window.pid,
            failCounts: &failCounts,
            skippedPIDs: &skippedPIDs
        )
    }
}
