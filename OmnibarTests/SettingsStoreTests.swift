import XCTest
@testable import Omnibar

final class SettingsStoreTests: XCTestCase {
    private var isolated: IsolatedDefaults!

    override func setUp() {
        super.setUp()
        isolated = IsolatedDefaults()
    }

    override func tearDown() {
        isolated = nil
        super.tearDown()
    }

    @MainActor
    func testEmptyDefaultsLoadsAppSettingsDefault() {
        let store = isolatedSettingsStore(isolated.defaults)
        XCTAssertEqual(store.settings, .default)
    }

    @MainActor
    func testUpdatePersistsAndReloads() {
        let store = isolatedSettingsStore(isolated.defaults)
        store.update {
            $0.transparency = 0.2
            $0.recentAppsLimit = 4
            $0.overlapSkipBundleIDs = ["com.skip"]
        }
        XCTAssertNotNil(isolated.defaults.data(forKey: SettingsStore.defaultsKey))
        let reloaded = isolatedSettingsStore(isolated.defaults)
        XCTAssertEqual(reloaded.settings.transparency, 0.2)
        XCTAssertEqual(reloaded.settings.recentAppsLimit, 4)
        XCTAssertEqual(reloaded.settings.overlapSkipBundleIDs, ["com.skip"])
    }

    @MainActor
    func testMalformedJSONFallsBackToDefault() {
        isolated.defaults.set(Data("not-json".utf8), forKey: SettingsStore.defaultsKey)
        let store = isolatedSettingsStore(isolated.defaults)
        XCTAssertEqual(store.settings, .default)
    }

    @MainActor
    func testLoadReadsPersistedValues() throws {
        let store = isolatedSettingsStore(isolated.defaults)
        var persisted = AppSettings.default
        persisted.pollInterval = 4.25
        isolated.defaults.set(try JSONEncoder().encode(persisted), forKey: SettingsStore.defaultsKey)
        store.load()
        XCTAssertEqual(store.settings.pollInterval, 4.25)
    }

    @MainActor
    func testResetToDefaultsKeepsLaunchAtLoginAndClearsOrder() {
        let backup = OrderStore.shared.order
        OrderStore.shared.reset()
        defer { OrderStore.shared.replace(backup) }
        let store = isolatedSettingsStore(isolated.defaults)
        store.update {
            $0.launchAtLogin = true
            $0.transparency = 0.1
            $0.taskbarHeight = 64
        }
        OrderStore.shared.replace(["a", "b"])
        store.resetToDefaults()
        XCTAssertTrue(store.settings.launchAtLogin)
        XCTAssertEqual(store.settings.transparency, AppSettings.default.transparency)
        XCTAssertEqual(store.settings.taskbarHeight, AppSettings.default.taskbarHeight)
        XCTAssertTrue(OrderStore.shared.order.isEmpty)
    }

    @MainActor
    func testFullyHideDockChangeUsesHookNotDockManager() {
        var applied = 0
        let store = SettingsStore(
            defaults: isolated.defaults,
            syncLoginItem: { _ in },
            applyDockFromSettings: { applied += 1 },
            revertDock: {}
        )
        store.update { $0.fullyHideDock = false }
        XCTAssertEqual(applied, 1)
    }
}
