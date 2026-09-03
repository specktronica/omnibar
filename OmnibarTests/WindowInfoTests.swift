import XCTest
@testable import Omnibar

final class WindowInfoTests: XCTestCase {
    @MainActor
    func testBelongsToSpace() {
        let window = stubWindow(id: 1, spaces: [10, 11])
        XCTAssertTrue(window.belongs(toSpace: nil))
        XCTAssertTrue(window.belongs(toSpace: 10))
        XCTAssertFalse(window.belongs(toSpace: 99))
        let unassigned = stubWindow(id: 2, spaces: [])
        XCTAssertTrue(unassigned.belongs(toSpace: 99))
    }

    @MainActor
    func testDisplayTitleFallsBackToAppName() {
        let titled = stubWindow(id: 1, title: "Docs", appName: "Safari")
        XCTAssertEqual(titled.displayTitle, "Docs")
        let blank = stubWindow(id: 2, title: "   ", appName: "Safari")
        XCTAssertEqual(blank.displayTitle, "Safari")
        let empty = stubWindow(id: 3, title: "", appName: "Safari")
        XCTAssertEqual(empty.displayTitle, "Safari")
    }

    @MainActor
    func testOrderKeyUsesPidAndID() {
        let window = stubWindow(id: 7, pid: 13)
        XCTAssertEqual(window.orderKey, "13-7")
    }
}
