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

    func testOverlapsBarReadsTopLeftFrames() {
        // 1000-point primary display, 25-point menu bar, 50-point bar.
        let bar = CGRect(x: 0, y: 0, width: 1440, height: 50)
        // Shrunk so the bottom edge sits on the bar (Cocoa y 50...975).
        let cleared = CGRect(x: 0, y: 25, width: 1440, height: 925)
        XCTAssertFalse(OverlapGeometry.overlapsBar(cgFrame: cleared, bar: bar, primaryHeight: 1000))
        // Zoomed to the bottom of the screen (Cocoa y 0...975).
        let filled = CGRect(x: 0, y: 25, width: 1440, height: 975)
        XCTAssertTrue(OverlapGeometry.overlapsBar(cgFrame: filled, bar: bar, primaryHeight: 1000))
        let middle = CGRect(x: 100, y: 300, width: 400, height: 400)
        XCTAssertFalse(OverlapGeometry.overlapsBar(cgFrame: middle, bar: bar, primaryHeight: 1000))
    }

    func testOverlapsBarOnDisplayAbovePrimary() {
        // Display stacked above a 1000-point primary: Cocoa y 1000...1900.
        let bar = CGRect(x: 0, y: 1000, width: 1600, height: 50)
        // Cocoa y 1050...1875.
        let cleared = CGRect(x: 0, y: -875, width: 1600, height: 825)
        XCTAssertFalse(OverlapGeometry.overlapsBar(cgFrame: cleared, bar: bar, primaryHeight: 1000))
        // Cocoa y 1000...1875.
        let filled = CGRect(x: 0, y: -875, width: 1600, height: 875)
        XCTAssertTrue(OverlapGeometry.overlapsBar(cgFrame: filled, bar: bar, primaryHeight: 1000))
    }

    // Top-left-origin frames on a 1000-point display with a 25-point menu bar
    // and a 50-point Taskbar.
    private let small = CGRect(x: 200, y: 200, width: 800, height: 500)
    private let filled = CGRect(x: 0, y: 25, width: 1440, height: 975)
    private let fitted = CGRect(x: 0, y: 25, width: 1440, height: 925)

    private func step(_ frame: CGRect, _ proposedHeight: CGFloat?, _ memory: inout FitMemory) -> FitAction {
        OverlapGeometry.fitAction(cgFrame: frame, proposedHeight: proposedHeight, memory: &memory)
    }

    func testSecondZoomRestoresFrameFromBeforeFirstZoom() {
        var memory = FitMemory()
        XCTAssertEqual(step(small, nil, &memory), .none)
        XCTAssertEqual(step(filled, 925, &memory), .fit(height: 925))
        memory.recordFit(fitted)
        XCTAssertEqual(step(fitted, nil, &memory), .none)
        XCTAssertEqual(step(filled, 925, &memory), .restore(small))
        // Back at the earlier size, the next zoom fits again.
        XCTAssertEqual(step(small, nil, &memory), .none)
        XCTAssertEqual(step(filled, 925, &memory), .fit(height: 925))
        XCTAssertEqual(memory.restore, small)
    }

    func testSecondZoomBeforeAnotherScanStillRestores() {
        var memory = FitMemory()
        _ = step(small, nil, &memory)
        _ = step(filled, 925, &memory)
        memory.recordFit(fitted)
        XCTAssertEqual(step(filled, 925, &memory), .restore(small))
    }

    func testWindowOpenedOverBarHasNothingToRestore() {
        var memory = FitMemory()
        XCTAssertEqual(step(filled, 925, &memory), .fit(height: 925))
        memory.recordFit(fitted)
        XCTAssertEqual(step(filled, 925, &memory), .fit(height: 925))
        XCTAssertNil(memory.restore)
    }

    func testDraggingFittedWindowOverBarFitsAndKeepsEarlierFrame() {
        var memory = FitMemory()
        _ = step(small, nil, &memory)
        _ = step(filled, 925, &memory)
        memory.recordFit(fitted)
        let dragged = fitted.offsetBy(dx: 0, dy: 100)
        XCTAssertEqual(step(dragged, 825, &memory), .fit(height: 825))
        memory.recordFit(CGRect(x: 0, y: 125, width: 1440, height: 825))
        XCTAssertEqual(step(filled, 925, &memory), .restore(small))
    }

    func testMovingFittedWindowForgetsEarlierFrame() {
        var memory = FitMemory()
        _ = step(small, nil, &memory)
        _ = step(filled, 925, &memory)
        memory.recordFit(fitted)
        let moved = CGRect(x: 300, y: 100, width: 900, height: 600)
        XCTAssertEqual(step(moved, nil, &memory), .none)
        XCTAssertNil(memory.fitted)
        XCTAssertNil(memory.restore)
        XCTAssertEqual(step(filled, 925, &memory), .fit(height: 925))
        XCTAssertEqual(memory.restore, moved)
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
