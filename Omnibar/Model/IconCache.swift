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
}
