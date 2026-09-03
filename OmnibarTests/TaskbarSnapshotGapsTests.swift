import XCTest
@testable import Omnibar

final class TaskbarSnapshotGapsTests: XCTestCase {
    @MainActor
    func testSpaceChangeIsNotUIEqual() {
        let window = stubWindow(id: 1)
        let item = TaskItem(id: window.orderKey, kind: .window(window))
        let lhs = TaskbarSnapshot(
            windows: [window],
            itemsByScreen: [1: [item]],
            currentSpaces: [1: 10],
            fullscreenDisplays: [],
            generatedAt: .now
        )
        let rhs = TaskbarSnapshot(
            windows: [window],
            itemsByScreen: [1: [item]],
            currentSpaces: [1: 11],
            fullscreenDisplays: [],
            generatedAt: .now
        )
        XCTAssertFalse(lhs.uiEquals(rhs))
    }

    @MainActor
    func testFullscreenSetChangeIsNotUIEqual() {
        let window = stubWindow(id: 1)
        let item = TaskItem(id: window.orderKey, kind: .window(window))
        let lhs = TaskbarSnapshot(
            windows: [window],
            itemsByScreen: [1: [item]],
            currentSpaces: [1: 10],
            fullscreenDisplays: [],
            generatedAt: .now
        )
        let rhs = TaskbarSnapshot(
            windows: [window],
            itemsByScreen: [1: [item]],
            currentSpaces: [1: 10],
            fullscreenDisplays: [1],
            generatedAt: .now
        )
        XCTAssertFalse(lhs.uiEquals(rhs))
        XCTAssertTrue(rhs.isFullscreen(1))
        XCTAssertTrue(rhs.items(for: 1).map(\.id) == [item.id])
        XCTAssertTrue(lhs.items(for: 99).isEmpty)
    }

    @MainActor
    func testGroupedBadgeChangeIsNotUIEqual() {
        let window = stubWindow(id: 1)
        let withoutBadge = TaskItem(
            id: "group-x",
            kind: .grouped(bundleID: "x", appName: "X", windows: [window], badge: nil)
        )
        let withBadge = TaskItem(
            id: "group-x",
            kind: .grouped(bundleID: "x", appName: "X", windows: [window], badge: "2")
        )
        let lhs = TaskbarSnapshot(
            windows: [window],
            itemsByScreen: [1: [withoutBadge]],
            currentSpaces: [1: 10],
            fullscreenDisplays: [],
            generatedAt: .now
        )
        let rhs = TaskbarSnapshot(
            windows: [window],
            itemsByScreen: [1: [withBadge]],
            currentSpaces: [1: 10],
            fullscreenDisplays: [],
            generatedAt: .now
        )
        XCTAssertFalse(lhs.uiEquals(rhs))
        XCTAssertEqual(lhs, rhs)
    }
}
