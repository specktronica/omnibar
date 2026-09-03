import AppKit
import XCTest
@testable import Omnibar

@MainActor
final class TaskbarHitTestingTests: XCTestCase {
    func testStartButtonIsHitInsteadOfLastTaskItem() {
        let bar = makeBar(itemCount: 3)
        let start = bar.startButtonFrame()
        XCTAssertGreaterThan(start.width, 0)
        let hit = bar.hitTest(NSPoint(x: start.midX, y: start.midY))
        XCTAssertTrue(hit is StartButtonView, "start button click hit \(String(describing: type(of: hit)))")
    }

    func testLastItemIsHitOnItsOwnTile() {
        let bar = makeBar(itemCount: 3)
        guard let last = bar.view(forItemID: "item-2") else {
            return XCTFail("missing last item view")
        }
        XCTAssertGreaterThan(last.frame.minX, bar.startButtonFrame().maxX)
        XCTAssertIdentical(bar.hitTest(NSPoint(x: last.frame.midX, y: last.frame.midY)), last)
    }

    func testFirstItemDoesNotCoverStartButton() {
        let bar = makeBar(itemCount: 3)
        guard let first = bar.view(forItemID: "item-0") else {
            return XCTFail("missing first item view")
        }
        XCTAssertGreaterThanOrEqual(first.frame.minX, bar.startButtonFrame().maxX)
    }

    private func makeBar(itemCount: Int) -> TaskbarView {
        let bar = TaskbarView(frame: NSRect(x: 0, y: 0, width: 900, height: 40))
        let items = (0..<itemCount).map { index in
            TaskItem(
                id: "item-\(index)",
                kind: .window(stubWindow(
                    id: CGWindowID(index + 1),
                    bundle: "app.\(index)",
                    title: "App \(index)",
                    active: index == itemCount - 1
                ))
            )
        }
        bar.update(items: items, settings: .default)
        bar.layoutSubtreeIfNeeded()
        return bar
    }
}
