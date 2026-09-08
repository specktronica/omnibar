import CoreGraphics
import Foundation

/// A window placement relative to a screen's usable area.
nonisolated enum Tile: String, Codable, CaseIterable, Sendable {
    case leftHalf
    case rightHalf
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

    var sequence: [Tile] {
        switch self {
        case .left: [.leftHalf, .topLeft, .bottomLeft]
        case .right: [.rightHalf, .topRight, .bottomRight]
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

    /// Control alone collides with Mission Control's Space-switching shortcuts.
    var conflictsWithMissionControl: Bool { self == .control }
}

/// The last tile applied to a window and the frame the app actually ended up
/// with. Apps that clamp their minimum size do not land on the exact tile
/// frame, so the observed frame is the value to compare against later.
nonisolated struct AppliedTile: Equatable, Sendable {
    var tile: Tile
    var frame: CGRect
}

nonisolated enum ScreenEdge: Hashable, Sendable {
    case left
    case right
    case top
    case bottom
}

nonisolated enum TilingGeometry {
    /// Distance from the tile frame, per edge, within which a window still
    /// counts as sitting on that tile.
    static let frameTolerance: CGFloat = 8
    /// Cursor distance from a screen edge that counts as touching it.
    static let edgeInset: CGFloat = 6
    /// Portion of the screen height, at the top and bottom of a side edge,
    /// that snaps to a quarter instead of a half.
    static let cornerFraction: CGFloat = 0.2

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

    /// Tile for a cursor position during a window drag. `screenFrame` and
    /// `cursor` are in the same coordinate space with y increasing upward
    /// (Cocoa). Edges in `sharedEdges` never snap so the cursor can cross to
    /// the adjacent display. The bottom edge alone never snaps; that is where
    /// the Taskbar sits.
    static func snapZone(
        cursor: CGPoint,
        screenFrame: CGRect,
        sharedEdges: Set<ScreenEdge>,
        edgeInset: CGFloat = edgeInset,
        cornerFraction: CGFloat = cornerFraction
    ) -> Tile? {
        let atLeft = cursor.x <= screenFrame.minX + edgeInset && !sharedEdges.contains(.left)
        let atRight = cursor.x >= screenFrame.maxX - edgeInset && !sharedEdges.contains(.right)
        let atTop = cursor.y >= screenFrame.maxY - edgeInset && !sharedEdges.contains(.top)
        let cornerHeight = screenFrame.height * cornerFraction
        let inTopBand = cursor.y >= screenFrame.maxY - cornerHeight
        let inBottomBand = cursor.y <= screenFrame.minY + cornerHeight

        if atLeft {
            if inTopBand { return .topLeft }
            if inBottomBand { return .bottomLeft }
            return .leftHalf
        }
        if atRight {
            if inTopBand { return .topRight }
            if inBottomBand { return .bottomRight }
            return .rightHalf
        }
        if atTop {
            return .maximize
        }
        return nil
    }

    /// Edges of `frame` that touch another screen. Two frames share an edge
    /// when the edge coordinates coincide within one point and the frames
    /// overlap along that edge.
    static func sharedEdges(of frame: CGRect, others: [CGRect]) -> Set<ScreenEdge> {
        var edges: Set<ScreenEdge> = []
        for other in others where other != frame {
            let verticalOverlap = other.minY < frame.maxY && other.maxY > frame.minY
            let horizontalOverlap = other.minX < frame.maxX && other.maxX > frame.minX
            if verticalOverlap {
                if abs(other.minX - frame.maxX) <= 1 { edges.insert(.right) }
                if abs(other.maxX - frame.minX) <= 1 { edges.insert(.left) }
            }
            if horizontalOverlap {
                if abs(other.minY - frame.maxY) <= 1 { edges.insert(.top) }
                if abs(other.maxY - frame.minY) <= 1 { edges.insert(.bottom) }
            }
        }
        return edges
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
