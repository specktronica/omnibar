import XCTest
@testable import Omnibar

@MainActor
final class ScreenGeometryGapsTests: XCTestCase {
    func testCocoaRectFlipsYAgainstPrimaryHeight() {
        let rect = CGRect(x: 10, y: 20, width: 100, height: 50)
        let cocoa = ScreenGeometry.cocoaRect(fromCGRect: rect, primaryHeight: 1080)
        XCTAssertEqual(cocoa.origin.x, 10)
        XCTAssertEqual(cocoa.origin.y, 1080 - 20 - 50)
        XCTAssertEqual(cocoa.size, CGSize(width: 100, height: 50))
    }

    func testDisplayIDUsesLargestIntersectionWhenCenterMisses() {
        let screens: [(id: CGDirectDisplayID, frame: CGRect)] = [
            (1, CGRect(x: 0, y: 0, width: 800, height: 600)),
            (2, CGRect(x: 1000, y: 0, width: 800, height: 600))
        ]
        // CG y is flipped to cocoa y = 1080 - 0 - 200 = 880, which still misses both
        // frames (they occupy cocoa y 0...600). Intersection is empty too, so this
        // would return nil. Use a CG rect whose flipped center is in the gap
        // while the frame overlaps both screens.
        let overlapping = ScreenGeometry.displayID(
            containingCGRect: CGRect(x: 600, y: 480, width: 500, height: 100),
            screens: screens,
            cocoaPrimaryHeight: 1080
        )
        // cocoa: y = 1080-480-100=500, height 100 → y 500-600.
        // center x = 850 (gap), y = 550.
        // left intersection width 200, right 100 → display 1.
        XCTAssertEqual(overlapping, 1)
    }

    func testDisplayIDReturnsNilWhenNoOverlap() {
        let screens: [(id: CGDirectDisplayID, frame: CGRect)] = [
            (1, CGRect(x: 0, y: 0, width: 800, height: 600))
        ]
        let missed = ScreenGeometry.displayID(
            containingCGRect: CGRect(x: 9000, y: 0, width: 100, height: 100),
            screens: screens,
            cocoaPrimaryHeight: 1080
        )
        XCTAssertNil(missed)
    }
}
