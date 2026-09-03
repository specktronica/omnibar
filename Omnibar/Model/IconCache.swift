import AppKit
import Foundation

enum IconCache {
    private static var cache: [String: NSImage] = [:]
    private static var names: [String: String] = [:]

    static func icon(forBundleID bundleID: String) -> NSImage? {
        if let cached = cache[bundleID] { return cached }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        let image = NSWorkspace.shared.icon(forFile: url.path)
        cache[bundleID] = image
        return image
    }

    static func icon(for url: URL) -> NSImage {
        let key = url.path
        if let cached = cache[key] { return cached }
        let image = NSWorkspace.shared.icon(forFile: url.path)
        cache[key] = image
        return image
    }

    static func appName(for bundleID: String) -> String {
        if let cached = names[bundleID] { return cached }
        var name = bundleID
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID),
           let bundle = Bundle(url: url) {
            if let display = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String, !display.isEmpty {
                name = display
            } else if let bundleName = bundle.object(forInfoDictionaryKey: "CFBundleName") as? String, !bundleName.isEmpty {
                name = bundleName
            }
        }
        names[bundleID] = name
        return name
    }
}

enum BrandIcon {
    /// In-app mark. Avoid `applicationIconName`: macOS plates that image onto a rounded square.
    static func image(pointSize: CGFloat) -> NSImage? {
        guard let base = NSImage(named: "BrandLogo") else { return nil }
        guard let image = base.copy() as? NSImage else { return base }
        image.size = NSSize(width: pointSize, height: pointSize)
        image.isTemplate = false
        return image
    }

    /// Menu-bar extra. Template so it tints like other status items.
    nonisolated static func menuBarImage(pointSize: CGFloat = 18) -> NSImage {
        let size = NSSize(width: pointSize, height: pointSize)
        let image = NSImage(size: size, flipped: false) { rect in
            drawMenuBarGlyph(in: rect)
            return true
        }
        image.isTemplate = true
        return image
    }

    /// Four equal circles packed in a larger circle; center curvilinear diamond filled.
    nonisolated private static func drawMenuBarGlyph(in rect: NSRect) {
        let inset = max(1 as CGFloat, rect.width * 0.07)
        let bounds = rect.insetBy(dx: inset, dy: inset)
        let cx = bounds.midX
        let cy = bounds.midY
        let outerR = min(bounds.width, bounds.height) / 2
        let root2 = CGFloat(2).squareRoot()
        let innerR = outerR / (1 + root2)
        let offset = innerR * root2

        NSColor.black.set()

        let center = NSBezierPath()
        addInnerArc(to: center, cx: cx + offset, cy: cy, radius: innerR, from: 225, to: 135, clockwise: true)
        addInnerArc(to: center, cx: cx, cy: cy + offset, radius: innerR, from: 315, to: 225, clockwise: true)
        addInnerArc(to: center, cx: cx - offset, cy: cy, radius: innerR, from: 45, to: 315, clockwise: true)
        addInnerArc(to: center, cx: cx, cy: cy - offset, radius: innerR, from: 135, to: 45, clockwise: true)
        center.close()
        center.fill()

        let lineWidth = max(1 as CGFloat, outerR * 0.13)
        strokeCircle(cx: cx, cy: cy, radius: outerR, lineWidth: lineWidth)
        strokeCircle(cx: cx + offset, cy: cy, radius: innerR, lineWidth: lineWidth)
        strokeCircle(cx: cx - offset, cy: cy, radius: innerR, lineWidth: lineWidth)
        strokeCircle(cx: cx, cy: cy + offset, radius: innerR, lineWidth: lineWidth)
        strokeCircle(cx: cx, cy: cy - offset, radius: innerR, lineWidth: lineWidth)
    }

    nonisolated private static func strokeCircle(cx: CGFloat, cy: CGFloat, radius: CGFloat, lineWidth: CGFloat) {
        let path = NSBezierPath(
            ovalIn: NSRect(x: cx - radius, y: cy - radius, width: radius * 2, height: radius * 2)
        )
        path.lineWidth = lineWidth
        path.lineJoinStyle = .round
        path.stroke()
    }

    nonisolated private static func addInnerArc(
        to path: NSBezierPath,
        cx: CGFloat,
        cy: CGFloat,
        radius: CGFloat,
        from startDeg: CGFloat,
        to endDeg: CGFloat,
        clockwise: Bool
    ) {
        let start = startDeg * .pi / 180
        let end = endDeg * .pi / 180
        var delta = end - start
        if clockwise, delta > 0 { delta -= 2 * .pi }
        if !clockwise, delta < 0 { delta += 2 * .pi }
        let steps = 20
        for i in 0...steps {
            let t = CGFloat(i) / CGFloat(steps)
            let angle = start + delta * t
            let point = NSPoint(x: cx + radius * cos(angle), y: cy + radius * sin(angle))
            if path.elementCount == 0 {
                path.move(to: point)
            } else {
                path.line(to: point)
            }
        }
    }
}
