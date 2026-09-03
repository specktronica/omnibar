import CoreGraphics
import XCTest
@testable import Omnibar

@MainActor
final class ScreenRecordingAccessTests: XCTestCase {
    func testDeniedWhenNeitherPreflightNorTCCList() {
        XCTAssertEqual(
            ScreenRecordingAccess.resolve(trustedAtLaunch: false, preflight: false, tccListed: false),
            .denied
        )
    }

    func testRevokedWhenPreflightDropsAfterLaunchGrant() {
        XCTAssertEqual(
            ScreenRecordingAccess.resolve(trustedAtLaunch: true, preflight: false, tccListed: true),
            .denied
        )
    }

    func testPendingRestartWhenTitlesAppearWithoutPreflight() {
        XCTAssertEqual(
            ScreenRecordingAccess.resolve(trustedAtLaunch: false, preflight: false, tccListed: true),
            .pendingRestart
        )
    }

    func testPendingRestartWhenPreflightFlipsAfterLaunch() {
        XCTAssertEqual(
            ScreenRecordingAccess.resolve(trustedAtLaunch: false, preflight: true, tccListed: false),
            .pendingRestart
        )
    }

    func testTrustedWhenGrantedAtLaunch() {
        XCTAssertEqual(
            ScreenRecordingAccess.resolve(trustedAtLaunch: true, preflight: true, tccListed: true),
            .trusted
        )
    }

    func testTitlesIndicateTCCGrantIgnoresOwnProcessAndEmptyNames() {
        let selfPID: pid_t = 42
        let windows: [[String: Any]] = [
            [kCGWindowOwnerPID as String: NSNumber(value: selfPID), kCGWindowName as String: "Omnibar"],
            [kCGWindowOwnerPID as String: NSNumber(value: 99), kCGWindowName as String: ""],
        ]
        XCTAssertFalse(ScreenRecordingAccess.titlesIndicateTCCGrant(windows: windows, selfPID: selfPID))
    }

    func testTitlesIndicateTCCGrantWhenAnotherProcessHasATitle() {
        let selfPID: pid_t = 42
        let windows: [[String: Any]] = [
            [kCGWindowOwnerPID as String: NSNumber(value: 99), kCGWindowName as String: "Safari"],
        ]
        XCTAssertTrue(ScreenRecordingAccess.titlesIndicateTCCGrant(windows: windows, selfPID: selfPID))
    }

    func testPrivacySettingsURLsPreferModernThenLegacyAnchors() {
        let urls = PermissionsManager.privacySettingsURLStrings(anchor: "Privacy_Accessibility")
        XCTAssertEqual(
            urls,
            [
                "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility",
                "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
            ]
        )
        let screen = PermissionsManager.privacySettingsURLStrings(anchor: "Privacy_ScreenCapture")
        XCTAssertTrue(screen[0].hasSuffix("Privacy_ScreenCapture"))
        XCTAssertTrue(screen[1].hasSuffix("Privacy_ScreenCapture"))
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
