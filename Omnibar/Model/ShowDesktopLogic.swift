import CoreGraphics
import Foundation

/// Windows-style Show Desktop: a thin right-edge slice that minimizes every
/// visible window, then restores that set on the next click.
enum ShowDesktopLogic {
    static let buttonWidth: CGFloat = 8
    static let tileTrailingGap: CGFloat = 4
    static let defaultTrailingInset: CGFloat = 8

    static func trailingInset(buttonEnabled: Bool) -> CGFloat {
        buttonEnabled ? buttonWidth + tileTrailingGap : defaultTrailingInset
    }

    static func showingWindows(
        from windows: [WindowInfo],
        currentSpaces: [CGDirectDisplayID: UInt64]
    ) -> [WindowInfo] {
        let current = Set(currentSpaces.values)
        return windows.filter { window in
            guard !window.isMinimized, !window.isHidden, !window.isFullscreen else { return false }
            if current.isEmpty || window.spaces.isEmpty { return true }
            return window.spaces.contains { current.contains($0) }
        }
    }

    enum Action: Equatable {
        case minimize([WindowInfo])
        case restore([CGWindowID])
        case none
    }

    /// IDs already queued to minimize count as hidden, so a second click restores
    /// even if Accessibility has not yet reported those windows as minimized.
    static func action(showing: [WindowInfo], restoreIDs: [CGWindowID]) -> Action {
        let pending = Set(restoreIDs)
        let visibleOutsideSession = showing.filter { !pending.contains($0.id) }
        if !visibleOutsideSession.isEmpty {
            return .minimize(visibleOutsideSession)
        }
        if !restoreIDs.isEmpty {
            return .restore(restoreIDs)
        }
        return .none
    }

    static func appendingRestoreList(
        existing: [CGWindowID],
        newlyMinimized: [CGWindowID]
    ) -> [CGWindowID] {
        let newSet = Set(newlyMinimized)
        return newlyMinimized + existing.filter { !newSet.contains($0) }
    }
}
