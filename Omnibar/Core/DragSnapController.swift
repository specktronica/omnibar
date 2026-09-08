import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

/// Watches window drags from other apps and snaps the window to a tile when
/// the cursor is released on a screen edge. Uses global `NSEvent` monitors,
/// which need only Accessibility; no event tap is installed.
final class DragSnapController {
    static let shared = DragSnapController()

    /// Movement from the mouse-down point before the drag is inspected.
    private static let startDistance: CGFloat = 4
    /// Minimum origin change that counts as a window move.
    private static let moveThreshold: CGFloat = 3
    /// Minimum interval between Accessibility frame reads during a drag.
    private static let pollInterval: TimeInterval = 0.04
    /// Delay before applying the tile so the dragged app finishes its own move.
    private static let applyDelay: TimeInterval = 0.05
    /// Follow-up checks after the first apply, each relative to the previous
    /// step. macOS's own edge tiling (macOS 15+) animates the window to its
    /// tile for about 0.35 s after mouse-up and ignores Accessibility frame
    /// changes until roughly 0.6 s, so the first check waits past that.
    private static let verifyDelays: [TimeInterval] = [0.7, 0.5, 0.5]

    /// macOS 15 and later tile windows dragged to a screen edge on their own
    /// (System Settings → Desktop & Dock → “Tile by dragging windows to screen
    /// edges”). The default is on; the key is absent until the user changes it.
    static var systemEdgeTilingEnabled: Bool {
        guard #available(macOS 15, *) else { return false }
        let defaults = UserDefaults(suiteName: "com.apple.WindowManager")
        return defaults?.object(forKey: "EnableTilingByEdgeDrag") as? Bool ?? true
    }

    static let systemWindowsSettingsURL = URL(string: "x-apple.systempreferences:com.apple.Desktop-Settings.extension")

    /// Layer-0 window of another app found under the mouse-down point.
    private struct Hit {
        var id: CGWindowID
        var pid: pid_t
        /// `kCGWindowBounds` at mouse-down (CG coordinates).
        var frame: CGRect
    }

    private struct Drag {
        var downPoint: NSPoint
        var hit: Hit?
        /// Started over the Taskbar, over a non-tileable window, or turned out
        /// to be a resize. Nothing else happens until mouse-up.
        var ignored = false
        var resolved = false
        var window: AXElementRef?
        var isMoving = false
        var lastPoll: TimeInterval = 0
        var zone: (tile: Tile, displayID: CGDirectDisplayID)?
    }

    private var monitors: [Any] = []
    private var settingsObserver: NSObjectProtocol?
    private var drag: Drag?
    private lazy var preview = SnapPreviewPanel()

    func start() {
        if settingsObserver == nil {
            settingsObserver = NotificationCenter.default.addObserver(
                forName: .omnibarSettingsDidChange,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.applySettings()
                }
            }
        }
        applySettings()
    }

    func stop() {
        if let settingsObserver {
            NotificationCenter.default.removeObserver(settingsObserver)
            self.settingsObserver = nil
        }
        removeMonitors()
    }

    private func applySettings() {
        if SettingsStore.shared.settings.dragToTileEnabled {
            installMonitors()
        } else {
            removeMonitors()
        }
    }

    private func installMonitors() {
        guard monitors.isEmpty else { return }
        let down = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
            let point = NSEvent.mouseLocation
            Task { @MainActor in
                self?.handleMouseDown(at: point)
            }
        }
        let dragged = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDragged) { [weak self] _ in
            let point = NSEvent.mouseLocation
            let time = ProcessInfo.processInfo.systemUptime
            Task { @MainActor in
                self?.handleMouseDragged(at: point, time: time)
            }
        }
        let up = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { [weak self] _ in
            Task { @MainActor in
                self?.handleMouseUp()
            }
        }
        monitors = [down, dragged, up].compactMap { $0 }
    }

    private func removeMonitors() {
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors.removeAll()
        drag = nil
        preview.hide()
    }

    /// The window under the cursor is captured now, before it starts to follow
    /// the cursor. Only the CG window list is consulted here; the Accessibility
    /// element is resolved once the drag has actually started.
    private func handleMouseDown(at point: NSPoint) {
        var next = Drag(downPoint: point)
        if ScreenMonitor.shared.ownsCursor(point) {
            next.ignored = true
        } else if let hit = Self.window(under: point) {
            next.hit = hit
        } else {
            next.ignored = true
        }
        drag = next
    }

    private func handleMouseDragged(at point: NSPoint, time: TimeInterval) {
        guard var current = drag, !current.ignored else { return }
        defer { drag = current }

        if !current.resolved {
            let dx = point.x - current.downPoint.x
            let dy = point.y - current.downPoint.y
            guard hypot(dx, dy) > Self.startDistance else { return }
            current.resolved = true
            guard let hit = current.hit,
                  let element = WindowTracker.shared.axElement(for: hit.id)
                    ?? AXBridge.element(forWindowID: hit.id, pid: hit.pid),
                  WindowTiler.isTileable(element) else {
                current.ignored = true
                return
            }
            current.window = AXElementRef(element)
        } else {
            guard time - current.lastPoll >= Self.pollInterval else { return }
        }
        current.lastPoll = time

        guard let window = current.window, let startFrame = current.hit?.frame else {
            current.ignored = true
            return
        }

        if !current.isMoving {
            guard let frame = AXBridge.frame(of: window.element) else { return }
            let sizeChanged = abs(frame.width - startFrame.width) > 1 || abs(frame.height - startFrame.height) > 1
            if sizeChanged {
                current.ignored = true
                return
            }
            let moved = abs(frame.origin.x - startFrame.origin.x) >= Self.moveThreshold
                || abs(frame.origin.y - startFrame.origin.y) >= Self.moveThreshold
            guard moved else { return }
            current.isMoving = true
        }

        guard let screen = Self.screen(containing: point) else {
            current.zone = nil
            preview.hide()
            return
        }
        let others = NSScreen.screens.filter { $0 !== screen }.map(\.frame)
        let shared = TilingGeometry.sharedEdges(of: screen.frame, others: others)
        if let tile = TilingGeometry.snapZone(cursor: point, screenFrame: screen.frame, sharedEdges: shared) {
            current.zone = (tile, screen.displayID)
            preview.show(frame: tile.frame(in: WindowTiler.shared.usableFrame(on: screen)))
        } else {
            current.zone = nil
            preview.hide()
        }
    }

    private func handleMouseUp() {
        guard let finished = drag else { return }
        drag = nil
        preview.hide()
        guard !finished.ignored,
              finished.isMoving,
              let zone = finished.zone,
              let window = finished.window else { return }
        let windowID = finished.hit?.id
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.applyDelay) {
            guard let screen = NSScreen.screens.first(where: { $0.displayID == zone.displayID }),
                  let applied = WindowTiler.shared.apply(zone.tile, to: window.element, windowID: windowID, on: screen)
            else { return }
            let target = zone.tile.frame(in: WindowTiler.shared.usableFrame(on: screen))
            Self.verify(
                tile: zone.tile,
                window: window,
                windowID: windowID,
                displayID: zone.displayID,
                target: target,
                lastAccepted: applied,
                delays: Self.verifyDelays[...]
            )
        }
    }

    /// Re-applies the tile if something moved the window off it after the
    /// first apply. A frame that matches the target, or the frame the app
    /// settled on the last time the tile was accepted (apps that clamp their
    /// size), counts as done. An apply that leaves the frame unchanged was
    /// ignored and does not update `lastAccepted`.
    private static func verify(
        tile: Tile,
        window: AXElementRef,
        windowID: CGWindowID?,
        displayID: CGDirectDisplayID,
        target: CGRect,
        lastAccepted: CGRect,
        delays: ArraySlice<TimeInterval>
    ) {
        guard let delay = delays.first else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            guard let screen = NSScreen.screens.first(where: { $0.displayID == displayID }),
                  let currentCG = AXBridge.frame(of: window.element) else { return }
            let current = ScreenGeometry.cocoaRect(fromCGRect: currentCG)
            if TilingGeometry.framesMatch(current, target) || TilingGeometry.framesMatch(current, lastAccepted) {
                return
            }
            var accepted = lastAccepted
            if let observed = WindowTiler.shared.apply(tile, to: window.element, windowID: windowID, on: screen),
               !TilingGeometry.framesMatch(observed, current, tolerance: 1) {
                accepted = observed
            }
            verify(
                tile: tile,
                window: window,
                windowID: windowID,
                displayID: displayID,
                target: target,
                lastAccepted: accepted,
                delays: delays.dropFirst()
            )
        }
    }

    /// Screen whose frame contains the cursor. The right and top edges are
    /// exclusive in `CGRect.contains`, so the frame is grown by one point.
    private static func screen(containing point: NSPoint) -> NSScreen? {
        NSScreen.screens.first { $0.frame.contains(point) }
            ?? NSScreen.screens.first { $0.frame.insetBy(dx: -1, dy: -1).contains(point) }
    }

    /// Frontmost layer-0 window of another app under `cocoaPoint`.
    private static func window(under cocoaPoint: NSPoint) -> Hit? {
        let cgPoint = CGPoint(x: cocoaPoint.x, y: ScreenGeometry.cocoaPrimaryHeight - cocoaPoint.y)
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] ?? []
        let selfPID = ProcessInfo.processInfo.processIdentifier
        for info in list {
            let layer = (info[kCGWindowLayer as String] as? NSNumber)?.int32Value ?? 0
            guard layer == 0 else { continue }
            guard let pid = (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
                  pid != selfPID,
                  let id = (info[kCGWindowNumber as String] as? NSNumber)?.uint32Value,
                  let bounds = info[kCGWindowBounds as String] as? [String: CGFloat] else {
                continue
            }
            let frame = CGRect(
                x: bounds["X"] ?? 0,
                y: bounds["Y"] ?? 0,
                width: bounds["Width"] ?? 0,
                height: bounds["Height"] ?? 0
            )
            if frame.contains(cgPoint) {
                return Hit(id: id, pid: pid_t(pid), frame: frame)
            }
        }
        return nil
    }
}

