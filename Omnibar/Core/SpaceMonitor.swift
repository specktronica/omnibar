import CoreGraphics
import Foundation

final class SpaceMonitor {
    static let shared = SpaceMonitor()

    func isFullscreen(display displayID: CGDirectDisplayID) -> Bool {
        WindowTracker.shared.snapshot.isFullscreen(displayID)
    }

    func currentSpace(for displayID: CGDirectDisplayID) -> UInt64? {
        WindowTracker.shared.snapshot.currentSpaces[displayID]
    }
}
