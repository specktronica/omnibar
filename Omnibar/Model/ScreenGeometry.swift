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
        CGRect(
            x: rect.origin.x,
            y: cocoaPrimaryHeight - rect.origin.y - rect.height,
            width: rect.width,
            height: rect.height
        )
    }

    static func displayID(containingCGRect rect: CGRect) -> CGDirectDisplayID? {
        let cocoa = cocoaRect(fromCGRect: rect)
        let center = CGPoint(x: cocoa.midX, y: cocoa.midY)
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(center) }) {
            return screen.displayID
        }
        var best: (CGDirectDisplayID, CGFloat)?
        for screen in NSScreen.screens {
            let intersection = screen.frame.intersection(cocoa)
            let area = intersection.isNull ? 0 : intersection.width * intersection.height
            if area > 0, best == nil || area > best!.1 {
                best = (screen.displayID, area)
            }
        }
        return best?.0 ?? NSScreen.main?.displayID
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
