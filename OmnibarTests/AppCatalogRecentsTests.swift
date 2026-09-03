import XCTest
@testable import Omnibar

@MainActor
final class AppCatalogRecentsTests: XCTestCase {
    func testSkipsSelfBundle() {
        let safari = catalogStub(bundleID: "com.apple.Safari", name: "Safari")
        let next = AppCatalog.updatedRecents(
            bundleID: "io.specktronica.omnibar",
            recents: [safari],
            apps: [safari],
            limit: 10,
            resolved: { _ in nil }
        )
        XCTAssertEqual(next, [safari])
    }

    func testMostRecentFirstAndDedupes() {
        let safari = catalogStub(bundleID: "com.apple.Safari", name: "Safari")
        let mail = catalogStub(bundleID: "com.apple.mail", name: "Mail")
        let first = AppCatalog.updatedRecents(
            bundleID: safari.bundleID,
            recents: [mail],
            apps: [safari, mail],
            limit: 10,
            resolved: { _ in nil }
        )
        XCTAssertEqual(first.map(\.bundleID), ["com.apple.Safari", "com.apple.mail"])
        let again = AppCatalog.updatedRecents(
            bundleID: mail.bundleID,
            recents: first,
            apps: [safari, mail],
            limit: 10,
            resolved: { _ in nil }
        )
        XCTAssertEqual(again.map(\.bundleID), ["com.apple.mail", "com.apple.Safari"])
    }

    func testCapsAtLeastOne() {
        let apps = (1...5).map { catalogStub(bundleID: "app.\($0)", name: "App \($0)") }
        var recents: [AppCatalog.CatalogApp] = []
        for app in apps {
            recents = AppCatalog.updatedRecents(
                bundleID: app.bundleID,
                recents: recents,
                apps: apps,
                limit: 3,
                resolved: { _ in nil }
            )
        }
        XCTAssertEqual(recents.map(\.bundleID), ["app.5", "app.4", "app.3"])
        let capped = AppCatalog.updatedRecents(
            bundleID: "app.1",
            recents: recents,
            apps: apps,
            limit: 0,
            resolved: { _ in nil }
        )
        XCTAssertEqual(capped.map(\.bundleID), ["app.1"])
    }

    func testResolvesMissingCatalogEntry() {
        let resolved = catalogStub(bundleID: "com.resolved", name: "Resolved")
        let next = AppCatalog.updatedRecents(
            bundleID: "com.resolved",
            recents: [],
            apps: [],
            limit: 10,
            resolved: { $0 == "com.resolved" ? resolved : nil }
        )
        XCTAssertEqual(next, [resolved])
    }

    func testFilterEmptyQueryReturnsAllAndIsCaseInsensitive() {
        let apps = [
            catalogStub(bundleID: "a", name: "Arcade"),
            catalogStub(bundleID: "b", name: "Books")
        ]
        XCTAssertEqual(AppCatalog.filter(apps, query: "  ").map(\.name), ["Arcade", "Books"])
        XCTAssertEqual(AppCatalog.filter(apps, query: "ARC").map(\.name), ["Arcade"])
    }
}
