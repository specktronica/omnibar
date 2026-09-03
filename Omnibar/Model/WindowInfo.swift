import CoreGraphics
import Foundation

struct WindowInfo: Equatable, Hashable, Identifiable, Sendable {
    let id: CGWindowID
    let pid: pid_t
    let bundleID: String?
    let appName: String
    let title: String
    let frame: CGRect
    let screenID: CGDirectDisplayID?
    let spaces: [UInt64]
    let isMinimized: Bool
    let isHidden: Bool
    let isFullscreen: Bool
    let isOnScreen: Bool
    let isTabbed: Bool
    let isActive: Bool
    let layer: Int32

    var orderKey: String { "\(pid)-\(id)" }

    var displayTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? appName : title
    }

    func belongs(toSpace space: UInt64?) -> Bool {
        guard let space, !spaces.isEmpty else { return true }
        return spaces.contains(space)
    }

    /// Taskbar identity excluding `frame`, so move/resize does not refresh tiles.
    func matchesTaskbar(_ other: WindowInfo) -> Bool {
        id == other.id
            && pid == other.pid
            && bundleID == other.bundleID
            && appName == other.appName
            && title == other.title
            && screenID == other.screenID
            && spaces == other.spaces
            && isMinimized == other.isMinimized
            && isHidden == other.isHidden
            && isFullscreen == other.isFullscreen
            && isOnScreen == other.isOnScreen
            && isTabbed == other.isTabbed
            && isActive == other.isActive
            && layer == other.layer
    }
}
