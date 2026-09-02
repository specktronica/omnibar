import AppKit
import Foundation

final class TaskbarView: NSView {
    var onStartLeftClick: (() -> Void)?
    var onStartRightClick: ((NSEvent) -> Void)?
    var onItemClick: ((TaskItem) -> Void)?
    var onItemRightClick: ((TaskItem, NSEvent) -> Void)?
    var onItemHover: ((TaskItem) -> Void)?
    var onItemHoverEnd: (() -> Void)?
    var onReorder: (([TaskItem]) -> Void)?

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
        if draggingView == nil {
            self.items = items
            syncViews()
        }
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
        layoutItems()
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

    private func layoutItems() {
        let startWidth = startButton.frame.maxX + 4
        let available = max(0, bounds.width - startWidth - 8)
        let count = max(1, itemViews.count)
        let maxTile: CGFloat = settings.iconOnly ? bounds.height + 8 : 220
        let minTile: CGFloat = settings.iconOnly ? bounds.height : 72
        var tileWidth = min(maxTile, max(minTile, available / CGFloat(count)))
        if CGFloat(itemViews.count) * tileWidth > available, itemViews.count > 0 {
            tileWidth = max(bounds.height, available / CGFloat(itemViews.count))
        }
        var x = startWidth
        for view in itemViews {
            if view === draggingView {
                let pointer = convert(window?.mouseLocationOutsideOfEventStream ?? .zero, from: nil)
                view.frame = CGRect(x: pointer.x - dragOffset, y: 2, width: tileWidth, height: bounds.height - 4)
            } else {
                view.frame = CGRect(x: x, y: 2, width: tileWidth, height: bounds.height - 4)
            }
            x += tileWidth
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
        view.frame.origin.x = local.x - dragOffset
        if let from = itemViews.firstIndex(where: { $0 === view }) {
            let mid = view.frame.midX
            var target = from
            for (index, other) in itemViews.enumerated() where other !== view {
                if mid < other.frame.midX {
                    target = index
                    break
                }
                target = index
            }
            if target != from {
                let item = items.remove(at: from)
                items.insert(item, at: target)
                itemViews.remove(at: from)
                itemViews.insert(view, at: target)
            }
        }
        layoutItems()
    }

    private func endDrag(_ view: TaskItemView, event: NSEvent) {
        _ = event
        view.layer?.zPosition = 0
        draggingView = nil
        onReorder?(items)
        needsLayout = true
    }
}
