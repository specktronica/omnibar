import AppKit
import Foundation

enum IconCache: Sendable {
    nonisolated private final class Storage: @unchecked Sendable {
        let lock = NSLock()
        var cache: [String: NSImage] = [:]
        var names: [String: String] = [:]
    }

    nonisolated private static let storage = Storage()

    nonisolated static func icon(forBundleID bundleID: String) -> NSImage? {
        if let cached = cachedImage(bundleID) { return cached }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        return store(NSWorkspace.shared.icon(forFile: url.path), key: bundleID)
    }

    nonisolated static func icon(for url: URL) -> NSImage {
        let key = url.path
        if let cached = cachedImage(key) { return cached }
        return store(NSWorkspace.shared.icon(forFile: url.path), key: key)
    }

    nonisolated static func prefetch(urls: [URL]) {
        for url in urls {
            _ = icon(for: url)
        }
    }

    nonisolated static func appName(for bundleID: String) -> String {
        storage.lock.lock()
        if let cached = storage.names[bundleID] {
            storage.lock.unlock()
            return cached
        }
        storage.lock.unlock()
        var name = bundleID
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID),
           let bundle = Bundle(url: url) {
            if let display = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String, !display.isEmpty {
                name = display
            } else if let bundleName = bundle.object(forInfoDictionaryKey: "CFBundleName") as? String, !bundleName.isEmpty {
                name = bundleName
            }
        }
        storage.lock.lock()
        storage.names[bundleID] = name
        storage.lock.unlock()
        return name
    }

    nonisolated private static func cachedImage(_ key: String) -> NSImage? {
        storage.lock.lock()
        defer { storage.lock.unlock() }
        return storage.cache[key]
    }

    @discardableResult
    nonisolated private static func store(_ image: NSImage, key: String) -> NSImage {
        storage.lock.lock()
        storage.cache[key] = image
        storage.lock.unlock()
        return image
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
