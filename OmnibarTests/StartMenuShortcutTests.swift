import CoreGraphics
import XCTest
@testable import Omnibar

final class StartMenuShortcutTests: XCTestCase {
    func testTapFromEitherModifierOrderEmitsPressedThenTapped() {
        for first: StartMenuShortcut.Modifiers in [.control, .option] {
            var state = StartMenuShortcut.State()
            XCTAssertEqual(StartMenuShortcut.reduce(&state, .modifiers(first)), .none)
            XCTAssertEqual(StartMenuShortcut.reduce(&state, .modifiers(.chord)), .pressed)
            XCTAssertEqual(StartMenuShortcut.reduce(&state, .modifiers([])), .tapped)
        }
    }

    func testReleasingOneChordKeyTogglesOnce() {
        var state = StartMenuShortcut.State()
        XCTAssertEqual(StartMenuShortcut.reduce(&state, .modifiers(.chord)), .pressed)
        XCTAssertEqual(StartMenuShortcut.reduce(&state, .modifiers(.control)), .tapped)
        XCTAssertEqual(StartMenuShortcut.reduce(&state, .modifiers([])), .none)
    }

    func testDuplicateFlagsAreIgnored() {
        var state = StartMenuShortcut.State()
        XCTAssertEqual(StartMenuShortcut.reduce(&state, .modifiers(.chord)), .pressed)
        XCTAssertEqual(StartMenuShortcut.reduce(&state, .modifiers(.chord)), .none)
        XCTAssertEqual(StartMenuShortcut.reduce(&state, .modifiers([])), .tapped)
    }

    func testOtherInputCancelsTheTap() {
        var state = StartMenuShortcut.State()
        XCTAssertEqual(StartMenuShortcut.reduce(&state, .modifiers(.chord)), .pressed)
        XCTAssertEqual(StartMenuShortcut.reduce(&state, .otherInput), .none)
        XCTAssertEqual(state.phase, .suppressed)
        XCTAssertEqual(StartMenuShortcut.reduce(&state, .modifiers([])), .none)
        XCTAssertEqual(state.phase, .idle)
    }

    func testOtherInputWhileIdleDoesNotBlockTheNextTap() {
        var state = StartMenuShortcut.State()
        XCTAssertEqual(StartMenuShortcut.reduce(&state, .otherInput), .none)
        XCTAssertEqual(StartMenuShortcut.reduce(&state, .modifiers(.chord)), .pressed)
        XCTAssertEqual(StartMenuShortcut.reduce(&state, .modifiers([])), .tapped)
    }

    func testAddingAModifierCancelsUntilTheChordIsReleased() {
        var state = StartMenuShortcut.State()
        XCTAssertEqual(StartMenuShortcut.reduce(&state, .modifiers(.chord)), .pressed)
        XCTAssertEqual(StartMenuShortcut.reduce(&state, .modifiers([.control, .option, .command])), .none)
        XCTAssertEqual(state.phase, .suppressed)
        XCTAssertEqual(StartMenuShortcut.reduce(&state, .modifiers(.chord)), .none)
        XCTAssertEqual(StartMenuShortcut.reduce(&state, .modifiers([])), .none)
        XCTAssertEqual(StartMenuShortcut.reduce(&state, .modifiers(.chord)), .pressed)
    }

    func testChordPlusCommandInOneEventDoesNotArmWhenCommandIsReleased() {
        var state = StartMenuShortcut.State()
        let held: StartMenuShortcut.Modifiers = [.control, .option, .command]
        XCTAssertEqual(StartMenuShortcut.reduce(&state, .modifiers(held)), .none)
        XCTAssertEqual(StartMenuShortcut.reduce(&state, .modifiers(.chord)), .none)
        XCTAssertEqual(StartMenuShortcut.reduce(&state, .modifiers([])), .none)
    }

    func testShiftAloneDoesNotArm() {
        var state = StartMenuShortcut.State()
        XCTAssertEqual(StartMenuShortcut.reduce(&state, .modifiers(.shift)), .none)
        XCTAssertEqual(StartMenuShortcut.reduce(&state, .modifiers([])), .none)
    }
}

final class StartMenuShortcutTargetTests: XCTestCase {
    func testCursorDisplayWinsWhenItsBarIsVisible() {
        XCTAssertEqual(
            StartMenuShortcutTarget.presentationDisplayID(
                cursorDisplayID: 2,
                visibleDisplayIDs: [1, 2],
                preferredDisplayID: 1
            ),
            2
        )
    }

    func testHiddenCursorDisplayFallsBackToThePreferredBar() {
        XCTAssertEqual(
            StartMenuShortcutTarget.presentationDisplayID(
                cursorDisplayID: 9,
                visibleDisplayIDs: [1, 2],
                preferredDisplayID: 2
            ),
            2
        )
    }

    func testFallsBackToTheFirstVisibleBar() {
        XCTAssertEqual(
            StartMenuShortcutTarget.presentationDisplayID(
                cursorDisplayID: nil,
                visibleDisplayIDs: [4, 5],
                preferredDisplayID: 9
            ),
            4
        )
    }

    func testNilWhenNoBarIsVisible() {
        XCTAssertNil(
            StartMenuShortcutTarget.presentationDisplayID(
                cursorDisplayID: 1,
                visibleDisplayIDs: [],
                preferredDisplayID: 1
            )
        )
    }
}
