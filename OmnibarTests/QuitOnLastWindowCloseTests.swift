import XCTest
@testable import Omnibar

@MainActor
final class QuitOnLastWindowCloseTests: XCTestCase {
    private var enabled: AppSettings {
        var settings = AppSettings.default
        settings.quitAppOnLastWindowClose = true
        return settings
    }

    func testOffByDefaultEvenForTheOnlyWindow() {
        let window = stubWindow(id: 1)
        XCTAssertFalse(WindowActions.shouldQuitInsteadOfClosing(window, windows: [window], settings: .default))
    }

    func testQuitsWhenClosingTheOnlyWindow() {
        let window = stubWindow(id: 1)
        XCTAssertTrue(WindowActions.shouldQuitInsteadOfClosing(window, windows: [window], settings: enabled))
    }

    func testClosesWhenTheAppHasAnotherWindow() {
        let window = stubWindow(id: 1)
        let other = stubWindow(id: 2)
        XCTAssertFalse(WindowActions.shouldQuitInsteadOfClosing(window, windows: [window, other], settings: enabled))
    }

    func testOtherWindowOnAnotherSpaceOrMinimizedStillCounts() {
        let window = stubWindow(id: 1, spaces: [10])
        let elsewhere = stubWindow(id: 2, screen: 2, spaces: [20], onScreen: false)
        let minimized = stubWindow(id: 3, minimized: true, onScreen: false)
        XCTAssertFalse(WindowActions.shouldQuitInsteadOfClosing(window, windows: [window, elsewhere], settings: enabled))
        XCTAssertFalse(WindowActions.shouldQuitInsteadOfClosing(window, windows: [window, minimized], settings: enabled))
    }

    func testWindowsOfOtherAppsDoNotCount() {
        let window = stubWindow(id: 1, pid: 42)
        let otherApp = stubWindow(id: 2, bundle: "com.example.other", pid: 43)
        XCTAssertTrue(WindowActions.shouldQuitInsteadOfClosing(window, windows: [window, otherApp], settings: enabled))
    }

    func testQuitsWhenSnapshotNoLongerListsTheWindow() {
        let window = stubWindow(id: 1)
        XCTAssertTrue(WindowActions.shouldQuitInsteadOfClosing(window, windows: [], settings: enabled))
    }

    func testNeverQuitsFinder() {
        let window = stubWindow(id: 1, bundle: "com.apple.finder")
        XCTAssertFalse(WindowActions.shouldQuitInsteadOfClosing(window, windows: [window], settings: enabled))
    }
}
