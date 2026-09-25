import Foundation

/// Where a window sits relative to the Space a taskbar is showing.
nonisolated enum SpacePresence {
    static let anotherSpacePhrase = "Another Space"

    struct RunningMark: Equatable {
        /// Hollow when that window is on another Space.
        var ring: Bool
        /// The single-window pill widens only while that window is active here.
        var widens: Bool
    }

    /// Known assignment that does not include this taskbar's Space.
    static func isOnAnotherSpace(_ window: WindowInfo, currentSpace: UInt64?) -> Bool {
        guard let currentSpace, !window.spaces.isEmpty else { return false }
        return !window.spaces.contains(currentSpace)
    }

    static func labeled(_ title: String, onAnotherSpace: Bool) -> String {
        guard onAnotherSpace else { return title }
        return "\(title) - \(anotherSpacePhrase)"
    }

    /// Secondary line for one window. A mixed group keeps the phrase on that window.
    static func detail(title: String?, onAnotherSpace: Bool) -> String? {
        switch (title, onAnotherSpace) {
        case let (title?, true):
            return "\(title) - \(anotherSpacePhrase)"
        case (nil, true):
            return anotherSpacePhrase
        case let (title?, false):
            return title
        case (nil, false):
            return nil
        }
    }

    /// One window keeps the pill. Grouping draws two dots for two windows and three for more.
    static func markCount(windowCount: Int, grouped: Bool) -> Int {
        guard windowCount > 0 else { return 0 }
        guard grouped, windowCount > 1 else { return 1 }
        return min(3, windowCount)
    }

    /// This-Space windows come first. With more than three windows, the last
    /// mark stays a ring when any window is on another Space.
    static func runningMarks(
        windows: [WindowInfo],
        grouped: Bool,
        currentSpace: UInt64?
    ) -> [RunningMark] {
        let count = markCount(windowCount: windows.count, grouped: grouped)
        guard count > 0 else { return [] }
        if count == 1 {
            let away = windows.allSatisfy { isOnAnotherSpace($0, currentSpace: currentSpace) }
            let widens = windows.contains { $0.isActive && !isOnAnotherSpace($0, currentSpace: currentSpace) }
            return [RunningMark(ring: away, widens: widens)]
        }
        let here = windows.filter { !isOnAnotherSpace($0, currentSpace: currentSpace) }
        let elsewhere = windows.filter { isOnAnotherSpace($0, currentSpace: currentSpace) }
        var rings = (here + elsewhere).prefix(count).map { isOnAnotherSpace($0, currentSpace: currentSpace) }
        if windows.count > count, !elsewhere.isEmpty {
            rings[rings.count - 1] = true
        }
        return rings.map { RunningMark(ring: $0, widens: false) }
    }
}
