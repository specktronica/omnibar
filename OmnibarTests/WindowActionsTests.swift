import XCTest
@testable import Omnibar

final class WindowActionsTests: XCTestCase {
    @MainActor
    func testPinnedLaunches() {
        let item = TaskItem(
            id: "pin-x",
            kind: .pinned(bundleID: "com.apple.Safari", appName: "Safari", icon: nil, badge: nil)
        )
        XCTAssertEqual(
            action(for: item, frontmostPID: 1),
            .launch(bundleID: "com.apple.Safari")
        )
    }

    @MainActor
    func testInactiveWindowRaisesEvenIfSnapshotSaysActive() {
        let window = stubWindow(id: 1, pid: 10, active: true)
        let item = TaskItem(id: window.orderKey, kind: .window(window))
        XCTAssertEqual(action(for: item, frontmostPID: 99), .raise(window))
    }

    @MainActor
    func testFrontmostActiveWindowMinimizesByDefault() {
        let window = stubWindow(id: 1, pid: 10, active: true)
        let item = TaskItem(id: window.orderKey, kind: .window(window))
        XCTAssertEqual(action(for: item, frontmostPID: 10), .minimize(window))
    }

    @MainActor
    func testFrontmostActiveWindowHidesWhenConfigured() {
        let window = stubWindow(id: 1, pid: 77, active: true)
        let item = TaskItem(id: window.orderKey, kind: .window(window))
        XCTAssertEqual(
            action(for: item, hideOnClick: true, frontmostPID: 77),
            .hide(pid: 77)
        )
    }

    @MainActor
    func testBackgroundWindowOfFrontmostAppRaises() {
        let window = stubWindow(id: 2, pid: 10, active: false)
        let item = TaskItem(id: window.orderKey, kind: .window(window))
        XCTAssertEqual(action(for: item, frontmostPID: 10), .raise(window))
    }

    @MainActor
    func testGroupedRaisesFrontmostVisibleWindow() {
        let back = stubWindow(id: 1, title: "Back", pid: 10)
        let front = stubWindow(id: 2, title: "Front", pid: 10)
        let item = TaskItem(
            id: "group-x",
            kind: .grouped(bundleID: "x", appName: "X", windows: [back, front], badge: nil)
        )
        XCTAssertEqual(
            action(for: item, frontmostPID: 99, frontToBackIDs: [front.id, back.id]),
            .raise(front)
        )
    }

    @MainActor
    func testGroupedFrontmostAppMinimizes() {
        let window = stubWindow(id: 1, pid: 10, active: true)
        let other = stubWindow(id: 2, pid: 10)
        let item = TaskItem(
            id: "group-x",
            kind: .grouped(bundleID: "x", appName: "X", windows: [window, other], badge: nil)
        )
        XCTAssertEqual(action(for: item, frontmostPID: 10), .minimize(window))
    }

    @MainActor
    func testGroupedRaisesFirstVisibleThenFallsBack() {
        let minimized = stubWindow(id: 1, minimized: true)
        let hidden = stubWindow(id: 2, hidden: true)
        let visible = stubWindow(id: 3)
        let groupedVisible = TaskItem(
            id: "group-x",
            kind: .grouped(bundleID: "x", appName: "X", windows: [minimized, hidden, visible], badge: nil)
        )
        XCTAssertEqual(action(for: groupedVisible, frontmostPID: 99), .raise(visible))
        let allMin = TaskItem(
            id: "group-y",
            kind: .grouped(bundleID: "y", appName: "Y", windows: [minimized, hidden], badge: nil)
        )
        XCTAssertEqual(action(for: allMin, frontmostPID: 99), .raise(minimized))
        let empty = TaskItem(
            id: "group-z",
            kind: .grouped(bundleID: "z", appName: "Z", windows: [], badge: nil)
        )
        XCTAssertNil(action(for: empty, frontmostPID: 99))
    }

    @MainActor
    func testPreferredWindowSkipsMinimized() {
        let minimized = stubWindow(id: 1, pid: 10, minimized: true)
        let visible = stubWindow(id: 2, pid: 10)
        let preferred = WindowActions.preferredWindow(
            from: [minimized, visible],
            frontToBackIDs: [minimized.id, visible.id]
        )
        XCTAssertEqual(preferred, visible)
    }

    @MainActor
    private func action(
        for item: TaskItem,
        hideOnClick: Bool = false,
        frontmostPID: pid_t?,
        frontToBackIDs: [CGWindowID] = []
    ) -> WindowActions.PrimaryClickAction? {
        WindowActions.primaryClickAction(
            for: item,
            hideOnClickInsteadOfMinimize: hideOnClick,
            frontmostPID: frontmostPID,
            frontToBackIDs: frontToBackIDs
        )
    }
}
