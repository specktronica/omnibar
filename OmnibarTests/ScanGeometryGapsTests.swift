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

    func testOffScreenWindowNeedsSizeOrTitle() {
        let frame = CGRect(x: 0, y: 0, width: 800, height: 600)
        XCTAssertTrue(ScanGeometry.canListOffScreenWindow(layer: 0, alpha: 1, frame: frame, title: ""))
        XCTAssertTrue(ScanGeometry.canListOffScreenWindow(
            layer: 0,
            alpha: 1,
            frame: .zero,
            title: "Notes"
        ))
        XCTAssertFalse(ScanGeometry.canListOffScreenWindow(layer: 0, alpha: 1, frame: .zero, title: "  "))
        XCTAssertFalse(ScanGeometry.canListOffScreenWindow(layer: 3, alpha: 1, frame: frame, title: "Menu"))
        XCTAssertFalse(ScanGeometry.canListOffScreenWindow(layer: 0, alpha: 0, frame: frame, title: "Ghost"))
    }

    func testOtherSpacesRequireAHiddenSpace() {
        XCTAssertTrue(ScanGeometry.isAssignedOnlyToOtherSpaces(spaces: [11], visibleSpaces: [10]))
        XCTAssertFalse(ScanGeometry.isAssignedOnlyToOtherSpaces(spaces: [10, 11], visibleSpaces: [10]))
        XCTAssertFalse(ScanGeometry.isAssignedOnlyToOtherSpaces(spaces: [], visibleSpaces: [10]))
        XCTAssertFalse(ScanGeometry.isAssignedOnlyToOtherSpaces(spaces: [11], visibleSpaces: []))
    }

    func testEmptyScreenSizesNeverMatch() {
        XCTAssertFalse(ScanGeometry.looksLikeFullscreen(
            CGRect(x: 0, y: 0, width: 1920, height: 1080),
            screenSizes: []
        ))
    }
}
