import XCTest
@testable import Omnibar

@MainActor
final class ThumbnailCardSizeTests: XCTestCase {
    func testPreferredSizeUsesSixteenByNinePlusChrome() {
        let size = ThumbnailCardView.preferredSize(for: 240)
        let imageWidth = 240 - ThumbnailCardView.contentInset * 2
        let imageHeight = imageWidth * (9.0 / 16.0)
        XCTAssertEqual(size.width, 240)
        XCTAssertEqual(size.height, imageHeight + ThumbnailCardView.chromeHeight + ThumbnailCardView.contentInset)
    }
}
