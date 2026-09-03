import XCTest
@testable import Omnibar

@MainActor
final class ScanGeometryGapsTests: XCTestCase {
    func testLooksLikeFullscreenAllowsFourPointSlack() {
        let sizes = [CGSize(width: 1920, height: 1080)]
        XCTAssertTrue(ScanGeometry.looksLikeFullscreen(
            CGRect(x: 0, y: 0, width: 1916.5, height: 1083),
            screenSizes: sizes
        ))
        XCTAssertFalse(ScanGeometry.looksLikeFullscreen(
            CGRect(x: 0, y: 0, width: 1915, height: 1080),
            screenSizes: sizes
        ))
    }

    func testEmptyScreenSizesNeverMatch() {
        XCTAssertFalse(ScanGeometry.looksLikeFullscreen(
            CGRect(x: 0, y: 0, width: 1920, height: 1080),
            screenSizes: []
        ))
    }
}
