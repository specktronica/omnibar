import AppKit
import XCTest
@testable import Omnibar

@MainActor
final class StartMenuOutsideClickTests: XCTestCase {
    func testOpeningClickOnStartButtonIsSwallowedWithoutDismiss() {
        XCTAssertEqual(
            StartMenuOutsideClick.decision(
                eventWindowIsMenu: false,
                inStartButton: true,
                isOpeningClick: true
            ),
            .swallow
        )
    }

    func testOpeningClickElsewhereIsIgnored() {
        XCTAssertEqual(
            StartMenuOutsideClick.decision(
                eventWindowIsMenu: false,
                inStartButton: false,
                isOpeningClick: true
            ),
            .pass
        )
    }

    func testLaterClickOnStartButtonDismissesAndSwallows() {
        XCTAssertEqual(
            StartMenuOutsideClick.decision(
                eventWindowIsMenu: false,
                inStartButton: true,
                isOpeningClick: false
            ),
            .dismiss(swallow: true)
        )
    }

    func testLaterClickOutsideDismisses() {
        XCTAssertEqual(
            StartMenuOutsideClick.decision(
                eventWindowIsMenu: false,
                inStartButton: false,
                isOpeningClick: false
            ),
            .dismiss(swallow: false)
        )
    }

    func testClicksInsideMenuAreAllowed() {
        XCTAssertEqual(
            StartMenuOutsideClick.decision(
                eventWindowIsMenu: true,
                inStartButton: false,
                isOpeningClick: false
            ),
            .pass
        )
    }

    func testOpeningClickUsesEventTimestampAtOrBeforePresent() {
        XCTAssertTrue(StartMenuOutsideClick.isOpeningClick(eventTimestamp: 1.0, presentedAt: 1.0))
        XCTAssertTrue(StartMenuOutsideClick.isOpeningClick(eventTimestamp: 0.9, presentedAt: 1.0))
        XCTAssertFalse(StartMenuOutsideClick.isOpeningClick(eventTimestamp: 1.1, presentedAt: 1.0))
    }
}

@MainActor
final class StartButtonHitTestingTests: XCTestCase {
    func testAcceptsFirstMouse() {
        let button = StartButtonView(frame: NSRect(x: 0, y: 0, width: 40, height: 40))
        XCTAssertTrue(button.acceptsFirstMouse(for: nil))
    }
}
