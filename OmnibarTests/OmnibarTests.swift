import CoreGraphics
import XCTest
@testable import Omnibar

final class OrderStoreTests: XCTestCase {
    @MainActor
    func testNewWindowsAppendInArrivalOrder() {
        OrderStore.shared.reset()
        let store = OrderStore.shared
        store.record(keys: ["a", "b"], keepAcrossSpaceChange: true, appearing: ["a", "b"], disappearing: [])
        store.record(keys: ["a", "b", "c"], keepAcrossSpaceChange: true, appearing: ["c"], disappearing: [])
        XCTAssertEqual(store.sorted(["c", "a", "b"]) { $0 }, ["a", "b", "c"])
    }

    @MainActor
    func testKeepsPositionWhenWindowLeavesAndReturns() {
        OrderStore.shared.reset()
        let store = OrderStore.shared
        store.record(keys: ["a", "b", "c"], keepAcrossSpaceChange: true, appearing: ["a", "b", "c"], disappearing: [])
        store.record(keys: ["a", "c"], keepAcrossSpaceChange: true, appearing: [], disappearing: ["b"])
        store.record(keys: ["a", "b", "c"], keepAcrossSpaceChange: true, appearing: ["b"], disappearing: [])
        XCTAssertEqual(store.sorted(["c", "b", "a"]) { $0 }, ["a", "b", "c"])
    }

    @MainActor
    func testLegacyBehaviorMovesReturningWindowToEnd() {
        OrderStore.shared.reset()
        let store = OrderStore.shared
        store.record(keys: ["a", "b", "c"], keepAcrossSpaceChange: false, appearing: ["a", "b", "c"], disappearing: [])
        store.record(keys: ["a", "c"], keepAcrossSpaceChange: false, appearing: [], disappearing: ["b"])
        store.record(keys: ["a", "c", "b"], keepAcrossSpaceChange: false, appearing: ["b"], disappearing: [])
        XCTAssertEqual(store.sorted(["b", "a", "c"]) { $0 }, ["a", "c", "b"])
    }

    @MainActor
    func testMoveBeforeTarget() {
        OrderStore.shared.reset()
        let store = OrderStore.shared
        store.replace(["a", "b", "c"])
        store.move(id: "c", before: "a")
        XCTAssertEqual(store.sorted(["a", "b", "c"]) { $0 }, ["c", "a", "b"])
    }
}

final class SettingsTests: XCTestCase {
    @MainActor
    func testRoundTrip() throws {
        var settings = AppSettings.default
        settings.transparency = 0.2
        settings.groupByApplication = true
        settings.startButtonAction = .spotlight
        settings.hiddenDisplayIDs = [11, 22]
        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)
        XCTAssertEqual(decoded, settings)
    }

    @MainActor
    func testDisplayHidden() {
        var settings = AppSettings.default
        settings.hiddenDisplayIDs = [42]
        XCTAssertTrue(settings.isDisplayHidden(42))
        XCTAssertFalse(settings.isDisplayHidden(1))
    }

    @MainActor
    func testGroupByApplicationDefaultsOn() {
        XCTAssertTrue(AppSettings.default.groupByApplication)
    }

    @MainActor
    func testFullyHideDockDefaultsOn() {
        XCTAssertTrue(AppSettings.default.fullyHideDock)
    }
}

final class TaskListLogicTests: XCTestCase {
    @MainActor
    func testFiltersToCurrentSpace() {
        OrderStore.shared.reset()
        let current: UInt64 = 10
        let onSpace = stubWindow(id: 1, screen: 1, spaces: [10])
        let otherSpace = stubWindow(id: 2, screen: 1, spaces: [11])
        var settings = AppSettings.default
        settings.showWindowsFromAllScreens = false
        let result = TaskListLogic.windows(
            from: [onSpace, otherSpace],
            onScreen: 1,
            currentSpace: current,
            settings: settings
        )
        XCTAssertEqual(result.map(\.id) as [CGWindowID], [1])
    }

    @MainActor
    func testShowAllScreensIgnoresSpaceFilter() {
        let a = stubWindow(id: 1, screen: 1, spaces: [10])
        let b = stubWindow(id: 2, screen: 2, spaces: [11])
        var settings = AppSettings.default
        settings.showWindowsFromAllScreens = true
        let result = TaskListLogic.windows(
            from: [a, b],
            onScreen: 1,
            currentSpace: 10,
            settings: settings
        )
        XCTAssertEqual(result.count, 2)
    }

    @MainActor
    func testDedupesTabsWhenDisabled() {
        let a = stubWindow(id: 1, title: "Docs", pid: 9)
        let b = stubWindow(id: 2, title: "Docs", pid: 9)
        var settings = AppSettings.default
        settings.showTabsAsItems = false
        let result = TaskListLogic.windows(from: [a, b], onScreen: 1, currentSpace: nil, settings: settings)
        XCTAssertEqual(result.count, 1)
    }

    @MainActor
    func testGroupingProducesOneItemPerApp() {
        OrderStore.shared.reset()
        let chrome1 = stubWindow(id: 1, bundle: "com.google.Chrome", title: "A")
        let chrome2 = stubWindow(id: 2, bundle: "com.google.Chrome", title: "B")
        let finder = stubWindow(id: 3, bundle: "com.apple.finder", title: "Desktop")
        var settings = AppSettings.default
        settings.groupByApplication = true
        let items = TaskListLogic.items(
            windows: [chrome1, chrome2, finder],
            pinnedBundleIDs: [],
            settings: settings,
            badge: { _ in nil },
            icon: { _ in nil },
            appName: { $0 }
        )
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items[0].windows.count + items[1].windows.count, 3)
    }

    @MainActor
    func testPinnedLauncherAppearsWhenAppHasNoWindows() {
        OrderStore.shared.reset()
        let finder = stubWindow(id: 3, bundle: "com.apple.finder", title: "Desktop")
        let items = TaskListLogic.items(
            windows: [finder],
            pinnedBundleIDs: ["com.apple.Safari"],
            settings: .default,
            badge: { _ in nil },
            icon: { _ in nil },
            appName: { $0 }
        )
        XCTAssertTrue(items.contains { $0.id == "pin-com.apple.Safari" })
        XCTAssertTrue(items.contains { $0.bundleID == "com.apple.finder" })
    }

    @MainActor
    func testBlacklistIsCallerResponsibility() {
        let blocked = stubWindow(id: 1, bundle: "com.blocked.app")
        let open = stubWindow(id: 2, bundle: "com.ok.app")
        let filtered = [blocked, open].filter { $0.bundleID != "com.blocked.app" }
        XCTAssertEqual(filtered.map(\.bundleID), ["com.ok.app"])
    }
}

final class DragReorderTests: XCTestCase {
    @MainActor
    func testCommitSplitsPinsAndWindows() {
        let window = stubWindow(id: 4, bundle: "com.ok.app")
        let items = [
            TaskItem(id: "pin-com.apple.Safari", kind: .pinned(bundleID: "com.apple.Safari", appName: "Safari", icon: nil, badge: nil)),
            TaskItem(id: window.orderKey, kind: .window(window))
        ]
        let result = DragReorderController.commit(items: items)
        XCTAssertEqual(result.pins, ["com.apple.Safari"])
        XCTAssertEqual(result.windowKeys, [window.orderKey])
    }
}

final class AppCatalogGroupingTests: XCTestCase {
    @MainActor
    func testLetterGroups() {
        let apps = [
            AppCatalog.CatalogApp(bundleID: "a", name: "Arcade", url: URL(fileURLWithPath: "/tmp/a.app")),
            AppCatalog.CatalogApp(bundleID: "b", name: "Books", url: URL(fileURLWithPath: "/tmp/b.app")),
            AppCatalog.CatalogApp(bundleID: "c", name: "1Password", url: URL(fileURLWithPath: "/tmp/c.app"))
        ]
        let grouped = AppCatalog.shared.groupedByLetter(apps)
        XCTAssertEqual(grouped.map(\.letter), ["#", "A", "B"])
        XCTAssertEqual(grouped.first { $0.letter == "A" }?.apps.map(\.name), ["Arcade"])
        XCTAssertEqual(grouped.first { $0.letter == "#" }?.apps.map(\.name), ["1Password"])
    }

    @MainActor
    func testEmptyListHasNoGroups() {
        XCTAssertTrue(AppCatalog.shared.groupedByLetter([]).isEmpty)
    }
}

final class AppCatalogScanTests: XCTestCase {
    @MainActor
    func testCollectsAppsFromDirectoryAndNestedFolder() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("omnibar-catalog-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try makeStubApp(named: "Arcade", bundleID: "io.specktronica.arcade", in: root)
        let nested = root.appendingPathComponent("Utilities")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try makeStubApp(named: "Books", bundleID: "io.specktronica.books", in: nested)

        let apps = AppCatalog.shared.collectApps(from: [root])
        XCTAssertEqual(apps.map(\.name), ["Arcade", "Books"])
        XCTAssertEqual(apps.map(\.bundleID), ["io.specktronica.arcade", "io.specktronica.books"])
    }

    @MainActor
    func testReadsBundleIdentifierFromInfoPlist() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("omnibar-plist-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let appURL = try makeStubApp(named: "Zebra Test", bundleID: "io.specktronica.zebratest", in: root)
        let app = AppCatalog.shared.catalogApp(from: appURL)
        XCTAssertEqual(app?.bundleID, "io.specktronica.zebratest")
        XCTAssertEqual(app?.name, "Zebra Test")
    }
}

final class AppListViewTests: XCTestCase {
    @MainActor
    func testRendersLetterHeadersAndRows() {
        let view = AppListView(frame: NSRect(x: 0, y: 0, width: 300, height: 200))
        let apps = [
            AppCatalog.CatalogApp(bundleID: "a", name: "Arcade", url: URL(fileURLWithPath: "/tmp/Arcade.app")),
            AppCatalog.CatalogApp(bundleID: "b", name: "Books", url: URL(fileURLWithPath: "/tmp/Books.app"))
        ]
        view.update(AppCatalog.shared.groupedByLetter(apps))
        view.layoutSubtreeIfNeeded()

        let document = view.documentView
        XCTAssertEqual(document?.subviews.count, 4)
        XCTAssertGreaterThan(document?.frame.height ?? 0, 80)
        XCTAssertEqual(
            document?.subviews.compactMap { $0 as? NSTextField }.map(\.stringValue),
            ["A", "B"]
        )
    }
}

@MainActor
@discardableResult
private func makeStubApp(named name: String, bundleID: String, in directory: URL) throws -> URL {
    let app = directory.appendingPathComponent("\(name).app")
    let contents = app.appendingPathComponent("Contents")
    try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
    let plist: [String: Any] = [
        "CFBundleIdentifier": bundleID,
        "CFBundleName": name,
        "CFBundlePackageType": "APPL",
        "CFBundleExecutable": name
    ]
    let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
    try data.write(to: contents.appendingPathComponent("Info.plist"))
    return app
}

final class ScanCoalescerTests: XCTestCase {
    func testCoalescesWhileScanIsInFlight() {
        var coalescer = ScanCoalescer()
        XCTAssertTrue(coalescer.requestStart())
        XCTAssertFalse(coalescer.requestStart())
        XCTAssertTrue(coalescer.needsRescan)
        XCTAssertTrue(coalescer.finish())
        XCTAssertTrue(coalescer.requestStart())
        XCTAssertFalse(coalescer.finish())
    }

    func testFinishWithoutQueuedScanDoesNotRestart() {
        var coalescer = ScanCoalescer()
        XCTAssertTrue(coalescer.requestStart())
        XCTAssertFalse(coalescer.finish())
        XCTAssertFalse(coalescer.isScanning)
        XCTAssertFalse(coalescer.needsRescan)
    }
}

final class ScanGeometryTests: XCTestCase {
    func testLooksLikeFullscreenMatchesDisplaySize() {
        let sizes = [CGSize(width: 1920, height: 1080), CGSize(width: 1512, height: 982)]
        XCTAssertTrue(ScanGeometry.looksLikeFullscreen(
            CGRect(x: 0, y: 0, width: 1920, height: 1080),
            screenSizes: sizes
        ))
        XCTAssertFalse(ScanGeometry.looksLikeFullscreen(
            CGRect(x: 80, y: 80, width: 800, height: 600),
            screenSizes: sizes
        ))
    }
}

final class ScreenGeometryTests: XCTestCase {
    func testDisplayIDUsesContainingScreen() {
        let screens: [(id: CGDirectDisplayID, frame: CGRect)] = [
            (1, CGRect(x: 0, y: 0, width: 1920, height: 1080)),
            (2, CGRect(x: 1920, y: 0, width: 1920, height: 1080))
        ]
        let left = ScreenGeometry.displayID(
            containingCGRect: CGRect(x: 10, y: 10, width: 100, height: 100),
            screens: screens,
            cocoaPrimaryHeight: 1080
        )
        XCTAssertEqual(left, 1)
        let right = ScreenGeometry.displayID(
            containingCGRect: CGRect(x: 2000, y: 10, width: 100, height: 100),
            screens: screens,
            cocoaPrimaryHeight: 1080
        )
        XCTAssertEqual(right, 2)
    }
}

@MainActor
func stubWindow(
    id: CGWindowID,
    bundle: String? = "com.example.app",
    title: String = "Title",
    pid: pid_t = 42,
    screen: CGDirectDisplayID = 1,
    spaces: [UInt64] = [10],
    minimized: Bool = false
) -> WindowInfo {
    WindowInfo(
        id: id,
        pid: pid,
        bundleID: bundle,
        appName: bundle ?? "App",
        title: title,
        frame: CGRect(x: 0, y: 0, width: 800, height: 600),
        screenID: screen,
        spaces: spaces,
        isMinimized: minimized,
        isHidden: false,
        isFullscreen: false,
        isOnScreen: true,
        isTabbed: false,
        isActive: false,
        layer: 0
    )
}
