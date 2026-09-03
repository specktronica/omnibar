import XCTest
@testable import Omnibar

final class OrderStoreGapsTests: XCTestCase {
    @MainActor
    func testMoveToIndexClamps() {
        OrderStore.shared.reset()
        defer { OrderStore.shared.reset() }
        let store = OrderStore.shared
        store.replace(["a", "b", "c"])
        store.move(id: "a", to: 100)
        XCTAssertEqual(store.sorted(["a", "b", "c"]) { $0 }, ["b", "c", "a"])
        store.move(id: "a", to: -2)
        XCTAssertEqual(store.sorted(["a", "b", "c"]) { $0 }, ["a", "b", "c"])
    }

    @MainActor
    func testMoveBeforeNilAppends() {
        OrderStore.shared.reset()
        defer { OrderStore.shared.reset() }
        let store = OrderStore.shared
        store.replace(["a", "b", "c"])
        store.move(id: "a", before: nil)
        XCTAssertEqual(store.sorted(["a", "b", "c"]) { $0 }, ["b", "c", "a"])
    }

    @MainActor
    func testUnknownKeysSortLastThenLexicographically() {
        OrderStore.shared.reset()
        defer { OrderStore.shared.reset() }
        let store = OrderStore.shared
        store.replace(["b"])
        XCTAssertEqual(store.sorted(["z", "a", "b"]) { $0 }, ["b", "a", "z"])
    }

    @MainActor
    func testKeepAcrossSpaceChangePrunesAfterCap() {
        OrderStore.shared.reset()
        defer { OrderStore.shared.reset() }
        let store = OrderStore.shared
        let keys = (0..<401).map { "k\($0)" }
        store.record(
            keys: keys,
            keepAcrossSpaceChange: true,
            appearing: Set(keys),
            disappearing: []
        )
        XCTAssertEqual(store.order.count, 401)
        let dropped = keys[400]
        store.record(
            keys: Array(keys.dropLast()),
            keepAcrossSpaceChange: true,
            appearing: [],
            disappearing: [dropped]
        )
        XCTAssertFalse(store.order.contains(dropped))
        XCTAssertEqual(store.order.count, 400)
    }

    @MainActor
    func testKeepAcrossSpaceChangeDoesNotPruneBelowCap() {
        OrderStore.shared.reset()
        defer { OrderStore.shared.reset() }
        let store = OrderStore.shared
        store.record(
            keys: ["a", "b", "c"],
            keepAcrossSpaceChange: true,
            appearing: ["a", "b", "c"],
            disappearing: []
        )
        store.record(
            keys: ["a", "c"],
            keepAcrossSpaceChange: true,
            appearing: [],
            disappearing: ["b"]
        )
        XCTAssertEqual(store.order, ["a", "b", "c"])
    }
}
