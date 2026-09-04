import CoreGraphics
import Foundation

enum OnboardingLogic {
    enum LaunchPath: Equatable {
        case startTaskbar
        case showOnboarding
    }

    enum PrimaryAction: Equatable {
        case dismiss
        case relaunch
    }

    enum ReopenAction: Equatable {
        case ignore
        case revealOnboarding
        case showSettings
        case none
    }

    struct Presentation: Equatable {
        var accessibilityGranted: Bool
        var accessibilityShowsEnable: Bool
        var screenRecordingGranted: Bool
        var screenRecordingShowsEnable: Bool
        var screenRecordingNeedsRestart: Bool
        var screenRecordingSubtitle: String
        var primaryTitle: String
        var primaryEnabled: Bool
        var primaryAction: PrimaryAction
        var showsConflictWarning: Bool
        var windowHeight: CGFloat
        var contentHeight: CGFloat
    }

    static let windowWidth: CGFloat = 460
    static let windowHeightDefault: CGFloat = 430
    static let windowHeightWithConflict: CGFloat = 550
    static let contentHeightDefault: CGFloat = 410
    static let contentHeightWithConflict: CGFloat = 530

    static let screenRecordingRestartSubtitle =
        "Granted. Restart Omnibar to enable live hover thumbnails."
    static let screenRecordingOptionalSubtitle =
        "Optional. Enables live window thumbnails on hover."

    static func launchPath(accessibilityTrusted: Bool) -> LaunchPath {
        accessibilityTrusted ? .startTaskbar : .showOnboarding
    }

    static func presentation(
        accessibilityTrusted: Bool,
        screenRecording: ScreenRecordingAccess,
        conflictingCopyURL: URL?
    ) -> Presentation {
        let needsRestart = screenRecording == .pendingRestart
        let trusted = screenRecording == .trusted
        let hasConflict = conflictingCopyURL != nil
        return Presentation(
            accessibilityGranted: accessibilityTrusted,
            accessibilityShowsEnable: !accessibilityTrusted,
            screenRecordingGranted: trusted || needsRestart,
            screenRecordingShowsEnable: !trusted,
            screenRecordingNeedsRestart: needsRestart,
            screenRecordingSubtitle: needsRestart
                ? screenRecordingRestartSubtitle
                : screenRecordingOptionalSubtitle,
            primaryTitle: needsRestart ? "Restart" : "Continue",
            primaryEnabled: needsRestart || accessibilityTrusted,
            primaryAction: needsRestart ? .relaunch : .dismiss,
            showsConflictWarning: hasConflict,
            windowHeight: hasConflict ? windowHeightWithConflict : windowHeightDefault,
            contentHeight: hasConflict ? contentHeightWithConflict : contentHeightDefault
        )
    }

    static func shouldStartTaskbar(
        accessibilityTrusted: Bool,
        onboardingShowing: Bool,
        relaunchInProgress: Bool,
        alreadyStarted: Bool
    ) -> Bool {
        accessibilityTrusted && !onboardingShowing && !relaunchInProgress && !alreadyStarted
    }

    static func shouldPostPermissionsDidChange(
        relaunchInProgress: Bool,
        accessibilityTrusted: Bool
    ) -> Bool {
        !relaunchInProgress && accessibilityTrusted
    }

    static func reopenAction(
        suppressReopen: Bool,
        onboardingShowing: Bool,
        accessibilityTrusted: Bool
    ) -> ReopenAction {
        if suppressReopen { return .ignore }
        if onboardingShowing { return .revealOnboarding }
        if accessibilityTrusted { return .showSettings }
        return .none
    }

    static func sessionAccess(
        trustedAtLaunch: Bool,
        preflight: Bool,
        tccListed: Bool,
        previouslyObserved: Bool
    ) -> (observed: Bool, access: ScreenRecordingAccess) {
        let observed = ScreenRecordingAccess.observedGrant(
            trustedAtLaunch: trustedAtLaunch,
            preflight: preflight,
            tccListed: tccListed,
            previouslyObserved: previouslyObserved
        )
        let access = ScreenRecordingAccess.resolve(
            trustedAtLaunch: trustedAtLaunch,
            preflight: preflight,
            tccListed: observed
        )
        return (observed, access)
    }
}
