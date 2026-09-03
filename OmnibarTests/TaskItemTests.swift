import XCTest
@testable import Omnibar

final class TaskItemTests: XCTestCase {
    @MainActor
    func testGroupedActiveIfAnyWindowIsActive() {
        let background = stubWindow(id: 1, active: false)
        let active = stubWindow(id: 2, active: true)
        let item = TaskItem(
            id: "group-x",
            kind: .grouped(bundleID: "x", appName: "X", windows: [background, active], badge: nil)
        )
        XCTAssertTrue(item.isActive)
        XCTAssertEqual(item.primaryWindow?.id, 2)
        XCTAssertEqual(item.windows.count, 2)
        XCTAssertFalse(item.isPinnedLauncher)
    }

    @MainActor
    func testGroupedMinimizedOnlyWhenAllAreMinOrHidden() {
        let minimized = stubWindow(id: 1, minimized: true)
        let hidden = stubWindow(id: 2, hidden: true)
        let visible = stubWindow(id: 3)
        let allGone = TaskItem(
            id: "group-x",
            kind: .grouped(bundleID: "x", appName: "X", windows: [minimized, hidden], badge: nil)
        )
        XCTAssertTrue(allGone.isMinimizedOrHidden)
        let mixed = TaskItem(
            id: "group-y",
            kind: .grouped(bundleID: "y", appName: "Y", windows: [minimized, visible], badge: nil)
        )
        XCTAssertFalse(mixed.isMinimizedOrHidden)
        XCTAssertEqual(mixed.primaryWindow?.id, 1)
    }

    @MainActor
    func testPinnedLauncherHasNoWindows() {
        let item = TaskItem(
            id: "pin-x",
            kind: .pinned(bundleID: "x", appName: "X", icon: nil, badge: "3")
        )
        XCTAssertTrue(item.isPinnedLauncher)
        XCTAssertTrue(item.windows.isEmpty)
        XCTAssertNil(item.primaryWindow)
        XCTAssertNil(item.pid)
        XCTAssertFalse(item.isActive)
        XCTAssertFalse(item.isMinimizedOrHidden)
        XCTAssertEqual(item.badge, "3")
        XCTAssertTrue(item.uiKey.contains("3"))
    }

    @MainActor
    func testGroupedUiKeyIncludesBadge() {
        let window = stubWindow(id: 1, title: "Docs")
        let item = TaskItem(
            id: "group-x",
            kind: .grouped(bundleID: "x", appName: "X", windows: [window], badge: "9")
        )
        XCTAssertTrue(item.uiKey.contains("9"))
        let other = TaskItem(
            id: "group-x",
            kind: .grouped(bundleID: "x", appName: "X", windows: [window], badge: nil)
        )
        XCTAssertNotEqual(item.uiKey, other.uiKey)
    }
}
