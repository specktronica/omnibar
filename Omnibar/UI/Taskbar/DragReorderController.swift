import AppKit
import Foundation

final class DragReorderController {
    // Drag handling lives on TaskbarView; this type documents the drop mapping used by tests.
    static func targetIndex(
        dragMidX: CGFloat,
        current: Int,
        count: Int,
        originX: CGFloat,
        tileWidth: CGFloat,
        hysteresis: CGFloat = 8
    ) -> Int {
        guard count > 0 else { return 0 }
        let held = max(0, min(count - 1, current))
        guard tileWidth > 0 else { return held }
        let proposed = Int(floor((dragMidX - originX) / tileWidth))
        let clamped = max(0, min(count - 1, proposed))
        if clamped == held { return held }
        let boundary = originX + tileWidth * CGFloat(clamped > held ? held + 1 : held)
        if clamped > held {
            return dragMidX > boundary + hysteresis ? clamped : held
        }
        return dragMidX < boundary - hysteresis ? clamped : held
    }

    static func commit(items: [TaskItem]) -> (pins: [String], windowKeys: [String]) {
        var pins: [String] = []
        var windowKeys: [String] = []
        for item in items {
            switch item.kind {
            case .pinned(let id, _, _, _):
                pins.append(id)
            case .window(let window):
                windowKeys.append(window.orderKey)
            case .grouped(_, _, let windows, _):
                windowKeys.append(contentsOf: windows.map(\.orderKey))
            }
        }
        return (pins, windowKeys)
    }
}
