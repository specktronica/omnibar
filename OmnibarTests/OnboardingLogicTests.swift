import XCTest
@testable import Omnibar

@MainActor
final class OnboardingLogicTests: XCTestCase {
    private let cask = URL(fileURLWithPath: "/Applications/Omnibar.app")

    func testLaunchPathIgnoresScreenRecording() {
        let rows: [(ax: Bool, sr: ScreenRecordingAccess, path: OnboardingLogic.LaunchPath)] = [
            (false, .denied, .showOnboarding),
            (false, .pendingRestart, .showOnboarding),
            (false, .trusted, .showOnboarding),
            (true, .denied, .startTaskbar),
            (true, .pendingRestart, .startTaskbar),
            (true, .trusted, .startTaskbar),
        ]
        for row in rows {
            XCTAssertEqual(
                OnboardingLogic.launchPath(accessibilityTrusted: row.ax),
                row.path,
                "AX \(row.ax) SR \(row.sr)"
            )
        }
    }

    func testWelcomeContinueDisabledWhenAccessibilityDenied() {
        let ui = OnboardingLogic.presentation(
            accessibilityTrusted: false,
            screenRecording: .denied,
            conflictingCopyURL: nil
        )
        XCTAssertFalse(ui.accessibilityGranted)
        XCTAssertTrue(ui.accessibilityShowsEnable)
        XCTAssertFalse(ui.screenRecordingGranted)
        XCTAssertTrue(ui.screenRecordingShowsEnable)
        XCTAssertEqual(ui.screenRecordingSubtitle, OnboardingLogic.screenRecordingOptionalSubtitle)
        XCTAssertEqual(ui.primaryTitle, "Continue")
        XCTAssertFalse(ui.primaryEnabled)
        XCTAssertEqual(ui.primaryAction, .dismiss)
        XCTAssertFalse(ui.showsConflictWarning)
        XCTAssertEqual(ui.windowHeight, OnboardingLogic.windowHeightDefault)
        XCTAssertEqual(ui.contentHeight, OnboardingLogic.contentHeightDefault)
    }

    func testWelcomeContinueEnabledWhenAccessibilityGrantedAndScreenRecordingDenied() {
        let ui = OnboardingLogic.presentation(
            accessibilityTrusted: true,
            screenRecording: .denied,
            conflictingCopyURL: nil
        )
        XCTAssertTrue(ui.accessibilityGranted)
        XCTAssertFalse(ui.accessibilityShowsEnable)
        XCTAssertTrue(ui.screenRecordingShowsEnable)
        XCTAssertEqual(ui.primaryTitle, "Continue")
        XCTAssertTrue(ui.primaryEnabled)
        XCTAssertEqual(ui.primaryAction, .dismiss)
    }

    func testWelcomeRestartWhenScreenRecordingPendingWithoutAccessibility() {
        let ui = OnboardingLogic.presentation(
            accessibilityTrusted: false,
            screenRecording: .pendingRestart,
            conflictingCopyURL: nil
        )
        XCTAssertTrue(ui.screenRecordingGranted)
        XCTAssertTrue(ui.screenRecordingShowsEnable)
        XCTAssertEqual(ui.screenRecordingSubtitle, OnboardingLogic.screenRecordingRestartSubtitle)
        XCTAssertEqual(ui.primaryTitle, "Restart")
        XCTAssertTrue(ui.primaryEnabled)
        XCTAssertEqual(ui.primaryAction, .relaunch)
    }

    func testWelcomeRestartWhenScreenRecordingPendingWithAccessibility() {
        let ui = OnboardingLogic.presentation(
            accessibilityTrusted: true,
            screenRecording: .pendingRestart,
            conflictingCopyURL: nil
        )
        XCTAssertEqual(ui.primaryTitle, "Restart")
        XCTAssertTrue(ui.primaryEnabled)
        XCTAssertEqual(ui.primaryAction, .relaunch)
    }

    func testWelcomeHidesScreenRecordingEnableWhenTrustedAtLaunch() {
        let ui = OnboardingLogic.presentation(
            accessibilityTrusted: false,
            screenRecording: .trusted,
            conflictingCopyURL: nil
        )
        XCTAssertTrue(ui.screenRecordingGranted)
        XCTAssertFalse(ui.screenRecordingShowsEnable)
        XCTAssertEqual(ui.primaryTitle, "Continue")
        XCTAssertFalse(ui.primaryEnabled)
        XCTAssertEqual(ui.primaryAction, .dismiss)
    }

    func testConflictWarningDoesNotChangeContinueRules() {
        let ui = OnboardingLogic.presentation(
            accessibilityTrusted: false,
            screenRecording: .denied,
            conflictingCopyURL: cask
        )
        XCTAssertTrue(ui.showsConflictWarning)
        XCTAssertEqual(ui.windowHeight, OnboardingLogic.windowHeightWithConflict)
        XCTAssertEqual(ui.contentHeight, OnboardingLogic.contentHeightWithConflict)
        XCTAssertFalse(ui.primaryEnabled)
        XCTAssertEqual(ui.primaryTitle, "Continue")
    }

    func testMidSessionTitlesFlipToPendingRestartAndStayObserved() {
        let first = OnboardingLogic.sessionAccess(
            trustedAtLaunch: false,
            preflight: false,
            tccListed: true,
            previouslyObserved: false
        )
        XCTAssertTrue(first.observed)
        XCTAssertEqual(first.access, .pendingRestart)

        let later = OnboardingLogic.sessionAccess(
            trustedAtLaunch: false,
            preflight: false,
            tccListed: false,
            previouslyObserved: first.observed
        )
        XCTAssertTrue(later.observed)
        XCTAssertEqual(later.access, .pendingRestart)

        let ui = OnboardingLogic.presentation(
            accessibilityTrusted: false,
            screenRecording: later.access,
            conflictingCopyURL: nil
        )
        XCTAssertEqual(ui.primaryAction, .relaunch)
        XCTAssertTrue(ui.primaryEnabled)
    }

    func testMidSessionRevokeWhenPreflightDropsAfterLaunchGrant() {
        let revoked = OnboardingLogic.sessionAccess(
            trustedAtLaunch: true,
            preflight: false,
            tccListed: true,
            previouslyObserved: true
        )
        XCTAssertFalse(revoked.observed)
        XCTAssertEqual(revoked.access, .denied)
    }

    func testMidSessionAccessibilityProbeEnablesContinueWithoutRestart() {
        let session = OnboardingLogic.sessionAccess(
            trustedAtLaunch: false,
            preflight: false,
            tccListed: false,
            previouslyObserved: false
        )
        XCTAssertEqual(session.access, .denied)
        let ui = OnboardingLogic.presentation(
            accessibilityTrusted: true,
            screenRecording: session.access,
            conflictingCopyURL: nil
        )
        XCTAssertEqual(ui.primaryTitle, "Continue")
        XCTAssertTrue(ui.primaryEnabled)
        XCTAssertEqual(ui.primaryAction, .dismiss)
    }

    func testRelaunchHappyPathSkipsWelcomeWithTrustedScreenRecording() {
        let access = ScreenRecordingAccess.accessAtLaunch(preflight: true)
        XCTAssertEqual(access, .trusted)
        XCTAssertEqual(OnboardingLogic.launchPath(accessibilityTrusted: true), .startTaskbar)
    }

    func testRelaunchTCCMismatchShowsWelcomeWithContinueDisabled() {
        let access = ScreenRecordingAccess.accessAtLaunch(preflight: false)
        XCTAssertEqual(access, .denied)
        XCTAssertEqual(OnboardingLogic.launchPath(accessibilityTrusted: false), .showOnboarding)
        let afterRefresh = OnboardingLogic.sessionAccess(
            trustedAtLaunch: false,
            preflight: false,
            tccListed: false,
            previouslyObserved: false
        )
        XCTAssertEqual(afterRefresh.access, .denied)
        let ui = OnboardingLogic.presentation(
            accessibilityTrusted: false,
            screenRecording: afterRefresh.access,
            conflictingCopyURL: nil
        )
        XCTAssertEqual(ui.primaryTitle, "Continue")
        XCTAssertFalse(ui.primaryEnabled)
    }

    func testRelaunchTitlesStillVisibleShowsRestart() {
        let access = ScreenRecordingAccess.accessAtLaunch(preflight: false)
        XCTAssertEqual(access, .denied)
        XCTAssertEqual(OnboardingLogic.launchPath(accessibilityTrusted: false), .showOnboarding)
        let afterRefresh = OnboardingLogic.sessionAccess(
            trustedAtLaunch: false,
            preflight: false,
            tccListed: true,
            previouslyObserved: false
        )
        XCTAssertEqual(afterRefresh.access, .pendingRestart)
        let ui = OnboardingLogic.presentation(
            accessibilityTrusted: false,
            screenRecording: afterRefresh.access,
            conflictingCopyURL: nil
        )
        XCTAssertEqual(ui.primaryAction, .relaunch)
        XCTAssertTrue(ui.primaryEnabled)
    }

    func testRelaunchAccessibilityProbeSkipsWelcomeWithoutThumbnails() {
        let access = ScreenRecordingAccess.accessAtLaunch(preflight: false)
        XCTAssertEqual(access, .denied)
        XCTAssertEqual(OnboardingLogic.launchPath(accessibilityTrusted: true), .startTaskbar)
    }

    func testShouldStartTaskbarGuards() {
        XCTAssertTrue(
            OnboardingLogic.shouldStartTaskbar(
                accessibilityTrusted: true,
                onboardingShowing: false,
                relaunchInProgress: false,
                alreadyStarted: false
            )
        )
        XCTAssertFalse(
            OnboardingLogic.shouldStartTaskbar(
                accessibilityTrusted: false,
                onboardingShowing: false,
                relaunchInProgress: false,
                alreadyStarted: false
            )
        )
        XCTAssertFalse(
            OnboardingLogic.shouldStartTaskbar(
                accessibilityTrusted: true,
                onboardingShowing: true,
                relaunchInProgress: false,
                alreadyStarted: false
            )
        )
        XCTAssertFalse(
            OnboardingLogic.shouldStartTaskbar(
                accessibilityTrusted: true,
                onboardingShowing: false,
                relaunchInProgress: true,
                alreadyStarted: false
            )
        )
        XCTAssertFalse(
            OnboardingLogic.shouldStartTaskbar(
                accessibilityTrusted: true,
                onboardingShowing: false,
                relaunchInProgress: false,
                alreadyStarted: true
            )
        )
    }

    func testFinishPostsPermissionsChangeOnlyWhenAccessibilityTrustedAndNotRelaunching() {
        XCTAssertTrue(
            OnboardingLogic.shouldPostPermissionsDidChange(
                relaunchInProgress: false,
                accessibilityTrusted: true
            )
        )
        XCTAssertFalse(
            OnboardingLogic.shouldPostPermissionsDidChange(
                relaunchInProgress: true,
                accessibilityTrusted: true
            )
        )
        XCTAssertFalse(
            OnboardingLogic.shouldPostPermissionsDidChange(
                relaunchInProgress: false,
                accessibilityTrusted: false
            )
        )
    }

    func testReopenActions() {
        XCTAssertEqual(
            OnboardingLogic.reopenAction(
                suppressReopen: true,
                onboardingShowing: true,
                accessibilityTrusted: true
            ),
            .ignore
        )
        XCTAssertEqual(
            OnboardingLogic.reopenAction(
                suppressReopen: false,
                onboardingShowing: true,
                accessibilityTrusted: false
            ),
            .revealOnboarding
        )
        XCTAssertEqual(
            OnboardingLogic.reopenAction(
                suppressReopen: false,
                onboardingShowing: false,
                accessibilityTrusted: true
            ),
            .showSettings
        )
        XCTAssertEqual(
            OnboardingLogic.reopenAction(
                suppressReopen: false,
                onboardingShowing: false,
                accessibilityTrusted: false
            ),
            .none
        )
    }
}
