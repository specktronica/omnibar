import XCTest
@testable import Omnibar

@MainActor
final class OverlapGeometryTests: XCTestCase {
    @MainActor
    func testShouldConsiderSkipsFullscreenMinimizedHiddenAndLists() {
        XCTAssertFalse(OverlapGeometry.shouldConsider(
            stubWindow(id: 1, fullscreen: true),
            skipBundles: [],
            skippedPIDs: []
        ))
        XCTAssertFalse(OverlapGeometry.shouldConsider(
            stubWindow(id: 2, minimized: true),
            skipBundles: [],
            skippedPIDs: []
        ))
        XCTAssertFalse(OverlapGeometry.shouldConsider(
            stubWindow(id: 3, hidden: true),
            skipBundles: [],
            skippedPIDs: []
        ))
        XCTAssertFalse(OverlapGeometry.shouldConsider(
            stubWindow(id: 4, bundle: "com.skip"),
            skipBundles: ["com.skip"],
            skippedPIDs: []
        ))
        XCTAssertFalse(OverlapGeometry.shouldConsider(
            stubWindow(id: 5, pid: 99),
            skipBundles: [],
            skippedPIDs: [99]
        ))
        XCTAssertTrue(OverlapGeometry.shouldConsider(
            stubWindow(id: 6),
            skipBundles: ["com.skip"],
            skippedPIDs: [99]
        ))
    }

    func testProposedHeightShrinksToClearBar() {
        let window = CGRect(x: 0, y: 0, width: 800, height: 600)
        let bar = CGRect(x: 0, y: 0, width: 1440, height: 40)
        XCTAssertEqual(OverlapGeometry.proposedHeight(windowCocoa: window, bar: bar), 560)
    }

    func testProposedHeightIgnoresTinyOrMissingOverlap() {
        let window = CGRect(x: 0, y: 40, width: 800, height: 600)
        let bar = CGRect(x: 0, y: 0, width: 1440, height: 40)
        XCTAssertNil(OverlapGeometry.proposedHeight(windowCocoa: window, bar: bar))
        let hairline = CGRect(x: 0, y: 0, width: 800, height: 600.5)
        XCTAssertNil(OverlapGeometry.proposedHeight(
            windowCocoa: hairline,
            bar: CGRect(x: 0, y: 0, width: 100, height: 0.5)
        ))
    }

    func testProposedHeightNeverGoesBelowEighty() {
        let window = CGRect(x: 0, y: 0, width: 800, height: 100)
        let bar = CGRect(x: 0, y: 0, width: 1440, height: 40)
        XCTAssertEqual(OverlapGeometry.proposedHeight(windowCocoa: window, bar: bar), 80)
    }

    func testTwoFailedVerifiesSkipPid() {
        var failCounts: [pid_t: Int] = [:]
        var skipped: Set<pid_t> = []
        OverlapGeometry.recordVerifyResult(
            stillOverlaps: true,
            pid: 7,
            failCounts: &failCounts,
            skippedPIDs: &skipped
        )
        XCTAssertTrue(skipped.isEmpty)
        OverlapGeometry.recordVerifyResult(
            stillOverlaps: true,
            pid: 7,
            failCounts: &failCounts,
            skippedPIDs: &skipped
        )
        XCTAssertEqual(skipped, [7])
        OverlapGeometry.recordVerifyResult(
            stillOverlaps: false,
            pid: 8,
            failCounts: &failCounts,
            skippedPIDs: &skipped
        )
        XCTAssertEqual(failCounts[8], 0)
        XCTAssertFalse(skipped.contains(8))
    }
}
