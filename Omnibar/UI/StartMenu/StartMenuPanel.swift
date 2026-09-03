import AppKit
import Foundation

final class StartMenuPanel: NSPanel {
    var onPresented: (() -> Void)?
    var onDismissed: (() -> Void)?

    private let effect = NSVisualEffectView()
    private let searchField = SearchField()
    private let appList = AppListView()
    private let columnDivider = ColumnDivider()
    private let pinnedGrid = PinnedGridView()
    private let recents = RecentAppsView()
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var startButtonScreenRect: NSRect = .zero
    private var query = ""
    private var lastQuery: String?
    private var lastAppIDs: [String] = []
    private var lastPinIDs: [String] = []
    private var lastRecentIDs: [String] = []
    private var pendingSearchFocus = false
    private var presentedAt: TimeInterval = 0

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 480),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = false
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.popUpMenuWindow)))
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        effect.material = .menu
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 14
        effect.layer?.masksToBounds = true
        contentView = effect

        searchField.placeholderString = "Search"
        searchField.sendsSearchStringImmediately = true
        searchField.target = self
        searchField.action = #selector(searchChanged)
        effect.addSubview(searchField)
        effect.addSubview(appList)
        effect.addSubview(columnDivider)
        effect.addSubview(pinnedGrid)
        effect.addSubview(recents)

        let launch: (AppCatalog.CatalogApp) -> Void = { [weak self] app in
            AppCatalog.shared.launch(app)
            self?.dismiss()
        }
        appList.onLaunch = launch
        pinnedGrid.onLaunch = { [weak self] bundleID in
            AppCatalog.shared.launch(bundleID: bundleID)
            self?.dismiss()
        }
        recents.onLaunch = launch

        NotificationCenter.default.addObserver(
            forName: .omnibarCatalogDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.reload() }
        }
        NotificationCenter.default.addObserver(
            forName: .omnibarPinsDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.reload() }
        }
    }

    override var canBecomeKey: Bool { true }

    func present(from startButton: NSRect, screen: NSScreen) {
        startButtonScreenRect = startButton
        presentedAt = NSApp.currentEvent?.timestamp ?? ProcessInfo.processInfo.systemUptime
        let size = NSSize(width: 640, height: min(520, screen.visibleFrame.height - 80))
        var origin = NSPoint(x: startButton.minX, y: startButton.maxY + 8)
        if origin.x + size.width > screen.frame.maxX - 8 {
            origin.x = screen.frame.maxX - size.width - 8
        }
        setFrame(NSRect(origin: origin, size: size), display: true)
        layoutContent()
        searchField.stringValue = ""
        query = ""
        reload()
        pendingSearchFocus = true
        // Start-button clicks land on a nonactivating taskbar, so take key
        // status explicitly or the search field cannot accept typing.
        activateForSearch()
        makeKeyAndOrderFront(nil)
        orderFrontRegardless()
        focusSearchField()
        DispatchQueue.main.async { [weak self] in
            self?.focusSearchField()
        }
        installMonitor()
        onPresented?()
    }

    override func becomeKey() {
        super.becomeKey()
        if pendingSearchFocus {
            focusSearchField()
        }
    }

    func dismiss() {
        pendingSearchFocus = false
        let wasVisible = isVisible
        removeMonitor()
        orderOut(nil)
        if wasVisible {
            onDismissed?()
        }
    }

    override func cancelOperation(_ sender: Any?) {
        dismiss()
    }

    @objc private func searchChanged() {
        query = searchField.stringValue
        reload()
    }

    private func activateForSearch() {
        NSApp.activate()
        let current = NSRunningApplication.current
        if let front = NSWorkspace.shared.frontmostApplication,
           front.processIdentifier != current.processIdentifier {
            _ = current.activate(from: front)
        }
    }

    private func focusSearchField() {
        guard isVisible, pendingSearchFocus else { return }
        if firstResponder === searchField || firstResponder === searchField.currentEditor() {
            pendingSearchFocus = false
            return
        }
        makeFirstResponder(searchField)
        searchField.selectText(nil)
        if let editor = searchField.currentEditor() {
            let end = (editor.string as NSString).length
            editor.selectedRange = NSRange(location: end, length: 0)
        }
        if firstResponder === searchField || firstResponder === searchField.currentEditor() {
            pendingSearchFocus = false
        }
    }

    private func reload() {
        let groups = AppCatalog.shared.groups(matching: query)
        let appIDs = groups.flatMap { $0.apps.map(\.id) }
        if query != lastQuery || appIDs != lastAppIDs {
            lastQuery = query
            lastAppIDs = appIDs
            appList.update(groups)
        }

        let pins = PinStore.shared.pinnedBundleIDs
        if pins != lastPinIDs {
            lastPinIDs = pins
            pinnedGrid.update(pins)
        }

        let recentApps = AppCatalog.shared.recents
        let recentIDs = recentApps.map(\.id)
        if recentIDs != lastRecentIDs {
            lastRecentIDs = recentIDs
            recents.update(recentApps)
        }

        layoutContent()
    }

    private func layoutContent() {
        let bounds = effect.bounds
        let padding: CGFloat = 16
        let gutter: CGFloat = 12
        let searchHeight: CGFloat = 28
        let searchGap: CGFloat = 12
        let dividerX = bounds.width * 0.55
        let leftWidth = max(dividerX - padding - gutter, 0)
        searchField.frame = NSRect(
            x: padding,
            y: bounds.height - padding - searchHeight,
            width: leftWidth,
            height: searchHeight
        )
        appList.frame = NSRect(
            x: padding,
            y: padding,
            width: leftWidth,
            height: bounds.height - padding * 2 - searchHeight - searchGap
        )
        columnDivider.frame = NSRect(x: dividerX, y: 0, width: 1, height: bounds.height)
        let rightX = dividerX + gutter
        let rightW = max(bounds.width - rightX - padding, 0)
        pinnedGrid.frame = NSRect(x: rightX, y: bounds.height / 2, width: rightW, height: bounds.height / 2 - padding)
        recents.frame = NSRect(x: rightX, y: padding, width: rightW, height: bounds.height / 2 - padding)
    }

    private func installMonitor() {
        removeMonitor()
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] event in
            guard let self else { return event }
            if event.type == .keyDown, event.keyCode == 53 {
                self.dismiss()
                return nil
            }
            if event.type == .leftMouseDown || event.type == .rightMouseDown {
                return self.handleClickOutside(event)
            }
            return event
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            let timestamp = event.timestamp
            Task { @MainActor in
                guard let self else { return }
                let decision = StartMenuOutsideClick.decision(
                    eventWindowIsMenu: false,
                    inStartButton: false,
                    isOpeningClick: StartMenuOutsideClick.isOpeningClick(
                        eventTimestamp: timestamp,
                        presentedAt: self.presentedAt
                    )
                )
                if case .dismiss = decision {
                    self.dismiss()
                }
            }
        }
    }

    private func handleClickOutside(_ event: NSEvent) -> NSEvent? {
        let decision = StartMenuOutsideClick.decision(
            eventWindowIsMenu: event.window === self,
            inStartButton: isClickInStartButton(event),
            isOpeningClick: StartMenuOutsideClick.isOpeningClick(
                eventTimestamp: event.timestamp,
                presentedAt: presentedAt
            )
        )
        switch decision {
        case .pass:
            return event
        case .swallow:
            return nil
        case .dismiss(let swallow):
            dismiss()
            return swallow ? nil : event
        }
    }

    private func isClickInStartButton(_ event: NSEvent) -> Bool {
        guard let window = event.window else { return false }
        let point = window.convertToScreen(NSRect(origin: event.locationInWindow, size: .zero)).origin
        return startButtonScreenRect.contains(point)
    }

    private func removeMonitor() {
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }
    }

    static func openLaunchpad() {
        let candidates = [
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.launchpad.launcher"),
            URL(fileURLWithPath: "/System/Applications/Launchpad.app")
        ].compactMap { $0 }
        for url in candidates where FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { _, error in
                if error != nil {
                    Task { @MainActor in openSpotlight() }
                }
            }
            return
        }
        openSpotlight()
    }

    static func openSpotlight() {
        let source = CGEventSource(stateID: .hidSystemState)
        let down = CGEvent(keyboardEventSource: source, virtualKey: 0x31, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: 0x31, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }
}

/// Opening the menu from a non-key taskbar can re-deliver the same mouseDown
/// to click-outside monitors after `NSApp.activate()`. Ignore that click so
/// the menu is not dismissed before it appears.
nonisolated enum StartMenuOutsideClick: Sendable {
    enum Decision: Equatable {
        case pass
        case swallow
        case dismiss(swallow: Bool)
    }

    static func isOpeningClick(eventTimestamp: TimeInterval, presentedAt: TimeInterval) -> Bool {
        eventTimestamp <= presentedAt
    }

    static func decision(
        eventWindowIsMenu: Bool,
        inStartButton: Bool,
        isOpeningClick: Bool
    ) -> Decision {
        if eventWindowIsMenu { return .pass }
        if isOpeningClick { return inStartButton ? .swallow : .pass }
        return .dismiss(swallow: inStartButton)
    }
}

private final class ColumnDivider: NSView {
    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.separatorColor.withAlphaComponent(0.45).setFill()
        bounds.fill()
    }
}
