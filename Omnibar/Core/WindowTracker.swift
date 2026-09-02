import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

final class WindowTracker {
    static let shared = WindowTracker()

    private(set) var snapshot: TaskbarSnapshot = .empty
    private var pollTimer: Timer?
    private var observers: [pid_t: AXObserverBox] = [:]
    private var workspaceObservers: [NSObjectProtocol] = []
    private let spaces: SpacesProviding
    private var previousOrderKeys: Set<String> = []
    private var isRunning = false

    private let ignoredBundleIDs: Set<String> = [
        "com.apple.dock",
        "com.apple.controlcenter",
        "com.apple.notificationcenterui",
        "com.apple.Spotlight",
        "com.apple.loginwindow",
        "com.apple.WindowManager",
        "com.apple.systemuiserver",
        "com.apple.screencaptureui",
        "com.apple.OSDUIHelper",
        "com.apple.SecurityAgent",
        "io.specktronica.omnibar"
    ]

    init(spaces: SpacesProviding = CGSBridge.shared) {
        self.spaces = spaces
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        registerWorkspaceNotifications()
        refreshObservers()
        schedulePoll()
        DockBadgeReader.shared.start()
        reconcile()
    }

    func stop() {
        isRunning = false
        pollTimer?.invalidate()
        pollTimer = nil
        observers.removeAll()
        for token in workspaceObservers {
            NotificationCenter.default.removeObserver(token)
            NSWorkspace.shared.notificationCenter.removeObserver(token)
        }
        workspaceObservers.removeAll()
        DockBadgeReader.shared.stop()
    }

    private func schedulePoll() {
        pollTimer?.invalidate()
        let interval = max(0.5, SettingsStore.shared.settings.pollInterval)
        pollTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.reconcile()
            }
        }
    }

    private func registerWorkspaceNotifications() {
        let nc = NSWorkspace.shared.notificationCenter
        let names: [NSNotification.Name] = [
            NSWorkspace.didLaunchApplicationNotification,
            NSWorkspace.didTerminateApplicationNotification,
            NSWorkspace.didActivateApplicationNotification,
            NSWorkspace.didHideApplicationNotification,
            NSWorkspace.didUnhideApplicationNotification,
            NSWorkspace.activeSpaceDidChangeNotification
        ]
        for name in names {
            let token = nc.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    self?.refreshObservers()
                    self?.reconcile()
                }
            }
            workspaceObservers.append(token)
        }
        let extra: [Notification.Name] = [
            NSApplication.didChangeScreenParametersNotification,
            .omnibarSettingsDidChange,
            .omnibarPinsDidChange,
            .omnibarBlacklistDidChange,
            .omnibarBadgesDidChange
        ]
        for name in extra {
            let token = NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    if name == .omnibarSettingsDidChange {
                        self?.schedulePoll()
                    }
                    self?.reconcile()
                }
            }
            workspaceObservers.append(token)
        }
    }

    private func refreshObservers() {
        let running = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && $0.bundleIdentifier.map { !ignoredBundleIDs.contains($0) } ?? true
        }
        let pids = Set(running.map(\.processIdentifier))
        for pid in observers.keys where !pids.contains(pid) {
            observers.removeValue(forKey: pid)
        }
        for app in running where observers[app.processIdentifier] == nil {
            attachObserver(to: app.processIdentifier)
        }
    }

    private func attachObserver(to pid: pid_t) {
        let callback: AXObserverCallback = { _, _, _, refcon in
            guard let refcon else { return }
            let box = Unmanaged<AXObserverBox>.fromOpaque(refcon).takeUnretainedValue()
            Task { @MainActor in
                WindowTracker.shared.reconcile()
                _ = box
            }
        }
        guard let box = AXObserverBox(pid: pid, callback: callback) else { return }
        let app = AXBridge.application(pid: pid)
        let notes = [
            kAXWindowCreatedNotification as String,
            kAXUIElementDestroyedNotification as String,
            kAXTitleChangedNotification as String,
            kAXWindowMiniaturizedNotification as String,
            kAXWindowDeminiaturizedNotification as String,
            kAXFocusedWindowChangedNotification as String,
            kAXWindowMovedNotification as String,
            kAXWindowResizedNotification as String,
            kAXApplicationHiddenNotification as String,
            kAXApplicationShownNotification as String
        ]
        for note in notes {
            box.add(notification: note, element: app)
        }
        observers[pid] = box
    }

    func reconcile() {
        guard isRunning else { return }
        guard PermissionsManager.shared.accessibilityTrusted || AXIsProcessTrusted() else {
            publish(.empty)
            return
        }

        let settings = SettingsStore.shared.settings
        let blacklist = BlacklistStore.shared.bundleIDs
        let onScreen = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []
        let allCGWindows = CGWindowListCopyWindowInfo([], kCGNullWindowID) as? [[String: Any]] ?? []

        var cgByID: [CGWindowID: [String: Any]] = [:]
        for info in allCGWindows {
            if let id = (info[kCGWindowNumber as String] as? NSNumber)?.uint32Value {
                cgByID[id] = info
            }
        }
        let onScreenIDs = Set(onScreen.compactMap { ($0[kCGWindowNumber as String] as? NSNumber)?.uint32Value })

        let frontAppPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        var windows: [WindowInfo] = []
        var seen = Set<CGWindowID>()

        let apps = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
        for app in apps {
            let bundleID = app.bundleIdentifier
            if let bundleID, ignoredBundleIDs.contains(bundleID) || blacklist.contains(bundleID) {
                continue
            }
            let axWindows = AXBridge.windows(forApp: app.processIdentifier)
            let focused = AXBridge.focusedWindow(forApp: app.processIdentifier)
            let focusedID = focused.flatMap { AXBridge.cgWindowID(for: $0) }

            for axWindow in axWindows {
                let role = AXBridge.role(of: axWindow)
                guard role == (kAXWindowRole as String) || role.isEmpty else { continue }
                let subrole = AXBridge.subrole(of: axWindow)
                if subrole == "AXFloatingWindow" || subrole == "AXSystemFloatingWindow" {
                    let title = AXBridge.title(of: axWindow)
                    if title.isEmpty { continue }
                }

                guard let wid = AXBridge.cgWindowID(for: axWindow) else { continue }
                if seen.contains(wid) { continue }
                seen.insert(wid)

                let cgInfo = cgByID[wid]
                let layer = (cgInfo?[kCGWindowLayer as String] as? NSNumber)?.int32Value ?? 0
                if layer != 0 { continue }

                let boundsDict = cgInfo?[kCGWindowBounds as String] as? [String: CGFloat]
                let cgFrame: CGRect
                if let boundsDict {
                    cgFrame = CGRect(
                        x: boundsDict["X"] ?? 0,
                        y: boundsDict["Y"] ?? 0,
                        width: boundsDict["Width"] ?? 0,
                        height: boundsDict["Height"] ?? 0
                    )
                } else {
                    cgFrame = AXBridge.frame(of: axWindow) ?? .zero
                }
                if cgFrame.width < 40 || cgFrame.height < 40 { continue }

                let title = AXBridge.title(of: axWindow)
                let isMinimized = AXBridge.isMinimized(axWindow)
                let isFullscreen = AXBridge.isFullscreen(axWindow)
                let info = WindowInfo(
                    id: wid,
                    pid: app.processIdentifier,
                    bundleID: bundleID,
                    appName: app.localizedName ?? bundleID ?? "App",
                    title: title,
                    frame: cgFrame,
                    screenID: ScreenGeometry.displayID(containingCGRect: cgFrame),
                    spaces: [],
                    isMinimized: isMinimized,
                    isHidden: app.isHidden,
                    isFullscreen: isFullscreen,
                    isOnScreen: onScreenIDs.contains(wid),
                    isTabbed: false,
                    isActive: (app.processIdentifier == frontAppPID) && (focusedID == wid),
                    layer: layer
                )
                windows.append(info)
            }
        }

        let spaceMap = spaces.spaces(forWindowIDs: windows.map(\.id))
        windows = windows.map { window in
            var copy = window
            copy = WindowInfo(
                id: window.id,
                pid: window.pid,
                bundleID: window.bundleID,
                appName: window.appName,
                title: window.title,
                frame: window.frame,
                screenID: window.screenID,
                spaces: spaceMap[window.id] ?? [],
                isMinimized: window.isMinimized,
                isHidden: window.isHidden,
                isFullscreen: window.isFullscreen,
                isOnScreen: window.isOnScreen,
                isTabbed: window.isTabbed,
                isActive: window.isActive,
                layer: window.layer
            )
            return copy
        }

        var currentSpaces: [CGDirectDisplayID: UInt64] = [:]
        var fullscreenDisplays: Set<CGDirectDisplayID> = []
        for screen in NSScreen.screens {
            let did = screen.displayID
            if let space = spaces.currentSpace(forDisplay: did) {
                currentSpaces[did] = space
                if spaces.isFullscreenSpace(space) {
                    fullscreenDisplays.insert(did)
                }
            }
        }

        let keys = windows.map(\.orderKey)
        let keySet = Set(keys)
        let appearing = keySet.subtracting(previousOrderKeys)
        let disappearing = previousOrderKeys.subtracting(keySet)
        OrderStore.shared.record(
            keys: keys,
            keepAcrossSpaceChange: settings.keepOrderAcrossSpaceChange,
            appearing: appearing,
            disappearing: disappearing
        )
        previousOrderKeys = keySet

        var itemsByScreen: [CGDirectDisplayID: [TaskItem]] = [:]
        for screen in NSScreen.screens {
            let screenWindows = TaskListLogic.windows(
                from: windows,
                onScreen: screen.displayID,
                currentSpace: currentSpaces[screen.displayID],
                settings: settings
            )
            itemsByScreen[screen.displayID] = TaskListLogic.items(
                windows: screenWindows,
                pinnedBundleIDs: PinStore.shared.pinnedBundleIDs,
                settings: settings,
                badge: { DockBadgeReader.shared.badge(forBundleID: $0) },
                icon: { IconCache.icon(forBundleID: $0) },
                appName: { IconCache.appName(for: $0) }
            )
        }

        let snap = TaskbarSnapshot(
            windows: windows,
            itemsByScreen: itemsByScreen,
            currentSpaces: currentSpaces,
            fullscreenDisplays: fullscreenDisplays,
            generatedAt: Date()
        )
        publish(snap)

        if settings.autoResizeOverlapping {
            OverlapResizer.shared.handle(windows: windows)
        }
    }

    private func publish(_ snap: TaskbarSnapshot) {
        snapshot = snap
        NotificationCenter.default.post(name: .omnibarSnapshotDidChange, object: snap)
    }
}
