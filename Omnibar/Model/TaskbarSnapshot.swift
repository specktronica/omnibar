import CoreGraphics
import Foundation

struct TaskbarSnapshot {
    var windows: [WindowInfo]
    var itemsByScreen: [CGDirectDisplayID: [TaskItem]]
    var currentSpaces: [CGDirectDisplayID: UInt64]
    var fullscreenDisplays: Set<CGDirectDisplayID>
    var generatedAt: Date

    static let empty = TaskbarSnapshot(
        windows: [],
        itemsByScreen: [:],
        currentSpaces: [:],
        fullscreenDisplays: [],
        generatedAt: .distantPast
    )

    func items(for displayID: CGDirectDisplayID) -> [TaskItem] {
        itemsByScreen[displayID] ?? []
    }

    func isFullscreen(_ displayID: CGDirectDisplayID) -> Bool {
        fullscreenDisplays.contains(displayID)
    }
}

extension TaskbarSnapshot: Equatable {
    static func == (lhs: TaskbarSnapshot, rhs: TaskbarSnapshot) -> Bool {
        lhs.windows == rhs.windows
            && lhs.currentSpaces == rhs.currentSpaces
            && lhs.fullscreenDisplays == rhs.fullscreenDisplays
            && lhs.itemsByScreen.mapValues { $0.map(\.id) } == rhs.itemsByScreen.mapValues { $0.map(\.id) }
    }

    /// True when tiles, spaces, and badges match. Ignores window frames.
    func uiEquals(_ other: TaskbarSnapshot) -> Bool {
        guard currentSpaces == other.currentSpaces,
              fullscreenDisplays == other.fullscreenDisplays,
              windows.count == other.windows.count else {
            return false
        }
        for (lhs, rhs) in zip(windows, other.windows) where !lhs.matchesTaskbar(rhs) {
            return false
        }
        return itemsByScreen.mapValues { $0.map(\.uiKey) } == other.itemsByScreen.mapValues { $0.map(\.uiKey) }
    }
}
