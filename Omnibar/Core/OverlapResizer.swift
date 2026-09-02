import AppKit
import Foundation

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
                if window.isFullscreen || window.isMinimized || window.isHidden { continue }
                if let bundle = window.bundleID, skip.contains(bundle) { continue }
                if skippedPIDs.contains(window.pid) { continue }
                guard window.screenID == screen.displayID || settings.showWindowsFromAllScreens else { continue }
                let cocoa = ScreenGeometry.cocoaRect(fromCGRect: window.frame)
                let intersection = cocoa.intersection(bar)
                guard !intersection.isNull, intersection.height > 1 else { continue }

                let newHeight = max(80, cocoa.height - intersection.height)
                guard abs(newHeight - cocoa.height) > 1 else { continue }
                guard let element = AXBridge.element(forWindowID: window.id, pid: window.pid) else { continue }

                AXBridge.setSize(element, CGSize(width: cocoa.width, height: newHeight))

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                    self?.verify(window: window, bar: bar)
                }
            }
        }
    }

    private func verify(window: WindowInfo, bar: CGRect) {
        guard let element = AXBridge.element(forWindowID: window.id, pid: window.pid),
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
        if !intersection.isNull, intersection.height > 4 {
            let count = (failCounts[window.pid] ?? 0) + 1
            failCounts[window.pid] = count
            if count >= 2 {
                skippedPIDs.insert(window.pid)
            }
        } else {
            failCounts[window.pid] = 0
        }
    }
}
