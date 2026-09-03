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

    nonisolated private static func drawMenuBarGlyph(in rect: NSRect) {
        let inset = max(1 as CGFloat, rect.width * 0.06)
        let bounds = rect.insetBy(dx: inset, dy: inset)
        let cx = bounds.midX
        let cy = bounds.midY
        let radius = min(bounds.width, bounds.height) / 2

        let path = NSBezierPath()
        path.windingRule = .evenOdd
        path.appendOval(
            in: NSRect(x: cx - radius, y: cy - radius, width: radius * 2, height: radius * 2)
        )

        // Brand mark: four color seams on the diagonals and a 4-pointed star center.
        let rMin = radius * (42.0 / 225.0)
        let rMax = radius * (89.0 / 225.0)
        let star = NSBezierPath()
        let steps = 64
        for i in 0..<steps {
            let theta = CGFloat(i) / CGFloat(steps) * 2 * CGFloat.pi
            let r = rMin + (rMax - rMin) * abs(sin(2 * theta))
            let point = NSPoint(x: cx + r * cos(theta), y: cy + r * sin(theta))
            if i == 0 {
                star.move(to: point)
            } else {
                star.line(to: point)
            }
        }
        star.close()
        path.append(star)

        let gap = max(1.15 as CGFloat, radius * 0.14)
        path.append(bar(cx: cx, cy: cy, length: radius * 2, width: gap, angle: .pi / 4))
        path.append(bar(cx: cx, cy: cy, length: radius * 2, width: gap, angle: -.pi / 4))

        NSColor.black.setFill()
        path.fill()
    }

    nonisolated private static func bar(
        cx: CGFloat,
        cy: CGFloat,
        length: CGFloat,
        width: CGFloat,
        angle: CGFloat
    ) -> NSBezierPath {
        let ca = cos(angle)
        let sa = sin(angle)
        let hl = length / 2
        let hw = width / 2
        func corner(_ x: CGFloat, _ y: CGFloat) -> NSPoint {
            NSPoint(x: cx + x * ca - y * sa, y: cy + x * sa + y * ca)
        }
        let path = NSBezierPath()
        path.move(to: corner(-hl, -hw))
        path.line(to: corner(hl, -hw))
        path.line(to: corner(hl, hw))
        path.line(to: corner(-hl, hw))
        path.close()
        return path
    }
}
