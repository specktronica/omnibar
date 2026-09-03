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
    private var previousOrderKeys: Set<String> = []
    private var isRunning = false
    private var coalescer = ScanCoalescer()
    private var debounceWork: DispatchWorkItem?
    private var lastScan = ScanResult.empty
    private var elementCache: [CGWindowID: AXElementRef] = [:]
    private var lastSettings: AppSettings = .default
    private var appMetaByPID: [pid_t: ScanRequest.App] = [:]

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

    func start() {
        guard !isRunning else { return }
        isRunning = true
        lastSettings = SettingsStore.shared.settings
        registerWorkspaceNotifications()
        refreshObservers()
        schedulePoll()
        DockBadgeReader.shared.start()
        requestScan(immediate: true)
    }

    func stop() {
        isRunning = false
        pollTimer?.invalidate()
        pollTimer = nil
        debounceWork?.cancel()
        debounceWork = nil
        coalescer = ScanCoalescer()
        observers.removeAll()
        appMetaByPID.removeAll()
        for token in workspaceObservers {
            NotificationCenter.default.removeObserver(token)
            NSWorkspace.shared.notificationCenter.removeObserver(token)
        }
        workspaceObservers.removeAll()
        DockBadgeReader.shared.stop()
    }

    func axElement(for windowID: CGWindowID) -> AXUIElement? {
        elementCache[windowID]?.element
    }

    func reconcile() {
        requestScan(immediate: true)
    }

    func rebuildFromLastScan() {
        guard isRunning else { return }
        rebuildItems(from: lastScan)
    }

    func requestScan(immediate: Bool = false) {
        guard isRunning else { return }
        if immediate {
            debounceWork?.cancel()
            debounceWork = nil
            startScanIfNeeded()
            return
        }
        debounceWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.startScanIfNeeded()
        }
        debounceWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }

    private func handleSettingsDidChange() {
        let settings = SettingsStore.shared.settings
        let previous = lastSettings
        lastSettings = settings
        if settings.matchesExceptStartLogo(previous) {
            return
        }
        schedulePoll()
        rebuildFromLastScan()
        requestScan()
    }

    private func schedulePoll() {
        pollTimer?.invalidate()
        let interval = max(0.5, SettingsStore.shared.settings.pollInterval)
        pollTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.requestScan(immediate: true)
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
                    if name == NSWorkspace.didLaunchApplicationNotification
                        || name == NSWorkspace.didTerminateApplicationNotification {
                        self?.refreshObservers()
                    }
                    self?.requestScan()
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
                        self?.handleSettingsDidChange()
                    } else if name == .omnibarBlacklistDidChange {
                        self?.rebuildFromLastScan()
                        self?.requestScan()
                    } else if name == .omnibarPinsDidChange
                        || name == .omnibarBadgesDidChange {
                        self?.rebuildFromLastScan()
                    } else {
                        self?.requestScan()
                    }
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
                WindowTracker.shared.requestScan()
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

    private func startScanIfNeeded() {
        guard isRunning else { return }
        guard PermissionsManager.shared.accessibilityTrusted || AXIsProcessTrusted() else {
            lastScan = .empty
            elementCache = [:]
            publish(.empty)
            return
        }
        guard coalescer.requestStart() else { return }
        let request = makeScanRequest()
        Task { [weak self] in
            let result = await WindowScanner.shared.scan(request)
            await MainActor.run {
                self?.finishScan(result)
            }
        }
    }

    private func finishScan(_ result: ScanResult) {
        lastScan = result
        elementCache = result.elements
        rebuildItems(from: result)
        if coalescer.finish() {
            startScanIfNeeded()
        }
    }

    private func makeScanRequest() -> ScanRequest {
        let running = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
        let livePIDs = Set(running.map(\.processIdentifier))
        appMetaByPID = appMetaByPID.filter { livePIDs.contains($0.key) }
        let apps = running.map { app -> ScanRequest.App in
            let pid = app.processIdentifier
            if let cached = appMetaByPID[pid] {
                return ScanRequest.App(
                    pid: cached.pid,
                    bundleID: cached.bundleID,
                    appName: cached.appName,
                    isHidden: app.isHidden
                )
            }
            let meta = ScanRequest.App(
                pid: pid,
                bundleID: app.bundleIdentifier,
                appName: app.localizedName ?? app.bundleIdentifier ?? "App",
                isHidden: app.isHidden
            )
            appMetaByPID[pid] = meta
            return meta
        }
        let screens = NSScreen.screens.map {
            ScanRequest.Screen(displayID: $0.displayID, cocoaFrame: $0.frame)
        }
        return ScanRequest(
            apps: apps,
            frontAppPID: NSWorkspace.shared.frontmostApplication?.processIdentifier,
            screens: screens,
            cocoaPrimaryHeight: ScreenGeometry.cocoaPrimaryHeight,
            blacklist: BlacklistStore.shared.bundleIDs,
            ignoredBundleIDs: ignoredBundleIDs
        )
    }

    private func rebuildItems(from scan: ScanResult) {
        let settings = SettingsStore.shared.settings
        var windows = scan.windows
        if !BlacklistStore.shared.bundleIDs.isEmpty {
            let blocked = BlacklistStore.shared.bundleIDs
            windows = windows.filter { window in
                guard let bundleID = window.bundleID else { return true }
                return !blocked.contains(bundleID)
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
                currentSpace: scan.currentSpaces[screen.displayID],
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
            currentSpaces: scan.currentSpaces,
            fullscreenDisplays: scan.fullscreenDisplays,
            generatedAt: Date()
        )
        publish(snap)

        if settings.autoResizeOverlapping {
            OverlapResizer.shared.handle(windows: windows)
        }
    }

    private func publish(_ snap: TaskbarSnapshot) {
        let uiChanged = !snap.uiEquals(snapshot)
        snapshot = snap
        guard uiChanged else { return }
        NotificationCenter.default.post(name: .omnibarSnapshotDidChange, object: snap)
    }
}
