import AppKit
import Foundation

final class ShowDesktopController {
    static let shared = ShowDesktopController()

    private var restoreFrontToBack: [(id: CGWindowID, pid: pid_t)] = []

    func toggle() {
        let snapshot = WindowTracker.shared.snapshot
        let showing = ShowDesktopLogic.showingWindows(
            from: snapshot.windows,
            currentSpaces: snapshot.currentSpaces
        )
        switch ShowDesktopLogic.action(
            showing: showing,
            restoreIDs: restoreFrontToBack.map(\.id)
        ) {
        case .minimize(let windows):
            minimize(windows)
        case .restore(let ids):
            restore(ids)
        case .none:
            break
        }
        WindowTracker.shared.requestScan(immediate: true)
    }

    private func minimize(_ windows: [WindowInfo]) {
        let showingIDs = Set(windows.map(\.id))
        let pids = Set(windows.map(\.pid))
        var zOrder = CGSBridge.shared.onScreenFrontToBackIDs(ownerPIDs: pids)
            .filter { showingIDs.contains($0.id) }
        let captured = Set(zOrder.map(\.id))
        for window in windows where !captured.contains(window.id) {
            zOrder.append((window.id, window.pid))
        }
        let newIDs = zOrder.map(\.id)
        let combined = ShowDesktopLogic.appendingRestoreList(
            existing: restoreFrontToBack.map(\.id),
            newlyMinimized: newIDs
        )
        let byNew = Dictionary(uniqueKeysWithValues: zOrder.map { ($0.id, $0) })
        let byOld = Dictionary(uniqueKeysWithValues: restoreFrontToBack.map { ($0.id, $0) })
        restoreFrontToBack = combined.map { id in
            byNew[id] ?? byOld[id] ?? (id, windows.first { $0.id == id }?.pid ?? 0)
        }
        let byWindow = Dictionary(uniqueKeysWithValues: windows.map { ($0.id, $0) })
        for pair in zOrder {
            if let window = byWindow[pair.id] {
                WindowActions.minimize(window)
            }
        }
        activateFinder()
    }

    private func restore(_ ids: [CGWindowID]) {
        let snapshot = WindowTracker.shared.snapshot
        let byID = Dictionary(uniqueKeysWithValues: snapshot.windows.map { ($0.id, $0) })
        let idSet = Set(ids)
        let pairs = restoreFrontToBack.filter { idSet.contains($0.id) }
        for pair in pairs.reversed() {
            if let window = byID[pair.id] {
                WindowActions.unminimize(window)
            }
        }
        WindowActions.restack(frontToBack: pairs)
        if let front = pairs.first {
            NSRunningApplication(processIdentifier: front.pid)?.unhide()
            NSRunningApplication(processIdentifier: front.pid)?
                .activate(options: [.activateIgnoringOtherApps])
        }
        restoreFrontToBack.removeAll()
    }

    private func activateFinder() {
        NSWorkspace.shared.runningApplications.first { $0.bundleIdentifier == "com.apple.finder" }?
            .activate(options: [.activateIgnoringOtherApps])
    }
}
