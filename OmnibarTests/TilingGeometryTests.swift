import XCTest
@testable import Omnibar

@MainActor
final class TilingGeometryTests: XCTestCase {
    private let screen = CGRect(x: 0, y: 0, width: 1600, height: 900)
    private let visible = CGRect(x: 0, y: 0, width: 1600, height: 875) // 25 pt menu bar
    private let usable = CGRect(x: 0, y: 50, width: 1600, height: 825)

    // MARK: Usable frame

    func testUsableFrameWithoutTaskbarIsVisibleFrame() {
        let result = TilingGeometry.usableFrame(
            screenFrame: screen,
            visibleFrame: visible,
            taskbarHeight: 50,
            taskbarPresent: false
        )
        XCTAssertEqual(result, visible)
    }

    func testUsableFrameRaisesBottomAboveTaskbar() {
        let result = TilingGeometry.usableFrame(
            screenFrame: screen,
            visibleFrame: visible,
            taskbarHeight: 50,
            taskbarPresent: true
        )
        XCTAssertEqual(result, usable)
    }

    func testUsableFrameKeepsVisibleBottomWhenAlreadyAboveTaskbar() {
        // A visible Dock already pushed the bottom above the bar.
        let dockVisible = CGRect(x: 0, y: 80, width: 1600, height: 795)
        let result = TilingGeometry.usableFrame(
            screenFrame: screen,
            visibleFrame: dockVisible,
            taskbarHeight: 50,
            taskbarPresent: true
        )
        XCTAssertEqual(result, dockVisible)
    }

    func testUsableFrameOnSecondaryScreenWithOffsetOrigin() {
        let secondary = CGRect(x: 1600, y: -200, width: 1200, height: 800)
        let result = TilingGeometry.usableFrame(
            screenFrame: secondary,
            visibleFrame: secondary,
            taskbarHeight: 40,
            taskbarPresent: true
        )
        XCTAssertEqual(result, CGRect(x: 1600, y: -160, width: 1200, height: 760))
    }

    // MARK: Tile frames

    func testTileFramesPartitionUsableArea() {
        XCTAssertEqual(Tile.leftHalf.frame(in: usable), CGRect(x: 0, y: 50, width: 800, height: 825))
        XCTAssertEqual(Tile.rightHalf.frame(in: usable), CGRect(x: 800, y: 50, width: 800, height: 825))
        XCTAssertEqual(Tile.bottomLeft.frame(in: usable), CGRect(x: 0, y: 50, width: 800, height: 412))
        XCTAssertEqual(Tile.topLeft.frame(in: usable), CGRect(x: 0, y: 462, width: 800, height: 413))
        XCTAssertEqual(Tile.bottomRight.frame(in: usable), CGRect(x: 800, y: 50, width: 800, height: 412))
        XCTAssertEqual(Tile.topRight.frame(in: usable), CGRect(x: 800, y: 462, width: 800, height: 413))
        XCTAssertEqual(Tile.maximize.frame(in: usable), usable)
    }

    func testOddWidthHalvesMeetWithoutGap() {
        let odd = CGRect(x: 0, y: 0, width: 1001, height: 601)
        let left = Tile.leftHalf.frame(in: odd)
        let right = Tile.rightHalf.frame(in: odd)
        XCTAssertEqual(left.maxX, right.minX)
        XCTAssertEqual(left.width + right.width, odd.width)
        let bottom = Tile.bottomLeft.frame(in: odd)
        let top = Tile.topLeft.frame(in: odd)
        XCTAssertEqual(bottom.maxY, top.minY)
        XCTAssertEqual(bottom.height + top.height, odd.height)
    }

    // MARK: Keyboard cycle

    func testFreshWindowStartsAtHalf() {
        let floating = CGRect(x: 300, y: 200, width: 700, height: 500)
        XCTAssertEqual(
            TilingGeometry.nextTile(direction: .right, currentFrame: floating, usable: usable, remembered: nil),
            .rightHalf
        )
        XCTAssertEqual(
            TilingGeometry.nextTile(direction: .left, currentFrame: floating, usable: usable, remembered: nil),
            .leftHalf
        )
    }

    func testRepeatedPressesCycleAndWrap() {
        var frame = Tile.rightHalf.frame(in: usable)
        var tile = TilingGeometry.nextTile(direction: .right, currentFrame: frame, usable: usable, remembered: nil)
        XCTAssertEqual(tile, .topRight)
        frame = tile.frame(in: usable)
        tile = TilingGeometry.nextTile(direction: .right, currentFrame: frame, usable: usable, remembered: nil)
        XCTAssertEqual(tile, .bottomRight)
        frame = tile.frame(in: usable)
        tile = TilingGeometry.nextTile(direction: .right, currentFrame: frame, usable: usable, remembered: nil)
        XCTAssertEqual(tile, .rightHalf)
    }

    func testFrameMatchToleratesSmallOffsets() {
        var frame = Tile.leftHalf.frame(in: usable)
        frame.origin.x += 5
        frame.size.width -= 7
        XCTAssertEqual(
            TilingGeometry.nextTile(direction: .left, currentFrame: frame, usable: usable, remembered: nil),
            .topLeft
        )
        frame.origin.x += 10
        XCTAssertEqual(
            TilingGeometry.nextTile(direction: .left, currentFrame: frame, usable: usable, remembered: nil),
            .leftHalf
        )
    }

    func testOppositeDirectionRestartsAtHalf() {
        let frame = Tile.topRight.frame(in: usable)
        let remembered = AppliedTile(tile: .topRight, frame: frame)
        XCTAssertEqual(
            TilingGeometry.nextTile(direction: .left, currentFrame: frame, usable: usable, remembered: remembered),
            .leftHalf
        )
    }

    func testRememberedTileUsedWhenAppClampedSize() {
        // App refused the quarter height and stayed taller than the tile.
        let clamped = CGRect(x: 800, y: 262, width: 800, height: 613)
        let remembered = AppliedTile(tile: .topRight, frame: clamped)
        XCTAssertEqual(
            TilingGeometry.nextTile(direction: .right, currentFrame: clamped, usable: usable, remembered: remembered),
            .bottomRight
        )
    }

    func testRememberedTileIgnoredAfterUserMovedWindow() {
        let clamped = CGRect(x: 800, y: 262, width: 800, height: 613)
        let remembered = AppliedTile(tile: .topRight, frame: clamped)
        let moved = clamped.offsetBy(dx: -40, dy: 0)
        XCTAssertEqual(
            TilingGeometry.nextTile(direction: .right, currentFrame: moved, usable: usable, remembered: remembered),
            .rightHalf
        )
    }

    func testMaximizedWindowStartsSequenceAtHalf() {
        let frame = Tile.maximize.frame(in: usable)
        let remembered = AppliedTile(tile: .maximize, frame: frame)
        XCTAssertEqual(
            TilingGeometry.nextTile(direction: .right, currentFrame: frame, usable: usable, remembered: remembered),
            .rightHalf
        )
    }

    // MARK: Coordinate conversion

    func testCGRectRoundTripsThroughCocoa() {
        let primaryHeight: CGFloat = 900
        let cg = CGRect(x: 120, y: 40, width: 640, height: 480)
        let cocoa = ScreenGeometry.cocoaRect(fromCGRect: cg, primaryHeight: primaryHeight)
        XCTAssertEqual(cocoa, CGRect(x: 120, y: 380, width: 640, height: 480))
        XCTAssertEqual(TilingGeometry.cgRect(fromCocoaRect: cocoa, primaryHeight: primaryHeight), cg)
    }

    func testCGRectRoundTripsForScreenWithNegativeOrigin() {
        // Secondary display below and left of the primary: Cocoa y is negative.
        let primaryHeight: CGFloat = 900
        let cocoa = CGRect(x: -1200, y: -300, width: 1200, height: 800)
        let cg = TilingGeometry.cgRect(fromCocoaRect: cocoa, primaryHeight: primaryHeight)
        XCTAssertEqual(cg, CGRect(x: -1200, y: 400, width: 1200, height: 800))
        XCTAssertEqual(ScreenGeometry.cocoaRect(fromCGRect: cg, primaryHeight: primaryHeight), cocoa)
    }

    // MARK: Snap zones

    private func zone(_ x: CGFloat, _ y: CGFloat, shared: Set<ScreenEdge> = []) -> Tile? {
        TilingGeometry.snapZone(cursor: CGPoint(x: x, y: y), screenFrame: screen, sharedEdges: shared)
    }

    func testSideEdgesSnapToHalves() {
        XCTAssertEqual(zone(0, 450), .leftHalf)
        XCTAssertEqual(zone(5, 450), .leftHalf)
        XCTAssertEqual(zone(1599, 450), .rightHalf)
    }

    func testSideEdgeCornersSnapToQuarters() {
        // Corner band is 20% of 900 = 180 pt.
        XCTAssertEqual(zone(0, 899), .topLeft)
        XCTAssertEqual(zone(0, 721), .topLeft)
        XCTAssertEqual(zone(0, 719), .leftHalf)
        XCTAssertEqual(zone(0, 0), .bottomLeft)
        XCTAssertEqual(zone(0, 179), .bottomLeft)
        XCTAssertEqual(zone(0, 181), .leftHalf)
        XCTAssertEqual(zone(1599, 899), .topRight)
        XCTAssertEqual(zone(1599, 10), .bottomRight)
    }

    func testTopEdgeMaximizes() {
        XCTAssertEqual(zone(800, 899), .maximize)
        XCTAssertEqual(zone(800, 895), .maximize)
    }

    func testCenterAndBottomEdgeDoNotSnap() {
        XCTAssertNil(zone(800, 450))
        XCTAssertNil(zone(800, 0))
        XCTAssertNil(zone(800, 5))
        XCTAssertNil(zone(10, 450))
    }

    func testSharedEdgesAreIgnored() {
        XCTAssertNil(zone(1599, 450, shared: [.right]))
        XCTAssertNil(zone(1599, 50, shared: [.right]))
        XCTAssertEqual(zone(0, 450, shared: [.right]), .leftHalf)
        XCTAssertNil(zone(0, 450, shared: [.left]))
        XCTAssertNil(zone(800, 899, shared: [.top]))
    }

    func testSnapZoneUsesScreenOriginNotZero() {
        let secondary = CGRect(x: 1600, y: -200, width: 1200, height: 800)
        XCTAssertEqual(
            TilingGeometry.snapZone(cursor: CGPoint(x: 1600, y: 200), screenFrame: secondary, sharedEdges: []),
            .leftHalf
        )
        XCTAssertEqual(
            TilingGeometry.snapZone(cursor: CGPoint(x: 2200, y: 599), screenFrame: secondary, sharedEdges: []),
            .maximize
        )
        XCTAssertNil(
            TilingGeometry.snapZone(cursor: CGPoint(x: 2200, y: -200), screenFrame: secondary, sharedEdges: [])
        )
    }

    // MARK: Shared edges

    func testSharedEdgesDetectsAdjacentScreens() {
        let right = CGRect(x: 1600, y: 100, width: 1200, height: 800)
        let above = CGRect(x: 200, y: 900, width: 1000, height: 600)
        let edges = TilingGeometry.sharedEdges(of: screen, others: [right, above])
        XCTAssertEqual(edges, [.right, .top])
        XCTAssertEqual(TilingGeometry.sharedEdges(of: right, others: [screen, above]), [.left])
        XCTAssertEqual(TilingGeometry.sharedEdges(of: above, others: [screen, right]), [.bottom])
    }

    func testSharedEdgesRequireOverlapAlongTheEdge() {
        // Same x boundary but no vertical overlap: not adjacent.
        let diagonal = CGRect(x: 1600, y: 900, width: 1200, height: 800)
        XCTAssertEqual(TilingGeometry.sharedEdges(of: screen, others: [diagonal]), [])
        XCTAssertEqual(TilingGeometry.sharedEdges(of: screen, others: []), [])
        XCTAssertEqual(TilingGeometry.sharedEdges(of: screen, others: [screen]), [])
    }

    // MARK: Modifiers

    func testCarbonFlags() {
        let control: UInt32 = 0x1000
        let option: UInt32 = 0x0800
        let command: UInt32 = 0x0100
        XCTAssertEqual(TilingModifiers.controlOption.carbonFlags, control | option)
        XCTAssertEqual(TilingModifiers.control.carbonFlags, control)
        XCTAssertEqual(TilingModifiers.controlCommand.carbonFlags, control | command)
        XCTAssertEqual(TilingModifiers.controlOptionCommand.carbonFlags, control | option | command)
    }

    func testOnlyControlAloneConflictsWithMissionControl() {
        for modifiers in TilingModifiers.allCases {
            XCTAssertEqual(modifiers.conflictsWithMissionControl, modifiers == .control, "\(modifiers)")
        }
    }

    func testModifiersRoundTripThroughJSON() throws {
        for modifiers in TilingModifiers.allCases {
            let data = try JSONEncoder().encode([modifiers])
            let decoded = try JSONDecoder().decode([TilingModifiers].self, from: data)
            XCTAssertEqual(decoded, [modifiers])
        }
    }
}
