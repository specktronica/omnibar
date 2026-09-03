import XCTest
@testable import Omnibar

@MainActor
final class ShowDesktopLogicTests: XCTestCase {
    func testShowingWindowsSkipsMinimizedHiddenAndFullscreen() {
        let visible = stubWindow(id: 1)
        let minimized = stubWindow(id: 2, minimized: true)
        let hidden = stubWindow(id: 3, hidden: true)
        let fullscreen = stubWindow(id: 4, fullscreen: true)
        let showing = ShowDesktopLogic.showingWindows(
            from: [visible, minimized, hidden, fullscreen],
            currentSpaces: [1: 10]
        )
        XCTAssertEqual(showing.map(\.id), [1])
    }

    func testShowingWindowsKeepsCurrentSpaceAndUnassigned() {
        let onSpace = stubWindow(id: 1, spaces: [10])
        let otherSpace = stubWindow(id: 2, spaces: [11])
        let unassigned = stubWindow(id: 3, spaces: [])
        let showing = ShowDesktopLogic.showingWindows(
            from: [onSpace, otherSpace, unassigned],
            currentSpaces: [1: 10]
        )
        XCTAssertEqual(showing.map(\.id), [1, 3])
    }

    func testShowingWindowsIncludesAllWhenCurrentSpacesUnknown() {
        let a = stubWindow(id: 1, spaces: [10])
        let b = stubWindow(id: 2, spaces: [11])
        let showing = ShowDesktopLogic.showingWindows(
            from: [a, b],
            currentSpaces: [:]
        )
        XCTAssertEqual(showing.map(\.id), [1, 2])
    }

    func testActionMinimizesVisibleWindows() {
        let a = stubWindow(id: 1)
        let b = stubWindow(id: 2)
        let action = ShowDesktopLogic.action(showing: [a, b], restoreIDs: [])
        XCTAssertEqual(action, .minimize([a, b]))
    }

    func testActionRestoresWhenNothingVisible() {
        let action = ShowDesktopLogic.action(showing: [], restoreIDs: [1, 2])
        XCTAssertEqual(action, .restore([1, 2]))
    }

    func testActionNoneWhenDesktopAlreadyClear() {
        XCTAssertEqual(ShowDesktopLogic.action(showing: [], restoreIDs: []), .none)
    }

    func testActionTreatsPendingIDsAsHiddenForStaleScan() {
        let a = stubWindow(id: 1)
        let b = stubWindow(id: 2)
        let action = ShowDesktopLogic.action(showing: [a, b], restoreIDs: [1, 2])
        XCTAssertEqual(action, .restore([1, 2]))
    }

    func testActionMinimizesWindowsOpenedAfterShowDesktop() {
        let pending = stubWindow(id: 1)
        let opened = stubWindow(id: 2)
        let action = ShowDesktopLogic.action(showing: [pending, opened], restoreIDs: [1])
        XCTAssertEqual(action, .minimize([opened]))
    }

    func testAppendingRestoreListPutsNewWindowsInFront() {
        XCTAssertEqual(
            ShowDesktopLogic.appendingRestoreList(existing: [1, 2, 3], newlyMinimized: [4]),
            [4, 1, 2, 3]
        )
        XCTAssertEqual(
            ShowDesktopLogic.appendingRestoreList(existing: [1, 2], newlyMinimized: [2, 3]),
            [2, 3, 1]
        )
        XCTAssertEqual(
            ShowDesktopLogic.appendingRestoreList(existing: [], newlyMinimized: [8]),
            [8]
        )
    }

    func testTrailingInsetReservesTheSlice() {
        XCTAssertEqual(ShowDesktopLogic.trailingInset(buttonEnabled: false), 8)
        XCTAssertEqual(
            ShowDesktopLogic.trailingInset(buttonEnabled: true),
            ShowDesktopLogic.buttonWidth + ShowDesktopLogic.tileTrailingGap
        )
    }
}
