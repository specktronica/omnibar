import AppKit
import Foundation
import QuartzCore

final class TaskbarView: NSView {
    var onStartLeftClick: (() -> Void)?
    var onStartRightClick: ((NSEvent) -> Void)?
    var onShowDesktopClick: (() -> Void)?
    var onItemClick: ((TaskItem) -> Void)?
    var onItemMiddleClick: ((TaskItem) -> Void)?
    var onItemRightClick: ((TaskItem, NSEvent) -> Void)?
    var onItemHover: ((TaskItem) -> Void)?
    var onItemHoverEnd: (() -> Void)?
    var onReorder: (([TaskItem]) -> Void)?

    var isDragging: Bool { draggingView != nil }

    private let startButton = StartButtonView()
    private let startDivider = BarDivider()
    private let appsDivider = BarDivider()
    private let showDesktopButton = ShowDesktopButtonView()
    private var itemViews: [TaskItemView] = []
    private var items: [TaskItem] = []
    private var settings: AppSettings = .default
    private var draggingView: TaskItemView?
    private var dragOffset: CGFloat = 0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        startButton.onLeftClick = { [weak self] in self?.onStartLeftClick?() }
        startButton.onRightClick = { [weak self] event in self?.onStartRightClick?(event) }
        showDesktopButton.onClick = { [weak self] in self?.onShowDesktopClick?() }
        addSubview(startButton)
        addSubview(startDivider)
        appsDivider.isHidden = true
        addSubview(appsDivider)
        addSubview(showDesktopButton)
    }

    required init?(coder: NSCoder) { nil }

    func update(items: [TaskItem], settings: AppSettings) {
        startButton.apply(settings.startLogo)
        self.settings = settings
        if draggingView != nil { return }
        self.items = items
        syncViews()
        needsLayout = true
    }

    func startButtonFrame() -> NSRect {
        startButton.frame
    }

    func showDesktopButtonFrame() -> NSRect {
        showDesktopButton.isHidden ? .zero : showDesktopButton.frame
    }

    func spinStartButton(opening: Bool) {
        startButton.spin(opening: opening)
    }

    func view(forItemID id: String) -> NSView? {
        itemViews.first { $0.item.id == id }
    }

    func item(at event: NSEvent) -> TaskItem? {
        guard let window else { return nil }
        let screenPoint: NSPoint
        if let eventWindow = event.window {
            screenPoint = eventWindow.convertToScreen(NSRect(origin: event.locationInWindow, size: .zero)).origin
        } else {
            screenPoint = NSEvent.mouseLocation
        }
        guard window.frame.contains(screenPoint) else { return nil }
        let windowPoint = window.convertFromScreen(NSRect(origin: screenPoint, size: .zero)).origin
        let local = convert(windowPoint, from: nil)
        if settings.showDesktopButton, showDesktopButton.frame.contains(local) {
            return nil
        }
        return itemViews.first { $0.frame.contains(local) }?.item
    }

    override func layout() {
        super.layout()
        let height = bounds.height
        let startWidth = max(height, 36)
        let startFrame = CGRect(x: 4, y: 0, width: startWidth, height: height)
        if startButton.frame != startFrame {
            startButton.frame = startFrame
        }
        let dividerInset: CGFloat = 8
        startDivider.frame = CGRect(
            x: startButton.frame.maxX + 4,
            y: dividerInset,
            width: 1,
            height: max(0, height - dividerInset * 2)
        )
        layoutShowDesktopButton(height: height)
        if draggingView == nil {
            layoutItems()
        }
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .arrow)
    }

    private func syncViews() {
        while itemViews.count > items.count {
            itemViews.removeLast().removeFromSuperview()
        }
        while itemViews.count < items.count {
            let placeholder = TaskItem(
                id: "placeholder-\(itemViews.count)",
                kind: .pinned(bundleID: "", appName: "", icon: nil, badge: nil)
            )
            let view = TaskItemView(item: placeholder, settings: settings)
            wire(view)
            addSubview(view)
            itemViews.append(view)
        }
        for (index, item) in items.enumerated() {
            itemViews[index].apply(item: item, settings: settings)
        }
        addSubview(appsDivider, positioned: .above, relativeTo: nil)
        addSubview(showDesktopButton, positioned: .above, relativeTo: nil)
    }

    private func wire(_ view: TaskItemView) {
        view.onClick = { [weak self] item in self?.onItemClick?(item) }
        view.onMiddleClick = { [weak self] item in self?.onItemMiddleClick?(item) }
        view.onRightClick = { [weak self] item, event in self?.onItemRightClick?(item, event) }
        view.onHover = { [weak self] item in self?.onItemHover?(item) }
        view.onHoverEnd = { [weak self] in self?.onItemHoverEnd?() }
        view.onDragBegan = { [weak self] itemView, event in self?.beginDrag(itemView, event: event) }
        view.onDragged = { [weak self] itemView, event in self?.drag(itemView, event: event) }
        view.onDragEnded = { [weak self] itemView, event in self?.endDrag(itemView, event: event) }
    }

    private func layoutShowDesktopButton(height: CGFloat) {
        let enabled = settings.showDesktopButton
        showDesktopButton.isHidden = !enabled
        guard enabled else { return }
        let width = ShowDesktopLogic.buttonWidth
        let frame = CGRect(x: bounds.width - width, y: 0, width: width, height: height)
        if showDesktopButton.frame != frame {
            showDesktopButton.frame = frame
        }
    }

    private func slotMetrics() -> (originX: CGFloat, tileWidth: CGFloat, pinSplit: Int?) {
        let originX = startDivider.frame.maxX + 4
        let pinSplit = pinSplitIndex()
        let sectionGap: CGFloat = pinSplit == nil ? 0 : 9
        let trailing = ShowDesktopLogic.trailingInset(buttonEnabled: settings.showDesktopButton)
        let available = max(0, bounds.width - originX - trailing - sectionGap)
        let count = max(1, itemViews.count)
        let maxTile: CGFloat = settings.compactItems ? bounds.height + 16 : 220
        let minTile: CGFloat = settings.compactItems ? bounds.height + 8 : 72
        var tileWidth = min(maxTile, max(minTile, available / CGFloat(count)))
        if CGFloat(itemViews.count) * tileWidth > available, itemViews.count > 0 {
            tileWidth = max(bounds.height, available / CGFloat(itemViews.count))
        }
        return (originX, floor(tileWidth), pinSplit)
    }

    private func pinSplitIndex() -> Int? {
        let split = items.firstIndex { !Self.isPinnedSection($0) } ?? items.count
        guard split > 0, split < items.count else { return nil }
        return split
    }

    private static func isPinnedSection(_ item: TaskItem) -> Bool {
        if item.isPinnedLauncher { return true }
        if let id = item.bundleID { return PinStore.shared.isPinned(id) }
        return false
    }

    private func itemOriginX(index: Int, originX: CGFloat, tileWidth: CGFloat, pinSplit: Int?) -> CGFloat {
        let extra: CGFloat = (pinSplit.map { index >= $0 } ?? false) ? 9 : 0
        return originX + CGFloat(index) * tileWidth + extra
    }

    private func layoutItems(animateSiblings: Bool = false) {
        let (originX, tileWidth, pinSplit) = slotMetrics()
        let chrome: CGFloat = 2
        let height = bounds.height - chrome
        let originY = chrome / 2
        if let view = draggingView {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            view.frame.size = CGSize(width: tileWidth, height: height)
            view.frame.origin.y = originY
            CATransaction.commit()
        }
        let limitX = bounds.width - ShowDesktopLogic.trailingInset(buttonEnabled: settings.showDesktopButton)
        let frames: [(TaskItemView, CGRect)] = itemViews.enumerated().compactMap { index, view in
            guard view !== draggingView else { return nil }
            let x = min(
                itemOriginX(index: index, originX: originX, tileWidth: tileWidth, pinSplit: pinSplit),
                limitX
            )
            let frame = CGRect(
                x: x,
                y: originY,
                width: min(tileWidth, max(0, limitX - x)),
                height: height
            )
            return (view, frame)
        }
        let dividerInset: CGFloat = 8
        let dividerFrame: CGRect? = pinSplit.map { split in
            CGRect(
                x: originX + CGFloat(split) * tileWidth + 4,
                y: dividerInset,
                width: 1,
                height: max(0, bounds.height - dividerInset * 2)
            )
        }
        if animateSiblings {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.12
                ctx.allowsImplicitAnimation = true
                ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                for (view, frame) in frames {
                    view.animator().frame = frame
                }
                if let dividerFrame {
                    appsDivider.isHidden = false
                    appsDivider.animator().frame = dividerFrame
                }
            }
        } else {
            for (view, frame) in frames {
                view.frame = frame
            }
            if let dividerFrame {
                appsDivider.isHidden = false
                appsDivider.frame = dividerFrame
            }
        }
        if dividerFrame == nil {
            appsDivider.isHidden = true
        }
    }

    private func beginDrag(_ view: TaskItemView, event: NSEvent) {
        guard settings.allowDragReorder else { return }
        draggingView = view
        let local = convert(event.locationInWindow, from: nil)
        dragOffset = local.x - view.frame.minX
        view.layer?.zPosition = 10
    }

    private func drag(_ view: TaskItemView, event: NSEvent) {
        guard draggingView === view else { return }
        let local = convert(event.locationInWindow, from: nil)
        let (originX, tileWidth, pinSplit) = slotMetrics()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        view.frame = CGRect(
            x: local.x - dragOffset,
            y: 1,
            width: tileWidth,
            height: bounds.height - 2
        )
        CATransaction.commit()
        guard let from = itemViews.firstIndex(where: { $0 === view }) else { return }
        var midX = view.frame.midX
        if let pinSplit {
            let splitX = originX + CGFloat(pinSplit) * tileWidth
            if midX >= splitX + 4 {
                midX -= 9
            }
        }
        let target = DragReorderController.targetIndex(
            dragMidX: midX,
            current: from,
            count: itemViews.count,
            originX: originX,
            tileWidth: tileWidth
        )
        if target != from {
            let item = items.remove(at: from)
            items.insert(item, at: target)
            itemViews.remove(at: from)
            itemViews.insert(view, at: target)
            layoutItems(animateSiblings: true)
        }
    }

    private func endDrag(_ view: TaskItemView, event: NSEvent) {
        _ = event
        view.layer?.zPosition = 0
        draggingView = nil
        onReorder?(items)
        needsLayout = true
    }
}

private final class BarDivider: NSView {
    override var isOpaque: Bool { false }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.separatorColor.withAlphaComponent(0.45).setFill()
        bounds.fill()
    }
}
