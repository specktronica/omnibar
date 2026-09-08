import CoreGraphics
import Foundation

/// A window placement relative to a screen's usable area.
nonisolated enum Tile: String, Codable, CaseIterable, Sendable {
    case leftHalf
    case rightHalf
    case topHalf
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight
    case maximize

    /// Frame for this tile inside `usable`. Coordinates are whatever space
    /// `usable` is in; halves are split on integral points so left and right
    /// tiles meet without a gap or an overlap.
    func frame(in usable: CGRect) -> CGRect {
        let halfWidth = floor(usable.width / 2)
        let halfHeight = floor(usable.height / 2)
        let rightX = usable.minX + halfWidth
        let rightWidth = usable.width - halfWidth
        let topY = usable.minY + halfHeight
        let topHeight = usable.height - halfHeight
        switch self {
        case .leftHalf:
            return CGRect(x: usable.minX, y: usable.minY, width: halfWidth, height: usable.height)
        case .rightHalf:
            return CGRect(x: rightX, y: usable.minY, width: rightWidth, height: usable.height)
        case .topHalf:
            return CGRect(x: usable.minX, y: topY, width: usable.width, height: topHeight)
        case .topLeft:
            return CGRect(x: usable.minX, y: topY, width: halfWidth, height: topHeight)
        case .topRight:
            return CGRect(x: rightX, y: topY, width: rightWidth, height: topHeight)
        case .bottomLeft:
            return CGRect(x: usable.minX, y: usable.minY, width: halfWidth, height: halfHeight)
        case .bottomRight:
            return CGRect(x: rightX, y: usable.minY, width: rightWidth, height: halfHeight)
        case .maximize:
            return usable
        }
    }
}

/// Keyboard tiling direction. Repeated presses walk `sequence`.
nonisolated enum TileDirection: Sendable {
    case left
    case right
    case up

    var sequence: [Tile] {
        switch self {
        case .left: [.leftHalf, .topLeft, .bottomLeft]
        case .right: [.rightHalf, .topRight, .bottomRight]
        case .up: [.topHalf, .maximize]
        }
    }
}

/// Modifier set for the tiling hotkeys. Raw values are persisted in settings.
nonisolated enum TilingModifiers: String, Codable, CaseIterable, Identifiable, Sendable {
    case controlOption
    case control
    case controlCommand
    case controlOptionCommand

    var id: String { rawValue }

    /// Carbon modifier mask for `RegisterEventHotKey`.
    var carbonFlags: UInt32 {
        // From Carbon Events.h: cmdKey 1<<8, shiftKey 1<<9, optionKey 1<<11,
        // controlKey 1<<12.
        let control: UInt32 = 1 << 12
        let option: UInt32 = 1 << 11
        let command: UInt32 = 1 << 8
        switch self {
        case .controlOption: return control | option
        case .control: return control
        case .controlCommand: return control | command
        case .controlOptionCommand: return control | option | command
        }
    }

    var symbol: String {
        switch self {
        case .controlOption: "⌃⌥"
        case .control: "⌃"
        case .controlCommand: "⌃⌘"
        case .controlOptionCommand: "⌃⌥⌘"
        }
    }

    var title: String {
        switch self {
        case .controlOption: "Control + Option"
        case .control: "Control"
        case .controlCommand: "Control + Command"
        case .controlOptionCommand: "Control + Option + Command"
        }
    }

    /// Control alone collides with Mission Control (⌃↑) and Space-switching (⌃← / ⌃→).
    var conflictsWithMissionControl: Bool { self == .control }
}

/// The last tile applied to a window and the frame the app actually ended up
/// with. Apps that clamp their minimum size do not land on the exact tile
/// frame, so the observed frame is the value to compare against later.
nonisolated struct AppliedTile: Equatable, Sendable {
    var tile: Tile
    var frame: CGRect
}

nonisolated enum TilingGeometry {
    /// Distance from the tile frame, per edge, within which a window still
    /// counts as sitting on that tile.
    static let frameTolerance: CGFloat = 8

    /// Area available for tiles. Starts from `visibleFrame` (excludes the menu
    /// bar and a visible Dock) and raises the bottom edge above the Taskbar when
    /// Omnibar shows a bar on that display.
    static func usableFrame(
        screenFrame: CGRect,
        visibleFrame: CGRect,
        taskbarHeight: CGFloat,
        taskbarPresent: Bool
    ) -> CGRect {
        var usable = visibleFrame
        guard taskbarPresent else { return usable }
        let barTop = screenFrame.minY + taskbarHeight
        if usable.minY < barTop {
            let delta = barTop - usable.minY
            usable.origin.y += delta
            usable.size.height = max(0, usable.size.height - delta)
        }
        return usable
    }

    /// Next tile for a keyboard press. Order of checks:
    /// 1. The window's frame matches a tile in the direction's sequence: advance.
    /// 2. The frame matches what the app produced the last time a tile in the
    ///    sequence was applied (size clamped by the app): advance from that tile.
    /// 3. Otherwise start the sequence from the half.
    static func nextTile(
        direction: TileDirection,
        currentFrame: CGRect,
        usable: CGRect,
        remembered: AppliedTile?,
        tolerance: CGFloat = frameTolerance
    ) -> Tile {
        let sequence = direction.sequence
        if let index = sequence.firstIndex(where: {
            framesMatch($0.frame(in: usable), currentFrame, tolerance: tolerance)
        }) {
            return sequence[(index + 1) % sequence.count]
        }
        if let remembered,
           let index = sequence.firstIndex(of: remembered.tile),
           framesMatch(remembered.frame, currentFrame, tolerance: tolerance) {
            return sequence[(index + 1) % sequence.count]
        }
        return sequence[0]
    }

    static func framesMatch(_ lhs: CGRect, _ rhs: CGRect, tolerance: CGFloat = frameTolerance) -> Bool {
        abs(lhs.minX - rhs.minX) <= tolerance
            && abs(lhs.minY - rhs.minY) <= tolerance
            && abs(lhs.maxX - rhs.maxX) <= tolerance
            && abs(lhs.maxY - rhs.maxY) <= tolerance
    }

    /// Inverse of `ScreenGeometry.cocoaRect(fromCGRect:primaryHeight:)`.
    static func cgRect(fromCocoaRect rect: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(
            x: rect.origin.x,
            y: primaryHeight - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }
}
