import AppKit
import XCTest
@testable import Omnibar

@MainActor
final class SpacePresenceTests: XCTestCase {
    func testAnotherSpaceRequiresAKnownAssignment() {
        let elsewhere = stubWindow(id: 1, spaces: [11])
        let here = stubWindow(id: 2, spaces: [10, 11])
        let unassigned = stubWindow(id: 3, spaces: [])
        XCTAssertTrue(SpacePresence.isOnAnotherSpace(elsewhere, currentSpace: 10))
        XCTAssertFalse(SpacePresence.isOnAnotherSpace(here, currentSpace: 10))
        XCTAssertFalse(SpacePresence.isOnAnotherSpace(unassigned, currentSpace: 10))
        XCTAssertFalse(SpacePresence.isOnAnotherSpace(elsewhere, currentSpace: nil))
        XCTAssertEqual(SpacePresence.anotherSpacePhrase, "Another Space")
    }

    func testLabelsNameOnlyTheWindowThatIsElsewhere() {
        XCTAssertEqual(SpacePresence.labeled("Docs", onAnotherSpace: true), "Docs - Another Space")
        XCTAssertEqual(SpacePresence.labeled("Docs", onAnotherSpace: false), "Docs")
        XCTAssertEqual(SpacePresence.detail(title: "Docs", onAnotherSpace: true), "Docs - Another Space")
        XCTAssertEqual(SpacePresence.detail(title: nil, onAnotherSpace: true), "Another Space")
        XCTAssertEqual(SpacePresence.detail(title: "Docs", onAnotherSpace: false), "Docs")
        XCTAssertNil(SpacePresence.detail(title: nil, onAnotherSpace: false))
    }

    func testRunningMarksPutThisSpaceFirstAndKeepARingVisible() {
        let here = stubWindow(id: 1, spaces: [10])
        let away = stubWindow(id: 2, spaces: [11])
        let activeHere = stubWindow(id: 3, spaces: [10], active: true)
        let activeAway = stubWindow(id: 4, spaces: [11], active: true)

        XCTAssertEqual(
            SpacePresence.runningMarks(windows: [activeHere], grouped: true, currentSpace: 10),
            [SpacePresence.RunningMark(ring: false, widens: true)]
        )
        XCTAssertEqual(
            SpacePresence.runningMarks(windows: [activeAway], grouped: false, currentSpace: 10),
            [SpacePresence.RunningMark(ring: true, widens: false)]
        )
        XCTAssertEqual(
            SpacePresence.runningMarks(windows: [away, here], grouped: true, currentSpace: 10),
            [
                SpacePresence.RunningMark(ring: false, widens: false),
                SpacePresence.RunningMark(ring: true, widens: false),
            ]
        )

        let crowded = (1...4).map { stubWindow(id: CGWindowID($0), spaces: [10]) } + [away]
        let crowdedMarks = SpacePresence.runningMarks(windows: crowded, grouped: true, currentSpace: 10)
        XCTAssertEqual(crowdedMarks.map(\.ring), [false, false, true])

        let allHere = (1...6).map { stubWindow(id: CGWindowID($0), spaces: [10]) }
        XCTAssertEqual(
            SpacePresence.runningMarks(windows: allHere, grouped: true, currentSpace: 10).map(\.ring),
            [false, false, false]
        )
        let allAway = (1...4).map { stubWindow(id: CGWindowID($0), spaces: [11]) }
        XCTAssertEqual(
            SpacePresence.runningMarks(windows: allAway, grouped: true, currentSpace: 10).map(\.ring),
            [true, true, true]
        )
        XCTAssertEqual(
            SpacePresence.runningMarks(windows: allAway, grouped: false, currentSpace: 10).map(\.ring),
            [true]
        )
    }

    func testTileTooltipAndMarksFollowTheCurrentSpace() {
        var grouped = AppSettings.default
        grouped.groupByApplication = true
        let here = stubWindow(id: 1, title: "Here", spaces: [10], appName: "Safari")
        let away = stubWindow(id: 2, title: "Away", spaces: [11], appName: "Safari")
        let mixed = TaskItem(
            id: "group-safari",
            kind: .grouped(bundleID: "com.apple.Safari", appName: "Safari", windows: [here, away], badge: nil)
        )
        let mixedView = TaskItemView(item: mixed, settings: grouped, currentSpace: 10)
        XCTAssertEqual(mixedView.toolTip, "Safari (2) - Here")
        XCTAssertEqual(dots(in: mixedView).ringFlags, [false, true])

        let elsewhere = TaskItem(
            id: "group-away",
            kind: .grouped(
                bundleID: "com.apple.Safari",
                appName: "Safari",
                windows: [away, stubWindow(id: 3, title: "Other", spaces: [12], appName: "Safari")],
                badge: nil
            )
        )
        let elsewhereView = TaskItemView(item: elsewhere, settings: grouped, currentSpace: 10)
        XCTAssertEqual(elsewhereView.toolTip, "Safari (2) - Away - Another Space")
        XCTAssertEqual(dots(in: elsewhereView).ringFlags, [true, true])

        var labels = AppSettings.default
        labels.groupByApplication = false
        labels.iconOnly = false
        let named = TaskItem(
            id: "w",
            kind: .window(stubWindow(id: 4, title: "Docs", spaces: [11], appName: "Safari"))
        )
        XCTAssertEqual(
            TaskItemView(item: named, settings: labels, currentSpace: 10).toolTip,
            "Safari - Docs - Another Space"
        )
        let untitled = TaskItem(
            id: "u",
            kind: .window(stubWindow(id: 5, title: "Safari", spaces: [11], appName: "Safari"))
        )
        XCTAssertEqual(
            TaskItemView(item: untitled, settings: labels, currentSpace: 10).toolTip,
            "Safari - Another Space"
        )

        let activeAway = TaskItem(
            id: "a",
            kind: .window(stubWindow(id: 6, spaces: [11], active: true))
        )
        var icons = AppSettings.default
        icons.groupByApplication = false
        icons.iconOnly = true
        let activeDots = dots(in: TaskItemView(item: activeAway, settings: icons, currentSpace: 10))
        XCTAssertEqual(activeDots.ringFlags, [true])
        XCTAssertFalse(activeDots.widens)

        let tokenHere = TaskItemView.displayToken(item: named, settings: labels, currentSpace: 10)
        let tokenThere = TaskItemView.displayToken(item: named, settings: labels, currentSpace: 11)
        XCTAssertNotEqual(tokenHere, tokenThere)
    }

    func testWindowMenuSuffixesOnlyOtherSpaces() {
        let here = stubWindow(id: 1, title: "Here", spaces: [10])
        let away = stubWindow(id: 2, title: "Away", spaces: [11])
        let item = TaskItem(
            id: "group-x",
            kind: .grouped(bundleID: "x", appName: "X", windows: [here, away], badge: nil)
        )
        let menu = TaskContextMenu.build(item: item, displayID: 1, currentSpace: 10)
        XCTAssertNotNil(menu.items.first { $0.title == "Here" })
        XCTAssertNotNil(menu.items.first { $0.title == "Away - Another Space" })
        let unknown = TaskContextMenu.build(item: item, displayID: 1, currentSpace: nil)
        XCTAssertNotNil(unknown.items.first { $0.title == "Away" })
        XCTAssertNil(unknown.items.first { $0.title == "Away - Another Space" })
    }

    func testHoverCardSaysAnotherSpaceEvenWithoutTitles() {
        let away = stubWindow(id: 1, title: "Docs", spaces: [11], appName: "Safari")
        let here = stubWindow(id: 2, title: "Docs", spaces: [10], appName: "Safari")
        let item = TaskItem(id: "w", kind: .window(away))
        let card = ThumbnailCardView(frame: NSRect(x: 0, y: 0, width: 240, height: 160))

        card.configure(window: away, item: item, size: 240, showTitle: false, currentSpace: 10)
        XCTAssertEqual(titleField(in: card)?.stringValue, "Another Space")
        XCTAssertEqual(titleField(in: card)?.isHidden, false)

        card.configure(window: away, item: item, size: 240, showTitle: true, currentSpace: 10)
        XCTAssertEqual(titleField(in: card)?.stringValue, "Docs - Another Space")

        card.configure(window: here, item: item, size: 240, showTitle: true, currentSpace: 10)
        XCTAssertEqual(titleField(in: card)?.stringValue, "Docs")

        card.configure(window: here, item: item, size: 240, showTitle: false, currentSpace: 10)
        XCTAssertEqual(titleField(in: card)?.isHidden, true)
    }

    func testRingMarkLeavesAClearCenter() {
        let view = WindowDotsView(frame: NSRect(x: 0, y: 0, width: 38, height: 6))
        view.count = 2
        view.ringFlags = [false, true]
        view.activeIndex = 0
        let frames = WindowDotsView.markFrames(count: 2, active: false, in: view.bounds)
        let rep = draw(view, scale: 4)
        XCTAssertFalse(columnHasClearCenter(rep, scale: 4, viewX: frames[0].midX))
        XCTAssertTrue(columnHasClearCenter(rep, scale: 4, viewX: frames[1].midX))

        let pill = WindowDotsView(frame: NSRect(x: 0, y: 0, width: 26, height: 6))
        pill.count = 1
        pill.ringFlags = [true]
        pill.widens = false
        let pillFrames = WindowDotsView.markFrames(count: 1, active: false, in: pill.bounds)
        let pillRep = draw(pill, scale: 4)
        XCTAssertTrue(columnHasClearCenter(pillRep, scale: 4, viewX: pillFrames[0].midX))
    }

    private func dots(in view: TaskItemView) -> WindowDotsView {
        view.frame = NSRect(x: 0, y: 0, width: 50, height: 50)
        view.layoutSubtreeIfNeeded()
        return view.subviews.compactMap { $0 as? WindowDotsView }.first!
    }

    private func titleField(in card: ThumbnailCardView) -> NSTextField? {
        card.subviews.compactMap { $0 as? NSTextField }.first
    }

    private func draw(_ view: NSView, scale: Int) -> NSBitmapImageRep {
        let pixelsWide = Int(view.bounds.width) * scale
        let pixelsHigh = Int(view.bounds.height) * scale
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelsWide,
            pixelsHigh: pixelsHigh,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )!
        rep.size = view.bounds.size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        view.draw(view.bounds)
        NSGraphicsContext.restoreGraphicsState()
        return rep
    }

    /// True when the blue mark in this column has a transparent middle.
    private func columnHasClearCenter(_ rep: NSBitmapImageRep, scale: Int, viewX: CGFloat) -> Bool {
        let x = min(rep.pixelsWide - 1, max(0, Int((viewX * CGFloat(scale)).rounded(.down))))
        var blue: [Bool] = []
        blue.reserveCapacity(rep.pixelsHigh)
        for y in 0..<rep.pixelsHigh {
            guard let color = rep.colorAt(x: x, y: y) else {
                blue.append(false)
                continue
            }
            let lit = color.alphaComponent > 0.15
                && color.blueComponent > color.redComponent + 0.05
                && color.blueComponent > 0.15
            blue.append(lit)
        }
        guard let first = blue.firstIndex(of: true), let last = blue.lastIndex(of: true), last > first else {
            return false
        }
        return !blue[(first + last) / 2]
    }
}
