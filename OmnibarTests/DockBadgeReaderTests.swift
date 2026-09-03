import XCTest
@testable import Omnibar

@MainActor
final class DockBadgeReaderTests: XCTestCase {
    func testNumericBulletAndNewAreBadges() {
        XCTAssertTrue(DockBadgeReader.isBadgeLabel("1"))
        XCTAssertTrue(DockBadgeReader.isBadgeLabel("12"))
        XCTAssertTrue(DockBadgeReader.isBadgeLabel("•"))
        XCTAssertTrue(DockBadgeReader.isBadgeLabel("new"))
        XCTAssertTrue(DockBadgeReader.isBadgeLabel("NEW"))
    }

    func testEmptyAndWordsAreNotBadges() {
        XCTAssertFalse(DockBadgeReader.isBadgeLabel(""))
        XCTAssertFalse(DockBadgeReader.isBadgeLabel("unread"))
        XCTAssertFalse(DockBadgeReader.isBadgeLabel(" "))
    }
}
