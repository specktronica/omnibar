import AppKit
import Foundation

final class TaskbarPanel: NSPanel {
    private(set) var screenID: CGDirectDisplayID
    private var currentScreen: NSScreen
    private let effectView = NSVisualEffectView()
    private let overlay = NSView()
    private let taskbarView = TaskbarView()
    private let startMenu = StartMenuPanel()
    private let thumbnail = ThumbnailPopover()
    private var hoverWork: DispatchWorkItem?
    private var autoHidden = false
    private(set) var isSuppressed = false
    private var hoverItem: TaskItem?

    init(screen: NSScreen) {
        currentScreen = screen
        screenID = screen.displayID
        let height = CGFloat(SettingsStore.shared.settings.taskbarHeight)
        let frame = ScreenGeometry.taskbarFrame(on: screen, height: height)
        super.init(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        configureWindow()
        configureContent()
        taskbarView.onStartLeftClick = { [weak self] in self?.handleStartLeftClick() }
        taskbarView.onStartRightClick = { [weak self] event in self?.showStartActionMenu(event) }
        startMenu.onPresented = { [weak self] in self?.taskbarView.spinStartButton(opening: true) }
        startMenu.onDismissed = { [weak self] in self?.taskbarView.spinStartButton(opening: false) }
        taskbarView.onItemClick = { item in WindowActions.handlePrimaryClick(item) }
        taskbarView.onItemRightClick = { [weak self] item, event in
            self?.showContextMenu(for: item, event: event)
        }
        taskbarView.onItemHover = { [weak self] item in
            self?.scheduleThumbnail(for: item)
        }
        taskbarView.onItemHoverEnd = { [weak self] in
            self?.cancelThumbnail(immediately: false)
        }
        taskbarView.onReorder = { [weak self] items in
            self?.commitReorder(items)
        }
        orderFrontRegardless()
        applyAppearance()
        applySnapshot(WindowTracker.shared.snapshot)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func updateScreen(_ screen: NSScreen) {
        currentScreen = screen
        screenID = screen.displayID
        layoutBar()
    }

    func applySnapshot(_ snapshot: TaskbarSnapshot) {
        let items = snapshot.items(for: screenID)
        taskbarView.update(items: items, settings: SettingsStore.shared.settings)
        applyAppearance()
        if !taskbarView.isDragging {
            layoutBar()
        }
    }

    func setSuppressed(_ suppressed: Bool) {
        isSuppressed = suppressed
        if suppressed {
            orderOut(nil)
            startMenu.dismiss()
            thumbnail.dismiss()
        } else if !autoHidden {
            orderFrontRegardless()
        }
    }

    func setAutoHidden(_ hidden: Bool) {
        autoHidden = hidden
        layoutBar()
        if hidden {
            startMenu.dismiss()
            thumbnail.dismiss()
        }
    }

    func ownsCursor(_ point: NSPoint) -> Bool {
        frame.contains(point) || startMenu.isVisible && startMenu.frame.contains(point)
            || thumbnail.isVisible && thumbnail.frame.contains(point)
    }

    private func configureWindow() {
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = true
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.popUpMenuWindow)) - 1)
        sharingType = .none
        animationBehavior = .utilityWindow
        ignoresMouseEvents = false
    }

    private func configureContent() {
        let host = NSView(frame: .zero)
        host.wantsLayer = true
        contentView = host

        effectView.material = .menu
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        host.addSubview(effectView)

        overlay.wantsLayer = true
        host.addSubview(overlay)
        host.addSubview(taskbarView)
    }

    private func layoutBar() {
        let settings = SettingsStore.shared.settings
        let height = CGFloat(settings.taskbarHeight)
        var frame = ScreenGeometry.taskbarFrame(on: currentScreen, height: height)
        if autoHidden && settings.autoHide && !isSuppressed {
            frame.origin.y = currentScreen.frame.minY - height + 2
        }
        if self.frame != frame {
            setFrame(frame, display: true)
        }
        if !isSuppressed, !isVisible {
            orderFrontRegardless()
        }
        effectView.frame = contentView?.bounds ?? .zero
        overlay.frame = contentView?.bounds ?? .zero
        taskbarView.frame = contentView?.bounds ?? .zero
        let alpha = max(0, min(1, 1 - settings.transparency))
        overlay.layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(alpha * 0.92).cgColor
        if let contentView {
            contentView.wantsLayer = true
            contentView.layer?.cornerRadius = 0
        }
    }

    private func applyAppearance() {
        let settings = SettingsStore.shared.settings
        if settings.followSystemAppearance {
            appearance = nil
        } else if settings.forceDarkMode {
            appearance = NSAppearance(named: .darkAqua)
        } else {
            appearance = NSAppearance(named: .aqua)
        }
        startMenu.appearance = appearance
        thumbnail.appearance = appearance
    }

    private func handleStartLeftClick() {
        switch SettingsStore.shared.settings.startButtonAction {
        case .startMenu:
            toggleStartMenu()
        case .launchpad:
            taskbarView.spinStartButton(opening: true)
            StartMenuPanel.openLaunchpad()
        case .spotlight:
            taskbarView.spinStartButton(opening: true)
            StartMenuPanel.openSpotlight()
        }
    }

    private func toggleStartMenu() {
        if startMenu.isVisible {
            startMenu.dismiss()
        } else {
            let button = taskbarView.startButtonFrame()
            let rect = convertToScreen(button)
            startMenu.present(from: rect, screen: currentScreen)
        }
    }

    private func showStartActionMenu(_ event: NSEvent) {
        let menu = NSMenu()
        for action in StartButtonAction.allCases {
            let item = NSMenuItem(
                title: action.title,
                action: #selector(selectStartAction(_:)),
                keyEquivalent: ""
            )
            item.representedObject = action.rawValue
            item.state = SettingsStore.shared.settings.startButtonAction == action ? .on : .off
            item.target = self
            menu.addItem(item)
        }
        NSMenu.popUpContextMenu(menu, with: event, for: taskbarView)
    }

    @objc private func selectStartAction(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let action = StartButtonAction(rawValue: raw) else { return }
        SettingsStore.shared.update { $0.startButtonAction = action }
    }

    private func showContextMenu(for item: TaskItem, event: NSEvent) {
        let menu = TaskContextMenu.build(item: item, displayID: screenID)
        NSMenu.popUpContextMenu(menu, with: event, for: taskbarView)
    }

    private func scheduleThumbnail(for item: TaskItem) {
        hoverItem = item
        hoverWork?.cancel()
        let delay = SettingsStore.shared.settings.thumbnailDelay
        let work = DispatchWorkItem { [weak self] in
            self?.showThumbnail(for: item)
        }
        hoverWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func cancelThumbnail(immediately: Bool) {
        hoverWork?.cancel()
        hoverItem = nil
        if immediately {
            thumbnail.dismiss()
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                guard let self, self.hoverItem == nil, !self.thumbnail.isHovered else { return }
                self.thumbnail.dismiss()
            }
        }
    }

    private func showThumbnail(for item: TaskItem) {
        guard !item.windows.isEmpty else { return }
        guard let view = taskbarView.view(forItemID: item.id) else { return }
        let rect = convertToScreen(view.frame)
        thumbnail.present(item: item, anchor: rect)
    }

    private func commitReorder(_ items: [TaskItem]) {
        var pinIDs: [String] = []
        var windowKeys: [String] = []
        for item in items {
            switch item.kind {
            case .pinned(let id, _, _, _):
                pinIDs.append(id)
            case .window(let window):
                if let bundle = window.bundleID, PinStore.shared.isPinned(bundle) {
                    if !pinIDs.contains(bundle) { pinIDs.append(bundle) }
                }
                windowKeys.append(window.orderKey)
            case .grouped(let bundleID, _, let windows, _):
                if let bundleID, PinStore.shared.isPinned(bundleID), !pinIDs.contains(bundleID) {
                    pinIDs.append(bundleID)
                }
                windowKeys.append(contentsOf: windows.map(\.orderKey))
            }
        }
        if !pinIDs.isEmpty {
            let existing = PinStore.shared.pinnedBundleIDs
            let remaining = existing.filter { !pinIDs.contains($0) }
            PinStore.shared.replace(pinIDs + remaining)
        }
        OrderStore.shared.replace(windowKeys)
        WindowTracker.shared.rebuildFromLastScan()
    }
}
