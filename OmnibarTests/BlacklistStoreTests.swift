import XCTest
@testable import Omnibar

final class BlacklistStoreTests: XCTestCase {
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
    func testAddContainsAndPersistsSorted() {
        let store = BlacklistStore(defaults: isolated.defaults)
        store.add("com.b")
        store.add("com.a")
        XCTAssertTrue(store.contains("com.a"))
        XCTAssertEqual(store.bundleIDs, ["com.a", "com.b"])
        XCTAssertEqual(isolated.defaults.stringArray(forKey: BlacklistStore.defaultsKey), ["com.a", "com.b"])
        let reloaded = BlacklistStore(defaults: isolated.defaults)
        XCTAssertEqual(reloaded.bundleIDs, ["com.a", "com.b"])
    }

    @MainActor
    func testAddIgnoresEmpty() {
        let store = BlacklistStore(defaults: isolated.defaults)
        store.add("")
        XCTAssertTrue(store.bundleIDs.isEmpty)
        XCTAssertNil(isolated.defaults.stringArray(forKey: BlacklistStore.defaultsKey))
    }

    @MainActor
    func testRemoveAndReplace() {
        let store = BlacklistStore(defaults: isolated.defaults)
        store.replace(["x", "y", "x"])
        XCTAssertEqual(store.bundleIDs, ["x", "y"])
        store.remove("x")
        XCTAssertFalse(store.contains("x"))
        XCTAssertEqual(store.bundleIDs, ["y"])
    }
}
