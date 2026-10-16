import XCTest
@testable import Omnibar

@MainActor
final class WindowFocusTests: XCTestCase {
    func testSwitchesSpaceBeforeFocusingEvenWhenAXElementIsAvailable() {
        var controller = WindowFocusController()
        let window = stubWindow(id: 1, screen: 2, spaces: [20], onScreen: false)
        let now = Date()
        var events: [String] = []
        controller.raise(window, spaceState: .hidden(20), now: now, switchToSpace: {
            events.append("switch-\($0)")
            return true
        }, focus: { _ in
            events.append("focus")
            return true
        })
        XCTAssertEqual(events, ["switch-20"])
        XCTAssertTrue(controller.hasPendingFocus)

        // An AX element alone does not prove that the Space transition completed.
        for visible: Set<UInt64> in [[10], []] {
            controller.completePendingFocus(windows: [window], visibleSpaces: visible, now: now) { _ in
                events.append("premature-focus")
                return true
            }
        }
        XCTAssertEqual(events, ["switch-20"])
        controller.completePendingFocus(windows: [window], visibleSpaces: [10, 20], now: now) { focused in
            XCTAssertEqual(focused.id, window.id)
            events.append("focus")
            return true
        }
        XCTAssertEqual(events, ["switch-20", "focus"])
        XCTAssertFalse(controller.hasPendingFocus)
    }

    func testFailedSpaceSwitchDoesNotActivateOnCurrentSpace() {
        var controller = WindowFocusController()
        controller.raise(stubWindow(id: 1, spaces: [20]), spaceState: .hidden(20), switchToSpace: { _ in
            false
        }, focus: { _ in
            XCTFail("Must not activate an app on the wrong Space")
            return true
        })
        XCTAssertFalse(controller.hasPendingFocus)
    }

    func testVisibleWindowsFocusWithoutSwitchingIncludingOtherDisplaysAndStickyWindows() {
        for assignments: [UInt64] in [[20], [30, 20]] {
            var controller = WindowFocusController()
            let window = stubWindow(id: 1, screen: 2, spaces: assignments)
            let state = WindowSpaceState(windowSpaces: assignments, visibleSpaces: [10, 20])
            XCTAssertEqual(state, .visible)
            var didFocus = false
            controller.raise(window, spaceState: state, switchToSpace: { _ in
                XCTFail("A visible destination needs no Space switch")
                return false
            }, focus: { _ in
                didFocus = true
                return true
            })
            XCTAssertTrue(didFocus)
        }
        XCTAssertEqual(WindowSpaceState(windowSpaces: [0], visibleSpaces: [10]), .unknown)
        XCTAssertEqual(WindowSpaceState(windowSpaces: [20], visibleSpaces: [0]), .unknown)
        XCTAssertEqual(WindowSpaceState(windowSpaces: [20], visibleSpaces: [10]), .hidden(20))
    }

    func testMinimizedAndHiddenWindowsWaitForTheirSpace() {
        for window in [
            stubWindow(id: 1, spaces: [20], minimized: true, onScreen: false),
            stubWindow(id: 2, spaces: [20], hidden: true, onScreen: false),
        ] {
            var controller = WindowFocusController()
            controller.raise(window, spaceState: .hidden(20), switchToSpace: { _ in true }, focus: { _ in
                XCTFail("Must not restore a window on the wrong Space")
                return true
            })
            XCTAssertTrue(controller.hasPendingFocus)
        }
    }

    func testPendingFocusWaitsForAXThenExpiresIfWindowCloses() {
        var controller = WindowFocusController()
        let window = stubWindow(id: 1, spaces: [20], onScreen: false)
        let now = Date()
        controller.raise(window, spaceState: .hidden(20), now: now, switchToSpace: { _ in true }, focus: { _ in false })
        controller.completePendingFocus(windows: [window], visibleSpaces: [20], now: now) { _ in false }
        XCTAssertTrue(controller.hasPendingFocus)
        controller.completePendingFocus(windows: [], visibleSpaces: [20], now: now.addingTimeInterval(6)) { _ in
            XCTFail("Expired requests must not steal focus later")
            return true
        }
        XCTAssertFalse(controller.hasPendingFocus)
    }

    func testLatestClickCancelsPendingFocus() {
        var controller = WindowFocusController()
        let first = stubWindow(id: 1, spaces: [20], onScreen: false)
        let second = stubWindow(id: 2, spaces: [10])
        controller.raise(first, spaceState: .hidden(20), switchToSpace: { _ in true }, focus: { _ in false })
        controller.raise(second, spaceState: .visible, switchToSpace: { _ in false }, focus: { _ in true })
        controller.completePendingFocus(windows: [first], visibleSpaces: [20]) { _ in
            XCTFail("The earlier click must not steal focus")
            return true
        }
        XCTAssertFalse(controller.hasPendingFocus)
    }

    func testPinnedAppUsesExistingWindowOnAnotherScreen() {
        let elsewhere = stubWindow(id: 1, bundle: "pinned.app", screen: 2, spaces: [20], onScreen: false)
        let unrelated = stubWindow(id: 2, bundle: "other.app")
        XCTAssertEqual(
            WindowActions.windowToRaise(forPinnedBundleID: "pinned.app", windows: [unrelated, elsewhere])?.id,
            elsewhere.id
        )
        XCTAssertNil(WindowActions.windowToRaise(forPinnedBundleID: "closed.app", windows: [unrelated, elsewhere]))
    }
}
