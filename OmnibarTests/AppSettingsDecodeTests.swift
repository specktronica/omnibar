import XCTest
@testable import Omnibar

@MainActor
final class AppSettingsDecodeTests: XCTestCase {
    @MainActor
    func testMissingOptionalKeysUseDefaults() throws {
        var settings = AppSettings.default
        settings.transparency = 0.33
        settings.startButtonAction = .launchpad
        let data = try JSONEncoder().encode(settings)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        for key in [
            "pollInterval",
            "recentAppsLimit",
            "overlapSkipBundleIDs",
            "hideOnClickInsteadOfMinimize",
            "showDesktopButton",
            "mainDisplayOnly",
            "autoHide",
            "showTabsAsItems"
        ] {
            object.removeValue(forKey: key)
        }
        let stripped = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: stripped)
        XCTAssertEqual(decoded.pollInterval, AppSettings.default.pollInterval)
        XCTAssertEqual(decoded.recentAppsLimit, AppSettings.default.recentAppsLimit)
        XCTAssertEqual(decoded.overlapSkipBundleIDs, AppSettings.default.overlapSkipBundleIDs)
        XCTAssertEqual(decoded.hideOnClickInsteadOfMinimize, AppSettings.default.hideOnClickInsteadOfMinimize)
        XCTAssertEqual(decoded.showDesktopButton, AppSettings.default.showDesktopButton)
        XCTAssertTrue(decoded.showDesktopButton)
        XCTAssertEqual(decoded.mainDisplayOnly, AppSettings.default.mainDisplayOnly)
        XCTAssertEqual(decoded.autoHide, AppSettings.default.autoHide)
        XCTAssertEqual(decoded.showTabsAsItems, AppSettings.default.showTabsAsItems)
        XCTAssertEqual(decoded.transparency, 0.33)
        XCTAssertEqual(decoded.startButtonAction, .launchpad)
    }

    @MainActor
    func testUnknownStartButtonActionFailsDecode() throws {
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: try JSONEncoder().encode(AppSettings.default)) as? [String: Any]
        )
        object["startButtonAction"] = "missionControl"
        let data = try JSONSerialization.data(withJSONObject: object)
        XCTAssertThrowsError(try JSONDecoder().decode(AppSettings.self, from: data))
    }

    @MainActor
    func testAppearanceIsDarkForced() {
        var settings = AppSettings.default
        XCTAssertFalse(settings.appearanceIsDarkForced)
        settings.followSystemAppearance = false
        settings.forceDarkMode = true
        XCTAssertTrue(settings.appearanceIsDarkForced)
        settings.forceDarkMode = false
        XCTAssertFalse(settings.appearanceIsDarkForced)
    }

    @MainActor
    func testCompactItemsFollowsIconOnlyOrGrouping() {
        var settings = AppSettings.default
        XCTAssertTrue(settings.groupByApplication)
        XCTAssertTrue(settings.compactItems)
        settings.groupByApplication = false
        XCTAssertFalse(settings.compactItems)
        settings.iconOnly = true
        XCTAssertTrue(settings.compactItems)
    }
}
