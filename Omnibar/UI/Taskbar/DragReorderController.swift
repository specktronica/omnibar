import AppKit
import Foundation

final class DragReorderController {
    // Drag handling lives on TaskbarView; this type documents the drop mapping used by tests.
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
