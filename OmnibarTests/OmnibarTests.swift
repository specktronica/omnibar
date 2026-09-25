import AppKit
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

final class DockOrientationTests: XCTestCase {
    func testNormalizedKnownEdges() {
        XCTAssertEqual(DockOrientation.normalized("top"), "top")
        XCTAssertEqual(DockOrientation.normalized("left"), "left")
        XCTAssertEqual(DockOrientation.normalized("right"), "right")
        XCTAssertEqual(DockOrientation.normalized("bottom"), "bottom")
    }

    func testNormalizedUnknownFallsBackToBottom() {
        XCTAssertEqual(DockOrientation.normalized(nil), "bottom")
        XCTAssertEqual(DockOrientation.normalized(""), "bottom")
        XCTAssertEqual(DockOrientation.normalized("side"), "bottom")
    }
}

final class DockRelocationTests: XCTestCase {
    func testPlacedOnRightHidesAndKeepsTiming() {
        let original = DockPreferences(
            autohide: false,
            autohideDelay: 0.4,
            autohideTimeModifier: 1.2,
            orientation: "bottom"
        )
        let placed = DockRelocation.placedOnRight(original)
        XCTAssertEqual(placed.orientation, DockOrientation.right)
        XCTAssertTrue(placed.autohide)
        XCTAssertEqual(placed.autohideDelay, 0.4, accuracy: 0.001)
        XCTAssertEqual(placed.autohideTimeModifier, 1.2, accuracy: 0.001)
    }

    func testPlacedOnRightClearsLegacyHiddenDelay() {
        let original = DockPreferences(
            autohide: true,
            autohideDelay: DockRelocation.legacyHiddenDelay,
            autohideTimeModifier: 0,
            orientation: "top"
        )
        let placed = DockRelocation.placedOnRight(original)
        XCTAssertTrue(placed.autohide)
        XCTAssertEqual(placed.orientation, DockOrientation.right)
        XCTAssertEqual(placed.autohideDelay, DockPreferences.standardDelay, accuracy: 0.001)
        XCTAssertEqual(placed.autohideTimeModifier, DockPreferences.standardTimeModifier, accuracy: 0.001)
    }

    func testLegacyHiddenSignatureRestoresABottomDock() {
        let live = DockPreferences(
            autohide: true,
            autohideDelay: DockRelocation.legacyHiddenDelay,
            autohideTimeModifier: 0,
            orientation: "top"
        )
        XCTAssertTrue(DockRelocation.isLegacyHiddenSignature(delay: live.autohideDelay, orientation: live.orientation))
        let backup = DockRelocation.backup(from: live)
        XCTAssertEqual(backup.orientation, DockOrientation.bottom)
        XCTAssertEqual(backup.autohideDelay, DockPreferences.standardDelay, accuracy: 0.001)
        XCTAssertEqual(backup.autohideTimeModifier, DockPreferences.standardTimeModifier, accuracy: 0.001)
        XCTAssertTrue(backup.autohide)
        XCTAssertEqual(DockRelocation.placedOnRight(backup).orientation, DockOrientation.right)
    }

    func testOrdinaryTopDockIsPreservedInTheBackup() {
        let live = DockPreferences(
            autohide: false,
            autohideDelay: 0.5,
            autohideTimeModifier: 1,
            orientation: "top"
        )
        XCTAssertFalse(DockRelocation.isLegacyHiddenSignature(delay: live.autohideDelay, orientation: live.orientation))
        XCTAssertEqual(DockRelocation.backup(from: live), live)
    }
}

final class SettingsTests: XCTestCase {
    @MainActor
    func testRoundTrip() throws {
        var settings = AppSettings.default
        settings.transparency = 0.2
        settings.groupByApplication = true
        settings.showWindowsFromAllSpaces = true
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
    func testMoveDockToRightDefaultsOn() {
        XCTAssertTrue(AppSettings.default.moveDockToRight)
    }

    @MainActor
    func testTaskbarHeightDefaultsTo50() {
        XCTAssertEqual(AppSettings.default.taskbarHeight, 50)
    }

    @MainActor
    func testLaunchAtLoginDefaultsOn() {
        XCTAssertTrue(AppSettings.default.launchAtLogin)
    }

    @MainActor
    func testStartLogoDefaultsToClassic() {
        XCTAssertEqual(AppSettings.default.startLogo, .classic)
        XCTAssertEqual(StartLogoTheme.matching(.classic), .classic)
        XCTAssertEqual(StartLogoPalette.classic.left.hexRGB, 0x1070F0)
        XCTAssertEqual(StartLogoPalette.classic.top.hexRGB, 0x28C040)
        XCTAssertEqual(StartLogoPalette.classic.right.hexRGB, 0xF03018)
        XCTAssertEqual(StartLogoPalette.classic.bottom.hexRGB, 0xF8B000)
    }

    @MainActor
    func testStartLogoLegacyJSONUsesClassic() throws {
        var settings = AppSettings.default
        settings.transparency = 0.2
        settings.startButtonAction = .spotlight
        let data = try JSONEncoder().encode(settings)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object.removeValue(forKey: "startLogo")
        let stripped = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: stripped)
        XCTAssertEqual(decoded.startLogo, .classic)
        XCTAssertEqual(decoded.transparency, 0.2)
        XCTAssertEqual(decoded.startButtonAction, .spotlight)
    }

    @MainActor
    func testStartLogoRoundTripCustomPalette() throws {
        var settings = AppSettings.default
        settings.startLogo.left = RGBAColor(hex: 0xFF00AA)
        settings.startLogo.top = RGBAColor(hex: 0x00FFAA)
        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)
        XCTAssertEqual(decoded.startLogo.left.hexRGB, 0xFF00AA)
        XCTAssertEqual(decoded.startLogo.top.hexRGB, 0x00FFAA)
        XCTAssertEqual(decoded.startLogo.right, StartLogoPalette.classic.right)
        XCTAssertNil(StartLogoTheme.matching(decoded.startLogo))
    }

    @MainActor
    func testStartLogoPresetMatching() {
        XCTAssertEqual(StartLogoTheme.matching(StartLogoTheme.sunset.palette), .sunset)
        XCTAssertEqual(StartLogoTheme.matching(StartLogoTheme.ocean.palette), .ocean)
        var custom = StartLogoPalette.classic
        custom.left = RGBAColor(hex: 0xFFFFFF)
        XCTAssertNil(StartLogoTheme.matching(custom))
    }

    @MainActor
    func testMatchesExceptStartLogoIgnoresPalette() {
        var a = AppSettings.default
        var b = AppSettings.default
        b.startLogo = StartLogoTheme.neon.palette
        XCTAssertTrue(a.matchesExceptStartLogo(b))
        b.taskbarHeight = 48
        XCTAssertFalse(a.matchesExceptStartLogo(b))
        a.taskbarHeight = 48
        XCTAssertTrue(a.matchesExceptStartLogo(b))
    }

    @MainActor
    func testBrandIconImageSize() {
        let image = BrandIcon.image(pointSize: 32, palette: .classic)
        XCTAssertEqual(image.size, NSSize(width: 32, height: 32))
        XCTAssertFalse(image.isTemplate)
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
    func testShowAllScreensIncludesVisibleWindowsOnOtherDisplays() {
        let a = stubWindow(id: 1, screen: 1, spaces: [10], onScreen: true)
        let b = stubWindow(id: 2, screen: 2, spaces: [11], onScreen: true)
        var settings = AppSettings.default
        settings.showWindowsFromAllScreens = true
        let result = TaskListLogic.windows(
            from: [a, b],
            onScreen: 1,
            currentSpace: 10,
            settings: settings
        )
        XCTAssertEqual(result.map(\.id), [1, 2])
    }

    @MainActor
    func testShowAllScreensDoesNotIncludeInactiveSpaces() {
        let hidden = stubWindow(id: 2, screen: 1, spaces: [11], onScreen: false)
        var settings = AppSettings.default
        settings.showWindowsFromAllScreens = true
        settings.showWindowsFromAllSpaces = false
        let result = TaskListLogic.windows(
            from: [hidden],
            onScreen: 1,
            currentSpace: 10,
            settings: settings
        )
        XCTAssertTrue(result.isEmpty)
    }

    @MainActor
    func testShowAllSpacesIncludesThisDisplayOnly() {
        let here = stubWindow(id: 1, screen: 1, spaces: [11], onScreen: false)
        let there = stubWindow(id: 2, screen: 2, spaces: [12], onScreen: false)
        var settings = AppSettings.default
        settings.showWindowsFromAllSpaces = true
        let result = TaskListLogic.windows(
            from: [here, there],
            onScreen: 1,
            currentSpace: 10,
            settings: settings
        )
        XCTAssertEqual(result.map(\.id), [1])
    }

    @MainActor
    func testShowAllScreensAndSpacesIncludesEveryWindow() {
        let here = stubWindow(id: 1, screen: 1, spaces: [11], onScreen: false)
        let there = stubWindow(id: 2, screen: 2, spaces: [12], onScreen: false)
        var settings = AppSettings.default
        settings.showWindowsFromAllScreens = true
        settings.showWindowsFromAllSpaces = true
        let result = TaskListLogic.windows(
            from: [here, there],
            onScreen: 1,
            currentSpace: 10,
            settings: settings
        )
        XCTAssertEqual(result.map(\.id), [1, 2])
    }

    @MainActor
    func testGroupedRaisePrefersTheVisibleSpace() {
        let other = stubWindow(id: 1, onScreen: false)
        let current = stubWindow(id: 2, onScreen: true)
        let minimized = stubWindow(id: 3, minimized: true, onScreen: false)
        XCTAssertEqual(WindowActions.windowToRaise(in: [other, current, minimized])?.id, 2)
        XCTAssertEqual(WindowActions.windowToRaise(in: [other, minimized])?.id, 1)
        XCTAssertEqual(WindowActions.windowToRaise(in: [minimized])?.id, 3)
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
    func testPinnedAppWithWindowsIsNotALauncher() {
        OrderStore.shared.reset()
        let safari = stubWindow(id: 1, bundle: "com.apple.Safari", title: "Start")
        let items = TaskListLogic.items(
            windows: [safari],
            pinnedBundleIDs: ["com.apple.Safari"],
            settings: .default,
            badge: { _ in nil },
            icon: { _ in nil },
            appName: { $0 }
        )
        XCTAssertEqual(items.count, 1)
        XCTAssertFalse(items[0].isPinnedLauncher)
        XCTAssertFalse(items[0].isActive)
        XCTAssertEqual(items[0].windows.count, 1)
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

    @MainActor
    func testTargetIndexDoesNotOscillateAfterSlotChange() {
        let first = DragReorderController.targetIndex(
            dragMidX: 250,
            current: 1,
            count: 4,
            originX: 0,
            tileWidth: 100
        )
        let second = DragReorderController.targetIndex(
            dragMidX: 250,
            current: 2,
            count: 4,
            originX: 0,
            tileWidth: 100
        )
        XCTAssertEqual(first, 2)
        XCTAssertEqual(second, 2)
    }

    @MainActor
    func testTargetIndexHysteresisKeepsCurrentNearBoundary() {
        XCTAssertEqual(
            DragReorderController.targetIndex(
                dragMidX: 204,
                current: 1,
                count: 4,
                originX: 0,
                tileWidth: 100,
                hysteresis: 8
            ),
            1
        )
        XCTAssertEqual(
            DragReorderController.targetIndex(
                dragMidX: 96,
                current: 1,
                count: 4,
                originX: 0,
                tileWidth: 100,
                hysteresis: 8
            ),
            1
        )
    }

    @MainActor
    func testTargetIndexClampsToEnds() {
        XCTAssertEqual(
            DragReorderController.targetIndex(
                dragMidX: -50,
                current: 0,
                count: 4,
                originX: 0,
                tileWidth: 100
            ),
            0
        )
        XCTAssertEqual(
            DragReorderController.targetIndex(
                dragMidX: 1000,
                current: 0,
                count: 4,
                originX: 0,
                tileWidth: 100
            ),
            3
        )
    }
}

final class StartButtonSpinMotionTests: XCTestCase {
    func testOpenFromRestIsFullClockwiseTurn() {
        XCTAssertEqual(StartButtonSpinMotion.targetAngle(from: 0, opening: true), -StartButtonSpinMotion.turn, accuracy: 0.0001)
    }

    func testCloseFromRestIsFullReverseTurn() {
        XCTAssertEqual(StartButtonSpinMotion.targetAngle(from: 0, opening: false), StartButtonSpinMotion.turn, accuracy: 0.0001)
    }

    func testMidOpenContinuesClockwiseToRest() {
        XCTAssertEqual(StartButtonSpinMotion.targetAngle(from: -.pi, opening: true), -StartButtonSpinMotion.turn, accuracy: 0.0001)
    }

    func testMidOpenCloseUnwindsToRest() {
        XCTAssertEqual(StartButtonSpinMotion.targetAngle(from: -.pi, opening: false), 0, accuracy: 0.0001)
    }

    func testPartialTurnShortensDuration() {
        let full = StartButtonSpinMotion.duration(from: 0, to: -StartButtonSpinMotion.turn)
        let half = StartButtonSpinMotion.duration(from: -.pi, to: 0)
        XCTAssertEqual(full, StartButtonSpinMotion.fullTurnDuration, accuracy: 0.0001)
        XCTAssertEqual(half, StartButtonSpinMotion.fullTurnDuration / 2, accuracy: 0.0001)
    }
}

final class TaskItemIconLayoutTests: XCTestCase {
    func testIconGrowsWithTileHeight() {
        XCTAssertEqual(TaskItemView.iconLength(tileHeight: 26), 16)
        XCTAssertEqual(TaskItemView.iconLength(tileHeight: 38), 26)
        XCTAssertEqual(TaskItemView.iconLength(tileHeight: 62), 50)
    }

    func testBadgeGrowsWithIcon() {
        XCTAssertEqual(TaskItemView.badgeLength(iconLength: 26), 14)
        XCTAssertEqual(TaskItemView.badgeLength(iconLength: 50), 27)
    }

    func testBadgePullsInsideTallTile() {
        let tile = CGRect(x: 0, y: 0, width: 72, height: 62)
        let iconLength = TaskItemView.iconLength(tileHeight: tile.height)
        let icon = CGRect(
            x: (tile.width - iconLength) / 2,
            y: (tile.height - iconLength) / 2,
            width: iconLength,
            height: iconLength
        )
        let length = TaskItemView.badgeLength(iconLength: iconLength)
        let frame = TaskItemView.badgeFrame(iconFrame: icon, in: tile, length: length)
        XCTAssertTrue(tile.contains(frame))
        XCTAssertEqual(frame.width, length)
        XCTAssertEqual(frame.height, length)
        XCTAssertEqual(frame.maxX, tile.maxX, accuracy: 0.001)
        XCTAssertEqual(frame.maxY, tile.maxY, accuracy: 0.001)
    }

    func testBadgeKeepsIconCornerWhenItFits() {
        let tile = CGRect(x: 0, y: 0, width: 48, height: 38)
        let iconLength = TaskItemView.iconLength(tileHeight: tile.height)
        let icon = CGRect(
            x: (tile.width - iconLength) / 2,
            y: (tile.height - iconLength) / 2,
            width: iconLength,
            height: iconLength
        )
        let length = TaskItemView.badgeLength(iconLength: iconLength)
        let inset = length * (8 / 14)
        let frame = TaskItemView.badgeFrame(iconFrame: icon, in: tile, length: length)
        XCTAssertEqual(frame.minX, icon.maxX - inset, accuracy: 0.001)
        XCTAssertEqual(frame.minY, icon.maxY - inset, accuracy: 0.001)
        XCTAssertTrue(tile.contains(frame))
    }

    func testBadgePullsDownWithoutMovingLeftOnWideTile() {
        let tile = CGRect(x: 0, y: 0, width: 200, height: 62)
        let iconLength = TaskItemView.iconLength(tileHeight: tile.height)
        let icon = CGRect(x: 8, y: (tile.height - iconLength) / 2, width: iconLength, height: iconLength)
        let length = TaskItemView.badgeLength(iconLength: iconLength)
        let inset = length * (8 / 14)
        let frame = TaskItemView.badgeFrame(iconFrame: icon, in: tile, length: length)
        XCTAssertEqual(frame.minX, icon.maxX - inset, accuracy: 0.001)
        XCTAssertEqual(frame.maxY, tile.maxY, accuracy: 0.001)
        XCTAssertTrue(tile.contains(frame))
    }

    @MainActor
    func testCompactIconFillsTallerTiles() {
        let item = TaskItem(
            id: "pin-x",
            kind: .pinned(bundleID: "x", appName: "X", icon: nil, badge: nil)
        )
        var settings = AppSettings.default
        settings.iconOnly = true
        let view = TaskItemView(item: item, settings: settings)
        view.frame = NSRect(x: 0, y: 0, width: 72, height: 62)
        view.layoutSubtreeIfNeeded()
        let iconView = view.subviews.compactMap { $0 as? NSImageView }.first
        XCTAssertEqual(iconView?.frame.size, NSSize(width: 50, height: 50))
    }

    @MainActor
    func testLaidOutBadgeStaysInsideTallTile() {
        let item = TaskItem(
            id: "pin-x",
            kind: .pinned(bundleID: "x", appName: "X", icon: nil, badge: "1")
        )
        var settings = AppSettings.default
        settings.iconOnly = true
        let view = TaskItemView(item: item, settings: settings)
        view.frame = NSRect(x: 0, y: 0, width: 72, height: 62)
        view.layoutSubtreeIfNeeded()
        let badge = view.subviews.first {
            !($0 is NSImageView) && !($0 is NSTextField)
                && $0.frame.width >= 14
                && abs($0.frame.width - $0.frame.height) < 0.001
        }
        XCTAssertNotNil(badge)
        let frame = badge?.frame ?? .zero
        XCTAssertTrue(view.bounds.contains(frame))
        XCTAssertEqual(frame.maxX, view.bounds.maxX, accuracy: 0.001)
        XCTAssertEqual(frame.maxY, view.bounds.maxY, accuracy: 0.001)
    }
}

final class RunningMarkTests: XCTestCase {
    func testMarkCountFollowsGroupedWindows() {
        XCTAssertEqual(WindowDotsView.markCount(windowCount: 0, grouped: true), 0)
        XCTAssertEqual(WindowDotsView.markCount(windowCount: 1, grouped: true), 1)
        XCTAssertEqual(WindowDotsView.markCount(windowCount: 2, grouped: true), 2)
        XCTAssertEqual(WindowDotsView.markCount(windowCount: 3, grouped: true), 3)
        XCTAssertEqual(WindowDotsView.markCount(windowCount: 6, grouped: true), 3)
        XCTAssertEqual(WindowDotsView.markCount(windowCount: 4, grouped: false), 1)
    }

    func testSingleWindowKeepsThePill() {
        let bounds = CGRect(x: 0, y: 0, width: 26, height: 6)
        let active = WindowDotsView.markFrames(count: 1, active: true, in: bounds)
        let idle = WindowDotsView.markFrames(count: 1, active: false, in: bounds)
        XCTAssertEqual(active.count, 1)
        XCTAssertEqual(active[0].width, 22, accuracy: 0.001)
        XCTAssertEqual(active[0].height, 3, accuracy: 0.001)
        XCTAssertEqual(idle[0].width, 12, accuracy: 0.001)
        XCTAssertGreaterThan(active[0].width, idle[0].width)
    }

    func testTwoDotsSitUnderTheIcon() {
        let bounds = CGRect(x: 0, y: 0, width: 38, height: 6)
        let frames = WindowDotsView.markFrames(count: 2, active: true, in: bounds)
        XCTAssertEqual(frames.count, 2)
        XCTAssertEqual(frames[0].width, 4, accuracy: 0.001)
        XCTAssertEqual(frames[0].width, frames[0].height, accuracy: 0.001)
        XCTAssertEqual(frames[1].minX - frames[0].maxX, 3, accuracy: 0.001)
        let span = frames[1].maxX - frames[0].minX
        XCTAssertEqual(frames[0].minX, (bounds.width - span) / 2, accuracy: 0.001)
    }

    func testThreeDotsFitTheSmallestIcon() {
        let bounds = CGRect(x: 0, y: 0, width: 16, height: 6)
        let frames = WindowDotsView.markFrames(count: 5, active: false, in: bounds)
        XCTAssertEqual(frames.count, 3)
        XCTAssertGreaterThanOrEqual(frames[0].minX, 0)
        XCTAssertLessThanOrEqual(frames[2].maxX, bounds.width + 0.001)
        XCTAssertEqual(frames[0].width, frames[1].width, accuracy: 0.001)
        XCTAssertEqual(frames[0].width, frames[0].height, accuracy: 0.001)
        XCTAssertGreaterThan(frames[1].minX, frames[0].maxX)
    }

    @MainActor
    func testGroupedTileShowsDotCount() {
        var settings = AppSettings.default
        settings.groupByApplication = true
        let one = groupedItem(windowCount: 1)
        let two = groupedItem(windowCount: 2)
        let four = groupedItem(windowCount: 4)
        XCTAssertEqual(markCount(for: one, settings: settings), 1)
        XCTAssertEqual(markCount(for: two, settings: settings), 2)
        XCTAssertEqual(markCount(for: four, settings: settings), 3)
        XCTAssertFalse(dotsView(for: two, settings: settings).isHidden)

        settings.groupByApplication = false
        settings.iconOnly = true
        let window = TaskItem(id: "w", kind: .window(stubWindow(id: 1)))
        XCTAssertEqual(markCount(for: window, settings: settings), 1)
        XCTAssertEqual(markCount(for: two, settings: settings), 1)

        let pinned = TaskItem(
            id: "pin-x",
            kind: .pinned(bundleID: "x", appName: "X", icon: nil, badge: nil)
        )
        XCTAssertEqual(markCount(for: pinned, settings: AppSettings.default), 0)
        XCTAssertTrue(dotsView(for: pinned, settings: AppSettings.default).isHidden)
    }

    @MainActor
    func testDrawSplitsIntoSeparateDots() {
        XCTAssertEqual(blueRuns(count: 1, active: true), 1)
        XCTAssertEqual(blueRuns(count: 2, active: true), 2)
        XCTAssertEqual(blueRuns(count: 3, active: false), 3)
        XCTAssertEqual(blueRuns(count: 6, active: true), 3)
    }

    @MainActor
    private func groupedItem(windowCount: Int) -> TaskItem {
        let windows = (0..<windowCount).map { stubWindow(id: CGWindowID($0 + 1)) }
        return TaskItem(
            id: "group-x",
            kind: .grouped(bundleID: "x", appName: "X", windows: windows, badge: nil)
        )
    }

    @MainActor
    private func dotsView(for item: TaskItem, settings: AppSettings) -> WindowDotsView {
        let view = TaskItemView(item: item, settings: settings)
        view.frame = NSRect(x: 0, y: 0, width: 50, height: 50)
        view.layoutSubtreeIfNeeded()
        return view.subviews.compactMap { $0 as? WindowDotsView }.first!
    }

    @MainActor
    private func markCount(for item: TaskItem, settings: AppSettings) -> Int {
        dotsView(for: item, settings: settings).count
    }

    @MainActor
    private func blueRuns(count: Int, active: Bool) -> Int {
        let view = WindowDotsView(frame: NSRect(x: 0, y: 0, width: 38, height: 6))
        view.count = count
        view.activeIndex = active ? 0 : nil
        let scale = 2
        let pixelsWide = 38 * scale
        let pixelsHigh = 6 * scale
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelsWide,
            pixelsHigh: pixelsHigh,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            return -1
        }
        rep.size = view.bounds.size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        view.draw(view.bounds)
        NSGraphicsContext.restoreGraphicsState()

        var best = 0
        for y in 0..<pixelsHigh {
            var runs = 0
            var inside = false
            for x in 0..<pixelsWide {
                guard let color = rep.colorAt(x: x, y: y) else { continue }
                let lit = color.alphaComponent > 0.15
                    && color.blueComponent > color.redComponent + 0.05
                    && color.blueComponent > 0.15
                if lit && !inside {
                    runs += 1
                    inside = true
                } else if !lit {
                    inside = false
                }
            }
            best = max(best, runs)
        }
        return best
    }
}

final class TaskItemMiddleClickTests: XCTestCase {
    @MainActor
    func testMiddleClickFiresNewWindowCallback() {
        let item = TaskItem(
            id: "pin-x",
            kind: .pinned(bundleID: "x", appName: "X", icon: nil, badge: nil)
        )
        let view = TaskItemView(item: item, settings: .default)
        view.frame = NSRect(x: 0, y: 0, width: 48, height: 38)
        var clicked: String?
        view.onMiddleClick = { clicked = $0.id }
        view.otherMouseDown(with: mouseEvent(type: .otherMouseDown, button: .center, location: NSPoint(x: 24, y: 19)))
        XCTAssertEqual(clicked, item.id)
    }

    @MainActor
    func testTaskbarViewForwardsMiddleClick() {
        let bar = TaskbarView(frame: NSRect(x: 0, y: 0, width: 400, height: 40))
        let item = TaskItem(
            id: "pin-x",
            kind: .pinned(bundleID: "x", appName: "X", icon: nil, badge: nil)
        )
        bar.update(items: [item], settings: .default)
        bar.layoutSubtreeIfNeeded()
        var clicked: String?
        bar.onItemMiddleClick = { clicked = $0.id }
        let itemView = bar.view(forItemID: item.id) as? TaskItemView
        XCTAssertNotNil(itemView)
        itemView?.otherMouseDown(with: mouseEvent(type: .otherMouseDown, button: .center, location: NSPoint(x: 24, y: 19)))
        XCTAssertEqual(clicked, item.id)
    }

    @MainActor
    func testLeftClickDoesNotFireMiddleClick() {
        let item = TaskItem(
            id: "pin-x",
            kind: .pinned(bundleID: "x", appName: "X", icon: nil, badge: nil)
        )
        let view = TaskItemView(item: item, settings: .default)
        view.frame = NSRect(x: 0, y: 0, width: 48, height: 38)
        var middle = false
        view.onMiddleClick = { _ in middle = true }
        view.mouseDown(with: mouseEvent(type: .leftMouseDown, button: .left, location: NSPoint(x: 24, y: 19)))
        view.mouseUp(with: mouseEvent(type: .leftMouseUp, button: .left, location: NSPoint(x: 24, y: 19)))
        XCTAssertFalse(middle)
    }

    @MainActor
    private func mouseEvent(type: CGEventType, button: CGMouseButton, location: NSPoint) -> NSEvent {
        let cgEvent = CGEvent(
            mouseEventSource: nil,
            mouseType: type,
            mouseCursorPosition: CGPoint(x: location.x, y: location.y),
            mouseButton: button
        )!
        return NSEvent(cgEvent: cgEvent)!
    }
}

final class ThumbnailPreviewClickTests: XCTestCase {
    @MainActor
    func testMiddleClickClosesPreviewWindow() {
        let window = stubWindow(id: 7, title: "Doc")
        let item = TaskItem(id: window.orderKey, kind: .window(window))
        let card = ThumbnailCardView(frame: NSRect(x: 0, y: 0, width: 240, height: 160))
        card.configure(window: window, item: item, size: 240, showTitle: true)
        var closed: CGWindowID?
        card.onClose = { closed = $0.id }
        card.otherMouseDown(with: otherMouseEvent(at: NSPoint(x: 120, y: 80)))
        XCTAssertEqual(closed, window.id)
    }

    @MainActor
    func testLeftClickDoesNotClosePreviewWindow() {
        let window = stubWindow(id: 8, title: "Doc")
        let item = TaskItem(id: window.orderKey, kind: .window(window))
        let card = ThumbnailCardView(frame: NSRect(x: 0, y: 0, width: 240, height: 160))
        card.configure(window: window, item: item, size: 240, showTitle: true)
        var closed = false
        var raised = false
        card.onClose = { _ in closed = true }
        card.onRaise = { _ in raised = true }
        card.mouseDown(with: leftMouseEvent(at: NSPoint(x: 120, y: 80)))
        XCTAssertTrue(raised)
        XCTAssertFalse(closed)
    }

    @MainActor
    private func otherMouseEvent(at location: NSPoint) -> NSEvent {
        mouseEvent(type: .otherMouseDown, button: .center, location: location)
    }

    @MainActor
    private func leftMouseEvent(at location: NSPoint) -> NSEvent {
        mouseEvent(type: .leftMouseDown, button: .left, location: location)
    }

    @MainActor
    private func mouseEvent(type: CGEventType, button: CGMouseButton, location: NSPoint) -> NSEvent {
        let cgEvent = CGEvent(
            mouseEventSource: nil,
            mouseType: type,
            mouseCursorPosition: CGPoint(x: location.x, y: location.y),
            mouseButton: button
        )!
        return NSEvent(cgEvent: cgEvent)!
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

    @MainActor
    func testLetterClassifiesAsciiInitials() {
        XCTAssertEqual(AppCatalog.letter(for: "Arcade"), "A")
        XCTAssertEqual(AppCatalog.letter(for: "1Password"), "#")
        XCTAssertEqual(AppCatalog.letter(for: ""), "#")
    }

    @MainActor
    func testGroupsMatchingEmptyQueryUsesSortedLetters() {
        let catalog = AppCatalog.shared
        let apps = [
            AppCatalog.CatalogApp(bundleID: "c", name: "1Password", url: URL(fileURLWithPath: "/tmp/c.app")),
            AppCatalog.CatalogApp(bundleID: "a", name: "Arcade", url: URL(fileURLWithPath: "/tmp/a.app"))
        ]
        let grouped = catalog.groupedByLetter(apps)
        XCTAssertEqual(grouped.map(\.letter), ["#", "A"])
        let filtered = AppCatalog.filter(apps, query: "arc")
        XCTAssertEqual(filtered.map(\.name), ["Arcade"])
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

    @MainActor
    func testReuseKeepsRowIdentitiesOnUnchangedUpdate() {
        let view = AppListView(frame: NSRect(x: 0, y: 0, width: 300, height: 200))
        let apps = [
            AppCatalog.CatalogApp(bundleID: "a", name: "Arcade", url: URL(fileURLWithPath: "/tmp/Arcade.app")),
            AppCatalog.CatalogApp(bundleID: "b", name: "Books", url: URL(fileURLWithPath: "/tmp/Books.app"))
        ]
        let groups = AppCatalog.shared.groupedByLetter(apps)
        view.update(groups)
        view.layoutSubtreeIfNeeded()
        let before = view.documentView?.subviews.map { ObjectIdentifier($0) }
        view.update(groups)
        view.layoutSubtreeIfNeeded()
        let after = view.documentView?.subviews.map { ObjectIdentifier($0) }
        XCTAssertEqual(before, after)
        XCTAssertEqual(view.documentView?.subviews.count, 4)
    }

    @MainActor
    func testSearchNarrowsThenRestoresRows() {
        let view = AppListView(frame: NSRect(x: 0, y: 0, width: 300, height: 200))
        let apps = [
            AppCatalog.CatalogApp(bundleID: "a", name: "Arcade", url: URL(fileURLWithPath: "/tmp/Arcade.app")),
            AppCatalog.CatalogApp(bundleID: "b", name: "Books", url: URL(fileURLWithPath: "/tmp/Books.app"))
        ]
        view.update(AppCatalog.shared.groupedByLetter(apps))
        view.update(AppCatalog.shared.groupedByLetter(AppCatalog.filter(apps, query: "book")))
        view.layoutSubtreeIfNeeded()
        XCTAssertEqual(
            view.documentView?.subviews.compactMap { $0 as? NSTextField }.map(\.stringValue),
            ["B"]
        )
        view.update(AppCatalog.shared.groupedByLetter(apps))
        view.layoutSubtreeIfNeeded()
        XCTAssertEqual(
            view.documentView?.subviews.compactMap { $0 as? NSTextField }.map(\.stringValue),
            ["A", "B"]
        )
        XCTAssertEqual(view.documentView?.subviews.count, 4)
    }

    @MainActor
    func testHoverHighlightsOnlyTheRowUnderThePoint() {
        let view = AppListView(frame: NSRect(x: 0, y: 0, width: 300, height: 80))
        let apps = [
            AppCatalog.CatalogApp(bundleID: "a", name: "Arcade", url: URL(fileURLWithPath: "/tmp/Arcade.app")),
            AppCatalog.CatalogApp(bundleID: "b", name: "Books", url: URL(fileURLWithPath: "/tmp/Books.app")),
            AppCatalog.CatalogApp(bundleID: "c", name: "Chess", url: URL(fileURLWithPath: "/tmp/Chess.app")),
            AppCatalog.CatalogApp(bundleID: "d", name: "Dictionary", url: URL(fileURLWithPath: "/tmp/Dictionary.app")),
            AppCatalog.CatalogApp(bundleID: "t", name: "Tips", url: URL(fileURLWithPath: "/tmp/Tips.app"))
        ]
        view.update(AppCatalog.shared.groupedByLetter(apps))
        view.layoutSubtreeIfNeeded()

        for name in ["Arcade", "Books", "Chess", "Dictionary", "Tips"] {
            let point = view.documentPoint(forAppName: name)
            XCTAssertNotNil(point, name)
            view.syncHover(atDocumentPoint: point)
            XCTAssertEqual(view.highlightedAppNames, [name])
        }

        view.syncHover(atDocumentPoint: NSPoint(x: 10, y: 8))
        XCTAssertEqual(view.highlightedAppNames, [])

        view.syncHover(atDocumentPoint: view.documentPoint(forAppName: "Chess"))
        XCTAssertEqual(view.highlightedAppNames, ["Chess"])
        view.syncHover(atDocumentPoint: nil)
        XCTAssertEqual(view.highlightedAppNames, [])
    }

    @MainActor
    func testHoverClearsWhenMouseCannotBeResolved() {
        let view = AppListView(frame: NSRect(x: 0, y: 0, width: 300, height: 80))
        let apps = [
            AppCatalog.CatalogApp(bundleID: "a", name: "Arcade", url: URL(fileURLWithPath: "/tmp/Arcade.app")),
            AppCatalog.CatalogApp(bundleID: "b", name: "Books", url: URL(fileURLWithPath: "/tmp/Books.app"))
        ]
        view.update(AppCatalog.shared.groupedByLetter(apps))
        view.layoutSubtreeIfNeeded()
        view.syncHover(atDocumentPoint: view.documentPoint(forAppName: "Books"))
        XCTAssertEqual(view.highlightedAppNames, ["Books"])
        view.updateHoverFromMouse()
        XCTAssertEqual(view.highlightedAppNames, [])
    }

    @MainActor
    func testArrowKeysMoveHighlightAndClamp() {
        let view = AppListView(frame: NSRect(x: 0, y: 0, width: 300, height: 200))
        view.update(AppCatalog.shared.groupedByLetter(Self.navApps))
        view.layoutSubtreeIfNeeded()

        view.moveSelection(delta: 1)
        XCTAssertEqual(view.highlightedAppNames, ["Arcade"])
        view.moveSelection(delta: 1)
        XCTAssertEqual(view.highlightedAppNames, ["Books"])
        view.moveSelection(delta: 1)
        XCTAssertEqual(view.highlightedAppNames, ["Chess"])
        view.moveSelection(delta: 1)
        XCTAssertEqual(view.highlightedAppNames, ["Chess"])
        view.moveSelection(delta: -1)
        XCTAssertEqual(view.highlightedAppNames, ["Books"])
        view.moveSelection(delta: -1)
        XCTAssertEqual(view.highlightedAppNames, ["Arcade"])
        view.moveSelection(delta: -1)
        XCTAssertEqual(view.highlightedAppNames, ["Arcade"])
    }

    @MainActor
    func testFilterAutoselectsFirstAndKeepsVisibleSelection() {
        let view = AppListView(frame: NSRect(x: 0, y: 0, width: 300, height: 200))
        view.update(AppCatalog.shared.groupedByLetter(Self.navApps))
        view.update(
            AppCatalog.shared.groupedByLetter(AppCatalog.filter(Self.navApps, query: "arc")),
            autoselectFirst: true
        )
        XCTAssertEqual(view.highlightedAppNames, ["Arcade"])

        view.update(AppCatalog.shared.groupedByLetter(Self.navApps), autoselectFirst: false)
        view.moveSelection(delta: 1)
        XCTAssertEqual(view.highlightedAppNames, ["Books"])

        view.update(
            AppCatalog.shared.groupedByLetter(AppCatalog.filter(Self.navApps, query: "book")),
            autoselectFirst: true
        )
        XCTAssertEqual(view.highlightedAppNames, ["Books"])

        view.update(
            AppCatalog.shared.groupedByLetter(AppCatalog.filter(Self.navApps, query: "chess")),
            autoselectFirst: true
        )
        XCTAssertEqual(view.highlightedAppNames, ["Chess"])
    }

    @MainActor
    func testLaunchSelectedInvokesOnLaunch() {
        let view = AppListView(frame: NSRect(x: 0, y: 0, width: 300, height: 200))
        view.update(AppCatalog.shared.groupedByLetter(Self.navApps))
        var launched: [String] = []
        view.onLaunch = { launched.append($0.name) }

        view.launchSelected()
        XCTAssertEqual(launched, [])

        view.moveSelection(delta: 1)
        view.launchSelected()
        XCTAssertEqual(launched, ["Arcade"])
    }

    @MainActor
    func testKeyboardHighlightSurvivesMouseReconcile() {
        let view = AppListView(frame: NSRect(x: 0, y: 0, width: 300, height: 80))
        view.update(AppCatalog.shared.groupedByLetter(Self.navApps))
        view.layoutSubtreeIfNeeded()
        view.moveSelection(delta: 1)
        view.moveSelection(delta: 1)
        XCTAssertEqual(view.highlightedAppNames, ["Books"])
        view.updateHoverFromMouse()
        XCTAssertEqual(view.highlightedAppNames, ["Books"])
    }

    private static let navApps = [
        AppCatalog.CatalogApp(bundleID: "a", name: "Arcade", url: URL(fileURLWithPath: "/tmp/Arcade.app")),
        AppCatalog.CatalogApp(bundleID: "b", name: "Books", url: URL(fileURLWithPath: "/tmp/Books.app")),
        AppCatalog.CatalogApp(bundleID: "c", name: "Chess", url: URL(fileURLWithPath: "/tmp/Chess.app"))
    ]
}

final class TaskbarSnapshotUITests: XCTestCase {
    @MainActor
    func testFrameOnlyChangeIsUIEqual() {
        let window = stubWindow(id: 1, title: "Docs")
        var moved = window
        moved = WindowInfo(
            id: window.id,
            pid: window.pid,
            bundleID: window.bundleID,
            appName: window.appName,
            title: window.title,
            frame: CGRect(x: 40, y: 40, width: 800, height: 600),
            screenID: window.screenID,
            spaces: window.spaces,
            isMinimized: window.isMinimized,
            isHidden: window.isHidden,
            isFullscreen: window.isFullscreen,
            isOnScreen: window.isOnScreen,
            isTabbed: window.isTabbed,
            isActive: window.isActive,
            layer: window.layer
        )
        let item = TaskItem(id: window.orderKey, kind: .window(window))
        let lhs = TaskbarSnapshot(
            windows: [window],
            itemsByScreen: [1: [item]],
            currentSpaces: [1: 10],
            fullscreenDisplays: [],
            generatedAt: .now
        )
        let rhs = TaskbarSnapshot(
            windows: [moved],
            itemsByScreen: [1: [TaskItem(id: moved.orderKey, kind: .window(moved))]],
            currentSpaces: [1: 10],
            fullscreenDisplays: [],
            generatedAt: .now
        )
        XCTAssertTrue(window.matchesTaskbar(moved))
        XCTAssertTrue(lhs.uiEquals(rhs))
        XCTAssertNotEqual(lhs, rhs)
    }

    @MainActor
    func testTitleChangeIsNotUIEqual() {
        let window = stubWindow(id: 1, title: "Docs")
        let renamed = stubWindow(id: 1, title: "Other")
        let lhs = TaskbarSnapshot(
            windows: [window],
            itemsByScreen: [1: [TaskItem(id: window.orderKey, kind: .window(window))]],
            currentSpaces: [1: 10],
            fullscreenDisplays: [],
            generatedAt: .now
        )
        let rhs = TaskbarSnapshot(
            windows: [renamed],
            itemsByScreen: [1: [TaskItem(id: renamed.orderKey, kind: .window(renamed))]],
            currentSpaces: [1: 10],
            fullscreenDisplays: [],
            generatedAt: .now
        )
        XCTAssertFalse(window.matchesTaskbar(renamed))
        XCTAssertFalse(lhs.uiEquals(rhs))
    }
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
