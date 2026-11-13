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
        XCTAssertTrue(ScanGeometry.canListOffScreenWindow(layer: 0, alpha: 1, frame: frame, title: "", isOrderedIn: true))
        XCTAssertTrue(ScanGeometry.canListOffScreenWindow(
            layer: 0,
            alpha: 1,
            frame: .zero,
            title: "Notes",
            isOrderedIn: true
        ))
        XCTAssertFalse(ScanGeometry.canListOffScreenWindow(layer: 0, alpha: 1, frame: .zero, title: "  ", isOrderedIn: true))
        XCTAssertFalse(ScanGeometry.canListOffScreenWindow(layer: 3, alpha: 1, frame: frame, title: "Menu", isOrderedIn: true))
        XCTAssertFalse(ScanGeometry.canListOffScreenWindow(layer: 0, alpha: 0, frame: frame, title: "Ghost", isOrderedIn: true))
    }

    func testClosedRetainedWindowsAreNotListedOnOtherSpaces() {
        let frame = CGRect(x: 0, y: 0, width: 800, height: 600)
        // Closing the last window need not remove its CG record or Space assignment.
        for orderedIn: Bool? in [false, nil] {
            XCTAssertFalse(ScanGeometry.canListOffScreenWindow(
                layer: 0, alpha: 1, frame: frame, title: "Last document", isOrderedIn: orderedIn
            ))
            XCTAssertFalse(ScanGeometry.canListOffScreenWindow(
                layer: 0, alpha: 1, frame: .zero, title: "Last document", isOrderedIn: orderedIn
            ))
        }
        XCTAssertTrue(ScanGeometry.canListOffScreenWindow(
            layer: 0, alpha: 1, frame: frame, title: "Open on another desktop", isOrderedIn: true
        ))
    }

    func testUntitledUnknownSubroleIsNotATask() {
        // Chrome's full-screen toolbar strips and transition snapshot.
        XCTAssertTrue(ScanGeometry.requiresTitle(subrole: "AXUnknown"))
        XCTAssertTrue(ScanGeometry.requiresTitle(subrole: "AXFloatingWindow"))
        XCTAssertTrue(ScanGeometry.requiresTitle(subrole: "AXSystemFloatingWindow"))
        XCTAssertFalse(ScanGeometry.requiresTitle(subrole: "AXStandardWindow"))
        XCTAssertFalse(ScanGeometry.requiresTitle(subrole: "AXDialog"))
        XCTAssertFalse(ScanGeometry.requiresTitle(subrole: ""))
    }

    func testWindowServerTagsSeparateAppWindowsFromChromeStrips() {
        // Tags read from SkyLight on macOS 26 with Chrome 157 in full screen.
        let chromeWindow = WindowServerTraits(parentID: 0, tags: 0x0300_0401_0008_2401)
        let systemSettings = WindowServerTraits(parentID: 0, tags: 0x0000_0001_0048_2001)
        XCTAssertTrue(ScanGeometry.isAppWindow(chromeWindow))
        XCTAssertTrue(ScanGeometry.isAppWindow(systemSettings))
        XCTAssertTrue(ScanGeometry.isAppWindow(WindowServerTraits(parentID: 0, tags: 0x8000_0002)))

        let stripContainer = WindowServerTraits(parentID: 0, tags: 0x0804_0401_400C_2080)
        let tabStrip = WindowServerTraits(parentID: 23497, tags: 0x0000_0001_400C_2282)
        XCTAssertFalse(ScanGeometry.isAppWindow(stripContainer))
        XCTAssertFalse(ScanGeometry.isAppWindow(tabStrip))
        XCTAssertFalse(ScanGeometry.isAppWindow(WindowServerTraits(parentID: 23497, tags: 0x1)))
        XCTAssertFalse(ScanGeometry.isAppWindow(WindowServerTraits(parentID: 0, tags: 0x2)))
    }

    func testOtherSpacesRequireAHiddenSpace() {
        XCTAssertTrue(ScanGeometry.isAssignedOnlyToOtherSpaces(spaces: [11], visibleSpaces: [10]))
        XCTAssertFalse(ScanGeometry.isAssignedOnlyToOtherSpaces(spaces: [10, 11], visibleSpaces: [10]))
        XCTAssertFalse(ScanGeometry.isAssignedOnlyToOtherSpaces(spaces: [], visibleSpaces: [10]))
        XCTAssertFalse(ScanGeometry.isAssignedOnlyToOtherSpaces(spaces: [11], visibleSpaces: []))
    }

    func testForeignOwnerDropsAccessibilityClaim() {
        XCTAssertFalse(ScanGeometry.accessibilityOwnsWindow(ownerPID: 22, walkedPID: 10))
        XCTAssertTrue(ScanGeometry.accessibilityOwnsWindow(ownerPID: 10, walkedPID: 10))
        XCTAssertTrue(ScanGeometry.accessibilityOwnsWindow(ownerPID: nil, walkedPID: 10))
        XCTAssertTrue(ScanGeometry.accessibilityOwnsWindow(ownerPID: 0, walkedPID: 10))
    }

    func testEmptyScreenSizesNeverMatch() {
        XCTAssertFalse(ScanGeometry.looksLikeFullscreen(
            CGRect(x: 0, y: 0, width: 1920, height: 1080),
            screenSizes: []
        ))
    }
}
