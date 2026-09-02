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
        let visible = screen.frame
        return CGRect(
            x: visible.minX,
            y: visible.minY,
            width: visible.width,
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
