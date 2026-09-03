import XCTest
@testable import Omnibar

final class PinStoreTests: XCTestCase {
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
    func testPinAppendsAndRoundTrips() {
        let store = PinStore(defaults: isolated.defaults)
        store.pin("com.apple.Safari")
        store.pin("com.apple.finder")
        XCTAssertEqual(store.pinnedBundleIDs, ["com.apple.Safari", "com.apple.finder"])
        XCTAssertTrue(store.isPinned("com.apple.Safari"))
        XCTAssertEqual(
            isolated.defaults.stringArray(forKey: PinStore.defaultsKey),
            ["com.apple.Safari", "com.apple.finder"]
        )
        let reloaded = PinStore(defaults: isolated.defaults)
        XCTAssertEqual(reloaded.pinnedBundleIDs, ["com.apple.Safari", "com.apple.finder"])
    }

    @MainActor
    func testPinIgnoresEmptyAndDuplicates() {
        let store = PinStore(defaults: isolated.defaults)
        store.pin("")
        store.pin("a")
        store.pin("a")
        XCTAssertEqual(store.pinnedBundleIDs, ["a"])
    }

    @MainActor
    func testUnpinAndToggle() {
        let store = PinStore(defaults: isolated.defaults)
        store.toggle("a")
        XCTAssertTrue(store.isPinned("a"))
        store.toggle("a")
        XCTAssertFalse(store.isPinned("a"))
        store.pin("b")
        store.unpin("b")
        XCTAssertEqual(store.pinnedBundleIDs, [])
    }

    @MainActor
    func testMoveClampsAndIgnoresUnknown() {
        let store = PinStore(defaults: isolated.defaults)
        store.replace(["a", "b", "c"])
        store.move(id: "a", to: 99)
        XCTAssertEqual(store.pinnedBundleIDs, ["b", "c", "a"])
        store.move(id: "a", to: -4)
        XCTAssertEqual(store.pinnedBundleIDs, ["a", "b", "c"])
        store.move(id: "missing", to: 0)
        XCTAssertEqual(store.pinnedBundleIDs, ["a", "b", "c"])
    }
}
