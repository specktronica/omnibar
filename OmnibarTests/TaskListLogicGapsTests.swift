import CoreGraphics
import XCTest
@testable import Omnibar

final class TaskListLogicGapsTests: XCTestCase {
    @MainActor
    func testMinimizedWindowsStayOnTheirScreen() {
        let onThisScreen = stubWindow(id: 1, screen: 1, spaces: [11], minimized: true)
        let onOtherScreen = stubWindow(id: 2, screen: 2, spaces: [11], minimized: true)
        let nilScreen = stubWindow(id: 3, screen: nil, spaces: [11], minimized: true)
        var settings = AppSettings.default
        settings.showWindowsFromAllScreens = false
        let result = TaskListLogic.windows(
            from: [onThisScreen, onOtherScreen, nilScreen],
            onScreen: 1,
            currentSpace: 10,
            settings: settings
        )
        XCTAssertEqual(result.map(\.id), [1, 3])
    }

    @MainActor
    func testEmptySpacesFallsBackToScreen() {
        let here = stubWindow(id: 1, screen: 1, spaces: [])
        let there = stubWindow(id: 2, screen: 2, spaces: [])
        var settings = AppSettings.default
        settings.showWindowsFromAllScreens = false
        let result = TaskListLogic.windows(
            from: [here, there],
            onScreen: 1,
            currentSpace: 99,
            settings: settings
        )
        XCTAssertEqual(result.map(\.id), [1])
    }

    @MainActor
    func testNilCurrentSpaceFallsBackToScreen() {
        let here = stubWindow(id: 1, screen: 1, spaces: [10])
        let there = stubWindow(id: 2, screen: 2, spaces: [10])
        var settings = AppSettings.default
        settings.showWindowsFromAllScreens = false
        let result = TaskListLogic.windows(
            from: [here, there],
            onScreen: 1,
            currentSpace: nil,
            settings: settings
        )
        XCTAssertEqual(result.map(\.id), [1])
    }

    @MainActor
    func testShowTabsAsItemsKeepsDuplicateTitles() {
        let a = stubWindow(id: 1, title: "Docs", pid: 9)
        let b = stubWindow(id: 2, title: "Docs", pid: 9)
        var settings = AppSettings.default
        settings.showTabsAsItems = true
        let result = TaskListLogic.windows(
            from: [a, b],
            onScreen: 1,
            currentSpace: nil,
            settings: settings
        )
        XCTAssertEqual(result.map(\.id), [1, 2])
    }

    @MainActor
    func testPinOrderIsPrefixThenUnpinned() {
        OrderStore.shared.reset()
        let chrome = stubWindow(id: 1, bundle: "com.google.Chrome", title: "A")
        let finder = stubWindow(id: 2, bundle: "com.apple.finder", title: "Desktop")
        let safari = stubWindow(id: 3, bundle: "com.apple.Safari", title: "Start")
        var settings = AppSettings.default
        settings.groupByApplication = true
        let items = TaskListLogic.items(
            windows: [chrome, finder, safari],
            pinnedBundleIDs: ["com.apple.Safari", "com.missing"],
            settings: settings,
            badge: { _ in nil },
            icon: { _ in nil },
            appName: { $0 }
        )
        XCTAssertEqual(
            items.map(\.id),
            ["group-com.apple.Safari", "pin-com.missing", "group-com.apple.finder", "group-com.google.Chrome"]
        )
        OrderStore.shared.reset()
    }

    @MainActor
    func testUngroupedEmitsOneTilePerWindow() {
        OrderStore.shared.reset()
        OrderStore.shared.replace(["42-1", "42-2"])
        let a = stubWindow(id: 1, bundle: "com.google.Chrome", title: "A")
        let b = stubWindow(id: 2, bundle: "com.google.Chrome", title: "B")
        var settings = AppSettings.default
        settings.groupByApplication = false
        let items = TaskListLogic.items(
            windows: [b, a],
            pinnedBundleIDs: [],
            settings: settings,
            badge: { _ in nil },
            icon: { _ in nil },
            appName: { $0 }
        )
        XCTAssertEqual(items.map(\.id), ["42-1", "42-2"])
        XCTAssertEqual(items.compactMap(\.primaryWindow?.title), ["A", "B"])
        OrderStore.shared.reset()
    }

    @MainActor
    func testNilBundleIDGroupsByPid() {
        OrderStore.shared.reset()
        let a = stubWindow(id: 1, bundle: nil, pid: 9, appName: "Anon")
        let b = stubWindow(id: 2, bundle: nil, pid: 9, appName: "Anon")
        var settings = AppSettings.default
        settings.groupByApplication = true
        let items = TaskListLogic.items(
            windows: [a, b],
            pinnedBundleIDs: [],
            settings: settings,
            badge: { _ in nil },
            icon: { _ in nil },
            appName: { $0 }
        )
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].id, "group-pid:9")
        XCTAssertEqual(items[0].windows.count, 2)
        OrderStore.shared.reset()
    }

    @MainActor
    func testEmptyWindowsAndPins() {
        OrderStore.shared.reset()
        let items = TaskListLogic.items(
            windows: [],
            pinnedBundleIDs: [],
            settings: .default,
            badge: { _ in nil },
            icon: { _ in nil },
            appName: { $0 }
        )
        XCTAssertTrue(items.isEmpty)
    }

    @MainActor
    func testExcludingBlacklistedDropsMatchingBundlesAndKeepsNil() {
        let blocked = stubWindow(id: 1, bundle: "com.blocked.app")
        let open = stubWindow(id: 2, bundle: "com.ok.app")
        let anonymous = stubWindow(id: 3, bundle: nil)
        let filtered = TaskListLogic.excludingBlacklisted(
            [blocked, open, anonymous],
            bundleIDs: ["com.blocked.app"]
        )
        XCTAssertEqual(filtered.map(\.id), [2, 3])
        XCTAssertEqual(
            TaskListLogic.excludingBlacklisted([blocked], bundleIDs: []).map(\.id),
            [1]
        )
    }
}
