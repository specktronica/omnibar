import XCTest
@testable import Omnibar

@MainActor
final class TaskContextMenuTests: XCTestCase {
    func testPinnedLauncherDisablesWindowActions() {
        let item = TaskItem(
            id: "pin-x",
            kind: .pinned(bundleID: "x", appName: "X", icon: nil, badge: nil)
        )
        let menu = TaskContextMenu.build(item: item, displayID: 1)
        XCTAssertEqual(menuItem(named: "Keep in Taskbar", in: menu)?.isEnabled, true)
        XCTAssertEqual(menuItem(named: "Hide", in: menu)?.isEnabled, false)
        XCTAssertEqual(menuItem(named: "Quit", in: menu)?.isEnabled, false)
        XCTAssertEqual(menuItem(named: "Fullscreen", in: menu)?.isEnabled, false)
        XCTAssertEqual(menuItem(named: "Minimize", in: menu)?.isEnabled, false)
        XCTAssertEqual(menuItem(named: "Close", in: menu)?.isEnabled, false)
        XCTAssertEqual(menuItem(named: "Add to Blacklist", in: menu)?.isEnabled, true)
    }

    func testMissingBundleDisablesPinAndBlacklist() {
        let window = stubWindow(id: 1, bundle: nil, pid: 9)
        let item = TaskItem(id: window.orderKey, kind: .window(window))
        let menu = TaskContextMenu.build(item: item, displayID: 1)
        XCTAssertEqual(menuItem(named: "Keep in Taskbar", in: menu)?.isEnabled, false)
        XCTAssertEqual(menuItem(named: "Add to Blacklist", in: menu)?.isEnabled, false)
        XCTAssertEqual(menuItem(named: "Hide", in: menu)?.isEnabled, true)
        XCTAssertEqual(menuItem(named: "Close", in: menu)?.isEnabled, true)
    }

    func testGroupedWindowsAddSubmenuItems() {
        let first = stubWindow(id: 1, title: "One", active: true)
        let second = stubWindow(id: 2, title: "Two", active: false)
        let item = TaskItem(
            id: "group-x",
            kind: .grouped(bundleID: "x", appName: "X", windows: [first, second], badge: nil)
        )
        let menu = TaskContextMenu.build(item: item, displayID: 1)
        XCTAssertNotNil(menuItem(named: "One", in: menu))
        XCTAssertEqual(menuItem(named: "One", in: menu)?.state, .on)
        XCTAssertEqual(menuItem(named: "Two", in: menu)?.state, .off)
        XCTAssertEqual(menuItem(named: "Close", in: menu)?.isEnabled, true)
    }

    private func menuItem(named title: String, in menu: NSMenu) -> NSMenuItem? {
        menu.items.first { $0.title == title }
    }
}
