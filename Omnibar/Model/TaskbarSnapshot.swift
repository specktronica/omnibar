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
}
