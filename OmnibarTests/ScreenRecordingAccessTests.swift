import XCTest
@testable import Omnibar

@MainActor
final class ScreenRecordingAccessTests: XCTestCase {
    func testDeniedWhenPreflightIsFalse() {
        XCTAssertEqual(
            ScreenRecordingAccess.resolve(trustedAtLaunch: false, preflight: false),
            .denied
        )
        XCTAssertEqual(
            ScreenRecordingAccess.resolve(trustedAtLaunch: true, preflight: false),
            .denied
        )
    }

    func testPendingRestartWhenGrantedAfterLaunch() {
        XCTAssertEqual(
            ScreenRecordingAccess.resolve(trustedAtLaunch: false, preflight: true),
            .pendingRestart
        )
    }

    func testTrustedWhenGrantedAtLaunch() {
        XCTAssertEqual(
            ScreenRecordingAccess.resolve(trustedAtLaunch: true, preflight: true),
            .trusted
        )
    }
}

@MainActor
final class AppRelaunchTests: XCTestCase {
    func testShellQuotedWrapsInSingleQuotes() {
        XCTAssertEqual(AppRelaunch.shellQuoted("/Applications/Omnibar.app"), "'/Applications/Omnibar.app'")
    }

    func testShellQuotedEscapesEmbeddedSingleQuotes() {
        XCTAssertEqual(AppRelaunch.shellQuoted("it's"), "'it'\\''s'")
    }

    func testWaitThenOpenScriptWaitsForPidThenOpensBundle() {
        let script = AppRelaunch.waitThenOpenScript(pid: 4321, bundlePath: "/Apps/Omnibar.app")
        XCTAssertTrue(script.contains("/bin/kill -0 4321"))
        XCTAssertTrue(script.contains("/usr/bin/open '/Apps/Omnibar.app'"))
        XCTAssertFalse(script.contains("open -n"))
    }
}
