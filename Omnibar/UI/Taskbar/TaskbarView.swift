import AppKit
import Foundation
import QuartzCore

final class TaskbarView: NSView {
    var onStartLeftClick: (() -> Void)?
    var onStartRightClick: ((NSEvent) -> Void)?
    var onItemClick: ((TaskItem) -> Void)?
    var onItemRightClick: ((TaskItem, NSEvent) -> Void)?
    var onItemHover: ((TaskItem) -> Void)?
    var onItemHoverEnd: (() -> Void)?
    var onReorder: (([TaskItem]) -> Void)?

    var isDragging: Bool { draggingView != nil }

    private let startButton = StartButtonView()
    private var itemViews: [TaskItemView] = []
    private var items: [TaskItem] = []
    private var settings: AppSettings = .default
    private var draggingView: TaskItemView?
    private var dragOffset: CGFloat = 0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        startButton.onLeftClick = { [weak self] in self?.onStartLeftClick?() }
        startButton.onRightClick = { [weak self] event in self?.onStartRightClick?(event) }
        addSubview(startButton)
    }

    required init?(coder: NSCoder) { nil }

    func update(items: [TaskItem], settings: AppSettings) {
        self.settings = settings
        if draggingView != nil { return }
        self.items = items
        syncViews()
        needsLayout = true
    }

    func startButtonFrame() -> NSRect {
        startButton.frame
    }

    func view(forItemID id: String) -> NSView? {
        itemViews.first { $0.item.id == id }
    }

    override func layout() {
        super.layout()
        let height = bounds.height
        let startWidth = max(height, 36)
        startButton.frame = CGRect(x: 4, y: 0, width: startWidth, height: height)
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
    }

    private func wire(_ view: TaskItemView) {
        view.onClick = { [weak self] item in self?.onItemClick?(item) }
        view.onRightClick = { [weak self] item, event in self?.onItemRightClick?(item, event) }
        view.onHover = { [weak self] item in self?.onItemHover?(item) }
        view.onHoverEnd = { [weak self] in self?.onItemHoverEnd?() }
        view.onDragBegan = { [weak self] itemView, event in self?.beginDrag(itemView, event: event) }
        view.onDragged = { [weak self] itemView, event in self?.drag(itemView, event: event) }
        view.onDragEnded = { [weak self] itemView, event in self?.endDrag(itemView, event: event) }
    }

    private func slotMetrics() -> (originX: CGFloat, tileWidth: CGFloat) {
        let originX = startButton.frame.maxX + 4
        let available = max(0, bounds.width - originX - 8)
        let count = max(1, itemViews.count)
        let maxTile: CGFloat = settings.compactItems ? bounds.height + 16 : 220
        let minTile: CGFloat = settings.compactItems ? bounds.height + 8 : 72
        var tileWidth = min(maxTile, max(minTile, available / CGFloat(count)))
        if CGFloat(itemViews.count) * tileWidth > available, itemViews.count > 0 {
            tileWidth = max(bounds.height, available / CGFloat(itemViews.count))
        }
        return (originX, floor(tileWidth))
    }

    private func layoutItems(animateSiblings: Bool = false) {
        let (originX, tileWidth) = slotMetrics()
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
        let frames: [(TaskItemView, CGRect)] = itemViews.enumerated().compactMap { index, view in
            guard view !== draggingView else { return nil }
            let frame = CGRect(
                x: originX + CGFloat(index) * tileWidth,
                y: originY,
                width: tileWidth,
                height: height
            )
            return (view, frame)
        }
        if animateSiblings {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.12
                ctx.allowsImplicitAnimation = true
                ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                for (view, frame) in frames {
                    view.animator().frame = frame
                }
            }
        } else {
            for (view, frame) in frames {
                view.frame = frame
            }
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
        let (originX, tileWidth) = slotMetrics()
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
        let target = DragReorderController.targetIndex(
            dragMidX: view.frame.midX,
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
