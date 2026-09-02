import AppKit
import ScreenCaptureKit
import Foundation

final class ThumbnailService {
    static let shared = ThumbnailService()

    private struct Entry {
        var image: NSImage
        var date: Date
    }

    private var cache: [CGWindowID: Entry] = [:]
    private let cacheLimit = 40
    private var inFlight: Set<CGWindowID> = []
    private var shareableContent: SCShareableContent?
    private var shareableContentDate: Date = .distantPast

    func cached(windowID: CGWindowID) -> NSImage? {
        cache[windowID]?.image
    }

    func invalidate(windowID: CGWindowID) {
        cache.removeValue(forKey: windowID)
    }

    func capture(windowID: CGWindowID, maxSize: CGFloat) async -> NSImage? {
        if let entry = cache[windowID], Date().timeIntervalSince(entry.date) < 0.35 {
            return entry.image
        }
        guard PermissionsManager.shared.screenRecordingTrusted || CGPreflightScreenCaptureAccess() else {
            return nil
        }
        guard !inFlight.contains(windowID) else { return cache[windowID]?.image }
        inFlight.insert(windowID)
        defer { inFlight.remove(windowID) }

        do {
            let content = try await shareableContentIfNeeded()
            guard let window = content.windows.first(where: { $0.windowID == windowID }) else {
                return cache[windowID]?.image
            }
            let filter = SCContentFilter(desktopIndependentWindow: window)
            let config = SCStreamConfiguration()
            let scale = max(1, NSScreen.main?.backingScaleFactor ?? 2)
            let sourceWidth = max(window.frame.width, 1)
            let sourceHeight = max(window.frame.height, 1)
            let ratio = min(maxSize / sourceWidth, maxSize / sourceHeight, 1)
            config.width = Int(sourceWidth * ratio * scale)
            config.height = Int(sourceHeight * ratio * scale)
            config.showsCursor = false
            config.captureResolution = .best
            let cgImage = try await SCScreenshotManager.captureImage(
                contentFilter: filter,
                configuration: config
            )
            let image = NSImage(cgImage: cgImage, size: NSSize(
                width: CGFloat(config.width) / scale,
                height: CGFloat(config.height) / scale
            ))
            cache[windowID] = Entry(image: image, date: Date())
            if cache.count > cacheLimit {
                let oldest = cache.min { $0.value.date < $1.value.date }?.key
                if let oldest { cache.removeValue(forKey: oldest) }
            }
            return image
        } catch {
            return cache[windowID]?.image
        }
    }

    private func shareableContentIfNeeded() async throws -> SCShareableContent {
        if let shareableContent, Date().timeIntervalSince(shareableContentDate) < 2 {
            return shareableContent
        }
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        shareableContent = content
        shareableContentDate = Date()
        return content
    }
}
