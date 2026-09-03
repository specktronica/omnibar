import XCTest
@testable import Omnibar

final class DragReorderGapsTests: XCTestCase {
    @MainActor
    func testCommitFlattensGroupedWindows() {
        let a = stubWindow(id: 1, bundle: "com.ok.app")
        let b = stubWindow(id: 2, bundle: "com.ok.app")
        let items = [
            TaskItem(
                id: "group-com.ok.app",
                kind: .grouped(bundleID: "com.ok.app", appName: "Ok", windows: [a, b], badge: nil)
            )
        ]
        let result = DragReorderController.commit(items: items)
        XCTAssertTrue(result.pins.isEmpty)
        XCTAssertEqual(result.windowKeys, [a.orderKey, b.orderKey])
    }

    @MainActor
    func testCommitEmpty() {
        let result = DragReorderController.commit(items: [])
        XCTAssertTrue(result.pins.isEmpty)
        XCTAssertTrue(result.windowKeys.isEmpty)
    }

    @MainActor
    func testCommitTaskbarKeepsPinnedWindowAppsAndAppendsRemainingPins() {
        let safari = stubWindow(id: 1, bundle: "com.apple.Safari")
        let finder = stubWindow(id: 2, bundle: "com.apple.finder")
        let items = [
            TaskItem(id: safari.orderKey, kind: .window(safari)),
            TaskItem(
                id: "pin-com.missing",
                kind: .pinned(bundleID: "com.missing", appName: "Missing", icon: nil, badge: nil)
            ),
            TaskItem(id: finder.orderKey, kind: .window(finder))
        ]
        let result = DragReorderController.commitTaskbar(
            items: items,
            existingPins: ["com.apple.Safari", "com.left.over"]
        )
        XCTAssertEqual(result.pins, ["com.apple.Safari", "com.missing", "com.left.over"])
        XCTAssertEqual(result.windowKeys, [safari.orderKey, finder.orderKey])
    }

    @MainActor
    func testCommitTaskbarLeavesPinsUntouchedWithoutPinTiles() {
        let window = stubWindow(id: 4, bundle: "com.ok.app")
        let result = DragReorderController.commitTaskbar(
            items: [TaskItem(id: window.orderKey, kind: .window(window))],
            existingPins: ["com.apple.Safari"]
        )
        XCTAssertNil(result.pins)
        XCTAssertEqual(result.windowKeys, [window.orderKey])
    }

    @MainActor
    func testCommitTaskbarPinnedGroup() {
        let a = stubWindow(id: 1, bundle: "com.apple.Safari")
        let b = stubWindow(id: 2, bundle: "com.apple.Safari")
        let items = [
            TaskItem(
                id: "group-com.apple.Safari",
                kind: .grouped(bundleID: "com.apple.Safari", appName: "Safari", windows: [a, b], badge: nil)
            )
        ]
        let result = DragReorderController.commitTaskbar(
            items: items,
            existingPins: ["com.apple.Safari"]
        )
        XCTAssertEqual(result.pins, ["com.apple.Safari"])
        XCTAssertEqual(result.windowKeys, [a.orderKey, b.orderKey])
    }
}
