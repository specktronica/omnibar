import AppKit
import CoreGraphics
import Foundation

enum ScreenGeometry {
    static var cocoaPrimaryHeight: CGFloat {
        NSScreen.screens.first { $0.frame.origin == .zero }?.frame.height
            ?? NSScreen.screens.first?.frame.height
            ?? 0
    }

    static func cocoaRect(fromCGRect rect: CGRect) -> CGRect {
        cocoaRect(fromCGRect: rect, primaryHeight: cocoaPrimaryHeight)
    }

    nonisolated static func cocoaRect(fromCGRect rect: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(
            x: rect.origin.x,
            y: primaryHeight - rect.origin.y - rect.height,
            width: rect.width,
            height: rect.height
        )
    }

    static func displayID(containingCGRect rect: CGRect) -> CGDirectDisplayID? {
        let screens = NSScreen.screens.map { (id: $0.displayID, frame: $0.frame) }
        return displayID(
            containingCGRect: rect,
            screens: screens,
            cocoaPrimaryHeight: cocoaPrimaryHeight
        ) ?? NSScreen.main?.displayID
    }

    nonisolated static func displayID(
        containingCGRect rect: CGRect,
        screens: [(id: CGDirectDisplayID, frame: CGRect)],
        cocoaPrimaryHeight: CGFloat
    ) -> CGDirectDisplayID? {
        let cocoa = cocoaRect(fromCGRect: rect, primaryHeight: cocoaPrimaryHeight)
        let center = CGPoint(x: cocoa.midX, y: cocoa.midY)
        if let screen = screens.first(where: { $0.frame.contains(center) }) {
            return screen.id
        }
        var best: (CGDirectDisplayID, CGFloat)?
        for screen in screens {
            let intersection = screen.frame.intersection(cocoa)
            let area = intersection.isNull ? 0 : intersection.width * intersection.height
            if area > 0, best == nil || area > best!.1 {
                best = (screen.id, area)
            }
        }
        return best?.0
    }

    static func taskbarFrame(on screen: NSScreen, height: CGFloat) -> CGRect {
        taskbarFrame(screenFrame: screen.frame, visibleFrame: screen.visibleFrame, height: height)
    }

    /// Bottom strip of the display. The horizontal span follows `visibleFrame`,
    /// which macOS insets for a Dock on the left or right.
    nonisolated static func taskbarFrame(screenFrame: CGRect, visibleFrame: CGRect, height: CGFloat) -> CGRect {
        let minX = max(screenFrame.minX, visibleFrame.minX)
        let maxX = min(screenFrame.maxX, visibleFrame.maxX)
        return CGRect(
            x: minX,
            y: screenFrame.minY,
            width: max(0, maxX - minX),
            height: height
        )
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID {
        guard let num = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return 0
        }
        return CGDirectDisplayID(num.uint32Value)
    }
}
