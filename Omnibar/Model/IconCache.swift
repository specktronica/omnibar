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
    static func image(pointSize: CGFloat, palette: StartLogoPalette = .classic) -> NSImage {
        let size = NSSize(width: pointSize, height: pointSize)
        let image = NSImage(size: size, flipped: false) { rect in
            StartLogoRenderer.draw(in: rect, palette: palette)
            return true
        }
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
        let packing = StartLogoPacking(rect: rect)
        guard packing.outerR > 0.5 else { return }

        NSColor.black.set()
        packing.centerDiamond.fill()

        let lineWidth = max(1 as CGFloat, packing.outerR * 0.13)
        stroke(packing.outerCircle, lineWidth: lineWidth)
        stroke(packing.lobe(dx: 1, dy: 0), lineWidth: lineWidth)
        stroke(packing.lobe(dx: -1, dy: 0), lineWidth: lineWidth)
        stroke(packing.lobe(dx: 0, dy: 1), lineWidth: lineWidth)
        stroke(packing.lobe(dx: 0, dy: -1), lineWidth: lineWidth)
    }

    nonisolated private static func stroke(_ path: NSBezierPath, lineWidth: CGFloat) {
        path.lineWidth = lineWidth
        path.lineJoinStyle = .round
        path.stroke()
    }
}
