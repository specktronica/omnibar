import XCTest
@testable import Omnibar

@MainActor
final class ThumbnailPagingTests: XCTestCase {
    func testVisibleCountCapsAtThree() {
        XCTAssertEqual(ThumbnailPaging.visibleCount(windowCount: 0), 0)
        XCTAssertEqual(ThumbnailPaging.visibleCount(windowCount: 2), 2)
        XCTAssertEqual(ThumbnailPaging.visibleCount(windowCount: 8), 3)
    }

    func testInitialOffsetKeepsActiveCardInView() {
        XCTAssertEqual(ThumbnailPaging.initialOffset(activeIndex: 0, windowCount: 5), 0)
        XCTAssertEqual(ThumbnailPaging.initialOffset(activeIndex: 2, windowCount: 5), 0)
        XCTAssertEqual(ThumbnailPaging.initialOffset(activeIndex: 3, windowCount: 5), 1)
        XCTAssertEqual(ThumbnailPaging.initialOffset(activeIndex: 4, windowCount: 5), 2)
        XCTAssertEqual(ThumbnailPaging.initialOffset(activeIndex: 0, windowCount: 2), 0)
    }

    func testPageClamps() {
        XCTAssertEqual(ThumbnailPaging.page(offset: 0, delta: -1, windowCount: 5), 0)
        XCTAssertEqual(ThumbnailPaging.page(offset: 0, delta: 1, windowCount: 5), 1)
        XCTAssertEqual(ThumbnailPaging.page(offset: 2, delta: 1, windowCount: 5), 2)
        XCTAssertEqual(ThumbnailPaging.page(offset: 1, delta: 1, windowCount: 3), 0)
    }
}
