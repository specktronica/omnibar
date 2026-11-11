import CoreGraphics
import XCTest
@testable import Omnibar

@MainActor
final class CloseButtonQuitTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_000)

    private var enabled: AppSettings {
        var settings = AppSettings.default
        settings.quitAppOnLastWindowClose = true
        return settings
    }

    private func update(
        _ tracker: inout CloseButtonQuitTracker,
        windows: [WindowInfo],
        after seconds: TimeInterval,
        confirm: Bool = true
    ) -> [pid_t] {
        var quit: [pid_t] = []
        tracker.update(
            windows: windows,
            now: start.addingTimeInterval(seconds),
            confirm: { _ in confirm },
            quit: { quit.append($0) }
        )
        return quit
    }

    // MARK: Which clicks are watched

    func testWatchesAListedWindowWhenEnabled() {
        let window = stubWindow(id: 1)
        XCTAssertTrue(CloseButtonQuitTracker.shouldWatch(windowID: 1, pid: 42, windows: [window], settings: enabled))
    }

    func testIgnoresClicksWhenDisabled() {
        let window = stubWindow(id: 1)
        XCTAssertFalse(CloseButtonQuitTracker.shouldWatch(windowID: 1, pid: 42, windows: [window], settings: .default))
    }

    func testIgnoresWindowsOmnibarDoesNotList() {
        let window = stubWindow(id: 1)
        XCTAssertFalse(CloseButtonQuitTracker.shouldWatch(windowID: 2, pid: 42, windows: [window], settings: enabled))
        XCTAssertFalse(CloseButtonQuitTracker.shouldWatch(windowID: 1, pid: 43, windows: [window], settings: enabled))
    }

    func testIgnoresFinder() {
        let window = stubWindow(id: 1, bundle: "com.apple.finder")
        XCTAssertFalse(CloseButtonQuitTracker.shouldWatch(windowID: 1, pid: 42, windows: [window], settings: enabled))
    }

    // MARK: When to quit

    func testQuitsOnceTheLastWindowIsGone() {
        let window = stubWindow(id: 1)
        var tracker = CloseButtonQuitTracker()
        tracker.watch(windowID: 1, pid: 42, windows: [window], now: start)

        XCTAssertEqual(update(&tracker, windows: [window], after: 0.2), [])
        XCTAssertTrue(tracker.hasPending)
        XCTAssertEqual(update(&tracker, windows: [], after: 0.5), [42])
        XCTAssertFalse(tracker.hasPending)
    }

    func testOtherAppsDoNotKeepTheAppRunning() {
        let window = stubWindow(id: 1)
        let otherApp = stubWindow(id: 9, bundle: "com.example.other", pid: 43)
        var tracker = CloseButtonQuitTracker()
        tracker.watch(windowID: 1, pid: 42, windows: [window, otherApp], now: start)

        XCTAssertEqual(update(&tracker, windows: [otherApp], after: 0.5), [42])
    }

    func testDoesNotQuitWhenAnotherWindowStays() {
        let window = stubWindow(id: 1)
        let minimized = stubWindow(id: 2, minimized: true, onScreen: false)
        var tracker = CloseButtonQuitTracker()
        tracker.watch(windowID: 1, pid: 42, windows: [window, minimized], now: start)

        XCTAssertEqual(update(&tracker, windows: [minimized], after: 0.5), [])
        XCTAssertTrue(tracker.hasPending)
        XCTAssertEqual(update(&tracker, windows: [minimized], after: 0.5 + CloseButtonQuitTracker.settleTime), [])
        XCTAssertFalse(tracker.hasPending)
    }

    func testQuitsWhenTabsCloseAScanLater() {
        let window = stubWindow(id: 1)
        let tab = stubWindow(id: 2, onScreen: false)
        var tracker = CloseButtonQuitTracker()
        tracker.watch(windowID: 1, pid: 42, windows: [window, tab], now: start)

        XCTAssertEqual(update(&tracker, windows: [tab], after: 0.3), [])
        XCTAssertEqual(update(&tracker, windows: [], after: 0.6), [42])
    }

    func testWaitsForASaveDialogBeforeTheWindowCloses() {
        let window = stubWindow(id: 1)
        var tracker = CloseButtonQuitTracker()
        tracker.watch(windowID: 1, pid: 42, windows: [window], now: start)

        XCTAssertEqual(update(&tracker, windows: [window], after: 20), [])
        XCTAssertEqual(update(&tracker, windows: [], after: 25), [42])
    }

    func testStopsWatchingAWindowThatNeverCloses() {
        let window = stubWindow(id: 1)
        var tracker = CloseButtonQuitTracker()
        tracker.watch(windowID: 1, pid: 42, windows: [window], now: start)

        XCTAssertEqual(update(&tracker, windows: [window], after: CloseButtonQuitTracker.closeTimeout), [])
        XCTAssertFalse(tracker.hasPending)
        XCTAssertEqual(update(&tracker, windows: [], after: CloseButtonQuitTracker.closeTimeout + 1), [])
    }

    func testDoesNotQuitUntilConfirmed() {
        let window = stubWindow(id: 1)
        var tracker = CloseButtonQuitTracker()
        tracker.watch(windowID: 1, pid: 42, windows: [window], now: start)

        XCTAssertEqual(update(&tracker, windows: [], after: 0.5, confirm: false), [])
        XCTAssertTrue(tracker.hasPending)
        XCTAssertEqual(update(&tracker, windows: [], after: 1.0, confirm: true), [42])
    }

    func testGivesUpWhenNeverConfirmed() {
        let window = stubWindow(id: 1)
        var tracker = CloseButtonQuitTracker()
        tracker.watch(windowID: 1, pid: 42, windows: [window], now: start)

        XCTAssertEqual(update(&tracker, windows: [], after: 0.5, confirm: false), [])
        let late = 0.5 + CloseButtonQuitTracker.settleTime
        XCTAssertEqual(update(&tracker, windows: [], after: late, confirm: false), [])
        XCTAssertFalse(tracker.hasPending)
    }

    func testAWindowMissingFromOneScanKeepsWaiting() {
        let window = stubWindow(id: 1)
        var tracker = CloseButtonQuitTracker()
        tracker.watch(windowID: 1, pid: 42, windows: [window], now: start)

        XCTAssertEqual(update(&tracker, windows: [], after: 0.5, confirm: false), [])
        XCTAssertEqual(update(&tracker, windows: [window], after: 1.0), [])
        // Past the settle time of the first miss, but the window came back, so still watched.
        XCTAssertEqual(update(&tracker, windows: [window], after: 10), [])
        XCTAssertTrue(tracker.hasPending)
        XCTAssertEqual(update(&tracker, windows: [], after: 12), [42])
    }

    func testConfirmSeesEveryWindowListedWhileWaiting() {
        let window = stubWindow(id: 1)
        let later = stubWindow(id: 2)
        var tracker = CloseButtonQuitTracker()
        tracker.watch(windowID: 1, pid: 42, windows: [window], now: start)
        _ = update(&tracker, windows: [window, later], after: 0.2)

        var checked: Set<CGWindowID> = []
        tracker.update(
            windows: [],
            now: start.addingTimeInterval(0.5),
            confirm: { checked = $0.knownWindowIDs; return false },
            quit: { _ in }
        )
        XCTAssertEqual(checked, [1, 2])
    }

    func testTwoClosedWindowsOfOneAppQuitItOnce() {
        let first = stubWindow(id: 1)
        let second = stubWindow(id: 2)
        var tracker = CloseButtonQuitTracker()
        tracker.watch(windowID: 1, pid: 42, windows: [first, second], now: start)
        tracker.watch(windowID: 2, pid: 42, windows: [first, second], now: start)

        XCTAssertEqual(update(&tracker, windows: [], after: 0.5), [42])
        XCTAssertFalse(tracker.hasPending)
    }

    func testClickingTheSameButtonTwiceWatchesOnce() {
        let window = stubWindow(id: 1)
        var tracker = CloseButtonQuitTracker()
        tracker.watch(windowID: 1, pid: 42, windows: [window], now: start)
        tracker.watch(windowID: 1, pid: 42, windows: [window], now: start)

        XCTAssertEqual(tracker.pending.count, 1)
    }
}
