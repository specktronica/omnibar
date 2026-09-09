import AppKit
import XCTest
@testable import Omnibar

final class StartMenuListNavigationTests: XCTestCase {
    func testMoveOnEmptyListIsNil() {
        XCTAssertNil(StartMenuListNavigation.indexAfterMove(current: nil, count: 0, delta: 1))
        XCTAssertNil(StartMenuListNavigation.indexAfterMove(current: 0, count: 0, delta: -1))
    }

    func testMoveFromNoSelectionSelectsFirstOrLast() {
        XCTAssertEqual(StartMenuListNavigation.indexAfterMove(current: nil, count: 3, delta: 1), 0)
        XCTAssertEqual(StartMenuListNavigation.indexAfterMove(current: nil, count: 3, delta: 0), 0)
        XCTAssertEqual(StartMenuListNavigation.indexAfterMove(current: nil, count: 3, delta: -1), 2)
    }

    func testMoveClampsAtEnds() {
        XCTAssertEqual(StartMenuListNavigation.indexAfterMove(current: 0, count: 3, delta: -1), 0)
        XCTAssertEqual(StartMenuListNavigation.indexAfterMove(current: 2, count: 3, delta: 1), 2)
        XCTAssertEqual(StartMenuListNavigation.indexAfterMove(current: 1, count: 3, delta: 1), 2)
        XCTAssertEqual(StartMenuListNavigation.indexAfterMove(current: 1, count: 3, delta: -1), 0)
    }

    func testReloadKeepsVisibleID() {
        XCTAssertEqual(
            StartMenuListNavigation.indexAfterReload(
                previousID: "b",
                ids: ["a", "b", "c"],
                autoselectFirst: false
            ),
            1
        )
        XCTAssertEqual(
            StartMenuListNavigation.indexAfterReload(
                previousID: "b",
                ids: ["b"],
                autoselectFirst: true
            ),
            0
        )
    }

    func testReloadAutoselectsFirstWhenPreviousIsGone() {
        XCTAssertEqual(
            StartMenuListNavigation.indexAfterReload(
                previousID: "gone",
                ids: ["a", "b"],
                autoselectFirst: true
            ),
            0
        )
        XCTAssertEqual(
            StartMenuListNavigation.indexAfterReload(
                previousID: nil,
                ids: ["a"],
                autoselectFirst: true
            ),
            0
        )
    }

    func testReloadWithoutAutoselectClearsMissingID() {
        XCTAssertNil(
            StartMenuListNavigation.indexAfterReload(
                previousID: "gone",
                ids: ["a", "b"],
                autoselectFirst: false
            )
        )
        XCTAssertNil(
            StartMenuListNavigation.indexAfterReload(
                previousID: nil,
                ids: ["a"],
                autoselectFirst: false
            )
        )
        XCTAssertNil(
            StartMenuListNavigation.indexAfterReload(
                previousID: "a",
                ids: [],
                autoselectFirst: true
            )
        )
    }
}

final class StartMenuSearchCommandTests: XCTestCase {
    func testMapsListNavigationSelectors() {
        XCTAssertEqual(StartMenuSearchCommand.from(#selector(NSResponder.moveUp(_:))), .move(-1))
        XCTAssertEqual(StartMenuSearchCommand.from(#selector(NSResponder.moveDown(_:))), .move(1))
        XCTAssertEqual(StartMenuSearchCommand.from(#selector(NSResponder.insertNewline(_:))), .launch)
        XCTAssertEqual(
            StartMenuSearchCommand.from(#selector(NSResponder.insertNewlineIgnoringFieldEditor(_:))),
            .launch
        )
        XCTAssertNil(StartMenuSearchCommand.from(#selector(NSResponder.moveLeft(_:))))
        XCTAssertNil(StartMenuSearchCommand.from(#selector(NSResponder.cancelOperation(_:))))
    }

    func testMapsKeyCodes() {
        XCTAssertEqual(StartMenuSearchCommand.from(keyCode: 126), .move(-1))
        XCTAssertEqual(StartMenuSearchCommand.from(keyCode: 125), .move(1))
        XCTAssertEqual(StartMenuSearchCommand.from(keyCode: 36), .launch)
        XCTAssertEqual(StartMenuSearchCommand.from(keyCode: 76), .launch)
        XCTAssertNil(StartMenuSearchCommand.from(keyCode: 0))
        XCTAssertNil(StartMenuSearchCommand.from(keyCode: 53))
    }

    func testIgnoresModifiedArrowsAndAllowsFunctionFlag() {
        XCTAssertEqual(
            StartMenuSearchCommand.from(keyCode: 125, modifierFlags: .function),
            .move(1)
        )
        XCTAssertEqual(
            StartMenuSearchCommand.from(keyCode: 76, modifierFlags: .numericPad),
            .launch
        )
        XCTAssertNil(StartMenuSearchCommand.from(keyCode: 125, modifierFlags: [.command, .function]))
        XCTAssertNil(StartMenuSearchCommand.from(keyCode: 36, modifierFlags: .shift))
    }
}
